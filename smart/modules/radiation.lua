-- Modul: Promieniowanie Mekanism (AP Environment Detector, getRadiationRaw w Sv/h)
local U = require("lib.util")
local D = require("lib.devices")
local M = require("lib.mod")
local H = require("lib.history")

local mod = {
  id = "radiation",
  name = "Promieniowanie",
  kinds = { "env" },
  options = {},
}

local LEVEL_COLOR = {
  brak = colors.lime, LOW = colors.yellow, MEDIUM = colors.orange,
  ELEVATED = colors.red, HIGH = colors.red, EXTREME = colors.magenta,
}

function mod.update(ctx, m)
  local rows = {}
  for _, d in ipairs(D.sources(m.cfg.source, mod.kinds)) do
    local r = U.call(d.p, "getRadiationRaw")
    if type(r) == "number" then rows[#rows + 1] = { label = D.label(d), r = r } end
  end
  m.state.rows = rows
end

function mod.draw(ctx, m, c)
  local rows = m.state.rows or {}
  local title = M.title(m, "Promieniowanie")
  if #rows == 0 then
    return M.message(c, m, title, { "Brak danych", "Environment Detector (AP)", "+ Mekanism" })
  end
  local worst = rows[1]
  for _, r in ipairs(rows) do if r.r > worst.r then worst = r end end
  local lvl = ctx.auto.radLevel(worst.r)
  local col = LEVEL_COLOR[lvl] or colors.white
  c:clear(colors.black)
  c:header(title, col, lvl)
  local y = 3
  c:rect(2, y, c.w - 2, 3, col)
  c:center(y + 1, U.sv(worst.r) .. "  " .. lvl, colors.black, col)
  y = y + 4
  for _, r in ipairs(rows) do
    if y > c.h then break end
    local l = ctx.auto.radLevel(r.r)
    c:kv(2, y, c.w - 2, r.label, U.sv(r.r), colors.white, LEVEL_COLOR[l] or colors.white)
    y = y + 1
  end
  -- wykres ostatnich 6h (skala logarytmiczna, tlo 100 nSv/h ... 100 Sv/h)
  local pts = H.range("radiation", 6 * 3600)
  if #pts > 1 and c.h - y >= 4 then
    y = y + 1
    c:text(2, y, "Ostatnie 6h (log):", colors.lightGray, colors.black)
    y = y + 1
    local vals = {}
    local function log10(x) return math.log(x) / math.log(10) end
    local lo, hi = log10(1e-7), log10(100)
    for _, p in ipairs(pts) do
      vals[#vals + 1] = (log10(math.max(p[2], 1e-7)) - lo) / (hi - lo)
    end
    c:graph(2, y, c.w - 2, c.h - y + 1, vals, function(v)
      local sv = 10 ^ (lo + v * (hi - lo))
      return LEVEL_COLOR[ctx.auto.radLevel(sv)] or colors.white
    end, colors.black)
  end
end

return mod
