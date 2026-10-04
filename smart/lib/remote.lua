-- Smart System: serwer pilota (Pocket Computer przez rednet, najlepiej Ender Modem)
local U = require("lib.util")
local D = require("lib.devices")
local UI = require("lib.ui")

local R = {}
R.PROTOCOL = "smart_atm10"
R.opened = {}
R.hostname = nil

function R.wirelessModems()
  local r = {}
  for _, d in ipairs(D.list) do
    if d.kind == "modem" and U.call(d.p, "isWireless") then r[#r + 1] = d.name end
  end
  return r
end

-- otwiera modemy bezprzewodowe i rejestruje hosta (wywolywane przy przebudowie)
function R.setup(ctx)
  local rc = ctx.cfg.remote
  if not rc.enabled then
    if R.hostname then pcall(rednet.unhost, R.PROTOCOL) R.hostname = nil end
    return
  end
  local mods = R.wirelessModems()
  for _, name in ipairs(mods) do
    if not rednet.isOpen(name) then pcall(rednet.open, name) end
  end
  if #mods > 0 then
    local host = (ctx.cfg.title ~= "" and ctx.cfg.title or "Baza") .. " #" .. os.getComputerID()
    if host ~= R.hostname then
      pcall(rednet.host, R.PROTOCOL, host)
      R.hostname = host
    end
  end
end

local function findReactor(name)
  local d = D.get(name)
  if d and d.kind == "fission" then return d end
  return nil
end

function R.status(ctx)
  local f, stored, cap = ctx.auto.readEnergy("auto")
  local st = {
    title = ctx.cfg.title,
    theme = ctx.cfg.theme,
    time = textutils.formatTime(os.time("ingame"), true),
    energy = f and { f = f, stored = stored, cap = cap } or nil,
    reactors = {}, controls = {}, alarms = {},
  }
  for _, d in ipairs(D.byKind("fission")) do
    if D.formed(d) then
      st.reactors[#st.reactors + 1] = {
        name = d.name, label = D.label(d),
        on = U.call(d.p, "getStatus") == true,
        temp = U.call(d.p, "getTemperature"),
        damage = U.call(d.p, "getDamagePercent"),
        burn = U.call(d.p, "getBurnRate"),
        trip = ctx.auto.trips[d.name],
      }
    end
  end
  for i, c in ipairs(ctx.cfg.controls) do
    st.controls[i] = { label = c.label, state = c.state, mode = c.mode }
  end
  for _, a in ipairs(ctx.auto.list()) do st.alarms[#st.alarms + 1] = { text = a.text, level = a.level } end
  return st
end

---------------------------------------------------------------------------
-- Pelne menu na pilocie: dla kazdego pocketa trzymamy wlasna instancje menu rysowana
-- do niewidocznego okna; pilot dostaje gotowe linie (tekst + kolory blit) i odsyla klikniecia.
---------------------------------------------------------------------------
R.sessions = {}
local SESSION_TIMEOUT = 600

local function menuSession(ctx, id, w, h)
  w = U.clamp(math.floor(tonumber(w) or 26), 10, 100)
  h = U.clamp(math.floor(tonumber(h) or 19), 6, 50)
  local s = R.sessions[id]
  if not s then
    local win = window.create(term.native(), 1, 1, w, h, false)
    s = { menu = require("gui.menu").new(ctx, {}), win = win, canvas = UI.canvas(win), w = w, h = h }
    R.sessions[id] = s
  elseif s.w ~= w or s.h ~= h then
    s.win.reposition(1, 1, w, h)
    s.w, s.h = w, h
  end
  s.last = os.clock()
  -- sprzatanie porzuconych sesji
  for sid, other in pairs(R.sessions) do
    if os.clock() - (other.last or 0) > SESSION_TIMEOUT then R.sessions[sid] = nil end
  end
  return s
end

local function menuFrame(s)
  s.menu.draw(s.canvas)
  local lines = {}
  for y = 1, s.h do
    local t, f, b = s.win.getLine(y)
    lines[y] = { t, f, b }
  end
  return lines
end

function R.menu(ctx, sender, msg)
  local s = menuSession(ctx, sender, msg.w, msg.h)
  local a = msg.action
  if a ~= "frame" then
    -- akcje ida na ostatnio wyslana klatke (przyciski sa zarejestrowane w s.canvas)
    if s.drawn == nil then menuFrame(s) end
    if a == "click" then s.menu.click(tonumber(msg.x) or 0, tonumber(msg.y) or 0)
    elseif a == "scroll" then s.menu.scroll(tonumber(msg.dir) or 0)
    elseif a == "char" and type(msg.ch) == "string" then
      for ch in msg.ch:gmatch(".") do s.menu.char(ch) end
    elseif a == "key" then s.menu.key(tonumber(msg.key) or 0) end
  end
  local lines = menuFrame(s)
  s.drawn = true
  return { ok = true, lines = lines, input = s.menu.isInput(), theme = ctx.cfg.theme }
end

function R.handle(ctx, msg, sender)
  if type(msg) ~= "table" then return nil end
  local rc = ctx.cfg.remote
  if not rc.enabled then return { ok = false, err = "Pilot wylaczony" } end
  if rc.pin == "" or tostring(msg.pin) ~= rc.pin then return { ok = false, err = "Zly PIN" } end
  local cmd = msg.cmd
  if cmd == "menu" then
    return R.menu(ctx, sender, msg)
  elseif cmd == "status" then
    return { ok = true, status = R.status(ctx) }
  elseif cmd == "start" or cmd == "scram" or cmd == "reset" or cmd == "burn" then
    local d = findReactor(msg.name)
    if not d then return { ok = false, err = "Brak reaktora" } end
    if cmd == "start" then
      local ok, err = ctx.auto.start(d)
      if not ok then return { ok = false, err = err } end
    elseif cmd == "scram" then
      ctx.auto.scram(d)
    elseif cmd == "reset" then
      ctx.auto.reset(d.name)
    else
      local cur = U.call(d.p, "getBurnRate") or 0
      local max = U.call(d.p, "getMaxBurnRate") or 0
      local ok, err = pcall(d.p.setBurnRate, U.clamp(U.round(cur + (tonumber(msg.delta) or 0), 1), 0, max))
      if not ok then return { ok = false, err = tostring(err) } end
    end
    ctx.auto.logEvent("Pilot: " .. cmd .. " " .. D.label(d))
    return { ok = true, status = R.status(ctx) }
  elseif cmd == "control" then
    local i = tonumber(msg.index)
    if not i or not ctx.cfg.controls[i] then return { ok = false, err = "Brak przelacznika" } end
    ctx.auto.toggleControl(ctx.cfg, i)
    ctx.save()
    return { ok = true, status = R.status(ctx) }
  end
  return { ok = false, err = "Nieznana komenda" }
end

-- petla odbioru (osobna korutyna w main)
function R.loop(ctx)
  while true do
    local _, sender, msg, protocol = os.pullEvent("rednet_message")
    if protocol == R.PROTOCOL and ctx.cfg.remote.enabled then
      local ok, reply = pcall(R.handle, ctx, msg, sender)
      if not ok then reply = { ok = false, err = tostring(reply) } end
      if reply then
        reply.id = type(msg) == "table" and msg.id or nil
        rednet.send(sender, reply, R.PROTOCOL)
      end
    end
  end
end

return R
