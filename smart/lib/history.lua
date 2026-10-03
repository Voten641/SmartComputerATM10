-- Smart System: historia pomiarow zapisywana na dysku (przetrwa restart)
local U = require("lib.util")
local D = require("lib.devices")

local H = {}
H.path = "/smart/data/history.lua"
H.series = {}      -- [klucz] = { {t, v}, ... }
H.lastSample = 0

-- definicje serii: klucz -> { nazwa, jednostka, funkcja pomiaru(ctx) }
H.DEFS = {
  { key = "energy", label = "Energia %", unit = "%", fn = function(ctx)
      local f = ctx.auto.readEnergy("auto")
      return f and f * 100 or nil
    end },
  { key = "energyFE", label = "Energia (FE)", unit = "FE", fn = function(ctx)
      local _, stored = ctx.auto.readEnergy("auto")
      return stored
    end },
  { key = "gen", label = "Generacja FE/t", unit = "FE/t", fn = function()
      local g, any = 0, false
      for _, d in ipairs(D.byKind({ "turbine", "fusion" })) do
        if D.formed(d) then
          local v = D.mekFE(U.call(d.p, "getProductionRate"))
          if v then g, any = g + v, true end
        end
      end
      return any and g or nil
    end },
  { key = "storage", label = "ME/RS zajetosc %", unit = "%", fn = function()
      local d = D.byKind({ "me", "rs" })[1]
      if not d then return nil end
      local used, max = U.call(d.p, "getUsedItemStorage"), U.call(d.p, "getMaxItemStorage")
      if type(used) ~= "number" or type(max) ~= "number" or max <= 0 then return nil end
      return used / max * 100
    end },
  { key = "stress", label = "Create obciazenie %", unit = "%", fn = function()
      local worst
      for _, d in ipairs(D.byKind("stress")) do
        local s, c = U.call(d.p, "getStress"), U.call(d.p, "getStressCapacity")
        if type(s) == "number" and type(c) == "number" and c > 0 then
          local f = s / c * 100
          if not worst or f > worst then worst = f end
        end
      end
      return worst
    end },
  { key = "radiation", label = "Promieniowanie Sv/h", unit = "Sv/h", fn = function()
      local d = D.byKind("env")[1]
      if not d then return nil end
      local r = U.call(d.p, "getRadiationRaw")
      return type(r) == "number" and r or nil
    end },
  { key = "reactorTemp", label = "Temp. reaktora K", unit = "K", fn = function()
      local d = D.byKind("fission")[1]
      if not d or not D.formed(d) then return nil end
      return U.call(d.p, "getTemperature")
    end },
}
H.byKey = {}
for _, d in ipairs(H.DEFS) do H.byKey[d.key] = d end

function H.load()
  if not fs.exists(H.path) then return end
  local f = fs.open(H.path, "r")
  local data = textutils.unserialize(f.readAll())
  f.close()
  if type(data) == "table" then H.series = data end
end

function H.save()
  local dir = fs.getDir(H.path)
  if not fs.exists(dir) then fs.makeDir(dir) end
  local f = fs.open(H.path, "w")
  f.write(textutils.serialize(H.series, { compact = true }))
  f.close()
end

function H.sample(ctx)
  local now = U.now()
  local cfg = ctx.cfg.history
  if now - H.lastSample < (cfg.interval or 60) then return end
  H.lastSample = now
  local any = false
  for _, def in ipairs(H.DEFS) do
    local ok, v = pcall(def.fn, ctx)
    if ok and type(v) == "number" and v == v then
      local s = H.series[def.key] or {}
      s[#s + 1] = { math.floor(now), v }
      while #s > (cfg.points or 1440) do table.remove(s, 1) end
      H.series[def.key] = s
      any = true
    end
  end
  if any then pcall(H.save) end
end

-- probki z ostatnich `seconds` sekund
function H.range(key, seconds)
  local s = H.series[key] or {}
  local from = U.now() - seconds
  local out = {}
  for _, p in ipairs(s) do if p[1] >= from then out[#out + 1] = p end end
  return out
end

function H.available()
  local r = {}
  for _, d in ipairs(H.DEFS) do
    if H.series[d.key] and #H.series[d.key] > 0 then r[#r + 1] = d.key end
  end
  return r
end

return H
