-- Smart System ATM10 – glowny program
package.path = "/smart/?.lua;/smart/?/init.lua;" .. package.path

local U = require("lib.util")
local C = require("lib.config")
local D = require("lib.devices")
local UI = require("lib.ui")
local A = require("lib.auto")
local H = require("lib.history")
local AC = require("lib.autocraft")
local DS = require("lib.displays")
local R = require("lib.remote")
local TH = require("lib.theme")
local CB = require("lib.chatbot")

local MODULE_IDS = {
  "overview", "menu", "energy", "fission", "turbine", "boiler", "fusion",
  "storage", "mesearch", "autocraft", "tanks", "create", "flow", "radiation",
  "history", "machines", "players", "clock", "control", "alarms",
}

local function readVersion()
  if fs.exists("/smart/version.txt") then
    local f = fs.open("/smart/version.txt", "r")
    local v = f.readAll()
    f.close()
    return (v:gsub("%s+$", ""))
  end
  return "dev"
end

local ctx = {
  version = readVersion(),
  cfg = C.load(),
  auto = A,
  D = D,
  modules = {},
  moduleIds = MODULE_IDS,
  monitors = {},
  dirty = true,
}

for _, id in ipairs(MODULE_IDS) do
  local ok, mod = pcall(require, "modules." .. id)
  if ok then
    ctx.modules[id] = mod
  else
    A.logEvent("Blad modulu " .. id .. ": " .. tostring(mod), "crit")
  end
end

function ctx.save()
  C.save(ctx.cfg)
end

-- przeladowanie (po zmianie konfiguracji z GUI)
function ctx.reload()
  ctx.dirty = true
  os.queueEvent("smart_wake")
end

-- dzwiek potwierdzenia klikniecia (glosniki w sieci): wysoki = OK, niski = blad
function ctx.feedback(ok)
  if not ctx.cfg.clickSound then return end
  for _, s in ipairs(D.byKind("speaker")) do
    pcall(s.p.playNote, ok and "pling" or "bass", ok and 1 or 2, ok and 18 or 4)
  end
end

-- automatyka zmienila stan przelacznikow (np. SCRAM wylaczyl polaczony przelacznik)
A.cfg = ctx.cfg
A.onChange = function() pcall(ctx.save) end

function ctx.moduleName(id)
  local m = ctx.modules[id]
  return m and m.name or "(nieprzypisany)"
end

---------------------------------------------------------------------------
-- Monitory
---------------------------------------------------------------------------
local function fillOpts(m)
  local mod = ctx.modules[m.cfg.module]
  m.opts = m.cfg.opts
  if mod and mod.options then
    for _, o in ipairs(mod.options) do
      if m.opts[o.key] == nil then m.opts[o.key] = o.default end
    end
  end
end

local function setupMonitor(dev)
  local mcfg = C.monitor(ctx.cfg, dev.name)
  local mon = dev.p
  pcall(mon.setTextScale, mcfg.scale)
  -- paleta motywu PRZED utworzeniem okna (okno kopiuje palete rodzica)
  TH.apply(mon, ctx.cfg.theme)
  local w, h = mon.getSize()
  local win = window.create(mon, 1, 1, w, h, false)
  local old = ctx.monitors[dev.name]
  local m = {
    name = dev.name,
    cfg = mcfg,
    mon = mon,
    win = win,
    canvas = UI.canvas(win),
    accent = UI.color(mcfg.accent, colors.cyan),
    -- zachowujemy stan (historia wykresu itp.) jesli modul sie nie zmienil
    state = (old and old.cfg.module == mcfg.module) and old.state or {},
    identifyUntil = old and old.identifyUntil,
  }
  fillOpts(m)
  return m
end

local function rebuild()
  UI.setTheme(ctx.cfg.theme)
  D.scan(ctx.cfg)
  local mons = {}
  for _, d in ipairs(D.list) do
    if d.kind == "monitor" and not ctx.cfg.hidden[d.name] then
      local ok, m = pcall(setupMonitor, d)
      if ok then mons[d.name] = m end
    end
  end
  ctx.monitors = mons
  A.applyControls(ctx.cfg)
  pcall(R.setup, ctx)
  ctx.dirty = false
end

local function drawIdentify(m, c)
  c:clear(m.accent)
  local label = m.name
  local num = label:match("_(%d+)$")
  if num and c.w >= 8 and c.h >= 7 then
    c:bigCenter(math.max(1, math.floor(c.h / 2) - 3), num, colors.black, m.accent)
    c:center(math.min(c.h, math.floor(c.h / 2) + 3), label, colors.black, m.accent)
  else
    c:center(math.floor(c.h / 2), label, colors.black, m.accent)
  end
end

-- nieprzypisany monitor: wybor modulu dotykiem
local function drawPicker(m, c)
  c:clear(colors.black)
  c:header("Wybierz modul: " .. m.name, colors.gray)
  local cols = c.w >= 30 and 2 or 1
  local bw = math.floor((c.w - 1 - cols) / cols)
  local n = 0
  for _, id in ipairs(MODULE_IDS) do if ctx.modules[id] then n = n + 1 end end
  -- odstep miedzy przyciskami tylko gdy jest miejsce
  local step = (math.ceil(n / cols) * 2 <= c.h - 2) and 2 or 1
  local y, col = 3, 0
  for _, id in ipairs(MODULE_IDS) do
    local mod = ctx.modules[id]
    if mod then
      if y > c.h then break end
      c:button("pick", 2 + col * (bw + 1), y, bw, 1, mod.name, colors.white, colors.gray, id)
      col = col + 1
      if col >= cols then col, y = 0, y + step end
    end
  end
end

local function render(m)
  local c = m.canvas
  m.win.setVisible(false)
  c:reset()
  local ok, err = true, nil
  if m.identifyUntil and os.clock() < m.identifyUntil then
    drawIdentify(m, c)
  else
    local mod = ctx.modules[m.cfg.module]
    if not mod then
      drawPicker(m, c)
    elseif m.err then
      ok, err = false, m.err
    else
      ok, err = pcall(mod.draw, ctx, m, c)
    end
  end
  if not ok then
    c:clear(colors.black)
    c:header("Blad modulu", colors.red)
    local lines = require("cc.strings").wrap(tostring(err), c.w - 2)
    for i, l in ipairs(lines) do c:text(2, 2 + i, l, colors.red, colors.black) end
  end
  m.win.setVisible(true)
end

local function updateMonitor(m)
  local mod = ctx.modules[m.cfg.module]
  if not mod or not mod.update then m.err = nil return end
  local ok, err = pcall(mod.update, ctx, m)
  m.err = (not ok) and err or nil
end

function ctx.identify(name)
  local m = ctx.monitors[name]
  if m then
    m.identifyUntil = os.clock() + 3
    render(m)
  end
end

local function tick()
  -- multiblok uformowal sie po opakowaniu peryferium -> ponowny skan
  if D.stale then D.stale = false; ctx.dirty = true end
  if ctx.dirty then rebuild() end
  local ok, err = pcall(A.tick, ctx.cfg)
  if not ok then A.logEvent("Blad automatyki: " .. tostring(err), "crit") end
  ok, err = pcall(AC.tick, ctx)
  if not ok then A.logEvent("Blad autocraftingu: " .. tostring(err), "warn") end
  pcall(H.sample, ctx)
  pcall(DS.tick, ctx)
  for _, m in pairs(ctx.monitors) do
    updateMonitor(m)
    render(m)
  end
  os.queueEvent("smart_tick")
end

local function tickLoop()
  while true do
    tick()
    local t = os.startTimer(math.max(0.25, ctx.cfg.refresh))
    while true do
      local e, id = os.pullEvent()
      if (e == "timer" and id == t) or e == "smart_wake" then break end
    end
  end
end

local function eventLoop()
  while true do
    local e, a, x, y = os.pullEvent()
    if e == "monitor_touch" then
      local m = ctx.monitors[a]
      if m then
        local btn = m.canvas:hit(x, y)
        local mod = ctx.modules[m.cfg.module]
        if btn and btn.id == "pick" then
          m.cfg.module = btn.data
          m.cfg.opts = {}
          ctx.save()
          ctx.feedback(true)
          ctx.reload()
        elseif btn and mod and mod.touch then
          m.flash = nil
          local ok, err = pcall(mod.touch, ctx, m, btn)
          if not ok then
            A.logEvent("Dotyk: " .. tostring(err), "warn")
            m.flash = { text = tostring(err), untilT = os.clock() + 3, ok = false }
          end
          -- blad = modul ustawil czerwony pasek (flash bez ok)
          ctx.feedback(not (m.flash and not m.flash.ok))
          updateMonitor(m)
          render(m)
        end
      end
    elseif e == "peripheral" or e == "peripheral_detach" or e == "monitor_resize" then
      ctx.reload()
    end
  end
end

local function main()
  term.clear()
  term.setCursorPos(1, 1)
  print("Smart System " .. ctx.version .. " - start...")
  pcall(H.load)
  UI.setTheme(ctx.cfg.theme)
  rebuild()
  local gui = require("gui.menu")
  parallel.waitForAny(tickLoop, eventLoop, function() gui.run(ctx) end, function() R.loop(ctx) end,
    function() CB.listener(ctx) end, function() CB.worker(ctx) end)
end

local ok, err = pcall(main)
-- po wyjsciu zostawiamy monitory z informacja
TH.reset(term.native())
for _, m in pairs(ctx.monitors) do
  pcall(TH.reset, m.mon)
  pcall(function()
    m.win.setVisible(true)
    m.mon.setBackgroundColor(colors.black)
    m.mon.clear()
    m.mon.setCursorPos(1, 1)
    m.mon.setTextColor(colors.gray)
    m.mon.write("Smart System zatrzymany")
  end)
end
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
if not ok and err ~= "Terminated" then
  printError(err)
  return error(err, 0)
end
