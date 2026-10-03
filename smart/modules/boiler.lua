-- Modul: Boiler termoelektryczny (Mekanism)
local U = require("lib.util")
local D = require("lib.devices")
local M = require("lib.mod")

local mod = {
  id = "boiler",
  name = "Boiler",
  kinds = { "boiler" },
  single = true,
  options = {},
}

function mod.update(ctx, m)
  local d = M.single(m, mod.kinds)
  local st = {}
  m.state = st
  if not d then return end
  st.dev = d
  st.formed = D.formed(d)
  if not st.formed then return end
  local p = d.p
  st.temp = U.call(p, "getTemperature")
  st.boil = U.call(p, "getBoilRate")
  st.maxBoil = U.call(p, "getMaxBoilRate")
  st.cap = U.call(p, "getBoilCapacity")
  st.superheaters = U.call(p, "getSuperheaters")
  st.water = U.call(p, "getWaterFilledPercentage") or 0
  st.steam = U.call(p, "getSteamFilledPercentage") or 0
  st.heated = U.call(p, "getHeatedCoolantFilledPercentage") or 0
  st.cooled = U.call(p, "getCooledCoolantFilledPercentage") or 0
  st.envLoss = U.call(p, "getEnvironmentalLoss")
end

function mod.draw(ctx, m, c)
  local st = m.state
  local title = M.title(m, "Boiler")
  if not st.dev then return M.message(c, m, title, { "Brak boilera", "Podlacz Boiler Valve przez modem" }) end
  title = M.title(m, D.label(st.dev))
  if not st.formed then return M.message(c, m, title, { "Boiler nieuformowany" }) end
  c:clear(colors.black)
  c:header(title, m.accent, U.temp(st.temp))
  local w, y = c.w - 2, 3
  c:kv(2, y, w, "Temperatura", U.temp(st.temp), colors.lightGray, colors.orange); y = y + 1
  c:kv(2, y, w, "Gotowanie", U.fmt(st.boil, "mB/t"), colors.lightGray, colors.lime); y = y + 1
  c:kv(2, y, w, "Max (ostatnio)", U.fmt(st.maxBoil, "mB/t"), colors.lightGray, colors.white); y = y + 1
  c:kv(2, y, w, "Pojemnosc", U.fmt(st.cap, "mB/t"), colors.lightGray, colors.white); y = y + 1
  c:kv(2, y, w, "Superheatery", tostring(st.superheaters or "?"), colors.lightGray, colors.white); y = y + 2
  y = M.inlineBar(c, 2, y, w, "Woda", st.water, colors.blue)
  y = M.inlineBar(c, 2, y, w, "Para", st.steam, colors.lightGray)
  y = M.inlineBar(c, 2, y, w, "Gorace chl.", st.heated, colors.orange)
  M.inlineBar(c, 2, y, w, "Chlodne chl.", st.cooled, colors.lightBlue)
end

return mod
