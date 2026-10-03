-- Modul: Panel sterowania – przelaczniki redstone (komputer / redstone_relay / CC:C redrouter)
local U = require("lib.util")
local M = require("lib.mod")
local UI = require("lib.ui")

local mod = {
  id = "control",
  name = "Panel sterowania",
  kinds = {},
  options = {
    { key = "cols", label = "Kolumny", type = "choice", default = 2, choices = { 1, 2, 3, 4 } },
  },
}

function mod.update(ctx, m) end

function mod.draw(ctx, m, c)
  local list = ctx.cfg.controls
  local title = M.title(m, "Sterowanie")
  if #list == 0 then
    return M.message(c, m, title, { "Brak przelacznikow", "Dodaj je na komputerze:", "Menu > Panel sterowania" })
  end
  c:clear(colors.black)
  c:header(title, m.accent)
  local cols = math.min(m.opts.cols or 2, #list)
  local rows = math.ceil(#list / cols)
  local gap = 1
  local bw = math.floor((c.w - gap * (cols + 1)) / cols)
  local bh = math.max(1, math.min(5, math.floor((c.h - 2 - gap * rows) / rows)))
  for i, ctl in ipairs(list) do
    local col = (i - 1) % cols
    local row = math.floor((i - 1) / cols)
    local x = 1 + gap + col * (bw + gap)
    local y = 3 + row * (bh + gap)
    if y + bh - 1 <= c.h then
      local on = ctl.state and ctl.mode ~= "pulse"
      local bg = on and UI.color(ctl.color, colors.lime) or colors.gray
      c:button("ctl", x, y, bw, bh, U.trunc(ctl.label, bw), on and colors.black or colors.white, bg, i)
      if bh >= 3 and ctl.mode ~= "pulse" then
        c:center(y + bh - 1, on and "WL" or "WYL", on and colors.black or colors.lightGray, bg, x, bw)
      end
    end
  end
  M.flash(c, m)
end

function mod.touch(ctx, m, btn)
  if btn.id == "ctl" then
    ctx.auto.toggleControl(ctx.cfg, btn.data)
    ctx.save()
    local c = ctx.cfg.controls[btn.data]
    if c then
      m.flash = { text = c.mode == "pulse" and ("Impuls: " .. c.label) or ((c.state and "Wlaczono: " or "Wylaczono: ") .. c.label),
        untilT = os.clock() + 2, ok = true }
    end
  end
end

return mod
