-- Modul: Turbina przemyslowa (Mekanism Generators)
local U = require("lib.util")
local D = require("lib.devices")
local M = require("lib.mod")
local UI = require("lib.ui")

local mod = {
  id = "turbine",
  name = "Turbina",
  kinds = { "turbine" },
  single = true,
  options = {
    { key = "controls", label = "Przycisk trybu zrzutu", type = "toggle", default = true },
  },
}

local DUMP = { IDLE = "Bez zrzutu", DUMPING_EXCESS = "Zrzut nadmiaru", DUMPING = "Zrzut" }

function mod.update(ctx, m)
  local d = M.single(m, mod.kinds)
  local st = {}
  m.state = st
  if not d then return end
  st.dev = d
  st.formed = D.formed(d)
  if not st.formed then return end
  local p = d.p
  st.energy = D.mekFE(U.call(p, "getEnergy"))
  st.maxEnergy = D.mekFE(U.call(p, "getMaxEnergy"))
  st.efrac = U.call(p, "getEnergyFilledPercentage") or 0
  st.prod = D.mekFE(U.call(p, "getProductionRate"))
  st.maxProd = D.mekFE(U.call(p, "getMaxProduction"))
  st.steam = U.call(p, "getSteamFilledPercentage") or 0
  st.flow = U.call(p, "getFlowRate")
  st.maxFlow = U.call(p, "getMaxFlowRate")
  st.steamIn = U.call(p, "getLastSteamInputRate")
  st.dump = U.call(p, "getDumpingMode")
  st.blades = U.call(p, "getBlades")
  st.coils = U.call(p, "getCoils")
  st.vents = U.call(p, "getVents")
end

function mod.draw(ctx, m, c)
  local st, o = m.state, m.opts
  local title = M.title(m, "Turbina")
  if not st.dev then return M.message(c, m, title, { "Brak turbiny", "Podlacz Turbine Valve przez modem" }) end
  title = M.title(m, D.label(st.dev))
  if not st.formed then return M.message(c, m, title, { "Turbina nieuformowana" }) end
  c:clear(colors.black)
  c:header(title, m.accent, U.fmt(st.prod, "FE/t"))
  local w, y = c.w - 2, 3
  c:kv(2, y, w, "Produkcja", U.fmt(st.prod, "FE/t"), colors.lightGray, colors.lime); y = y + 1
  c:kv(2, y, w, "Maksimum", U.fmt(st.maxProd, "FE/t"), colors.lightGray, colors.white); y = y + 1
  c:kv(2, y, w, "Przeplyw", U.fmt(st.flow, "mB/t") .. " / " .. U.fmt(st.maxFlow, "mB/t"), colors.lightGray, colors.white); y = y + 1
  c:kv(2, y, w, "Para (wejscie)", U.fmt(st.steamIn, "mB/t"), colors.lightGray, colors.white); y = y + 1
  if c.h >= 18 then
    c:kv(2, y, w, "Lopatki/Cewki/Wenty", string.format("%s/%s/%s", st.blades or "?", st.coils or "?", st.vents or "?"), colors.lightGray, colors.white)
    y = y + 1
  end
  y = y + 1
  y = M.inlineBar(c, 2, y, w, "Energia", st.efrac, UI.levelColor(st.efrac))
  y = M.inlineBar(c, 2, y, w, "Para", st.steam, colors.lightGray)
  y = M.inlineBar(c, 2, y, w, "Obciazenie", U.frac(st.flow, st.maxFlow), colors.cyan)
  y = y + 1
  c:kv(2, y, w, "Tryb", DUMP[st.dump] or tostring(st.dump), colors.lightGray, st.dump == "IDLE" and colors.lime or colors.orange)
  if o.controls and c.h - y >= 3 then
    c:button("dump", 2, c.h - 1, w, 1, "Zmien tryb zrzutu", colors.black, colors.lightGray)
  end
end

function mod.touch(ctx, m, btn)
  local d = m.state.dev
  if d and btn.id == "dump" then pcall(d.p.incrementDumpingMode) end
end

return mod
