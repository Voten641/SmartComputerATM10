-- Modul: Zegar i srodowisko (AP Environment Detector opcjonalnie)
local U = require("lib.util")
local M = require("lib.mod")
local D = require("lib.devices")

local mod = {
  id = "clock",
  name = "Zegar / pogoda",
  kinds = { "env" },
  single = true,
  options = {
    { key = "real", label = "Czas rzeczywisty", type = "toggle", default = false },
  },
}

local MOON = { [0] = "Pelnia", "Ubywajacy garb", "Ostatnia kwadra", "Ubywajacy sierp", "Now", "Przybywajacy sierp", "Pierwsza kwadra", "Przybywajacy garb" }

function mod.update(ctx, m)
  local st = {}
  m.state = st
  if m.opts.real then
    st.time = os.date("%H:%M")
  else
    st.time = textutils.formatTime(os.time("ingame"), true)
  end
  st.day = os.day("ingame")
  local d = M.single(m, mod.kinds)
  if d then
    st.dev = d
    st.rain = U.call(d.p, "isRaining")
    st.thunder = U.call(d.p, "isThunder")
    local id = U.call(d.p, "getMoon")
    st.moon = type(id) == "number" and MOON[id] or nil
    st.biome = U.call(d.p, "getBiome")
    st.dim = U.call(d.p, "getDimension")
    st.rad = U.call(d.p, "getRadiationRaw")
  end
end

function mod.draw(ctx, m, c)
  local st = m.state
  c:clear(colors.black)
  c:header(M.title(m, "Zegar"), m.accent, "Dzien " .. tostring(st.day))
  local y = 3
  local t = st.time or "--:--"
  if #t < 5 then t = "0" .. t end
  if c.w >= 20 and c.h >= 8 then
    c:bigCenter(y, t, colors.white)
    y = y + 6
  else
    c:center(y, t, colors.white, colors.black)
    y = y + 2
  end
  if st.dev then
    local w = c.w - 2
    local weather = st.thunder and "Burza" or st.rain and "Deszcz" or "Slonecznie"
    c:kv(2, y, w, "Pogoda", weather, colors.lightGray, st.rain and colors.lightBlue or colors.yellow); y = y + 1
    if st.moon then c:kv(2, y, w, "Ksiezyc", st.moon, colors.lightGray, colors.white); y = y + 1 end
    if st.biome then c:kv(2, y, w, "Biom", U.prettyId(st.biome), colors.lightGray, colors.lime); y = y + 1 end
    if st.dim then c:kv(2, y, w, "Wymiar", U.prettyId(st.dim), colors.lightGray, colors.white); y = y + 1 end
    if type(st.rad) == "number" then
      c:kv(2, y, w, "Promieniowanie", U.fmt(st.rad, "Sv/h"), colors.lightGray, st.rad > 0.0001 and colors.red or colors.lime)
    end
  end
end

return mod
