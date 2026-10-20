require("hs.ipc")
-- Preload lazily-loaded extensions so CLI output isn't cluttered with "-- Loading extension" lines
local _ = hs.json, hs.screen, hs.geometry, hs.fs

hs.window.animationDuration = 0

local layoutDir = hs.configdir .. "/layouts/"

-- Stable part of a title, e.g. "network-identity - main.py" -> "network-identity"
local function titleKey(title)
  title = title or ""
  local a, b = title:find(" — ", 1, true), title:find(" - ", 1, true)
  local i = (a and b) and math.min(a, b) or a or b
  return i and title:sub(1, i - 1) or title
end

local function standardWindows()
  local wins = {}
  for _, w in ipairs(hs.window.allWindows()) do
    if w:isStandard() and w:isVisible() and w:application() then
      table.insert(wins, w)
    end
  end
  return wins
end

function saveLayout(name)
  local entries = {}
  for _, w in ipairs(standardWindows()) do
    local app, scr = w:application(), w:screen()
    local u = scr:toUnitRect(w:frame())
    table.insert(entries, {
      app = app:name(), bundleID = app:bundleID(),
      title = w:title(), key = titleKey(w:title()),
      screenUUID = scr:getUUID(), screenName = scr:name(),
      unit = { x = u.x, y = u.y, w = u.w, h = u.h },
    })
  end
  hs.json.write(entries, layoutDir .. name .. ".json", true, true)
  return string.format("Saved %d windows to layout '%s'", #entries, name)
end

local function isBuiltin(name) return (name or ""):find("Built%-in") ~= nil end

local function findScreen(e)
  local screens = hs.screen.allScreens()
  for _, s in ipairs(screens) do
    if s:getUUID() == e.screenUUID then return s end
  end
  for _, s in ipairs(screens) do
    if s:name() == e.screenName then return s end
  end
  -- Different physical monitor: match by role (built-in vs external)
  for _, s in ipairs(screens) do
    if isBuiltin(s:name()) == isBuiltin(e.screenName) then return s end
  end
  return hs.screen.primaryScreen()
end

function restoreLayout(name)
  local entries = hs.json.read(layoutDir .. name .. ".json")
  if not entries then return "No layout named '" .. name .. "'" end

  local wins, used, moved, missing = standardWindows(), {}, 0, {}
  local function pick(pred)
    for _, w in ipairs(wins) do
      if not used[w:id()] and pred(w) then used[w:id()] = true; return w end
    end
  end

  -- Match exact title first, then stable title prefix, then any window of the same app
  local passes = {
    function(e, w) return w:title() == e.title end,
    function(e, w) return e.key ~= "" and titleKey(w:title()) == e.key end,
    function(e, w) return true end,
  }
  local pending = entries
  for _, pass in ipairs(passes) do
    local rest = {}
    for _, e in ipairs(pending) do
      local w = pick(function(w)
        return w:application():bundleID() == e.bundleID and pass(e, w)
      end)
      if w then
        w:setFrame(findScreen(e):fromUnitRect(hs.geometry.rect(e.unit.x, e.unit.y, e.unit.w, e.unit.h)))
        moved = moved + 1
      else
        table.insert(rest, e)
      end
    end
    pending = rest
  end
  for _, e in ipairs(pending) do table.insert(missing, e.app .. ": " .. e.title) end

  local msg = string.format("Restored %d/%d windows from '%s'", moved, #entries, name)
  if #missing > 0 then msg = msg .. "\nNot found:\n  " .. table.concat(missing, "\n  ") end
  return msg
end

function listLayouts()
  local names = {}
  for f in hs.fs.dir(layoutDir) do
    local n = f:match("^(.*)%.json$")
    if n then table.insert(names, n) end
  end
  table.sort(names)
  return table.concat(names, "\n")
end

function listWindows()
  local out = {}
  for _, w in ipairs(standardWindows()) do
    table.insert(out, string.format("%-20s %-25s %s", w:application():name(), w:screen():name(), w:title()))
  end
  return table.concat(out, "\n")
end
