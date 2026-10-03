-- Modul: Wykresy historii (dane zapisywane na dysku przez lib/history)
local U = require("lib.util")
local M = require("lib.mod")
local H = require("lib.history")

local KEYS, LABELS = {}, {}
for _, d in ipairs(H.DEFS) do KEYS[#KEYS + 1] = d.key; LABELS[d.key] = d.label end
local RANGES = { 3600, 6 * 3600, 24 * 3600 }
local RANGE_LABEL = { [3600] = "1h", [6 * 3600] = "6h", [24 * 3600] = "24h" }

local mod = {
  id = "history",
  name = "Wykresy historii",
  kinds = {},
  options = {
    { key = "series", label = "Seria", type = "choice", default = "energy", choices = KEYS, labels = LABELS },
    { key = "range", label = "Zakres", type = "choice", default = 6 * 3600, choices = RANGES, labels = RANGE_LABEL },
  },
}

local function fmtValue(def, v)
  if type(v) ~= "number" then return "-" end
  if def.unit == "%" then return string.format("%.1f%%", v) end
  if def.unit == "Sv/h" then return U.sv(v) end
  return U.fmt(v, def.unit)
end

function mod.update(ctx, m) end

function mod.draw(ctx, m, c)
  local def = H.byKey[m.opts.series] or H.DEFS[1]
  local range = m.opts.range or 3600
  local pts = H.range(def.key, range)
  c:clear(colors.black)
  c:header(M.title(m, def.label), m.accent, RANGE_LABEL[range] or "")
  -- przyciski zmiany serii i zakresu
  c:button("prev", 1, 2, 3, 1, "<", colors.white, colors.gray)
  c:button("range", 5, 2, 5, 1, RANGE_LABEL[range] or "?", colors.black, colors.lightGray)
  c:button("next", c.w - 2, 2, 3, 1, ">", colors.white, colors.gray)
  if #pts == 0 then
    c:center(math.floor(c.h / 2), "Brak danych - probki co " .. ctx.cfg.history.interval .. "s", colors.lightGray, colors.black)
    return
  end
  local lo, hi = math.huge, -math.huge
  for _, p in ipairs(pts) do
    if p[2] < lo then lo = p[2] end
    if p[2] > hi then hi = p[2] end
  end
  local last = pts[#pts][2]
  c:kv(11, 2, c.w - 14, "teraz", fmtValue(def, last), colors.lightGray, colors.yellow)

  local gx, gy, gw, gh = 2, 4, c.w - 2, c.h - 4
  if def.unit == "%" then lo, hi = 0, 100 end
  local span = hi - lo
  if span <= 0 then span = math.abs(hi) > 0 and math.abs(hi) * 0.1 or 1; lo = lo - span / 2 end
  -- probki grupowane w kolumny po czasie
  local now = U.now()
  local cols = {}
  local per = range / gw
  for _, p in ipairs(pts) do
    local i = math.floor((p[1] - (now - range)) / per) + 1
    if i >= 1 and i <= gw then
      local col = cols[i] or { s = 0, n = 0 }
      col.s, col.n = col.s + p[2], col.n + 1
      cols[i] = col
    end
  end
  local vals = {}
  local prev
  for i = 1, gw do
    local col = cols[i]
    if col then prev = (col.s / col.n - lo) / span end
    vals[i] = prev or 0
  end
  c:graph(gx, gy, gw, gh, vals, m.accent, colors.black)
  c:text(gx, gy, fmtValue(def, lo + span), colors.white, colors.black)
  c:text(gx, gy + gh - 1, fmtValue(def, lo), colors.white, colors.black)
  c:right(c.h, "-" .. (RANGE_LABEL[range] or "") .. " ... teraz", colors.gray, colors.black)
end

function mod.touch(ctx, m, btn)
  local i = U.indexOf(KEYS, m.opts.series) or 1
  if btn.id == "prev" then m.opts.series = KEYS[(i - 2) % #KEYS + 1]
  elseif btn.id == "next" then m.opts.series = KEYS[i % #KEYS + 1]
  elseif btn.id == "range" then
    local r = U.indexOf(RANGES, m.opts.range) or 1
    m.opts.range = RANGES[r % #RANGES + 1]
  else return end
  ctx.save()
end

return mod
