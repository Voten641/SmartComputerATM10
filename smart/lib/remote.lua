-- Smart System: serwer pilota (Pocket Computer przez rednet, najlepiej Ender Modem)
local U = require("lib.util")
local D = require("lib.devices")

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

function R.handle(ctx, msg)
  if type(msg) ~= "table" then return nil end
  local rc = ctx.cfg.remote
  if not rc.enabled then return { ok = false, err = "Pilot wylaczony" } end
  if rc.pin == "" or tostring(msg.pin) ~= rc.pin then return { ok = false, err = "Zly PIN" } end
  local cmd = msg.cmd
  if cmd == "status" then
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
      local ok, reply = pcall(R.handle, ctx, msg)
      if not ok then reply = { ok = false, err = tostring(reply) } end
      if reply then
        reply.id = type(msg) == "table" and msg.id or nil
        rednet.send(sender, reply, R.PROTOCOL)
      end
    end
  end
end

return R
