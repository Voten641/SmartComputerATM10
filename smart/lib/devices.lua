-- Smart System: wykrywanie i klasyfikacja peryferiow
-- API zweryfikowane w zrodlach: CC:Tweaked 1.120.2, Advanced Peripherals 0.8.1,
-- Mekanism 10.7, Create 6, CC:C Bridge 1.7.3 (patrz docs/API_NOTES.md)
local U = require("lib.util")

local D = {}

-- znormalizowany typ (U.norm) -> rodzaj
local TYPE_MAP = {
  -- Advanced Peripherals 0.8 (snake_case; norm usuwa "_")
  mebridge = "me",
  rsbridge = "rs",
  playerdetector = "player",
  environmentdetector = "env",
  energydetector = "flowdet",
  fluiddetector = "flowdet",
  gasdetector = "flowdet",
  chatbox = "chat",
  geoscanner = "geo",
  inventorymanager = "invmgr",
  blockreader = "blockreader",
  nbtstorage = "nbt",
  colonyintegrator = "colony",
  distancedetector = "distance",
  -- AP: integracja Powah (typ dodatkowy)
  energycell = "energy",
  endercell = "energy",
  uraninitereactor = "powahreactor",
  furnator = "generator",
  magmator = "generator",
  thermo = "generator",
  solarpanel = "generator",
  -- CC:Tweaked
  redstonerelay = "relay",
  monitor = "monitor",
  speaker = "speaker",
  modem = "modem",
  printer = "printer",
  drive = "drive",
  computer = "computer",
  turtle = "computer",
  -- CC:C Bridge
  redrouter = "relay",
  createtarget = "ctarget",
  createsource = "csource",
  scroller = "scroller",
  -- Create 6
  createstressometer = "stress",
  createspeedometer = "speed",
  createrotationspeedcontroller = "rsc",
  -- Mekanism (camelCase)
  fissionreactorlogicadapter = "fission",
  -- Reactor Porty NIE udostepniaja danych reaktora (Mekanism: exposesMultiblockToComputer = false),
  -- tylko tryb portu (getMode/setMode). Dane reaktora daje wylacznie Logic Adapter.
  fissionreactorport = "fissionport",
  turbinevalve = "turbine",
  boilervalve = "boiler",
  fusionreactorlogicadapter = "fusion",
  fusionreactorport = "fusionport",
  inductionport = "matrix",
  dynamicvalve = "dyntank",
  spsport = "sps",
  thermalevaporationvalve = "evap",
  thermalevaporationcontroller = "evap",
}

D.KINDS = {
  me = "ME Bridge (AE2)",
  rs = "RS Bridge",
  player = "Player Detector",
  env = "Environment Detector",
  flowdet = "Detektor przeplywu",
  chat = "Chat Box",
  geo = "Geo Scanner",
  invmgr = "Inventory Manager",
  blockreader = "Block Reader",
  nbt = "NBT Storage",
  colony = "Colony Integrator",
  distance = "Distance Detector",
  relay = "Redstone Relay",
  ctarget = "Create Target",
  csource = "Create Source",
  scroller = "Scroller Pane",
  stress = "Stressometer",
  speed = "Speedometer",
  rsc = "Speed Controller",
  fission = "Reaktor Fission",
  turbine = "Turbina",
  boiler = "Boiler",
  fusion = "Reaktor Fusion",
  fissionport = "Fission Port (bez danych)",
  fusionport = "Fusion Port (bez danych)",
  matrix = "Induction Matrix",
  dyntank = "Dynamic Tank",
  sps = "SPS",
  evap = "Thermal Evaporation",
  cube = "Energy Cube",
  powahreactor = "Reaktor Powah",
  generator = "Generator",
  energy = "Magazyn energii",
  fluid = "Zbiornik",
  inventory = "Inwentarz",
  machine = "Maszyna",
  monitor = "Monitor",
  speaker = "Glosnik",
  modem = "Modem",
  printer = "Drukarka",
  drive = "Stacja dyskow",
  computer = "Komputer",
  unknown = "Inne",
}

-- rodzaje nie pokazywane jako "maszyny"
D.UTILITY = {
  monitor = true, speaker = true, modem = true, printer = true, drive = true, computer = true,
  chat = true, relay = true, csource = true, nbt = true, geo = true, blockreader = true,
}

-- multibloki Mekanism: kilka portow tego samego multibloku = jedno urzadzenie
D.MULTIBLOCK = { fission = true, turbine = true, boiler = true, fusion = true, matrix = true, dyntank = true, sps = true, evap = true }

local GENERIC = { energy_storage = true, fluid_storage = true, inventory = true }

local function classify(types)
  for _, t in ipairs(types) do
    local k = TYPE_MAP[U.norm(t)]
    if k then return k end
  end
  local has = {}
  for _, t in ipairs(types) do has[t] = true end
  local primary = (types[1] or ""):lower()
  -- Mekanism: basicEnergyCube, eliteEnergyCube, creativeEnergyCube...
  if primary:find("energycube$") then return "cube" end
  if has.energy_storage then
    if primary:find("cell") or primary:find("battery") or primary:find("capacitor")
      or primary:find("accumulator") or primary:find("flux_storage") or primary:find("energy_storage") then
      return "energy"
    end
    return "machine"
  end
  if has.fluid_storage then
    if primary:find("tank") or primary:find("drum") or primary:find("barrel") then return "fluid" end
    return "machine"
  end
  if has.inventory then return "inventory" end
  -- inne peryferia Mekanism (maszyny, tanki chemiczne itd.) – jeden typ camelCase bez ":"
  if #types == 1 and not primary:find(":") then return "machine" end
  return "unknown"
end

-- czy peryferium pochodzi z Mekanism (energia w Joulach)
local function isMekanism(dev)
  if D.MULTIBLOCK[dev.kind] or dev.kind == "cube" then return true end
  return dev.kind == "machine" and #dev.types == 1 and not dev.types[1]:find(":")
    and U.has(dev.p, "getEnergyFilledPercentage")
end

local function posKey(p)
  local a = U.call(p, "getMinPos")
  local b = U.call(p, "getMaxPos")
  if type(a) == "table" and type(b) == "table" then
    return string.format("%s,%s,%s|%s,%s,%s", tostring(a.x), tostring(a.y), tostring(a.z), tostring(b.x), tostring(b.y), tostring(b.z))
  end
  return nil
end

D.list = {}
D.byName = {}

function D.scan(cfg)
  local list, byName, seen = {}, {}, {}
  D.cfg = cfg
  for _, name in ipairs(peripheral.getNames()) do
    local types = { peripheral.getType(name) }
    local dev = { name = name, types = types, p = peripheral.wrap(name) }
    dev.kind = classify(types)
    dev.mek = isMekanism(dev)
    -- AP: peryferium wylaczone w configu serwera
    dev.disabled = dev.p ~= nil and type(dev.p.peripheralDisabled) == "function"
    if D.MULTIBLOCK[dev.kind] and dev.p then
      local key = posKey(dev.p)
      if key then
        key = dev.kind .. "@" .. key
        if seen[key] then dev.dupOf = seen[key] else seen[key] = name end
      end
    end
    list[#list + 1] = dev
    byName[name] = dev
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  D.list, D.byName = list, byName
  D.feRate = nil
  return list
end

function D.label(dev)
  if not dev then return "?" end
  local a = D.cfg and D.cfg.aliases[dev.name]
  if a and a ~= "" then return a end
  return dev.name
end

function D.kindLabel(kind)
  return D.KINDS[kind] or kind
end

function D.get(name)
  return D.byName[name]
end

function D.isActive(dev)
  return not dev.dupOf and not dev.disabled and not (D.cfg and D.cfg.hidden[dev.name])
end

-- metoda, ktora ma kazdy uformowany multiblok danego rodzaju
local FORMED_METHOD = {
  fission = "getStatus", turbine = "getProductionRate", boiler = "getBoilRate", fusion = "isIgnited",
  matrix = "getLastInput", dyntank = "getStored", sps = "getProcessRate", evap = "getProductionAmount",
}

-- multiblok Mekanism: metody sa dostepne tylko gdy jest uformowany. Mekanism podpina je przy
-- tworzeniu peryferium; jesli opakowanie jest sprzed uformowania, oznaczamy potrzebe ponownego skanu.
function D.formed(dev)
  if not D.MULTIBLOCK[dev.kind] then return true end
  local formed = U.call(dev.p, "isFormed") == true
  local key = FORMED_METHOD[dev.kind]
  if formed and key and not U.has(dev.p, key) then
    D.stale = true
    return false
  end
  return formed
end

function D.byKind(kinds)
  if type(kinds) == "string" then kinds = { kinds } end
  local want = {}
  for _, k in ipairs(kinds) do want[k] = true end
  local r = {}
  for _, d in ipairs(D.list) do
    if want[d.kind] and D.isActive(d) then r[#r + 1] = d end
  end
  return r
end

-- zrodla dla monitora: "auto" -> wszystkie aktywne danego rodzaju, inaczej konkretne urzadzenie
function D.sources(source, kinds)
  if source and source ~= "auto" then
    local d = D.byName[source]
    if d then return { d } end
    return {}
  end
  return D.byKind(kinds)
end

-- Mekanism zwraca Joule; kurs J->FE bierzemy z mekanismEnergyHelper (config Mekanism)
function D.feRateMek()
  if D.feRate then return D.feRate end
  local rate = 1 / 2.5
  if mekanismEnergyHelper and mekanismEnergyHelper.joulesToFE then
    local ok, r = pcall(mekanismEnergyHelper.joulesToFE, 1000000000)
    if ok and type(r) == "number" and r > 0 then rate = r / 1000000000 end
  end
  D.feRate = rate
  return rate
end

function D.mekFE(v)
  if type(v) ~= "number" then return v end
  return v * D.feRateMek()
end

-- zgadywanie energii dowolnego urzadzenia -> stored, max (FE)
function D.energy(dev)
  local p = dev.p
  if not p then return nil end
  if dev.mek then
    local e, m = U.call(p, "getEnergy"), U.call(p, "getMaxEnergy")
    if type(e) == "number" and type(m) == "number" then return D.mekFE(e), D.mekFE(m) end
    return nil
  end
  -- AP Powah: getStoredEnergy / getMaxEnergy
  local e, m = U.call(p, "getStoredEnergy"), U.call(p, "getMaxEnergy")
  if type(e) == "number" and type(m) == "number" then return e, m end
  -- CC:T generic energy_storage
  e, m = U.call(p, "getEnergy"), U.call(p, "getEnergyCapacity")
  if type(e) == "number" and type(m) == "number" then return e, m end
  return nil
end

-- wyjscie redstone: target = "computer" (strony komputera) albo nazwa redstone_relay / redrouter
D.SIDES = { "top", "bottom", "left", "right", "front", "back" }

function D.setRedstone(target, side, on)
  if not side or side == "" then return false end
  if target == nil or target == "" or target == "computer" then
    return pcall(redstone.setOutput, side, on and true or false)
  end
  local d = D.byName[target]
  if d and d.p and d.p.setOutput then
    return pcall(d.p.setOutput, side, on and true or false)
  end
  return false
end

function D.redstoneTargets()
  local r = { "computer" }
  for _, d in ipairs(D.list) do
    if d.kind == "relay" then r[#r + 1] = d.name end
  end
  return r
end

return D
