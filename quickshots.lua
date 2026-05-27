-- quickshots.lua — drag-area screenshots, grouped paste, multi-format clipboard.
-- Load from ~/.hammerspoon/init.lua with: require("quickshots").start()

local M = {}

----------------------------------------------------------------
-- USER CONFIGURATION (edit values to taste)
----------------------------------------------------------------
local config = {
  -- Where screenshots are stored.
  saveDir = (os.getenv("HOME") or "") .. "/Pictures/QuickShots",

  -- Two screenshots whose timestamps differ by <= this many seconds
  -- belong to the same auto-group.
  groupWindowSeconds = 20,

  -- Persistent history is capped at this many entries.
  maxHistory = 300,

  -- Default count for "last N" actions.
  defaultLastN = 4,

  -- Clipboard payload format. One of:
  --   "paths"    — newline-separated absolute paths (default; great for Claude Code).
  --   "quoted"   — shell-quoted paths joined by spaces, one line.
  --   "markdown" — newline-separated `![](path)` links.
  --   "files"    — file references (Finder-style); multi-file paste is app-dependent.
  --   "images"   — image objects on the pasteboard; multi-image is app-dependent.
  --   "codex"    — `<codexCommandPrefix> --image '...' --image '...'` for Codex CLI.
  pasteMode = "paths",

  -- After updating the clipboard, send Cmd+V automatically.
  pasteAfterCopy = true,

  -- Delay between clipboard write and Cmd+V (seconds).
  pasteDelay = 0.15,

  -- Used by the "codex" paste mode.
  codexCommandPrefix = "codex resume --last",

  -- Alert durations (seconds).
  alertDurationOk  = 0.6,
  alertDurationErr = 1.5,

  -- Standard Hammerspoon hotkeys. Each entry is { {modifiers}, key } or nil.
  -- Disabled by default because the active layout uses Caps-as-modifier below.
  hotkeys = {
    capture     = nil,
    pasteGroup  = nil,
    pasteLastN  = nil,
    promptLastN = nil,
    openFolder  = nil,
  },

  -- "Caps Lock as held modifier" bindings.
  -- Requires Caps Lock remapped to F18 system-wide (run caps-setup.sh once).
  -- While the (former) Caps key is held, these key-presses fire QuickShots
  -- actions and are consumed; everything else types normally.
  capsBindings = {
    capture     = { {},          "a" }, -- Caps+A           drag-area screenshot
    pasteGroup  = { {},          "v" }, -- Caps+V           paste latest auto-group
    pasteLastN  = { {},          "n" }, -- Caps+N           paste last defaultLastN
    promptLastN = { { "shift" }, "v" }, -- Caps+Shift+V     prompt for N, then paste
    openFolder  = { {},          "o" }, -- Caps+O           open saveDir in Finder
    toggleBurst = { {},          "z" }, -- Caps+Z           toggle burst mode
    pasteFiles  = { {},          "f" }, -- Caps+F           paste latest group as files
  },

  -- Delay (seconds) between one burst capture finishing and the next launching.
  burstRelaunchDelay = 0.15,
}

local SETTINGS_KEY = "quickshots.history.v1"

----------------------------------------------------------------
-- INTERNAL STATE
----------------------------------------------------------------
local capturing = false       -- guard against double-capture
local activeTask = nil        -- holds the running screencapture task
local burstMode = false       -- true while a burst session is active
local burstId = nil           -- stable id stamped onto every shot in the burst

----------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------
local function shellQuote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function osaQuote(s)
  return '"' .. tostring(s):gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

local function ensureDir()
  hs.execute("/bin/mkdir -p " .. shellQuote(config.saveDir))
end

local function fileOk(path)
  if not path or path == "" then return false end
  local attrs = hs.fs.attributes(path)
  return attrs ~= nil and (attrs.size or 0) > 0
end

local function newPath()
  local now = hs.timer.secondsSinceEpoch()
  local secs = math.floor(now)
  local ms = math.floor((now - secs) * 1000)
  return string.format("%s/quickshot-%s-%03d.png",
    config.saveDir, os.date("%Y%m%d-%H%M%S", secs), ms)
end

----------------------------------------------------------------
-- HISTORY (persisted via hs.settings)
----------------------------------------------------------------
local function loadHistory()
  local h = hs.settings.get(SETTINGS_KEY)
  if type(h) ~= "table" then h = {} end
  return h
end

local function saveHistory(h)
  hs.settings.set(SETTINGS_KEY, h)
end

local function appendHistory(path, burst)
  local h = loadHistory()
  table.insert(h, { path = path, t = os.time(), burst = burst })
  while #h > config.maxHistory do
    table.remove(h, 1)
  end
  saveHistory(h)
end

----------------------------------------------------------------
-- SELECTION
----------------------------------------------------------------
-- If the newest entry was taken in a burst, group all consecutive entries
-- with the same burst id (no time check — bursts can pause for any length).
-- Otherwise fall back to the rolling time window: include each prior entry
-- as long as it is within groupWindowSeconds of its successor.
local function latestGroup()
  local h = loadHistory()
  if #h == 0 then return {} end

  local last = h[#h]
  if last.burst then
    local group = {}
    for i = #h, 1, -1 do
      if h[i].burst == last.burst then
        table.insert(group, 1, h[i])
      else
        break
      end
    end
    return group
  end

  local group = { last }
  for i = #h - 1, 1, -1 do
    if (group[1].t - h[i].t) <= config.groupWindowSeconds then
      table.insert(group, 1, h[i])
    else
      break
    end
  end
  return group
end

local function lastN(n)
  local h = loadHistory()
  n = math.max(1, math.floor(tonumber(n) or config.defaultLastN))
  local out = {}
  for i = math.max(1, #h - n + 1), #h do
    out[#out + 1] = h[i]
  end
  return out
end

local function pathsFromItems(items)
  local out = {}
  for _, it in ipairs(items or {}) do
    if it and fileOk(it.path) then out[#out + 1] = it.path end
  end
  return out
end

----------------------------------------------------------------
-- CLIPBOARD WRITERS
----------------------------------------------------------------
local function writePaths(paths)
  hs.pasteboard.setContents(table.concat(paths, "\n"))
end

local function writeQuoted(paths)
  local q = {}
  for _, p in ipairs(paths) do q[#q + 1] = shellQuote(p) end
  hs.pasteboard.setContents(table.concat(q, " "))
end

local function writeMarkdown(paths)
  local lines = {}
  for _, p in ipairs(paths) do lines[#lines + 1] = string.format("![](%s)", p) end
  hs.pasteboard.setContents(table.concat(lines, "\n"))
end

local function writeFiles(paths)
  if #paths == 0 then return end
  -- AppleScript's `set the clipboard to {POSIX file ...}` only sets a generic
  -- list type; apps like Messages, Mail, and Slack look for the modern
  -- public.file-url pasteboard items that Finder copy produces. Build that
  -- via JXA so multi-file paste lands as a real multi-item file paste.
  local jsUrls = {}
  for _, p in ipairs(paths) do
    local esc = tostring(p):gsub("\\", "\\\\"):gsub("'", "\\'")
    jsUrls[#jsUrls + 1] = "$.NSURL.fileURLWithPath('" .. esc .. "')"
  end
  local script = "ObjC.import('AppKit');"
    .. "var pb=$.NSPasteboard.generalPasteboard;"
    .. "pb.clearContents;"
    .. "pb.writeObjects($([" .. table.concat(jsUrls, ",") .. "]));"
  hs.osascript.javascript(script)
end

local function writeImages(paths)
  local imgs = {}
  for _, p in ipairs(paths) do
    local img = hs.image.imageFromPath(p)
    if img then imgs[#imgs + 1] = img end
  end
  if #imgs == 0 then
    hs.pasteboard.setContents(table.concat(paths, "\n"))
  elseif #imgs == 1 then
    hs.pasteboard.writeObjects(imgs[1])
  else
    hs.pasteboard.writeObjects(imgs)
  end
end

local function writeCodex(paths)
  local parts = { config.codexCommandPrefix }
  for _, p in ipairs(paths) do
    parts[#parts + 1] = "--image " .. shellQuote(p)
  end
  hs.pasteboard.setContents(table.concat(parts, " "))
end

local writers = {
  paths    = writePaths,
  quoted   = writeQuoted,
  markdown = writeMarkdown,
  files    = writeFiles,
  images   = writeImages,
  codex    = writeCodex,
}

----------------------------------------------------------------
-- ACTIONS
----------------------------------------------------------------
local function copyAndMaybePaste(items)
  local paths = pathsFromItems(items)
  if #paths == 0 then
    hs.alert.show("QuickShots: nothing to paste", config.alertDurationErr)
    return
  end
  local writer = writers[config.pasteMode] or writers.paths
  writer(paths)
  hs.alert.show(
    string.format("QuickShots: %d → %s", #paths, config.pasteMode),
    config.alertDurationOk
  )
  if config.pasteAfterCopy then
    hs.timer.doAfter(config.pasteDelay, function()
      hs.eventtap.keyStroke({ "cmd" }, "v", 0)
    end)
  end
end

function M.capture()
  if capturing then
    hs.alert.show("QuickShots: capture already in progress", config.alertDurationErr)
    return
  end
  ensureDir()
  local path = newPath()
  local thisBurst = burstId  -- snapshot so the tag matches the moment of capture
  capturing = true
  -- screencapture -i: native macOS interactive capture (drag region; Space toggles window).
  -- Escape aborts and writes no file, which we detect via fileOk().
  activeTask = hs.task.new("/usr/sbin/screencapture", function(_, _, _)
    capturing = false
    activeTask = nil
    if fileOk(path) then
      appendHistory(path, thisBurst)
      hs.alert.show(
        thisBurst and "📸 Burst shot saved" or "📸 QuickShot saved",
        config.alertDurationOk
      )
      -- Burst chaining: as long as we're still in burst mode, line up the
      -- next capture so the user can drag again immediately.
      if burstMode and thisBurst == burstId then
        hs.timer.doAfter(config.burstRelaunchDelay or 0.15, function()
          if burstMode then M.capture() end
        end)
      end
    else
      -- Empty/cancelled (Escape). If the user was in a burst, treat that
      -- Escape as "stop" — exit burst mode cleanly.
      if burstMode and thisBurst == burstId then
        M.toggleBurst()
      end
    end
  end, { "-i", path })
  if not activeTask or not activeTask:start() then
    capturing = false
    activeTask = nil
    hs.alert.show("QuickShots: failed to launch screencapture", config.alertDurationErr)
  end
end

function M.pasteGroup()
  copyAndMaybePaste(latestGroup())
end

function M.pasteLastN(n)
  copyAndMaybePaste(lastN(n))
end

function M.promptLastN()
  local btn, txt = hs.dialog.textPrompt(
    "QuickShots",
    "Paste how many recent screenshots?",
    tostring(config.defaultLastN),
    "Paste",
    "Cancel"
  )
  if btn ~= "Paste" then return end
  local n = tonumber(txt)
  if n and n > 0 then M.pasteLastN(n) end
end

function M.openFolder()
  ensureDir()
  hs.execute("/usr/bin/open " .. shellQuote(config.saveDir))
end

-- Toggle "burst mode": stays on until called again. Each capture taken
-- while on is tagged with a shared burst id, so latestGroup() returns the
-- entire burst regardless of how long pauses between drags ran.
function M.toggleBurst()
  if not burstMode then
    burstMode = true
    burstId = string.format("burst-%d-%d", os.time(), math.random(0, 99999))
    hs.alert.show("📸 Burst ON — drag shots; Caps+Z (or Esc) to stop", 1.5)
    -- Kick off the first capture immediately if we're not already in one.
    if not capturing then M.capture() end
  else
    local stoppingId = burstId
    burstMode = false
    burstId = nil
    local count = 0
    if stoppingId then
      for _, it in ipairs(loadHistory()) do
        if it.burst == stoppingId then count = count + 1 end
      end
    end
    hs.alert.show(
      string.format("📸 Burst stopped (%d shot%s)", count, count == 1 and "" or "s"),
      config.alertDurationOk
    )
  end
end

----------------------------------------------------------------
-- "Caps as held modifier" eventtap (Caps Lock remapped to F18 by hidutil)
----------------------------------------------------------------
local capsTap = nil
local capsHeld = false
local capsActions = {}

local MODIFIER_CHARS = { shift = "S", ctrl = "C", alt = "A", option = "A", cmd = "M" }

local function flagsKeyForBinding(modifiers, keyName)
  local s = ""
  for _, m in ipairs(modifiers or {}) do
    s = s .. (MODIFIER_CHARS[m] or "")
  end
  local code = hs.keycodes.map[tostring(keyName):lower()]
  return s .. ":" .. tostring(code)
end

local function flagsKeyForEvent(flags, keycode)
  local s = ""
  if flags.shift then s = s .. "S" end
  if flags.ctrl  then s = s .. "C" end
  if flags.alt   then s = s .. "A" end
  if flags.cmd   then s = s .. "M" end
  return s .. ":" .. tostring(keycode)
end

local function setupCapsBindings()
  capsActions = {}
  if type(config.capsBindings) ~= "table" then return end

  local function add(name, fn)
    local b = config.capsBindings[name]
    if type(b) == "table" and type(b[1]) == "table" and b[2] then
      capsActions[flagsKeyForBinding(b[1], b[2])] = fn
    end
  end

  add("capture",     function() M.capture() end)
  add("pasteGroup",  function() M.pasteGroup() end)
  add("pasteLastN",  function() M.pasteLastN() end)
  add("promptLastN", function() M.promptLastN() end)
  add("openFolder",  function() M.openFolder() end)
  add("toggleBurst", function() M.toggleBurst() end)
  add("pasteFiles",  function()
    local saved = config.pasteMode
    config.pasteMode = "files"
    M.pasteGroup()
    config.pasteMode = saved
  end)

  if not next(capsActions) then return end

  if capsTap then capsTap:stop(); capsTap = nil end

  local f18code = hs.keycodes.map.f18
  local autorepeatProp = hs.eventtap.event.properties.keyboardEventAutorepeat
  local typeKeyDown = hs.eventtap.event.types.keyDown
  local typeKeyUp   = hs.eventtap.event.types.keyUp

  capsTap = hs.eventtap.new({ typeKeyDown, typeKeyUp }, function(e)
    local code = e:getKeyCode()
    local etype = e:getType()

    if code == f18code then
      capsHeld = (etype == typeKeyDown)
      return true -- consume Caps (= F18) keystrokes entirely
    end

    if capsHeld and etype == typeKeyDown then
      local fn = capsActions[flagsKeyForEvent(e:getFlags(), code)]
      if fn then
        if e:getProperty(autorepeatProp) == 0 then fn() end
        return true -- consume so the host app never sees the key
      end
    end

    return false
  end)
  capsTap:start()
end

----------------------------------------------------------------
-- SETUP
----------------------------------------------------------------
local function bindHotkey(hk, fn)
  if type(hk) == "table" and type(hk[1]) == "table" and hk[2] then
    hs.hotkey.bind(hk[1], hk[2], fn)
  end
end

-- One-level deep merge so users can override a subset of keys (incl. hotkeys).
local function mergeConfig(user)
  if type(user) ~= "table" then return end
  for k, v in pairs(user) do
    if type(v) == "table" and type(config[k]) == "table" then
      for k2, v2 in pairs(v) do config[k][k2] = v2 end
    else
      config[k] = v
    end
  end
end

function M.start(userConfig)
  mergeConfig(userConfig)
  ensureDir()

  -- Enable ipc + AppleScript so the `hs` CLI and `osascript` can drive
  -- Hammerspoon for debugging. Both are wrapped in pcall so a missing
  -- module never blocks startup.
  pcall(function() require("hs.ipc") end)
  pcall(function() hs.allowAppleScript(true) end)

  bindHotkey(config.hotkeys.capture,     function() M.capture() end)
  bindHotkey(config.hotkeys.pasteGroup,  function() M.pasteGroup() end)
  bindHotkey(config.hotkeys.pasteLastN,  function() M.pasteLastN() end)
  bindHotkey(config.hotkeys.promptLastN, function() M.promptLastN() end)
  bindHotkey(config.hotkeys.openFolder,  function() M.openFolder() end)

  setupCapsBindings()

  hs.urlevent.bind("quickshot-capture",     function() M.capture() end)
  hs.urlevent.bind("quickshot-paste-group", function() M.pasteGroup() end)
  hs.urlevent.bind("quickshot-paste-last",  function(_, params)
    local n = config.defaultLastN
    if params and params.n then
      local parsed = tonumber(params.n)
      if parsed and parsed > 0 then n = math.floor(parsed) end
    end
    M.pasteLastN(n)
  end)
  hs.urlevent.bind("quickshot-open-folder", function() M.openFolder() end)
  hs.urlevent.bind("quickshot-toggle-burst", function() M.toggleBurst() end)

  -- Visible confirmation that the config loaded and bindings are live.
  hs.alert.show("QuickShots ready", config.alertDurationOk)
end

-- Exposed so users can read/mutate config from init.lua before/after start().
M.config = config

return M
