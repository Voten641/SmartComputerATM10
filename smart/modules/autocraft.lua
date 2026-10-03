-- Modul: Autocrafting – stan utrzymywanych zapasow ME/RS
local U = require("lib.util")
local M = require("lib.mod")
local AC = require("lib.autocraft")

local mod = {
  id = "autocraft",
  name = "Autocrafting",
  kinds = {},
  options = {},
}

local STATE_COLOR = { ok = colors.lime, crafting = colors.yellow, error = colors.red, off = colors.gray }

function mod.update(ctx, m) end

function mod.draw(ctx, m, c)
  local cfg = ctx.cfg.autocraft
  local title = M.title(m, "Autocrafting")
  c:clear(colors.black)
  c:header(title, m.accent)
  c:button("toggle", c.w - 7, 1, 7, 1, cfg.enabled and "WL" or "WYL", colors.black, cfg.enabled and colors.lime or colors.red)
  if #cfg.items == 0 then
    c:center(math.floor(c.h / 2), "Dodaj przedmioty w menu komputera:", colors.lightGray, colors.black)
    c:center(math.floor(c.h / 2) + 1, "Menu > Autocrafting", colors.lightGray, colors.black)
    return
  end
  local w = c.w - 2
  local perRow = c.h >= #cfg.items * 2 + 2 and 2 or 1
  local visible = math.floor((c.h - 2) / perRow)
  local maxOff = math.max(0, #cfg.items - visible)
  m.state.offset = U.clamp(m.state.offset or 0, 0, maxOff)
  local lw = w - (maxOff > 0 and 4 or 0)
  local y = 3
  for i = 1, visible do
    local it = cfg.items[i + m.state.offset]
    if not it then break end
    local st = AC.status[it.name] or {}
    local label = it.label ~= "" and it.label or U.prettyId(it.name)
    local count = st.count or 0
    local col = STATE_COLOR[st.state or "off"] or colors.gray
    if perRow == 2 then
      c:kv(2, y, lw, label, st.msg or "-", colors.white, col)
      c:bar(2, y + 1, lw, U.frac(count, it.keep), col, colors.gray, U.fmt(count) .. " / " .. U.fmt(it.keep), colors.black)
      y = y + 2
    else
      M.inlineBar(c, 2, y, lw, label, U.frac(count, it.keep), col, U.fmt(count) .. "/" .. U.fmt(it.keep))
      y = y + 1
    end
  end
  if maxOff > 0 then c:scrollButtons("list", c.w - 3, 3, c.h - 2, m.accent) end
end

function mod.touch(ctx, m, btn)
  if btn.id == "toggle" then
    ctx.cfg.autocraft.enabled = not ctx.cfg.autocraft.enabled
    ctx.save()
  elseif btn.id == "list_up" then m.state.offset = (m.state.offset or 0) - 3
  elseif btn.id == "list_down" then m.state.offset = (m.state.offset or 0) + 3 end
end

return mod
