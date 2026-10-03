-- Modul: Reaktor fuzyjny (Mekanism Generators)
local U = require("lib.util")
local D = require("lib.devices")
local M = require("lib.mod")

local mod = {
  id = "fusion",
  name = "Reaktor fusion",
  kinds = { "fusion" },
  single = true,
  options = {
    { key = "controls", label = "Przyciski wtrysku", type = "toggle", default = true },
  },
}

local function mk(n)
  if type(n) ~= "number" then return "?" end
  return U.fmt(n, "K")
end

function mod.update(ctx, m)
  local d = M.single(m, mod.kinds)
  local st = {}
  m.state = st
  if not d then return end
  st.dev = d
  st.formed = D.formed(d)
  if not st.formed then return end
  local p = d.p
  st.ignited = U.call(p, "isIgnited")
  st.plasma = U.call(p, "getPlasmaTemperature")
  st.case = U.call(p, "getCaseTemperature")
  st.inj = U.call(p, "getInjectionRate")
  st.prod = D.mekFE(U.call(p, "getProductionRate"))
  st.deut = U.call(p, "getDeuteriumFilledPercentage") or 0
  st.trit = U.call(p, "getTritiumFilledPercentage") or 0
  st.dt = U.call(p, "getDTFuelFilledPercentage") or 0
  st.water = U.call(p, "getWaterFilledPercentage") or 0
  st.steam = U.call(p, "getSteamFilledPercentage") or 0
  st.efrac = U.call(p, "getEnergyFilledPercentage") or 0
end

function mod.draw(ctx, m, c)
  local st, o = m.state, m.opts
  local title = M.title(m, "Reaktor fusion")
  if not st.dev then
    return M.message(c, m, title, M.portHint({ "Brak reaktora fuzyjnego", "Podlacz modemem Fusion Reactor", "Logic Adapter" }, "fusionport"))
  end
  title = M.title(m, D.label(st.dev))
  if not st.formed then return M.message(c, m, title, { "Reaktor nieuformowany" }) end
  c:clear(colors.black)
  c:header(title, m.accent, st.ignited and "ZAPLON" or "WYGASZONY")
  local w, y = c.w - 2, 3
  c:kv(2, y, w, "Plazma", mk(st.plasma), colors.lightGray, colors.magenta); y = y + 1
  c:kv(2, y, w, "Obudowa", mk(st.case), colors.lightGray, colors.orange); y = y + 1
  c:kv(2, y, w, "Wtrysk", tostring(st.inj or "?") .. " mB/t", colors.lightGray, colors.white); y = y + 1
  c:kv(2, y, w, "Produkcja", U.fmt(st.prod, "FE/t"), colors.lightGray, colors.lime); y = y + 2
  y = M.inlineBar(c, 2, y, w, "D-T", st.dt, colors.purple)
  y = M.inlineBar(c, 2, y, w, "Deuter", st.deut, colors.red)
  y = M.inlineBar(c, 2, y, w, "Tryt", st.trit, colors.lime)
  y = M.inlineBar(c, 2, y, w, "Woda", st.water, colors.blue)
  y = M.inlineBar(c, 2, y, w, "Para", st.steam, colors.lightGray)
  y = M.inlineBar(c, 2, y, w, "Energia", st.efrac, colors.yellow)
  if o.controls and c.h - y >= 2 then
    local bw = math.floor((w - 1) / 2)
    -- Mekanism przyjmuje tylko parzyste wartosci wtrysku 0-98
    c:button("inj", 2, c.h - 1, bw, 1, "Wtrysk -2", colors.white, colors.gray, -2)
    c:button("inj", 3 + bw, c.h - 1, w - bw - 1, 1, "Wtrysk +2", colors.white, colors.gray, 2)
  end
end

function mod.touch(ctx, m, btn)
  local d = m.state.dev
  if d and btn.id == "inj" then
    local cur = U.call(d.p, "getInjectionRate") or 0
    pcall(d.p.setInjectionRate, U.clamp(cur + btn.data, 0, 98))
  end
end

return mod
