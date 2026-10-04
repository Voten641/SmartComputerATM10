-- Modul: Menu konfiguracji na monitorze dotykowym – to samo menu co na komputerze bazy
-- (klawiatura ekranowa do wpisywania, opcjonalna blokada PIN-em pilota)
local U = require("lib.util")
local M = require("lib.mod")

local mod = {
  id = "menu",
  name = "Menu konfiguracji",
  kinds = {},
  options = {
    { key = "lock", label = "Blokada PIN (PIN z Menu > Pilot)", type = "toggle", default = false },
    { key = "lockAfter", label = "Zablokuj po bezczynnosci (s)", type = "number", default = 120, min = 15, max = 3600, step = 15 },
  },
}

local function menu(ctx, m)
  if not m.state.menu then m.state.menu = require("gui.menu").new(ctx, { osk = true }) end
  return m.state.menu
end

local function pin(ctx) return ctx.cfg.remote.pin or "" end

local function locked(ctx, m)
  if not m.opts.lock or pin(ctx) == "" then return false end
  local st = m.state
  return not st.unlocked or os.clock() - (st.lastTouch or 0) > (m.opts.lockAfter or 120)
end

local function drawLock(ctx, m, c)
  local st = m.state
  c:clear(colors.black)
  c:header(M.title(m, "Menu - zablokowane"), colors.red)
  local entry = string.rep("*", #(st.pinEntry or ""))
  c:center(3, "Wpisz PIN:", colors.lightGray, colors.black)
  c:card(math.floor(c.w / 2) - 5, 4, 11, 1, colors.white)
  c:center(4, entry ~= "" and entry or " ", colors.black, colors.white)
  -- klawiatura numeryczna 3x4
  local keysPad = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "C", "0", "OK" }
  local bw = math.max(3, math.min(7, math.floor((c.w - 4) / 3)))
  local bh = math.max(1, math.min(3, math.floor((c.h - 7) / 4)))
  local x0 = math.floor((c.w - (bw * 3 + 2)) / 2) + 1
  for i, k in ipairs(keysPad) do
    local col = (i - 1) % 3
    local row = math.floor((i - 1) / 3)
    local bg = k == "OK" and colors.lime or (k == "C" and colors.orange or colors.gray)
    c:button("pin", x0 + col * (bw + 1), 6 + row * (bh + 1), bw, bh, k, k == "OK" and colors.black or colors.white, bg, k)
  end
  M.flash(c, m)
end

function mod.update(ctx, m) end

function mod.draw(ctx, m, c)
  if locked(ctx, m) then
    m.state.unlocked = false
    return drawLock(ctx, m, c)
  end
  menu(ctx, m).draw(c)
  if m.opts.lock and pin(ctx) == "" then
    c:rect(1, c.h, c.w, 1, colors.orange)
    c:center(c.h, "Blokada nie dziala: ustaw PIN w Menu > Pilot", colors.black, colors.orange)
  end
end

function mod.touch(ctx, m, btn)
  local st = m.state
  if locked(ctx, m) then
    st.unlocked = false
    if btn.id ~= "pin" then return end
    local k = btn.data
    if k == "C" then st.pinEntry = ""
    elseif k == "OK" then
      if (st.pinEntry or "") == pin(ctx) then
        st.unlocked, st.lastTouch = true, os.clock()
        m.flash = { text = "Odblokowano", untilT = os.clock() + 2, ok = true }
      else
        m.flash = { text = "Zly PIN", untilT = os.clock() + 2 }
        ctx.auto.logEvent("Zly PIN na monitorze " .. m.name, "warn")
      end
      st.pinEntry = ""
    elseif #(st.pinEntry or "") < 12 then
      st.pinEntry = (st.pinEntry or "") .. k
    end
    return
  end
  st.lastTouch = os.clock()
  menu(ctx, m).button(btn)
end

return mod
