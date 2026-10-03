-- Modul: Gracze (AP Player Detector)
local U = require("lib.util")
local M = require("lib.mod")

local mod = {
  id = "players",
  name = "Gracze",
  kinds = { "player" },
  single = true,
  options = {
    { key = "range", label = "Zasieg 'w bazie'", type = "number", default = 32, min = 1, max = 1000, step = 8 },
  },
}

function mod.update(ctx, m)
  local d = M.single(m, mod.kinds)
  local st = {}
  m.state = st
  if not d then return end
  st.dev = d
  st.online = U.call(d.p, "getOnlinePlayers") or {}
  local near = U.call(d.p, "getPlayersInRange", m.opts.range or 32) or {}
  st.near = {}
  for _, n in ipairs(near) do st.near[n] = true end
  table.sort(st.online)
end

function mod.draw(ctx, m, c)
  local st = m.state
  local title = M.title(m, "Gracze")
  if not st.dev then return M.message(c, m, title, { "Brak Player Detectora" }) end
  c:clear(colors.black)
  c:header(title, m.accent, #st.online .. " online")
  local y = 3
  for _, n in ipairs(st.online) do
    if y > c.h then break end
    local home = st.near[n]
    c:text(2, y, home and "\7 " or "  ", colors.lime, colors.black)
    c:text(4, y, U.trunc(n, c.w - 14), colors.white, colors.black)
    c:right(y, home and "w bazie " or "", colors.lime, colors.black)
    y = y + 1
  end
  if #st.online == 0 then c:center(4, "Nikogo nie ma", colors.lightGray, colors.black) end
end

return mod
