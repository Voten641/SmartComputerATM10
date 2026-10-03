-- Modul: Create – obciazenie sieci (Stressometer), predkosci (Speedometer), sterowanie Rotation Speed Controller
local U = require("lib.util")
local D = require("lib.devices")
local M = require("lib.mod")
local UI = require("lib.ui")

local mod = {
  id = "create",
  name = "Create (stres / RPM)",
  kinds = { "stress", "speed", "rsc" },
  options = {
    { key = "step", label = "Krok RPM", type = "choice", default = 16, choices = { 1, 4, 8, 16, 32, 64 } },
  },
}

-- Create domyslnie ogranicza predkosc do 256 RPM (maxRotationSpeed), gra i tak przycina wartosc
local MAX_RPM = 256

function mod.update(ctx, m)
  local rows = {}
  for _, d in ipairs(D.sources(m.cfg.source, mod.kinds)) do
    if d.kind == "stress" then
      local s, c = U.call(d.p, "getStress"), U.call(d.p, "getStressCapacity")
      rows[#rows + 1] = { kind = "stress", label = D.label(d), s = s or 0, c = c or 0 }
    elseif d.kind == "speed" then
      rows[#rows + 1] = { kind = "speed", label = D.label(d), v = U.call(d.p, "getSpeed") or 0 }
    elseif d.kind == "rsc" then
      rows[#rows + 1] = { kind = "rsc", label = D.label(d), v = U.call(d.p, "getTargetSpeed") or 0, name = d.name }
    end
  end
  m.state.rows = rows
end

function mod.draw(ctx, m, c)
  local rows = m.state.rows or {}
  local title = M.title(m, "Create")
  if #rows == 0 then
    return M.message(c, m, title, { "Brak urzadzen Create", "Stressometer / Speedometer /", "Rotation Speed Controller + modem" })
  end
  c:clear(colors.black)
  local over = false
  for _, r in ipairs(rows) do if r.kind == "stress" and r.c > 0 and r.s > r.c then over = true end end
  c:header(title, over and colors.red or m.accent, over and "PRZECIAZENIE" or nil)
  local w, y = c.w - 2, 3
  for _, r in ipairs(rows) do
    if y > c.h then break end
    if r.kind == "stress" then
      local f = U.frac(r.s, r.c)
      local ov = r.c > 0 and r.s > r.c
      c:kv(2, y, w, r.label, U.fmt(r.s, "su") .. " / " .. U.fmt(r.c, "su"), colors.white, ov and colors.red or colors.lightGray)
      c:bar(2, y + 1, w, ov and 1 or f, ov and colors.red or UI.levelColor(f, true), colors.gray, ov and "PRZECIAZONE" or U.pct(f), colors.black)
      y = y + 3
    elseif r.kind == "speed" then
      c:kv(2, y, w, r.label, string.format("%.0f RPM", r.v), colors.white, r.v == 0 and colors.red or colors.lime)
      y = y + 2
    else
      c:kv(2, y, w, r.label, string.format("cel %.0f RPM", r.v), colors.white, colors.cyan)
      local step = m.opts.step or 16
      local bw = math.floor((w - 3) / 4)
      c:button("rpm", 2, y + 1, bw, 1, "-" .. step, colors.white, colors.red, { r.name, -step })
      c:button("rpm", 3 + bw, y + 1, bw, 1, "0", colors.black, colors.lightGray, { r.name, 0 })
      c:button("rpm", 4 + bw * 2, y + 1, bw, 1, "+" .. step, colors.white, colors.green, { r.name, step })
      c:button("rpm", 5 + bw * 3, y + 1, w - 3 - bw * 3, 1, "MAX", colors.black, colors.yellow, { r.name, "max" })
      y = y + 3
    end
  end
end

function mod.touch(ctx, m, btn)
  if btn.id ~= "rpm" then return end
  local d = D.get(btn.data[1])
  if not d then return end
  local delta = btn.data[2]
  local cur = U.call(d.p, "getTargetSpeed") or 0
  local new
  if delta == "max" then new = MAX_RPM
  elseif delta == 0 then new = 0
  else new = U.clamp(math.floor(cur + delta + 0.5), -MAX_RPM, MAX_RPM) end
  pcall(d.p.setTargetSpeed, new)
end

return mod
