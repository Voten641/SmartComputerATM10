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
keys = { backspace = 14, up = 200, down = 208, pageUp = 201, pageDown = 209, enter = 28 }

---------------------------------------------------------------------------
-- terminal z buforem
---------------------------------------------------------------------------
local function makeTerm(w, h, isColor)
  local t = { w = w, h = h, cx = 1, cy = 1, fg = colors.white, bg = colors.black, lines = {}, bgs = {} }
  local function blank()
    t.lines, t.bgs = {}, {}
    for y = 1, t.h do t.lines[y] = string.rep(" ", t.w); t.bgs[y] = {} end
  end
  blank()
  local o = {}
  o._t = t
  function o.getSize() return t.w, t.h end
  function o.setCursorPos(x, y) t.cx, t.cy = math.floor(x), math.floor(y) end
  function o.getCursorPos() return t.cx, t.cy end
  function o.setTextColor(c) assert(type(c) == "number", "zly kolor"); t.fg = c end
  function o.setBackgroundColor(c) assert(type(c) == "number", "zly kolor tla"); t.bg = c end
  o.setTextColour, o.setBackgroundColour = o.setTextColor, o.setBackgroundColor
  function o.getTextColor() return t.fg end
  function o.getBackgroundColor() return t.bg end
  function o.isColor() return isColor ~= false end
  o.isColour = o.isColor
  function o.setCursorBlink() end
  function o.getCursorBlink() return false end
  function o.write(s)
    s = tostring(s)
    local y = t.cy
    if y >= 1 and y <= t.h then
      local line = t.lines[y]
      for i = 1, #s do
        local x = t.cx + i - 1
        if x >= 1 and x <= t.w then
          line = line:sub(1, x - 1) .. s:sub(i, i) .. line:sub(x + 1)
          t.bgs[y][x] = t.bg
        end
      end
      t.lines[y] = line
    end
    t.cx = t.cx + #s
  end
  function o.blit(s) o.write(s) end
  function o.clear() blank() end
  function o.clearLine() t.lines[t.cy] = string.rep(" ", t.w) end
  function o.scroll(n)
    for _ = 1, n do table.remove(t.lines, 1); t.lines[#t.lines + 1] = string.rep(" ", t.w) end
  end
  function o.redraw() end
  function o.getPaletteColor() return 0, 0, 0 end
  function o.setPaletteColor() end
  return o
end

local function dump(o, title)
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

local computerTerm = makeTerm(51, 19)
local current = computerTerm
term = setmetatable({}, { __index = function(_, k)
  if k == "current" then return function() return current end end
  if k == "redirect" then return function(t) local old = current; current = t; return old end end
  if k == "native" then return function() return computerTerm end end
  return function(...) return current[k](...) end
end })

window = {}
function window.create(parent, x, y, w, h, visible)
  local win = makeTerm(w, h, parent.isColor())
  local vis = visible ~= false
  local function flush()
    if not vis then return end
    for yy = 1, h do
      parent.setCursorPos(x, y + yy - 1)
      parent.write(win._t.lines[yy])
    end
  end
  local origWrite = win.write
  function win.write(s) origWrite(s); if vis then flush() end end
  function win.setVisible(v) vis = v; if v then flush() end end
  function win.isVisible() return vis end
  function win.reposition() end
  function win.getPosition() return x, y end
  function win.getLine(yy) return win._t.lines[yy] end
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
add("fissionReactorPort_0", { "fissionReactorPort" }, fissionMethods) -- ten sam reaktor -> duplikat

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
for i = 1, 40 do items[i] = { name = "minecraft:item_" .. i, displayName = "Przedmiot " .. i, count = i * 37, isCraftable = i % 5 == 0 } end
add("me_bridge_0", { "me_bridge" }, {
  isConnected = function() return true end, isOnline = function() return true end,
  getItems = function(f) assert(type(f) == "table") return items end,
  getUsedItemStorage = function() return 97000 end, getMaxItemStorage = function() return 100000 end,
  getUsedFluidStorage = function() return 10 end, getMaxFluidStorage = function() return 100 end,
  getStoredEnergy = function() return 1000 end, getEnergyCapacity = function() return 1600 end,
  getEnergyUsage = function() return 55.5 end, getCraftingTasks = function() return { {}, {} } end,
  getCraftingCPUs = function() return { { isBusy = true }, { isBusy = false } } end,
})
add("player_detector_0", { "player_detector" }, {
  getOnlinePlayers = function() return { "Voten641", "Steve" } end,
  getPlayersInRange = function(r) assert(type(r) == "number") return { "Voten641" } end,
})
add("environment_detector_0", { "environment_detector" }, {
  isRaining = function() return true end, isThunder = function() return false end,
  getMoon = function() return 3, "Waning crescent" end, getBiome = function() return "minecraft:plains" end,
  getDimension = function() return "minecraft:overworld" end, getRadiationRaw = function() return 0.00000001 end,
})
local chatMsgs = {}
add("chat_box_0", { "chat_box" }, {
  sendMessage = function(msg, opts) assert(type(opts) == "table") chatMsgs[#chatMsgs + 1] = msg; return true end,
})
add("speaker_0", { "speaker" }, { playNote = function(i, v, p) assert(v <= 3 and p <= 24) return true end })
local relayOut = {}
add("redstone_relay_0", { "redstone_relay" }, {
  setOutput = function(s, v) relayOut[s] = v end, getOutput = function(s) return relayOut[s] == true end, getInput = function() return false end,
})
add("Create_Stressometer_0", { "Create_Stressometer" }, { getStress = function() return 512 end, getStressCapacity = function() return 1024 end })
add("create_target_0", { "create_target" }, { getLine = function() return "Hello Create" end })
add("minecraft:chest_0", { "minecraft:chest", "inventory" }, {
  size = function() return 27 end, list = function() return { [1] = { name = "x", count = 1 }, [5] = { name = "y", count = 2 } } end,
})
add("energy_detector_0", { "energy_detector" }, { getTransferRate = function() return 2048 end })
add("chat_box_disabled", { "chat_box" }, { peripheralDisabled = function() return true end })

local MODS = { "overview", "energy", "fission", "turbine", "boiler", "fusion", "storage", "tanks", "machines", "players", "clock", "control", "alarms" }
local mons = {}
for i, id in ipairs(MODS) do mons[id] = monitor("monitor_" .. i, i % 2 == 0 and 39 or 29, i % 3 == 0 and 26 or 19) end
local bigMon = monitor("monitor_big", 79, 38)
local tiny = monitor("monitor_tiny", 15, 10)
local picker = monitor("monitor_new", 29, 19)

peripheral = {}
function peripheral.getNames() local r = {} for n in pairs(devs) do r[#r + 1] = n end table.sort(r) return r end
function peripheral.getType(n) local d = devs[n]; if d then return table.unpack(d.types) end end
function peripheral.wrap(n) return devs[n] and devs[n].m end

mekanismEnergyHelper = { joulesToFE = function(j) return math.floor(j / 2.5) end }
local rsOut = {}
redstone = { setOutput = function(s, v) rsOut[s] = v end, getInput = function() return false end }
shell = { run = function() return true end }
http = {}

-- konfiguracja startowa: kazdy modul na swoim monitorze
os.execute("mkdir -p " .. TMP .. "/smart/data")
local cfg = { monitors = {}, controls = {
  { label = "Lampy", target = "redstone_relay_0", side = "top", mode = "toggle", state = false, color = "yellow" },
  { label = "Brama", target = "computer", side = "back", mode = "pulse", state = false, color = "lime" },
}, alarms = { chat = { enabled = true, player = "Voten641", prefix = "Baza" } } }
for i, id in ipairs(MODS) do cfg.monitors["monitor_" .. i] = { module = id, scale = 1, accent = "cyan", opts = {} } end
cfg.monitors.monitor_big = { module = "overview", scale = 0.5, accent = "orange", opts = {} }
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
local function click(text)
  local x, y = findText(computerTerm, text)
  check(x ~= nil, "GUI: nie znaleziono '" .. text .. "'")
  if x then os.queueEvent("mouse_click", 1, x + 1, y) end
end

local actions = {}
local function at(n, fn) actions[n] = fn end
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
  touchText("monitor_7", mons.storage, "v")
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
  function() readQueue[1] = "Pompa"; click("Nazwa") end,
  back, back,
  function() click("Ustawienia i") end,
  function() readQueue[1] = "2"; click("Odswiezanie") end,
  back,
  function() click("Dziennik") end,
  back,
  function() click("Wyjdz do konsoli") end,
}
for i, fn in ipairs(seq) do at(8 + i, fn) end
at(8 + #seq + 5, function() check(false, "GUI nie zakonczylo sie - wymuszam terminate"); os.queueEvent("terminate") end)

local screens = {}
scriptHook = function()
  -- liczymy zdarzenia smart_tick w kolejce
  for _, ev in ipairs(queue) do
    if ev[1] == "smart_tick" and not ev.seen then ev.seen = true; tick = tick + 1 end
  end
  if tick ~= lastTick then
    lastTick = tick
    if actions[tick] then actions[tick]() end
    if tick == 10 then screens[#screens + 1] = dump(computerTerm, "GUI monitory") end
    if tick == 17 then screens[#screens + 1] = dump(computerTerm, "GUI alarmy") end
    if tick == 3 then
      screens[#screens + 1] = dump(computerTerm, "GUI glowne")
      for _, id in ipairs(MODS) do screens[#screens + 1] = dump(mons[id], "monitor: " .. id) end
      screens[#screens + 1] = dump(bigMon, "monitor_big (overview, 0.5)")
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
-- monitory zrzucane przed wyjsciem nie sa dostepne (main czysci je), wiec rysujemy ponownie ponizej
local fo = io.open(TMP .. "/screens.txt", "w"); fo:write(table.concat(out, "\n\n")); fo:close()

-- weryfikacja zapisanej konfiguracji
local saved = textutils.unserialize(io.open(TMP .. "/smart/data/config.lua"):read("a"))
check(saved and saved.monitors.monitor_new and saved.monitors.monitor_new.module == "energy", "wybor modulu z monitora nie zapisany")
check(saved and saved.refresh == 2, "zmiana odswiezania z GUI nie zapisana")
check(saved and saved.controls[3] and saved.controls[3].label == "Pompa", "nowy przelacznik nie zapisany")
check(#chatMsgs > 0, "brak powiadomien na chat")
local hasScram = false
for _, c in ipairs(calls) do if c == "scram" then hasScram = true end end
check(hasScram, "nie wywolano scram()")

print("Wywolania: " .. table.concat(calls, ", "))
print("Chat: " .. table.concat(chatMsgs, " | "))
io.stdout:write(table.concat(printed, "\n"), "\n")
if #failures > 0 then
  io.stdout:write("\nBLEDY (" .. #failures .. "):\n - " .. table.concat(failures, "\n - ") .. "\n")
  os.exit(1)
end
io.stdout:write("\nOK - wszystkie testy przeszly. Zrzuty: " .. TMP .. "/screens.txt\n")
