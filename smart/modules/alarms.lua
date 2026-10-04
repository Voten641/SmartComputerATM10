-- Modul: Alarmy i dziennik zdarzen
local U = require("lib.util")
local M = require("lib.mod")

local mod = {
  id = "alarms",
  name = "Alarmy i dziennik",
  kinds = {},
  options = {
    { key = "log", label = "Pokaz dziennik", type = "toggle", default = true },
  },
}

function mod.update(ctx, m) end

local LEVEL = { crit = colors.red, warn = colors.orange, ok = colors.lime, info = colors.lightGray }

function mod.draw(ctx, m, c)
  local list = ctx.auto.list()
  c:clear(colors.black)
  local hdr = #list == 0 and colors.green or (list[1].level == "crit" and colors.red or colors.orange)
  c:header(M.title(m, "Alarmy"), hdr, #list == 0 and "OK" or (#list .. " aktywne"))
  local y = 3
  if #list == 0 then
    c:center(y, "Brak aktywnych alarmow", colors.lime, colors.black)
    y = y + 2
  else
    for _, a in ipairs(list) do
      if y > c.h then break end
      c:card(1, y, c.w, 1, LEVEL[a.level])
      c:text(2, y, U.trunc(a.text, c.w - 2), colors.black, LEVEL[a.level])
      y = y + 1
    end
    y = y + 1
  end
  if m.opts.log and y < c.h then
    c:text(2, y, "Dziennik:", colors.yellow, colors.black)
    y = y + 1
    for _, e in ipairs(ctx.auto.log) do
      if y > c.h then break end
      c:text(2, y, e.t, colors.gray, colors.black)
      c:text(11, y, U.trunc(e.text, c.w - 11), LEVEL[e.level] or colors.white, colors.black)
      y = y + 1
    end
  end
end

return mod
