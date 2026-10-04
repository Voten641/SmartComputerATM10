-- Test integracyjny: makieta API CC:Tweaked + falszywe peryferia (zgodne z docs/API_NOTES.md)
-- Uruchom z katalogu repo:  lua tests/harness.lua
local ROOT = arg and arg[0] and arg[0]:match("^(.*)/tests/") or "."
local TMP = os.getenv("SMART_TMP") or "/tmp/smart_test"
os.execute("rm -rf " .. TMP .. " && mkdir -p " .. TMP)

-- Cobalt nie ma integer subtype: sprawdzamy %d z ulamkiem
local realFormat = string.format
string.format = function(fmt, ...)
  local a = table.pack(...)
  local i = 0
  for spec in fmt:gmatch("%%[%-%+ #0]*%d*%.?%d*([%a%%])") do
    if spec ~= "%" then
      i = i + 1
      if spec == "d" and type(a[i]) == "number" and a[i] ~= math.floor(a[i]) then
        error("string.format %d z liczba niecalkowita: " .. tostring(a[i]), 2)
      end
    end
  end
  return realFormat(fmt, ...)
end

---------------------------------------------------------------------------
-- colors / keys
---------------------------------------------------------------------------
colors = {}
local CN = { "white", "orange", "magenta", "lightBlue", "yellow", "lime", "pink", "gray", "lightGray", "cyan", "purple", "blue", "brown", "green", "red", "black" }
for i, n in ipairs(CN) do colors[n] = 2 ^ (i - 1) end
colours = colors
keys = { q = 16, backspace = 14, up = 200, down = 208, pageUp = 201, pageDown = 209, enter = 28, numPadEnter = 335 }

---------------------------------------------------------------------------
-- terminal z buforem
---------------------------------------------------------------------------
local HEXC = {}
for i = 0, 15 do HEXC[2 ^ i] = ("0123456789abcdef"):sub(i + 1, i + 1) end
local DEFAULT_PAL = {
  0xF0F0F0, 0xF2B233, 0xE57FD8, 0x99B2F2, 0xDEDE6C, 0x7FCC19, 0xF2B2CC, 0x4C4C4C,
  0x999999, 0x4C99B2, 0xB266E5, 0x3366CC, 0x7F664C, 0x57A64E, 0xCC4C4C, 0x111111,
}
local function makeTerm(w, h, isColor)
  local t = { w = w, h = h, cx = 1, cy = 1, fg = colors.white, bg = colors.black, lines = {}, fgl = {}, bgl = {}, pal = {} }
  for i = 1, 16 do t.pal[i] = DEFAULT_PAL[i] end
  local function blank()
    t.lines, t.fgl, t.bgl = {}, {}, {}
    for y = 1, t.h do
      t.lines[y] = string.rep(" ", t.w)
      t.fgl[y] = string.rep(HEXC[t.fg], t.w)
      t.bgl[y] = string.rep(HEXC[t.bg], t.w)
    end
  end
  blank()
  local o = {}
  o._t = t
  local function put(s, f, b)
    local y = t.cy
    if y >= 1 and y <= t.h then
      local x1 = t.cx
      local a1 = math.max(1, x1)
      local a2 = math.min(t.w, x1 + #s - 1)
      if a2 >= a1 then
        local off = a1 - x1
        local n = a2 - a1 + 1
        local function splice(line, piece) return line:sub(1, a1 - 1) .. piece .. line:sub(a2 + 1) end
        t.lines[y] = splice(t.lines[y], s:sub(off + 1, off + n))
        t.fgl[y] = splice(t.fgl[y], f:sub(off + 1, off + n))
        t.bgl[y] = splice(t.bgl[y], b:sub(off + 1, off + n))
      end
    end
    t.cx = t.cx + #s
  end
  function o.getSize() return t.w, t.h end
  function o.setCursorPos(x, y) t.cx, t.cy = math.floor(x), math.floor(y) end
  function o.getCursorPos() return t.cx, t.cy end
  function o.setTextColor(c) assert(HEXC[c], "zly kolor"); t.fg = c end
  function o.setBackgroundColor(c) assert(HEXC[c], "zly kolor tla"); t.bg = c end
  o.setTextColour, o.setBackgroundColour = o.setTextColor, o.setBackgroundColor
  function o.getTextColor() return t.fg end
  function o.getBackgroundColor() return t.bg end
  function o.isColor() return isColor ~= false end
  o.isColour = o.isColor
  function o.setCursorBlink() end
  function o.getCursorBlink() return false end
  function o.write(s)
    s = tostring(s)
    put(s, string.rep(HEXC[t.fg], #s), string.rep(HEXC[t.bg], #s))
  end
  function o.blit(s, f, b)
    assert(#s == #f and #s == #b, "blit: rozne dlugosci")
    assert(not f:find("[^0-9a-f]") and not b:find("[^0-9a-f]"), "blit: zly kolor")
    put(s, f, b)
  end
  function o.clear() blank() end
  function o.clearLine()
    local y = t.cy
    if y >= 1 and y <= t.h then
      t.lines[y] = string.rep(" ", t.w)
      t.bgl[y] = string.rep(HEXC[t.bg], t.w)
      t.fgl[y] = string.rep(HEXC[t.fg], t.w)
    end
  end
  function o.scroll(n)
    for _ = 1, n do
      table.remove(t.lines, 1); t.lines[#t.lines + 1] = string.rep(" ", t.w)
      table.remove(t.fgl, 1); t.fgl[#t.fgl + 1] = string.rep(HEXC[t.fg], t.w)
      table.remove(t.bgl, 1); t.bgl[#t.bgl + 1] = string.rep(HEXC[t.bg], t.w)
    end
  end
  function o.redraw() end
  function o.setPaletteColour(c, r, g, b)
    local i = math.floor(math.log(c, 2) + 0.5) + 1
    if g == nil then t.pal[i] = r else t.pal[i] = math.floor(r * 255) * 65536 + math.floor(g * 255) * 256 + math.floor(b * 255) end
  end
  o.setPaletteColor = o.setPaletteColour
  function o.getPaletteColour(c)
    local v = t.pal[math.floor(math.log(c, 2) + 0.5) + 1]
    return math.floor(v / 65536) / 255, (math.floor(v / 256) % 256) / 255, (v % 256) / 255
  end
  o.getPaletteColor = o.getPaletteColour
  return o
end

-- zrzut do pliku podgladu PNG (tests/render_preview.py): naglowek + wiersze tekst/fg/bg + paleta
previewFile = nil
function previewDump(o, title)
  if not previewFile then return end
  local t = o._t
  previewFile:write("@@SCREEN ", title, " ", t.w, " ", t.h, "\n")
  local pal = {}
  for i = 1, 16 do pal[i] = string.format("%06X", t.pal[i]) end
  previewFile:write(table.concat(pal, " "), "\n")
  for y = 1, t.h do
    previewFile:write(t.lines[y], "\n", t.fgl[y], "\n", t.bgl[y], "\n")
  end
end

if os.getenv("SMART_PREVIEW") then previewFile = io.open(TMP .. "/preview.txt", "wb") end

local function dump(o, title)
  if previewDump then previewDump(o, title) end
  local t = o._t
  local out = { "+" .. string.rep("-", t.w) .. "+ " .. (title or "") }
  for y = 1, t.h do out[#out + 1] = "|" .. t.lines[y] .. "|" end
  out[#out + 1] = "+" .. string.rep("-", t.w) .. "+"
  return table.concat(out, "\n")
end

local function findText(o, s)
  for y, l in ipairs(o._t.lines) do
    local x = l:find(s, 1, true)
    if x then return x, y end
  end
end

-- SMART_TERM=240x135 -> duzy terminal komputera i pocketa (config CC term_sizes)
local TW, TH = (os.getenv("SMART_TERM") or "51x19"):match("(%d+)x(%d+)")
TW, TH = tonumber(TW), tonumber(TH)
BIG = TW >= 100
local computerTerm = makeTerm(TW, TH)
local current = computerTerm
term = setmetatable({}, { __index = function(_, k)
  if k == "current" then return function() return current end end
  if k == "redirect" then return function(t) local old = current; current = t; return old end end
  if k == "native" then return function() return computerTerm end end
  if k == "nativePaletteColour" or k == "nativePaletteColor" then
    return function(c)
      local v = DEFAULT_PAL[math.floor(math.log(c, 2) + 0.5) + 1]
      return math.floor(v / 65536) / 255, (math.floor(v / 256) % 256) / 255, (v % 256) / 255
    end
  end
  return function(...) return current[k](...) end
end })

window = {}
function window.create(parent, x, y, w, h, visible)
  local win = makeTerm(w, h, parent.isColor())
  -- jak w CC: okno kopiuje palete rodzica przy tworzeniu
  if parent._t then for i = 1, 16 do win._t.pal[i] = parent._t.pal[i] end end
  local vis = visible ~= false
  local function flush()
    if not vis then return end
    if parent._t then for i = 1, 16 do parent._t.pal[i] = win._t.pal[i] end end
    for yy = 1, h do
      parent.setCursorPos(x, y + yy - 1)
      parent.blit(win._t.lines[yy], win._t.fgl[yy], win._t.bgl[yy])
    end
  end
  local origWrite, origBlit = win.write, win.blit
  function win.write(s) origWrite(s); if vis then flush() end end
  function win.blit(s, f, b) origBlit(s, f, b); if vis then flush() end end
  function win.setVisible(v) vis = v; if v then flush() end end
  function win.isVisible() return vis end
  function win.reposition(nx, ny, nw, nh)
    if nw and nh then
      w, h = nw, nh
      win._t.w, win._t.h = nw, nh
      win.clear()
    end
  end
  function win.getPosition() return x, y end
  function win.getLine(yy)
    return win._t.lines[yy], win._t.fgl[yy], win._t.bgl[yy]
  end
  return win
end

---------------------------------------------------------------------------
-- os / zdarzenia / czas
---------------------------------------------------------------------------
local clock = 0
local queue = {}
local timers = {}
local timerId = 0
local realOs = os
os = setmetatable({}, { __index = realOs })
function os.clock() return clock end
function os.epoch() return math.floor(clock * 1000) + 1700000000000 end
function os.time(l) if l == "ingame" or l == nil then return (6 + clock / 50) % 24 end return realOs.time() end
function os.day() return 3 end
function os.date(f) return realOs.date(f) end
function os.startTimer(s) timerId = timerId + 1; timers[timerId] = clock + s; return timerId end
function os.cancelTimer(id) timers[id] = nil end
function os.queueEvent(...) queue[#queue + 1] = table.pack(...) end
function os.pullEventRaw(filter)
  while true do
    local ev = table.pack(coroutine.yield(filter))
    if filter == nil or ev[1] == filter or ev[1] == "terminate" then return table.unpack(ev, 1, ev.n) end
  end
end
function os.pullEvent(filter)
  local ev = table.pack(os.pullEventRaw(filter))
  if ev[1] == "terminate" then error("Terminated", 0) end
  return table.unpack(ev, 1, ev.n)
end
function os.reboot() error("REBOOT", 0) end
function sleep(s)
  local id = os.startTimer(s or 0)
  repeat local _, t = os.pullEvent("timer") until t == id
end
os.sleep = sleep
function os.getComputerID() return 1 end

local function nextEvent()
  if #queue > 0 then return table.remove(queue, 1) end
  local best, bt
  for id, t in pairs(timers) do if not bt or t < bt then best, bt = id, t end end
  if best then
    timers[best] = nil
    clock = math.max(clock, bt)
    return table.pack("timer", best)
  end
  return nil
end

parallel = {}
local scriptHook -- wywolywany przed kazdym zdarzeniem
function parallel.waitForAny(...)
  local fns = { ... }
  local cos, filters = {}, {}
  for i, f in ipairs(fns) do cos[i] = coroutine.create(f) end
  local function resume(i, ev)
    local ok, res = coroutine.resume(cos[i], table.unpack(ev, 1, ev.n))
    if not ok then error(res, 0) end
    filters[i] = res
    return coroutine.status(cos[i]) == "dead"
  end
  for i = 1, #cos do if resume(i, { n = 0 }) then return i end end
  local steps = 0
  while true do
    steps = steps + 1
    if steps > 200000 then error("za duzo krokow - zawieszenie?") end
    if scriptHook then scriptHook() end
    if os.getenv("DBG") and steps % 200 == 0 then io.stderr:write("steps ", steps, " clock ", clock, " q ", #queue, " ev ", tostring(queue[1] and queue[1][1]), "\n") end
    local ev = nextEvent()
    if not ev then error("brak zdarzen - wszystko czeka") end
    for i = 1, #cos do
      if coroutine.status(cos[i]) ~= "dead" and (filters[i] == nil or filters[i] == ev[1] or ev[1] == "terminate") then
        if resume(i, ev) then return i end
      end
    end
  end
end

---------------------------------------------------------------------------
-- fs (mapowanie na katalog tymczasowy) / textutils / misc
---------------------------------------------------------------------------
local function hp(p) return TMP .. "/" .. p:gsub("^/+", "") end
fs = {}
function fs.exists(p) local f = io.open(hp(p)); if f then f:close() return true end return realOs.execute("test -e '" .. hp(p) .. "'") == true end
function fs.getDir(p) return (p:match("^(.*)/[^/]*$") or "") end
function fs.makeDir(p) realOs.execute("mkdir -p '" .. hp(p) .. "'") end
function fs.delete(p) realOs.execute("rm -rf '" .. hp(p) .. "'") end
function fs.move(a, b) realOs.execute("mv '" .. hp(a) .. "' '" .. hp(b) .. "'") end
function fs.list(p) local r = {} for l in io.popen("ls '" .. hp(p) .. "'"):lines() do r[#r + 1] = l end return r end
function fs.open(p, mode)
  local f = io.open(hp(p), mode:sub(1, 1) == "r" and "rb" or "wb")
  if not f then return nil end
  return {
    readAll = function() return f:read("a") end,
    write = function(s) f:write(s) end,
    close = function() f:close() end,
  }
end

textutils = {}
local function ser(v, ind)
  ind = ind or ""
  if type(v) == "table" then
    local out = { "{" }
    for k, x in pairs(v) do
      local key = type(k) == "string" and string.format("[%q]", k) or "[" .. tostring(k) .. "]"
      out[#out + 1] = ind .. "  " .. key .. " = " .. ser(x, ind .. "  ") .. ","
    end
    out[#out + 1] = ind .. "}"
    return table.concat(out, "\n")
  elseif type(v) == "string" then return string.format("%q", v)
  else return tostring(v) end
end
textutils.serialize = function(v) return ser(v) end
textutils.serialise = textutils.serialize
textutils.unserialize = function(s) local f = load("return " .. s, "u", "t", {}); if not f then return nil end local ok, v = pcall(f) return ok and v or nil end
textutils.formatTime = function(t, h24) local h = math.floor(t); local m = math.floor((t - h) * 60); return string.format("%d:%02d", h, m) end

printed = {}
print = function(...) local t = table.pack(...); for i = 1, t.n do t[i] = tostring(t[i]) end printed[#printed + 1] = table.concat(t, " ") end
write = function(s) printed[#printed + 1] = tostring(s) end
printError = function(...) print("ERR", ...) end
local readQueue = {}
read = function() return table.remove(readQueue, 1) or "" end

package.preload["cc.strings"] = function()
  return { wrap = function(s, w) local r = {} for i = 1, #s, w do r[#r + 1] = s:sub(i, i + w - 1) end return r end }
end
table.unpack = table.unpack or unpack

-- require: moduly ladowane z repo (main.lua dodaje "/smart/?.lua")
table.insert(package.searchers, 2, function(name)
  local path = ROOT .. "/smart/" .. name:gsub("%.", "/") .. ".lua"
  local f = io.open(path)
  if not f then return nil end
  f:close()
  return loadfile(path), path
end)

---------------------------------------------------------------------------
-- Falszywe peryferia
---------------------------------------------------------------------------
local calls = {}
local function log(n) calls[#calls + 1] = n end

local devs = {}
local function add(name, types, methods) devs[name] = { types = types, m = methods } end

local function monitor(name, w, h)
  local base = { w = w, h = h, scale = 1 }
  local t = makeTerm(w, h)
  t.setTextScale = function(s)
    assert(s >= 0.5 and s <= 5 and (s * 2) % 1 == 0, "Expected number in range 0.5-5")
    base.scale = s
    t._t.w = math.floor(base.w / s); t._t.h = math.floor(base.h / s)
    t.clear()
  end
  t.getTextScale = function() return base.scale end
  add(name, { "monitor" }, t)
  return t
end

local reactor = { active = false, temp = 400, damage = 0, burn = 5, maxBurn = 1440, coolant = 1, waste = 0.1 }
local fissionMethods = {
  isFormed = function() return true end,
  getStatus = function() return reactor.active end,
  activate = function() if reactor.active then error("Reactor is already active") end reactor.active = true; log("activate") end,
  scram = function() if not reactor.active then error("Scram requires the reactor to be active") end reactor.active = false; log("scram") end,
  getTemperature = function() return reactor.temp end,
  getDamagePercent = function() return reactor.damage end,
  getFuelFilledPercentage = function() return 0.8 end,
  getCoolantFilledPercentage = function() return reactor.coolant end,
  getHeatedCoolantFilledPercentage = function() return 0.05 end,
  getWasteFilledPercentage = function() return reactor.waste end,
  getBurnRate = function() return reactor.burn end,
  getActualBurnRate = function() return reactor.active and reactor.burn or 0 end,
  getMaxBurnRate = function() return reactor.maxBurn end,
  setBurnRate = function(r) reactor.burn = r; log("setBurnRate " .. r) end,
  getHeatingRate = function() return 12345 end,
  getEnvironmentalLoss = function() return 0.1 end,
  isForceDisabled = function() return false end,
  getCoolant = function() return { name = "minecraft:water", amount = 1000 } end,
  getMinPos = function() return { x = 0, y = 60, z = 0 } end,
  getMaxPos = function() return { x = 4, y = 65, z = 4 } end,
}
add("fissionReactorLogicAdapter_0", { "fissionReactorLogicAdapter" }, fissionMethods)
-- Reactor Port w Mekanism 10.7 NIE udostepnia multibloku (exposesMultiblockToComputer = false)
add("fissionReactorPort_0", { "fissionReactorPort" }, {
  getMode = function() return "INPUT" end, setMode = function() end,
  incrementMode = function() end, decrementMode = function() end,
})

local matrixE = 4e12
add("inductionPort_0", { "inductionPort" }, {
  isFormed = function() return true end,
  getEnergy = function() return matrixE end,
  getMaxEnergy = function() return 1e13 end,
  getEnergyFilledPercentage = function() return matrixE / 1e13 end,
  getLastInput = function() return 250000 end,
  getLastOutput = function() return 100000 end,
  getTransferCap = function() return 1e9 end,
  getMinPos = function() return { x = 10, y = 60, z = 0 } end,
  getMaxPos = function() return { x = 14, y = 65, z = 4 } end,
})
add("turbineValve_0", { "turbineValve" }, { isFormed = function() return false end })
add("boilerValve_0", { "boilerValve" }, {
  isFormed = function() return true end, getTemperature = function() return 1500 end, getBoilRate = function() return 2000 end,
  getMaxBoilRate = function() return 5000 end, getBoilCapacity = function() return 8000 end, getSuperheaters = function() return 4 end,
  getWaterFilledPercentage = function() return 0.9 end, getSteamFilledPercentage = function() return 0.3 end,
  getHeatedCoolantFilledPercentage = function() return 0.2 end, getCooledCoolantFilledPercentage = function() return 0.1 end,
  getEnvironmentalLoss = function() return 0 end,
  getMinPos = function() return { x = 20, y = 60, z = 0 } end, getMaxPos = function() return { x = 24, y = 70, z = 4 } end,
})
add("fusionReactorLogicAdapter_0", { "fusionReactorLogicAdapter" }, {
  isFormed = function() return true end, isIgnited = function() return true end,
  getPlasmaTemperature = function() return 4.5e8 end, getCaseTemperature = function() return 1.2e8 end,
  getInjectionRate = function() return 10 end, setInjectionRate = function(r) assert(r % 2 == 0) log("inj " .. r) end,
  getProductionRate = function() return 5e6 end, getDeuteriumFilledPercentage = function() return 0.5 end,
  getTritiumFilledPercentage = function() return 0.4 end, getDTFuelFilledPercentage = function() return 0.3 end,
  getWaterFilledPercentage = function() return 1 end, getSteamFilledPercentage = function() return 0 end,
  getEnergyFilledPercentage = function() return 0.2 end,
  getMinPos = function() return { x = 30, y = 60, z = 0 } end, getMaxPos = function() return { x = 34, y = 65, z = 4 } end,
})
add("dynamicValve_0", { "dynamicValve" }, {
  isFormed = function() return true end,
  getStored = function() return { name = "minecraft:water", amount = 640000 } end,
  getTankCapacity = function() return 1000000 end, getFilledPercentage = function() return 0.64 end,
  getMinPos = function() return { x = 40, y = 60, z = 0 } end, getMaxPos = function() return { x = 44, y = 65, z = 4 } end,
})
add("basicEnergyCube_0", { "basicEnergyCube" }, {
  getEnergy = function() return 2e6 end, getMaxEnergy = function() return 4e6 end, getEnergyFilledPercentage = function() return 0.5 end,
})
genMode = "HIGH"
add("gasBurningGenerator_0", { "gasBurningGenerator" }, {
  getEnergy = function() return 5e5 end, getMaxEnergy = function() return 1e6 end, getEnergyFilledPercentage = function() return 0.5 end,
  getProductionRate = function() return genMode == "DISABLED" and 25000 or 0 end, getMaxOutput = function() return 50000 end,
  getRedstoneMode = function() return genMode end,
  setRedstoneMode = function(m) assert(m == "DISABLED" or m == "HIGH" or m == "LOW" or m == "PULSE") genMode = m end,
})
add("crusher_0", { "crusher" }, {
  getEnergy = function() return 1000 end, getMaxEnergy = function() return 20000 end, getEnergyFilledPercentage = function() return 0.05 end,
})
add("powah:energy_cell_0", { "powah:energy_cell", "energy_cell", "energy_storage" }, {
  getStoredEnergy = function() return 5e5 end, getMaxEnergy = function() return 1e6 end,
  getEnergy = function() return 5e5 end, getEnergyCapacity = function() return 1e6 end,
})
add("powah:reactor_part_0", { "powah:reactor_part", "uraninite_reactor", "energy_storage" }, {
  isRunning = function() return true end, getFuel = function() return 70 end, getTemperature = function() return 45 end,
  getStoredEnergy = function() return 1 end, getMaxEnergy = function() return 2 end,
})
local items = {}
crafts, exports = {}, {}
for i = 1, 40 do items[i] = { name = "minecraft:item_" .. i, displayName = "Przedmiot " .. i, count = i * 37, isCraftable = i % 5 == 0 } end
add("me_bridge_0", { "me_bridge" }, {
  isConnected = function() return true end, isOnline = function() return true end,
  getItems = function(f) assert(type(f) == "table") return items end,
  getUsedItemStorage = function() return 97000 end, getMaxItemStorage = function() return 100000 end,
  getUsedFluidStorage = function() return 10 end, getMaxFluidStorage = function() return 100 end,
  getStoredEnergy = function() return 1000 end, getEnergyCapacity = function() return 1600 end,
  getEnergyUsage = function() return 55.5 end, getCraftingTasks = function() return { {}, {} } end,
  getCraftingCPUs = function() return { { isBusy = true }, { isBusy = false } } end,
  getItem = function(f)
    assert(type(f) == "table" and f.name, "getItem bez filtra")
    for _, it in ipairs(items) do if it.name == f.name then return it end end
    return nil, "NOT_FOUND"
  end,
  isCrafting = function(f) assert(f.type == "item" and f.name) return false end,
  craftItem = function(f)
    assert(type(f.name) == "string" and type(f.count) == "number")
    if f.name == "minecraft:nopattern" then return nil, "NOT_CRAFTABLE" end
    crafts[#crafts + 1] = f.name .. " x" .. f.count
    return { getId = function() return 1 end }
  end,
  exportItem = function(target, f)
    assert(type(target) == "string" and type(f) == "table")
    exports[#exports + 1] = target .. " " .. f.name .. " x" .. f.count
    return f.count
  end,
})
add("player_detector_0", { "player_detector" }, {
  getOnlinePlayers = function() return { "Voten641", "Steve" } end,
  getPlayersInRange = function(r) assert(type(r) == "number") return { "Voten641" } end,
})
add("environment_detector_0", { "environment_detector" }, {
  isRaining = function() return true end, isThunder = function() return false end,
  getMoon = function() return 3, "Waning crescent" end, getBiome = function() return "minecraft:plains" end,
  getDimension = function() return "minecraft:overworld" end, getRadiationRaw = function() return radiation end,
})
radiation = 0.0000001
local chatMsgs = {}
add("chat_box_0", { "chat_box" }, {
  sendMessage = function(msg, opts) assert(type(opts) == "table") chatMsgs[#chatMsgs + 1] = msg; return true end,
})
notes = {}
add("speaker_0", { "speaker" }, { playNote = function(i, v, p) assert(v <= 3 and p <= 24) notes[#notes + 1] = i return true end })
local relayOut = {}
add("redstone_relay_0", { "redstone_relay" }, {
  setOutput = function(s, v) relayOut[s] = v end, getOutput = function(s) return relayOut[s] == true end, getInput = function() return false end,
})
stress = 512
add("Create_Stressometer_0", { "Create_Stressometer" }, { getStress = function() return stress end, getStressCapacity = function() return 1024 end })
rpm = 0
add("Create_RotationSpeedController_0", { "Create_RotationSpeedController" }, {
  getTargetSpeed = function() return rpm end,
  setTargetSpeed = function(v) assert(v == math.floor(v), "setTargetSpeed wymaga int") rpm = v end,
})
limits = { energy_detector_0 = 1000, fluid_detector_0 = 500 }
local function detector(name, t, rate)
  add(name, { t }, {
    getTransferRate = function() return rate end,
    getTransferRateLimit = function() return limits[name] end,
    setTransferRateLimit = function(v) limits[name] = v end,
    getMaxTransferRate = function() return 1000000 end,
  })
end
detector("fluid_detector_0", "fluid_detector", 250)
sourceTerm = makeTerm(20, 2)
add("create_source_0", { "create_source" }, sourceTerm)
add("back", { "modem" }, { isWireless = function() return true end })
add("create_target_0", { "create_target" }, { getLine = function() return "Hello Create" end })
add("minecraft:chest_0", { "minecraft:chest", "inventory" }, {
  size = function() return 27 end, list = function() return { [1] = { name = "x", count = 1 }, [5] = { name = "y", count = 2 } } end,
})
detector("energy_detector_0", "energy_detector", 2048)
add("chat_box_disabled", { "chat_box" }, { peripheralDisabled = function() return true end })

local MODS = { "overview", "energy", "fission", "turbine", "boiler", "fusion", "storage", "tanks", "machines", "players", "clock", "control", "alarms",
  "mesearch", "autocraft", "create", "flow", "radiation", "history" }
local MONNAME = {}
for i, id in ipairs(MODS) do MONNAME[id] = "monitor_" .. i end
local mons = {}
for i, id in ipairs(MODS) do mons[id] = monitor("monitor_" .. i, i % 2 == 0 and 39 or 29, i % 3 == 0 and 26 or 19) end
local bigMon = monitor("monitor_big", 79, 38)
local menuMon = monitor("monitor_menu", 51, 26)
local tiny = monitor("monitor_tiny", 15, 10)
local picker = monitor("monitor_new", 29, 19)

peripheral = {}
function peripheral.getNames() local r = {} for n in pairs(devs) do r[#r + 1] = n end table.sort(r) return r end
function peripheral.getType(n) local d = devs[n]; if d then return table.unpack(d.types) end end
function peripheral.wrap(n) return devs[n] and devs[n].m end
function peripheral.find(t, filter)
  for _, n in ipairs(peripheral.getNames()) do
    for _, ty in ipairs(devs[n].types) do
      if ty == t and (not filter or filter(n, devs[n].m)) then return devs[n].m end
    end
  end
end
function peripheral.getName(m) for n, d in pairs(devs) do if d.m == m then return n end end end

mekanismEnergyHelper = { joulesToFE = function(j) return math.floor(j / 2.5) end }
local rsOut = {}
redstone = { setOutput = function(s, v) rsOut[s] = v end, getInput = function() return false end }
shell = { run = function() return true end }
rednetSent = {}
local openModems = {}
rednet = {
  open = function(n) openModems[n] = true end,
  isOpen = function(n) return openModems[n] == true end,
  host = function(p, h) assert(p and h) rednetHost = h end,
  unhost = function() rednetHost = nil end,
  send = function(id, msg, proto) rednetSent[#rednetSent + 1] = { id = id, msg = msg, proto = proto } return true end,
}
http = {}

-- konfiguracja startowa: kazdy modul na swoim monitorze
os.execute("mkdir -p " .. TMP .. "/smart/data")
local cfg = { monitors = {}, controls = {
  { label = "Lampy", target = "redstone_relay_0", side = "top", mode = "toggle", state = false, color = "yellow", tags = "energia" },
  { label = "Brama", target = "computer", side = "back", mode = "pulse", state = false, color = "lime" },
  { label = "Zasilanie reaktora", target = "redstone_relay_0", side = "left", mode = "toggle", state = false, color = "lime",
    link = "fissionReactorLogicAdapter_0", tags = "energia" },
  { label = "Pompa uranu", target = "redstone_relay_0", side = "right", mode = "toggle", state = false, color = "lime",
    link = "powah:reactor_part_0", linkSync = false },
}, alarms = { chat = { enabled = true, player = "Voten641", prefix = "Baza" } } }
for i, id in ipairs(MODS) do cfg.monitors["monitor_" .. i] = { module = id, scale = 1, accent = "cyan", opts = {} } end
cfg.monitors.monitor_big = { module = "energy", scale = 0.5, accent = "orange", opts = {} }
cfg.tags = { ["powah:energy_cell_0"] = "energia" }
cfg.monitors[MONNAME.energy].opts = { avg = 30 }
cfg.monitors[MONNAME.mesearch].opts = { target = "@up" }
cfg.autocraft = { enabled = true, bridge = "auto", every = 1, items = {
  { name = "minecraft:item_3", label = "", keep = 1000, batch = 64, enabled = true },
  { name = "minecraft:item_40", label = "Pelny", keep = 10, batch = 64, enabled = true },
  { name = "minecraft:nopattern", label = "", keep = 5, batch = 64, enabled = true },
} }
cfg.remote = { enabled = true, pin = "1234" }
cfg.theme = os.getenv("SMART_THEME") or "modern"
cfg.monitors.monitor_menu = { module = "menu", scale = 1, accent = "cyan", opts = { lock = true, lockAfter = 120 } }
cfg.history = { interval = 1, points = 100 }
cfg.monitors.monitor_tiny = { module = "fission", scale = 0.5, accent = "red", opts = {} }
local f = io.open(TMP .. "/smart/data/config.lua", "w"); f:write(textutils.serialize(cfg)); f:close()

---------------------------------------------------------------------------
-- Scenariusz
---------------------------------------------------------------------------
local step = 0
local failures = {}
local function check(cond, msg) if not cond then failures[#failures + 1] = msg end end
local function touchText(monName, mon, text)
  local x, y = findText(mon, text)
  check(x ~= nil, "nie znaleziono '" .. text .. "' na " .. monName)
  if x then os.queueEvent("monitor_touch", monName, x + 1, y) end
end
local function touchLast(id, text)
  local mon = mons[id]
  for y = #mon._t.lines, 1, -1 do
    local x = mon._t.lines[y]:find(text, 1, true)
    if x then os.queueEvent("monitor_touch", MONNAME[id], x, y) return end
  end
  check(false, "nie znaleziono (od dolu) '" .. text .. "' na " .. id)
end
local function touchBelow(mon, monName, anchor, text)
  local ax, ay = findText(mon, anchor)
  check(ax ~= nil, "brak '" .. anchor .. "' na " .. monName)
  if not ax then return end
  for y = ay, math.min(ay + 5, #mon._t.lines) do
    local x = mon._t.lines[y]:find(text, 1, true)
    if x then os.queueEvent("monitor_touch", monName, x + 1, y) return end
  end
  check(false, "brak '" .. text .. "' pod '" .. anchor .. "' na " .. monName)
end
local function typeText(str)
  for ch in str:gmatch(".") do os.queueEvent("char", ch) end
  os.queueEvent("key", keys.enter)
end
-- klawisz klawiatury ekranowej: szukamy wiersza klawiatury i litery w nim
local function touchKey(mon, monName, ch)
  local rowsPat = { "1[^%w]+2[^%w]+3", "q[^%w]+w[^%w]+e", "a[^%w]+s[^%w]+d", "z[^%w]+x[^%w]+c" }
  for y = #mon._t.lines, 1, -1 do
    local line = mon._t.lines[y]
    for _, pat in ipairs(rowsPat) do
      if line:find(pat) then
        local x = line:find(ch, 1, true)
        if x then os.queueEvent("monitor_touch", monName, x, y) return end
      end
    end
  end
  check(false, "klawiatura ekranowa: brak klawisza '" .. ch .. "'")
end
-- przycisk "Wyczysc" w oknie wpisywania (ten obok OK, nie np. "Wyczysc historie" w liscie)
local function clickInputClear()
  for y, line in ipairs(computerTerm._t.lines) do
    if line:find("OK", 1, true) and line:find("Anuluj", 1, true) then
      local x = line:find("Wyczysc", 1, true)
      if x then os.queueEvent("mouse_click", 1, x + 1, y) return end
    end
  end
  check(false, "GUI: brak przycisku Wyczysc w oknie wpisywania")
end
local function click(text)
  local x, y = findText(computerTerm, text)
  check(x ~= nil, "GUI: nie znaleziono '" .. text .. "'")
  if x then os.queueEvent("mouse_click", 1, x + 1, y) end
end

local actions = {}
local function at(n, fn) actions[n] = actions[n] or {}; table.insert(actions[n], fn) end
local tick = 0
local lastTick = 0

-- kroki wykonywane po kolejnych odswiezeniach (smart_tick)
at(2, function()
  touchText("monitor_new", picker, "Energia")              -- wybor modulu na nowym monitorze
  touchText("monitor_3", mons.fission, "START")
end)
at(3, function()
  check(reactor.active, "reaktor nie wystartowal z monitora")
  touchText("monitor_3", mons.fission, "+1")
  touchText("monitor_12", mons.control, "Lampy")
  touchText("monitor_7", mons.storage, os.getenv("SMART_THEME") == "classic" and "v" or string.char(31)) -- strzalka w dol
end)
at(4, function()
  check(reactor.burn == 6, "burn rate nie zmienil sie: " .. tostring(reactor.burn))
  check(relayOut.top == true, "przelacznik nie wlaczyl relay")
  reactor.temp = 1300 -- przegrzanie -> SCRAM
end)
at(6, function()
  check(not reactor.active, "brak SCRAM przy przegrzaniu")
  check(findText(mons.fission, "START") == nil, "po SCRAM powinien zniknac START")
  check(findText(mons.fission, "RESET") ~= nil, "po SCRAM brak przycisku RESET")
end)
at(7, function()
  reactor.temp = 400
  touchText("monitor_3", mons.fission, "RESET")
end)
at(8, function()
  check(findText(mons.fission, "START") ~= nil, "po RESET brak START")
  touchText("monitor_6", mons.fusion, "Wtrysk +2")
  click("Monitory  - co gdzie")
end)
local function back() os.queueEvent("key", keys.backspace) end
local seq = {
  function() click("monitor_3") end,
  function() click("Identyfikuj") end,
  back, back,
  function() click("Urzadzenia - nazwy") end,
  function() os.queueEvent("mouse_scroll", 1, 10, 10) end,
  back,
  function() click("Alarmy i automatyka") end,
  function() os.queueEvent("mouse_scroll", 30, 10, 10) end,
  back,
  function() click("Panel sterowania (") end,
  function() click("+ Dodaj") end,
  function() click("Nazwa") end,
  clickInputClear,
  function() typeText("Pompa") end,
  back, back,
  function() click("Ustawienia i") end,
  function() click("Odswiezanie") end,
  clickInputClear,
  function() typeText("2") end,
  back,
  function() click("Dziennik") end,
  back,
  function() click("Autocrafting (ME") end,
  back,
  function() click("Wyswietlacze Create") end,
  function() click("create_source_0") end,
  back, back,
  function() click("Pilot (Pocket") end,
  back,
  function() click("Wyjdz do konsoli") end,
}
for i, fn in ipairs(seq) do at(8 + i, fn) end
at(8 + #seq + 5, function() check(false, "GUI nie zakonczylo sie - wymuszam terminate"); os.queueEvent("terminate") end)

-- energia spada -> sredni bilans ujemny i czas do rozladowania
for t = 2, 12 do at(t, function() matrixE = matrixE - 5e9 end) end
at(9, function()
  check(findText(mons.energy, "Do rozladowania") ~= nil, "brak czasu do rozladowania ze sredniego bilansu")
  check(findText(mons.energy, "Bilans sr.") ~= nil, "brak sredniego bilansu")
end)
-- wyszukiwarka: litery z klawiatury, wybor, wydanie 64
at(3, function() touchLast("mesearch", "P") end)
at(4, function() touchLast("mesearch", "R") end)
at(5, function()
  check(findText(mons.mesearch, "pr") ~= nil, "zapytanie nie wpisane")
  touchText(MONNAME.mesearch, mons.mesearch, "Przedmiot 40")
end)
at(6, function() touchLast("mesearch", "64") end)
at(7, function() check(exports[1] == "@up minecraft:item_40 x64", "exportItem: " .. tostring(exports[1])) end)
-- Create: +16 RPM, potem przeciazenie
at(3, function() touchText(MONNAME.create, mons.create, "+16") end)
at(5, function() check(rpm == 16, "setTargetSpeed nie zadzialal: " .. rpm); stress = 2000 end)
at(7, function() check(findText(mons.create, "PRZECIAZ") ~= nil, "brak informacji o przeciazeniu") end)
-- detektory: x2
at(3, function() touchText(MONNAME.flow, mons.flow, "x2") end)
at(5, function() check(limits.energy_detector_0 == 2000 or limits.fluid_detector_0 == 1000, "limit detektora nie zmieniony") end)
-- promieniowanie
at(4, function() radiation = 0.01 end)
at(7, function() check(findText(mons.radiation, "MEDIUM") ~= nil, "promieniowanie: brak poziomu MEDIUM") end)
-- pilot rednet: status, zly PIN, start reaktora
at(3, function()
  os.queueEvent("rednet_message", 7, { cmd = "status", pin = "1234", id = 1 }, "smart_atm10")
  os.queueEvent("rednet_message", 7, { cmd = "status", pin = "0000", id = 2 }, "smart_atm10")
end)
at(5, function()
  local r1, r2
  for _, m in ipairs(rednetSent) do
    if m.msg.id == 1 then r1 = m.msg end
    if m.msg.id == 2 then r2 = m.msg end
  end
  check(r1 and r1.ok and r1.status and #r1.status.reactors == 1, "pilot: brak poprawnego statusu")
  check(r2 and not r2.ok and r2.err == "Zly PIN", "pilot: zly PIN nie odrzucony")
end)
-- menu na monitorze: blokada PIN, nawigacja, klawiatura ekranowa
at(2, function()
  check(findText(menuMon, "Wpisz PIN") ~= nil, "menu monitora: brak blokady PIN")
  for _, k in ipairs({ "1", "2", "3", "4", "OK" }) do touchText("monitor_menu", menuMon, k) end
end)
at(3, function()
  check(findText(menuMon, "Monitory  - co gdzie") ~= nil, "menu monitora: nie odblokowano / brak menu")
  touchText("monitor_menu", menuMon, "Ustawienia i")
end)
at(4, function() touchText("monitor_menu", menuMon, "Nazwa bazy") end)
at(5, function()
  check(findText(menuMon, "spacja") ~= nil, "menu monitora: brak klawiatury ekranowej")
  for y, line in ipairs(menuMon._t.lines) do
    if line:find("OK", 1, true) and line:find("Anuluj", 1, true) then
      local x = line:find("Wyczysc", 1, true)
      if x then os.queueEvent("monitor_touch", "monitor_menu", x + 1, y) end
    end
  end
end)
at(6, function()
  oskShot = dump(menuMon, "monitor_menu: wpisywanie (klawiatura ekranowa)")
  for _, ch in ipairs({ "b", "a", "z", "a" }) do touchKey(menuMon, "monitor_menu", ch) end
end)
at(7, function()
  check(findText(menuMon, "baza_") ~= nil, "menu monitora: tekst nie wpisany z klawiatury ekranowej")
  for y, line in ipairs(menuMon._t.lines) do
    if line:find("Wyczysc", 1, true) and line:find("Anuluj", 1, true) then
      local x = line:find("OK", 1, true)
      if x then os.queueEvent("monitor_touch", "monitor_menu", x, y) end
    end
  end
end)
at(8, function()
  menuShot = dump(menuMon, "monitor_menu (menu na monitorze)")
  touchText("monitor_menu", menuMon, os.getenv("SMART_THEME") == "classic" and "<" or string.char(17)) -- przycisk wstecz
end)
-- menu zdalne (serwer): klatka, klikniecie w wiersz
at(3, function()
  os.queueEvent("rednet_message", 8, { cmd = "menu", action = "frame", w = 26, h = 19, pin = "1234", id = 11 }, "smart_atm10")
  os.queueEvent("rednet_message", 8, { cmd = "menu", action = "frame", w = 26, h = 19, pin = "9999", id = 13 }, "smart_atm10")
end)
local function reply(id) for _, m in ipairs(rednetSent) do if m.msg.id == id then return m.msg end end end
at(4, function()
  local r = reply(11)
  check(r and r.ok and r.lines and #r.lines == 19, "menu zdalne: brak klatki 26x19")
  if r and r.lines then
    local t = { "+--------------------------+ klatka menu dla pilota (26x19)" }
    for _, l in ipairs(r.lines) do t[#t + 1] = "|" .. l[1] .. "|" end
    remoteShot = table.concat(t, "\n")
  end
  local rb = reply(13)
  check(rb and not rb.ok and rb.err == "Zly PIN", "menu zdalne: zly PIN nie odrzucony")
  if r and r.lines then
    check(#r.lines[1][1] == 26 and #r.lines[1][2] == 26 and #r.lines[1][3] == 26, "menu zdalne: zla szerokosc linii blit")
    for y, l in ipairs(r.lines) do
      if l[1]:find("Monitory  -", 1, true) then
        os.queueEvent("rednet_message", 8, { cmd = "menu", action = "click", x = 5, y = y, w = 26, h = 19, pin = "1234", id = 12 }, "smart_atm10")
        break
      end
    end
  end
end)
at(5, function()
  local r = reply(12)
  check(r and r.ok and r.lines and r.lines[1][1]:find("Monitory"), "menu zdalne: klikniecie nie otworzylo ekranu Monitory")
end)
-- duzy ekran komputera: panele z modulami obok menu, klikanie w panel
if BIG then
  local function findRight(text, minX)
    for y, line in ipairs(computerTerm._t.lines) do
      local x = line:find(text, minX or 1, true)
      if x and x > (minX or 1) then return x, y end
    end
  end
  at(3, function()
    local menuW = math.max(51, math.floor(TW * 0.3))
    check(findText(computerTerm, "Monitory  - co gdzie") ~= nil, "duzy ekran: brak menu")
    local ex, ey = findRight("Zrodla", menuW + 1)
    check(ex ~= nil, "duzy ekran: brak panelu Energia z zakladkami")
    check(findRight("Alarmy", menuW + 1) ~= nil, "duzy ekran: brak panelu Alarmy")
    if ex then os.queueEvent("mouse_click", 1, ex + 1, ey) end
    bigShot = dump(computerTerm, "KOMPUTER " .. TW .. "x" .. TH)
  end)
  at(4, function()
    check(findText(computerTerm, "Produkcja razem") ~= nil, "duzy ekran: klikniecie w panel nie przelaczylo zakladki")
  end)
end
-- zakladka Zrodla na ekranie energii (monitor_big)
at(10, function() touchText("monitor_big", bigMon, "Zrodla") end)
at(11, function()
  for _, t in ipairs({ "Produkcja razem", "fissionReactorLogicAdapter_0", "fusionReactorLogicAdapter_0", "gasBurningGenerator_0",
                       "powah:energy_cell_0", "powah:reactor_part_0", "turbineValve_0", "Przelaczniki", "Lampy" }) do
    check(findText(bigMon, t) ~= nil, "Zrodla: brak '" .. t .. "'")
  end
  check(findText(bigMon, "crusher_0") == nil, "Zrodla: kruszarka nie jest zrodlem")
  check(findText(bigMon, "BRAK DANYCH") ~= nil, "Zrodla: Reactor Port powinien miec 'BRAK DANYCH'")
  check(findText(bigMon, "nieuformowany") == nil or findText(bigMon, "turbineValve_0") ~= nil, "Zrodla: falszywe 'nieuformowany'")
  -- przelacznik polaczony z reaktorem: w bloku reaktora, nie w sekcji Przelaczniki
  check(findText(bigMon, "+ Zasilanie reaktora WYL") ~= nil, "polaczony przelacznik nie widoczny w bloku reaktora")
  local _, hy = findText(bigMon, "Przelaczniki")
  local _, zy = findText(bigMon, "Zasilanie reaktora")
  check(hy and zy and zy < hy, "polaczony przelacznik wyswietla sie osobno")
  check(findText(bigMon, "Pompa uranu [WYL]") ~= nil, "przelacznik bez 'razem' powinien miec wlasny przycisk w bloku")
  touchBelow(bigMon, "monitor_big", "gasBurningGenerator_0", "WLACZ")
  touchBelow(bigMon, "monitor_big", "fissionReactorLogicAdapter_0", "WLACZ")
  touchBelow(bigMon, "monitor_big", "powah:reactor_part_0", "Pompa uranu [")
  notesBefore = #notes
end)
at(12, function()
  check(genMode == "DISABLED", "generator nie wlaczony (tryb " .. genMode .. ")")
  check(reactor.active, "reaktor nie wlaczony z zakladki Zrodla")
  check(relayOut.left == true, "przelacznik polaczony z reaktorem nie wlaczyl sie razem z nim")
  check(relayOut.right == true, "przycisk Pompa uranu w bloku Powah nie zadzialal")
  local pl = false
  for k = notesBefore + 1, #notes do if notes[k] == "pling" then pl = true end end
  check(pl, "brak dzwieku potwierdzenia")
  check(findText(bigMon, "Wlaczono") ~= nil, "brak zielonego paska potwierdzenia")
  touchBelow(bigMon, "monitor_big", "Przelaczniki", "Lampy")
  touchBelow(bigMon, "monitor_big", "fissionReactorLogicAdapter_0", "WYLACZ")
end)
at(13, function()
  check(relayOut.top == false, "przelacznik Lampy nie przelaczony z zakladki Zrodla")
  check(not reactor.active, "reaktor nie wylaczony z zakladki Zrodla")
  check(relayOut.left == false, "przelacznik polaczony nie wylaczyl sie razem z reaktorem")
  check(findText(bigMon, "25.0kFE/t") ~= nil or findText(bigMon, "10.0kFE/t") ~= nil, "brak produkcji generatora")
  screensExtra = dump(bigMon, "monitor_big: energia / zakladka Zrodla")
end)
-- historia
at(10, function() check(findText(mons.history, "Brak danych") == nil, "historia: brak danych mimo probek") end)
-- wyswietlacz Create
at(4, function() check(sourceTerm._t.lines[1]:find("Energia") ~= nil, "Source Block: brak linii energii: " .. sourceTerm._t.lines[1]) end)

local screens = {}
scriptHook = function()
  -- liczymy zdarzenia smart_tick w kolejce
  for _, ev in ipairs(queue) do
    if ev[1] == "smart_tick" and not ev.seen then ev.seen = true; tick = tick + 1 end
  end
  if tick ~= lastTick then
    lastTick = tick
    for _, fn in ipairs(actions[tick] or {}) do fn() end
    if tick == 10 then screens[#screens + 1] = dump(computerTerm, "GUI monitory") end
    if tick == 17 then screens[#screens + 1] = dump(computerTerm, "GUI alarmy") end
    if tick == 8 then
      screens[#screens + 1] = dump(mons.mesearch, "monitor: mesearch (po wyborze)")
      screens[#screens + 1] = dump(mons.history, "monitor: history")
      screens[#screens + 1] = dump(mons.energy, "monitor: energy (sredni bilans)")
      screens[#screens + 1] = dump(sourceTerm, "create_source_0")
    end
    if tick == 3 then
      screens[#screens + 1] = dump(computerTerm, "GUI glowne")
      for _, id in ipairs(MODS) do if id ~= "mesearch" and id ~= "history" then screens[#screens + 1] = dump(mons[id], "monitor: " .. id) end end

      screens[#screens + 1] = dump(tiny, "monitor_tiny (fission, 0.5)")
      screens[#screens + 1] = dump(picker, "monitor_new (picker)")
    end
  end
end

local ok, err = pcall(dofile, ROOT .. "/smart/main.lua")
check(ok, "main.lua zakonczyl sie bledem: " .. tostring(err))

-- zrzuty ekranow
local out = {}
out[#out + 1] = dump(computerTerm, "KOMPUTER (po wyjsciu)")
for _, s in ipairs(screens) do out[#out + 1] = s end
if screensExtra then out[#out + 1] = screensExtra end
if oskShot then out[#out + 1] = oskShot end
if menuShot then out[#out + 1] = menuShot end
if bigShot then out[#out + 1] = bigShot end
if remoteShot then out[#out + 1] = remoteShot end
-- monitory zrzucane przed wyjsciem nie sa dostepne (main czysci je), wiec rysujemy ponownie ponizej
local fo = io.open(TMP .. "/screens.txt", "w"); fo:write(table.concat(out, "\n\n")); fo:close()

-- weryfikacja zapisanej konfiguracji
local saved = textutils.unserialize(io.open(TMP .. "/smart/data/config.lua"):read("a"))
check(saved and saved.monitors.monitor_new and saved.monitors.monitor_new.module == "energy", "wybor modulu z monitora nie zapisany")
check(saved and saved.refresh == 2, "zmiana odswiezania z GUI nie zapisana")
check(saved and saved.title == "baza", "menu monitora: nazwa bazy nie zapisana (" .. tostring(saved and saved.title) .. ")")
local foundPompa = false
for _, c in ipairs(saved and saved.controls or {}) do if c.label == "Pompa" then foundPompa = true end end
check(foundPompa, "nowy przelacznik nie zapisany")
check(#chatMsgs > 0, "brak powiadomien na chat")
local hasScram = false
for _, c in ipairs(calls) do if c == "scram" then hasScram = true end end
check(hasScram, "nie wywolano scram()")
check(crafts[1] == "minecraft:item_3 x64", "autocraft: zle zlecenie: " .. tostring(crafts[1]))
for _, c in ipairs(crafts) do check(not c:find("item_40"), "autocraft zlecil przedmiot ktorego jest dosc") end
local hasRad = false
for _, m in ipairs(chatMsgs) do if m:find("Promieniowanie") then hasRad = true end end
check(hasRad, "brak alarmu promieniowania na chat")
check(io.open(TMP .. "/smart/data/history.lua") ~= nil, "historia nie zapisana na dysk")
check(rednetHost ~= nil, "rednet.host nie wywolany")

---------------------------------------------------------------------------
-- Faza 2: pilot na Pocket Computerze
---------------------------------------------------------------------------
pocket = {}
local pocketTerm = BIG and makeTerm(TW, TH) or makeTerm(26, 20)
-- klatka menu pilota: max 80x40, wysrodkowana
local PFW, PFH = math.min(pocketTerm._t.w, 80), math.min(pocketTerm._t.h - 1, 40)
local POX, POY = math.floor((pocketTerm._t.w - PFW) / 2), math.floor((pocketTerm._t.h - 1 - PFH) / 2)
current = pocketTerm
for k in pairs(queue) do queue[k] = nil end
for k in pairs(timers) do timers[k] = nil end
readQueue = { "1", "1234" }
local pocketSent = {}
local replies = {}
menuActions = {}
local fakeStatus = {
  title = "Baza", time = "12:00", energy = { f = 0.5, stored = 1e9, cap = 2e9 },
  reactors = { { name = "fissionReactorLogicAdapter_0", label = "Reaktor A", on = false, temp = 400, burn = 5 } },
  controls = { { label = "Lampy", state = false, mode = "toggle" } },
  alarms = { { text = "Test alarmu", level = "warn" } },
}
rednet.lookup = function(p) assert(p == "smart_atm10") return 5 end
rednet.send = function(id, msg, proto)
  assert(id == 5 and proto == "smart_atm10")
  pocketSent[#pocketSent + 1] = msg
  if msg.cmd == "menu" then
    menuActions[#menuActions + 1] = msg
    local lines = {}
    for y = 1, msg.h do
      local t = y == 1 and "MENU BAZY" or ""
      t = (t .. string.rep(" ", msg.w)):sub(1, msg.w)
      lines[y] = { t, string.rep("0", msg.w), string.rep("f", msg.w) }
    end
    replies[#replies + 1] = { ok = true, id = msg.id, lines = lines }
    return true
  end
  replies[#replies + 1] = msg.pin == "1234" and { ok = true, id = msg.id, status = fakeStatus } or { ok = false, id = msg.id, err = "Zly PIN" }
  return true
end
rednet.receive = function(proto, timeout)
  local r = table.remove(replies, 1)
  if r then return 5, r, proto end
  sleep(timeout or 1)
end
local steps = {
  { "Reak", function(x, y) os.queueEvent("mouse_click", 1, x, y) end },
  { "START", function(x, y) pocketShot = dump(pocketTerm, "POCKET: reaktory"); os.queueEvent("mouse_click", 1, x, y) end },
  { "Prze", function(x, y) os.queueEvent("mouse_click", 1, x, y) end },
  { "Lampy", function(x, y) os.queueEvent("mouse_click", 1, x, y) end },
  { "Alar", function(x, y) os.queueEvent("mouse_click", 1, x, y) end },
  { "Test alarmu", function() end },
  { "Menu", function(x, y) os.queueEvent("mouse_click", 1, x, y) end },
  { "MENU BAZY", function() os.queueEvent("mouse_click", 1, POX + 3, POY + 5) end },
  { "MENU BAZY", function() os.queueEvent("char", "x") end },
  { "<< Pilot", function(x, y) pocketMenuShot = dump(pocketTerm, "POCKET: menu bazy"); os.queueEvent("mouse_click", 1, x, y) end },
  { "Reaktory", function() os.queueEvent("key", keys.q) end },
}
local si, guard = 1, 0
scriptHook = function()
  guard = guard + 1
  if guard > 2000 then error("pilot: zawieszenie") end
  local stp = steps[si]
  if stp and #queue == 0 then
    local x, y = findText(pocketTerm, stp[1])
    if x then si = si + 1; stp[2](x + 1, y) end
  end
end
local pok, perr = pcall(parallel.waitForAny, function() dofile(ROOT .. "/smart/pocket.lua") end)
check(pok, "pocket.lua blad: " .. tostring(perr))
check(si > #steps, "pilot: nie przeszedl wszystkich krokow (krok " .. si .. ")")
local cmds = {}
for _, m in ipairs(pocketSent) do cmds[#cmds + 1] = m.cmd end
local joined = table.concat(cmds, ",")
check(joined:find("start") and joined:find("control"), "pilot: nie wyslal komend start/control: " .. joined)
check(pocketSent[1] and pocketSent[1].pin == "1234", "pilot: zly PIN w zapytaniu")
check(io.open(TMP .. "/smart/data/pocket.lua") ~= nil, "pilot: konfiguracja nie zapisana")
local acts = {}
for _, m in ipairs(menuActions) do acts[#acts + 1] = m.action .. (m.action == "click" and ("@" .. m.x .. "," .. m.y) or "") .. (m.ch and (":" .. m.ch) or "") end
local actStr = table.concat(acts, " ")
check(actStr:find("frame") and actStr:find("click@3,5") and actStr:find("char:x"), "pilot menu: brak akcji (" .. actStr .. ")")
check(menuActions[1] and menuActions[1].h == PFH and menuActions[1].w == PFW,
  "pilot menu: zly rozmiar zadania " .. tostring(menuActions[1] and menuActions[1].w) .. "x" .. tostring(menuActions[1] and menuActions[1].h))
print("Pilot menu: " .. actStr)
out[#out + 1] = pocketShot or dump(pocketTerm, "POCKET")
fo = io.open(TMP .. "/screens.txt", "w"); fo:write(table.concat(out, "\n\n")); fo:close()
print("Pilot wyslal: " .. joined)

if previewFile then previewFile:close() end
print("Wywolania: " .. table.concat(calls, ", "))
print("Chat: " .. table.concat(chatMsgs, " | "))
io.stdout:write(table.concat(printed, "\n"), "\n")
if #failures > 0 then
  io.stdout:write("\nBLEDY (" .. #failures .. "):\n - " .. table.concat(failures, "\n - ") .. "\n")
  os.exit(1)
end
io.stdout:write("\nOK - wszystkie testy przeszly. Zrzuty: " .. TMP .. "/screens.txt\n")
