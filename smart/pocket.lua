-- Smart System – pilot na Pocket Computer (wymaga Ender Modemu lub Wireless Modemu)
package.path = "/smart/?.lua;/smart/?/init.lua;" .. package.path
local U = require("lib.util")
local UI = require("lib.ui")

local PROTO = "smart_atm10"
local CFG_PATH = "/smart/data/pocket.lua"

local function loadCfg()
  if fs.exists(CFG_PATH) then
    local f = fs.open(CFG_PATH, "r")
    local t = textutils.unserialize(f.readAll())
    f.close()
    if type(t) == "table" then return t end
  end
  return {}
end

local function saveCfg(t)
  if not fs.exists("/smart/data") then fs.makeDir("/smart/data") end
  local f = fs.open(CFG_PATH, "w")
  f.write(textutils.serialize(t))
  f.close()
end

local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
if not modem then
  printError("Brak modemu bezprzewodowego!")
  print("Zaloz Ender Modem na Pocket Computer (crafting).")
  return
end
rednet.open(peripheral.getName(modem))

local cfg = loadCfg()
local c = UI.canvas(term.current())

---------------------------------------------------------------------------
local function setup()
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)
  print("Szukam baz Smart System...")
  local ids = { rednet.lookup(PROTO, nil, 3) }
  if #ids == 0 then
    printError("Nie znaleziono.")
    print("Na komputerze bazy: Menu > Pilot > Wlaczony + PIN, modem bezprzewodowy.")
    print("Enter = ponow, Q = wyjdz")
    local _, k = os.pullEvent("key")
    if k == keys.q then return false end
    return setup()
  end
  print("Znalezione komputery (ID):")
  for i, id in ipairs(ids) do print(" " .. i .. ") #" .. id) end
  write("Wybierz numer: ")
  local n = tonumber(read()) or 1
  cfg.server = ids[n] or ids[1]
  write("PIN: ")
  cfg.pin = read("*")
  saveCfg(cfg)
  return true
end

local reqId = 0
local function request(msg)
  reqId = reqId + 1
  msg.id, msg.pin = reqId, cfg.pin
  rednet.send(cfg.server, msg, PROTO)
  local deadline = os.clock() + 3
  while os.clock() < deadline do
    local sender, reply = rednet.receive(PROTO, deadline - os.clock())
    if sender == cfg.server and type(reply) == "table" and reply.id == reqId then return reply end
  end
  return { ok = false, err = "Brak odpowiedzi" }
end

---------------------------------------------------------------------------
local TABS = { { id = "stan", label = "Stan" }, { id = "reakt", label = "Reakt" }, { id = "przel", label = "Przel" }, { id = "alarm", label = "Alarm" } }
local tab = "stan"
local status, lastErr, lastOk = nil, nil, 0
local scroll = 0

local function draw()
  c:reset()
  c:clear(colors.black)
  local alarms = status and #status.alarms or 0
  c:header(status and status.title or "Smart", alarms > 0 and colors.red or colors.cyan, status and status.time or "")
  local tw = math.floor(c.w / #TABS)
  for i, t in ipairs(TABS) do
    local active = t.id == tab
    c:button("tab", 1 + (i - 1) * tw, 2, i == #TABS and c.w - (i - 1) * tw or tw, 1,
      t.label .. (t.id == "alarm" and alarms > 0 and "!" or ""), active and colors.black or colors.white,
      active and colors.lightBlue or colors.gray, t.id)
  end
  local y, w = 4, c.w - 2
  if not status then
    c:center(8, lastErr or "Laczenie...", colors.orange, colors.black)
  elseif tab == "stan" then
    if status.energy then
      local f = status.energy.f
      c:text(2, y, "Energia", colors.yellow, colors.black); y = y + 1
      c:bar(2, y, w, f, UI.levelColor(f), colors.gray, U.pct(f), colors.black); y = y + 1
      c:text(2, y, U.fmt(status.energy.stored, "FE") .. " / " .. U.fmt(status.energy.cap, "FE"), colors.lightGray, colors.black)
      y = y + 2
    end
    c:text(2, y, "Reaktory", colors.yellow, colors.black); y = y + 1
    for _, r in ipairs(status.reactors) do
      local s, col = r.trip and "SCRAM" or (r.on and "ON" or "OFF"), r.trip and colors.red or (r.on and colors.lime or colors.orange)
      c:kv(2, y, w, U.trunc(r.label, 12), s .. " " .. U.temp(r.temp), colors.white, col)
      y = y + 1
    end
    y = y + 1
    c:text(2, y, alarms == 0 and "Alarmy: brak" or ("Alarmy: " .. alarms), alarms == 0 and colors.lime or colors.red, colors.black)
  elseif tab == "reakt" then
    if #status.reactors == 0 then c:center(6, "Brak reaktorow", colors.lightGray, colors.black) end
    for _, r in ipairs(status.reactors) do
      if y + 4 > c.h then break end
      c:text(2, y, U.trunc(r.label, w), colors.yellow, colors.black); y = y + 1
      c:kv(2, y, w, "Temp " .. U.temp(r.temp), string.format("%.1f mB/t", r.burn or 0), colors.lightGray, colors.white); y = y + 1
      local half = math.floor((w - 1) / 2)
      if r.trip then
        c:button("cmd", 2, y, w, 1, "RESET", colors.black, colors.yellow, { "reset", r.name })
      else
        c:button("cmd", 2, y, half, 1, "START", colors.black, colors.lime, { "start", r.name })
        c:button("cmd", 3 + half, y, w - half - 1, 1, "SCRAM", colors.white, colors.red, { "scram", r.name })
      end
      y = y + 1
      local q = math.floor((w - 3) / 4)
      c:button("cmd", 2, y, q, 1, "-10", colors.white, colors.gray, { "burn", r.name, -10 })
      c:button("cmd", 3 + q, y, q, 1, "-1", colors.white, colors.gray, { "burn", r.name, -1 })
      c:button("cmd", 4 + q * 2, y, q, 1, "+1", colors.white, colors.gray, { "burn", r.name, 1 })
      c:button("cmd", 5 + q * 3, y, w - 3 - q * 3, 1, "+10", colors.white, colors.gray, { "burn", r.name, 10 })
      y = y + 2
    end
  elseif tab == "przel" then
    if #status.controls == 0 then c:center(6, "Brak przelacznikow", colors.lightGray, colors.black) end
    for i, ctl in ipairs(status.controls) do
      if y > c.h - 1 then break end
      local on = ctl.state and ctl.mode ~= "pulse"
      c:button("ctl", 2, y, w, 1, ctl.label .. (ctl.mode == "pulse" and " (impuls)" or (on and " [WL]" or " [WYL]")),
        on and colors.black or colors.white, on and colors.lime or colors.gray, i)
      y = y + 2
    end
  elseif tab == "alarm" then
    if alarms == 0 then c:center(6, "Brak alarmow", colors.lime, colors.black) end
    local lines = {}
    for _, a in ipairs(status.alarms) do
      for _, l in ipairs(require("cc.strings").wrap(a.text, w)) do lines[#lines + 1] = { l, a.level } end
    end
    scroll = U.clamp(scroll, 0, math.max(0, #lines - (c.h - y)))
    for i = 1 + scroll, #lines do
      if y > c.h - 1 then break end
      c:text(2, y, lines[i][1], lines[i][2] == "crit" and colors.red or colors.orange, colors.black)
      y = y + 1
    end
  end
  -- stopka
  c:rect(1, c.h, c.w, 1, colors.gray)
  local foot = lastErr and ("! " .. lastErr) or ("OK " .. math.floor(os.clock() - lastOk) .. "s temu")
  c:text(1, c.h, U.trunc(foot, c.w - 6), lastErr and colors.red or colors.lightGray, colors.gray)
  c:button("setup", c.w - 4, c.h, 5, 1, "Baza", colors.black, colors.lightGray)
end

local function apply(reply)
  if reply.ok then
    status, lastErr, lastOk = reply.status or status, nil, os.clock()
  else
    lastErr = reply.err
    if reply.err == "Zly PIN" then
      draw()
      sleep(1)
      cfg.pin = nil
    end
  end
end

---------------------------------------------------------------------------
if not cfg.server or not cfg.pin then
  if not setup() then return end
end

apply(request({ cmd = "status" }))
draw()
local timer = os.startTimer(2)
while true do
  if not cfg.pin then
    if not setup() then return end
    apply(request({ cmd = "status" }))
  end
  local e, a, b, y = os.pullEvent()
  if e == "timer" and a == timer then
    apply(request({ cmd = "status" }))
    timer = os.startTimer(2)
  elseif e == "mouse_click" then
    local btn = c:hit(b, y)
    if btn then
      if btn.id == "tab" then tab, scroll = btn.data, 0
      elseif btn.id == "cmd" then
        apply(request({ cmd = btn.data[1], name = btn.data[2], delta = btn.data[3] }))
      elseif btn.id == "ctl" then
        apply(request({ cmd = "control", index = btn.data }))
      elseif btn.id == "setup" then
        cfg.server, cfg.pin = nil, nil
        saveCfg(cfg)
        if not setup() then return end
        apply(request({ cmd = "status" }))
      end
    end
    -- nowy timer, bo podczas zapytania stary mogl zostac pominiety
    timer = os.startTimer(2)
  elseif e == "mouse_scroll" then
    scroll = scroll + a
  elseif e == "key" and a == keys.q then
    break
  end
  draw()
end
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
