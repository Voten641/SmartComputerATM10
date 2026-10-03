-- Modul: Reaktor fission (Mekanism) – podglad + sterowanie z monitora
local U = require("lib.util")
local D = require("lib.devices")
local M = require("lib.mod")
local UI = require("lib.ui")

local mod = {
  id = "fission",
  name = "Reaktor fission",
  kinds = { "fission" },
  single = true,
  options = {
    { key = "controls", label = "Przyciski sterowania", type = "toggle", default = true },
    { key = "step", label = "Krok burn rate", type = "choice", default = 1, choices = { 0.1, 1, 10, 100 } },
  },
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
  st.active = U.call(p, "getStatus")
  st.temp = U.call(p, "getTemperature")
  st.damage = U.call(p, "getDamagePercent")
  st.fuel = U.call(p, "getFuelFilledPercentage")
  st.coolant = U.call(p, "getCoolantFilledPercentage")
  st.heated = U.call(p, "getHeatedCoolantFilledPercentage")
  st.waste = U.call(p, "getWasteFilledPercentage")
  st.burn = U.call(p, "getBurnRate")
  st.actual = U.call(p, "getActualBurnRate")
  st.maxBurn = U.call(p, "getMaxBurnRate")
  st.heating = U.call(p, "getHeatingRate")
  st.envLoss = U.call(p, "getEnvironmentalLoss")
  st.forceDisabled = U.call(p, "isForceDisabled")
  local cool = U.call(p, "getCoolant")
  st.coolantName = type(cool) == "table" and cool.name and U.prettyId(cool.name) or nil
  st.trip = ctx.auto.trips[d.name]
end

local function statusText(st)
  if st.trip then return "SCRAM", colors.red end
  if st.forceDisabled then return "WYMUSZONO STOP", colors.red end
  if st.active then return "PRACUJE", colors.lime end
  return "WYLACZONY", colors.orange
end

function mod.draw(ctx, m, c)
  local st, o = m.state, m.opts
  local title = M.title(m, "Reaktor fission")
  if not st.dev then
    return M.message(c, m, title, { "Brak reaktora", "Podlacz Fission Reactor Logic Adapter", "lub Reactor Port przez modem" })
  end
  title = M.title(m, D.label(st.dev))
  if not st.formed then
    return M.message(c, m, title, { "Reaktor nieuformowany", "Sprawdz konstrukcje multibloku" })
  end
  c:clear(colors.black)
  local stxt, scol = statusText(st)
  c:header(title, m.accent, stxt)
  local w, y = c.w - 2, 3

  c:rect(2, y, w, 1, scol)
  c:center(y, stxt .. (st.trip and (" - " .. st.trip) or ""), colors.black, scol, 2, w)
  y = y + 2

  local tcol = (st.temp or 0) > 1000 and colors.red or (st.temp or 0) > 600 and colors.orange or colors.lime
  c:kv(2, y, w, "Temperatura", U.temp(st.temp), colors.lightGray, tcol); y = y + 1
  c:kv(2, y, w, "Uszkodzenie", string.format("%d%%", math.floor(st.damage or 0)), colors.lightGray, (st.damage or 0) > 0 and colors.red or colors.lime); y = y + 1
  c:kv(2, y, w, "Burn rate", string.format("%.1f / %.1f mB/t", st.actual or 0, st.burn or 0), colors.lightGray, colors.white); y = y + 1
  c:kv(2, y, w, "Max", string.format("%s mB/t", U.fmt(st.maxBurn)), colors.lightGray, colors.white); y = y + 1
  if c.h >= 20 then
    c:kv(2, y, w, "Grzanie", U.fmt(st.heating, "mB/t"), colors.lightGray, colors.white); y = y + 1
  end
  y = y + 1

  y = M.inlineBar(c, 2, y, w, "Paliwo", st.fuel or 0, colors.lime)
  y = M.inlineBar(c, 2, y, w, st.coolantName or "Chlodziwo", st.coolant or 0, colors.lightBlue)
  y = M.inlineBar(c, 2, y, w, "Gorace", st.heated or 0, (st.heated or 0) > 0.9 and colors.red or colors.orange)
  y = M.inlineBar(c, 2, y, w, "Odpady", st.waste or 0, (st.waste or 0) > 0.8 and colors.red or colors.brown)

  if o.controls and c.h - y >= 4 then
    local by = c.h - 2
    local half = math.floor((w - 1) / 2)
    if st.trip then
      c:button("reset", 2, by, w, 3, "RESET ZABEZPIECZENIA", colors.black, colors.yellow)
    else
      c:button("start", 2, by, half, 3, "START", colors.black, colors.lime)
      c:button("scram", 3 + half, by, w - half - 1, 3, "SCRAM", colors.white, colors.red)
    end
    if c.h - y >= 6 then
      local step = o.step or 1
      local bw = math.floor((w - 3) / 4)
      local ry = by - 2
      c:button("burn", 2, ry, bw, 1, "-" .. step * 10, colors.white, colors.gray, -step * 10)
      c:button("burn", 3 + bw, ry, bw, 1, "-" .. step, colors.white, colors.gray, -step)
      c:button("burn", 4 + bw * 2, ry, bw, 1, "+" .. step, colors.white, colors.gray, step)
      c:button("burn", 5 + bw * 3, ry, w - 3 - bw * 3, 1, "+" .. step * 10, colors.white, colors.gray, step * 10)
    end
  end
  if m.flash and m.flash.untilT > os.clock() then
    c:rect(1, c.h, c.w, 1, colors.red)
    c:center(c.h, m.flash.text, colors.white, colors.red)
  end
end

function mod.touch(ctx, m, btn)
  local d = m.state.dev
  if not d then return end
  local id = btn.id
  if id == "start" then
    local ok, err = ctx.auto.start(d)
    if not ok then m.flash = { text = err, untilT = os.clock() + 3 } end
  elseif id == "scram" then
    ctx.auto.scram(d)
  elseif id == "reset" then
    ctx.auto.reset(d.name)
  elseif id == "burn" then
    local delta = btn.data
    local cur = U.call(d.p, "getBurnRate") or 0
    local max = U.call(d.p, "getMaxBurnRate") or 0
    local new = U.clamp(U.round(cur + delta, 1), 0, max)
    local ok, err = pcall(d.p.setBurnRate, new)
    if not ok then m.flash = { text = tostring(err), untilT = os.clock() + 3 } end
  end
end

return mod
