-- Smart System: teksty dla wyswietlaczy Create (CC:C Bridge Source Block -> Display Link -> Flap Display / Nixie itp.)
local U = require("lib.util")
local D = require("lib.devices")

local DS = {}

-- krotkie teksty (wyswietlacze Create sa male), kazdy provider dostaje ctx i szerokosc
DS.PROVIDERS = {
  { id = "none", label = "(pusta linia)", fn = function() return "" end },
  { id = "title", label = "Nazwa bazy", fn = function(ctx) return ctx.cfg.title end },
  { id = "time", label = "Czas gry", fn = function() return textutils.formatTime(os.time("ingame"), true) end },
  { id = "energy", label = "Energia %", fn = function(ctx)
      local f = ctx.auto.readEnergy("auto")
      return f and ("Energia " .. U.pct(f)) or "Energia -"
    end },
  { id = "energyFE", label = "Energia FE", fn = function(ctx)
      local _, s = ctx.auto.readEnergy("auto")
      return s and U.fmt(s, "FE") or "-"
    end },
  { id = "reactor", label = "Reaktor (stan)", fn = function(ctx)
      local d = D.byKind("fission")[1]
      if not d or not D.formed(d) then return "Reaktor -" end
      if ctx.auto.trips[d.name] then return "Reaktor SCRAM" end
      local on = U.call(d.p, "getStatus")
      return "Reaktor " .. (on and "ON " or "OFF ") .. U.temp(U.call(d.p, "getTemperature"))
    end },
  { id = "gen", label = "Generacja", fn = function()
      local g = 0
      for _, d in ipairs(D.byKind({ "turbine", "fusion" })) do
        if D.formed(d) then g = g + (D.mekFE(U.call(d.p, "getProductionRate")) or 0) end
      end
      return "Gen " .. U.fmt(g, "FE/t")
    end },
  { id = "storage", label = "Magazyn ME/RS %", fn = function()
      local d = D.byKind({ "me", "rs" })[1]
      if not d then return "ME -" end
      return (d.kind == "me" and "ME " or "RS ") .. U.pct(U.frac(U.call(d.p, "getUsedItemStorage"), U.call(d.p, "getMaxItemStorage")))
    end },
  { id = "stress", label = "Create obciazenie", fn = function()
      local d = D.byKind("stress")[1]
      if not d then return "Stres -" end
      local s, c = U.call(d.p, "getStress"), U.call(d.p, "getStressCapacity")
      return "Stres " .. U.pct(U.frac(s, c))
    end },
  { id = "players", label = "Gracze online", fn = function()
      local d = D.byKind("player")[1]
      if not d then return "Gracze -" end
      local l = U.call(d.p, "getOnlinePlayers") or {}
      return "Online " .. #l
    end },
  { id = "radiation", label = "Promieniowanie", fn = function()
      local d = D.byKind("env")[1]
      local r = d and U.call(d.p, "getRadiationRaw")
      return type(r) == "number" and ("Rad " .. U.sv(r)) or "Rad -"
    end },
  { id = "alarms", label = "Alarmy", fn = function(ctx)
      local l = ctx.auto.list()
      if #l == 0 then return "Alarmy: brak" end
      return "! " .. l[1].text
    end },
  { id = "custom", label = "Wlasny tekst", fn = function(ctx, dcfg) return dcfg.custom or "" end },
}
DS.byId = {}
for _, p in ipairs(DS.PROVIDERS) do DS.byId[p.id] = p end

function DS.config(cfg, name)
  local d = cfg.displays[name]
  if not d then
    d = { lines = { "energy", "reactor", "none", "none" }, custom = "", align = "left" }
    cfg.displays[name] = d
  end
  return d
end

local function render(ctx, dev)
  local p = dev.p
  local dcfg = DS.config(ctx.cfg, dev.name)
  local w, h = p.getSize()
  p.clear()
  for y = 1, h do
    local prov = DS.byId[dcfg.lines[y] or "none"] or DS.byId.none
    local ok, txt = pcall(prov.fn, ctx, dcfg)
    txt = U.trunc(ok and tostring(txt) or "blad", w)
    local x = 1
    if dcfg.align == "center" then x = math.floor((w - #txt) / 2) + 1
    elseif dcfg.align == "right" then x = w - #txt + 1 end
    p.setCursorPos(x, y)
    p.write(txt)
  end
end

function DS.tick(ctx)
  for _, dev in ipairs(D.byKind("csource")) do
    pcall(render, ctx, dev)
  end
end

return DS
