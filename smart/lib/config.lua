-- Smart System: konfiguracja (zapisywana w /smart/data/config.lua)
local U = require("lib.util")

local C = {}
C.path = "/smart/data/config.lua"

C.defaults = {
  title = "Baza ATM10",
  refresh = 1,            -- co ile sekund odswiezac dane
  itemsEvery = 5,
  clickSound = true,      -- dzwiek potwierdzenia klikniecia na monitorze (wymaga glosnika)         -- co ile odswiezen pobierac liste przedmiotow z ME/RS (ciezka operacja)
  monitors = {},          -- [nazwaMonitora] = { module, source, scale, accent, title, opts }
  aliases = {},           -- [nazwaPeryferium] = "przyjazna nazwa"
  hidden = {},            -- [nazwaPeryferium] = true
  tags = {},              -- [nazwaPeryferium] = "energia, ..." (tagi decyduja gdzie urzadzenie sie pokazuje)
  controls = {},          -- przelaczniki redstone: { label, target, side, mode, state, color }
  displays = {},          -- [create_source] = { lines = { "energy", "reactor", ... }, custom = "" }
  autocraft = {
    enabled = false,
    bridge = "auto",
    every = 10,           -- co ile sekund sprawdzac stany
    items = {},           -- { name, label, keep, batch, enabled }
  },
  history = {
    interval = 60,        -- co ile sekund zapisywac probke
    points = 1440,        -- ile probek trzymac (1440 x 60s = 24h)
  },
  remote = {
    enabled = false,
    pin = "",
  },
  alarms = {
    chat = { enabled = false, player = "", prefix = "Smart" },
    speaker = true,
    redstone = { enabled = false, target = "computer", side = "back" },
    fission = {
      autoScram = true,
      maxTemp = 1000,      -- K
      maxDamage = 0,       -- % (getDamagePercent 0-100; 0 = SCRAM przy jakimkolwiek uszkodzeniu)
      maxWaste = 90,       -- %
      minCoolant = 10,     -- %
      maxHeated = 95,      -- %
    },
    autoPower = {
      enabled = false,
      reactor = "auto",
      source = "auto",
      startBelow = 20,     -- % energii
      stopAbove = 90,
    },
    lowEnergy = { enabled = true, below = 10 },
    storageFull = { enabled = true, above = 95 },
    tankFull = { enabled = false, above = 95 },
    stress = { enabled = true, above = 90 },          -- % obciazenia sieci Create
    radiation = { enabled = true, above = 0.00001 },  -- Sv/h (0.00001 = poziom LOW w Mekanism)
  },
}

C.monitorDefaults = {
  module = "none",
  source = "auto",
  scale = 1,
  accent = "cyan",
  title = "",
  opts = {},
}

function C.load()
  local cfg
  if fs.exists(C.path) then
    local f = fs.open(C.path, "r")
    local s = f.readAll()
    f.close()
    cfg = textutils.unserialize(s)
  end
  if type(cfg) ~= "table" then cfg = {} end
  U.fill(cfg, C.defaults)
  for _, m in pairs(cfg.monitors) do U.fill(m, C.monitorDefaults) end
  return cfg
end

function C.save(cfg)
  local dir = fs.getDir(C.path)
  if not fs.exists(dir) then fs.makeDir(dir) end
  local tmp = C.path .. ".tmp"
  local f = fs.open(tmp, "w")
  f.write(textutils.serialize(cfg))
  f.close()
  if fs.exists(C.path) then fs.delete(C.path) end
  fs.move(tmp, C.path)
end

function C.monitor(cfg, name)
  local m = cfg.monitors[name]
  if not m then
    m = U.deepcopy(C.monitorDefaults)
    cfg.monitors[name] = m
  end
  U.fill(m, C.monitorDefaults)
  return m
end

return C
