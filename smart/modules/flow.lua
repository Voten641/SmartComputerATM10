-- Modul: Detektory przeplywu AP (energy_detector / fluid_detector / gas_detector)
local U = require("lib.util")
local D = require("lib.devices")
local M = require("lib.mod")
local UI = require("lib.ui")

local mod = {
  id = "flow",
  name = "Przeplywy (detektory)",
  kinds = { "flowdet" },
  options = {},
}

local function unitOf(d)
  for _, t in ipairs(d.types) do
    if t == "energy_detector" then return "FE/t", colors.yellow end
    if t == "fluid_detector" then return "mB/t", colors.lightBlue end
    if t == "gas_detector" then return "mB/t", colors.magenta end
  end
  return "/t", colors.white
end

function mod.update(ctx, m)
  local rows = {}
  for _, d in ipairs(D.sources(m.cfg.source, mod.kinds)) do
    local unit, col = unitOf(d)
    rows[#rows + 1] = {
      name = d.name, label = D.label(d), unit = unit, col = col,
      rate = U.call(d.p, "getTransferRate") or 0,
      limit = U.call(d.p, "getTransferRateLimit") or 0,
      max = U.call(d.p, "getMaxTransferRate") or 0,
    }
  end
  m.state.rows = rows
end

function mod.draw(ctx, m, c)
  local rows = m.state.rows or {}
  local title = M.title(m, "Przeplywy")
  if #rows == 0 then
    return M.message(c, m, title, { "Brak detektorow", "Energy / Fluid / Gas Detector (AP)" })
  end
  c:clear(colors.black)
  c:header(title, m.accent, #rows .. " szt.")
  local w, y = c.w - 2, 3
  for _, r in ipairs(rows) do
    if y + 2 > c.h then break end
    c:kv(2, y, w, r.label, U.fmt(r.rate, r.unit), colors.white, r.col)
    local f = U.frac(r.rate, r.limit)
    c:bar(2, y + 1, w, f, UI.levelColor(f, true), colors.gray, "limit " .. U.fmt(r.limit, r.unit), colors.black)
    local bw = math.floor((w - 3) / 4)
    c:button("lim", 2, y + 2, bw, 1, "/2", colors.white, colors.red, { r.name, 0.5 })
    c:button("lim", 3 + bw, y + 2, bw, 1, "x2", colors.white, colors.green, { r.name, 2 })
    c:button("lim", 4 + bw * 2, y + 2, bw, 1, "0", colors.black, colors.lightGray, { r.name, 0 })
    c:button("lim", 5 + bw * 3, y + 2, w - 3 - bw * 3, 1, "MAX", colors.black, colors.yellow, { r.name, "max" })
    y = y + 4
  end
end

function mod.touch(ctx, m, btn)
  if btn.id ~= "lim" then return end
  local d = D.get(btn.data[1])
  if not d then return end
  local k = btn.data[2]
  local cur = U.call(d.p, "getTransferRateLimit") or 0
  local max = U.call(d.p, "getMaxTransferRate") or 0
  local new
  if k == "max" then new = max
  elseif k == 0 then new = 0
  else new = math.floor(math.max(1, cur) * k) end
  pcall(d.p.setTransferRateLimit, U.clamp(new, 0, max))
end

return mod
