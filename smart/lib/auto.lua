-- Smart System: alarmy, zabezpieczenia reaktora, automatyka
local U = require("lib.util")
local D = require("lib.devices")

local A = {}
A.active = {}   -- [id] = { id, level = "crit"|"warn", text, since }
A.log = {}      -- ostatnie zdarzenia { t, text, level }
A.trips = {}    -- [nazwaReaktora] = powod (zatrzask SCRAM do recznego resetu)
A.chatQueue = {}
A.energyFrac = nil

local function logEvent(text, level)
  table.insert(A.log, 1, { t = os.date("%H:%M:%S"), text = text, level = level or "info" })
  while #A.log > 50 do table.remove(A.log) end
end
A.logEvent = logEvent

local function notify(cfg, text, level)
  local ch = cfg.alarms.chat
  if ch.enabled then
    A.chatQueue[#A.chatQueue + 1] = (level == "crit" and "&c" or "&e") .. text
  end
end

local function raise(cur, cfg, id, level, text)
  cur[id] = { id = id, level = level, text = text, since = (A.active[id] and A.active[id].since) or os.clock() }
  if not A.active[id] then
    logEvent(text, level)
    notify(cfg, text, level)
  end
end

-- suma energii (FE) z magazynow
function A.readEnergy(source)
  local kinds = { "matrix", "cube", "energy" }
  local stored, cap = 0, 0
  for _, d in ipairs(D.sources(source, kinds)) do
    if D.formed(d) then
      local e, m = D.energy(d)
      if e and m then stored, cap = stored + e, cap + m end
    end
  end
  if cap <= 0 then return nil end
  return stored / cap, stored, cap
end

function A.reactors(which)
  if which and which ~= "auto" then
    local d = D.get(which)
    return d and { d } or {}
  end
  return D.byKind("fission")
end

function A.reset(name)
  if A.trips[name] then
    logEvent("Reset zabezpieczenia: " .. D.label(D.get(name)), "info")
  end
  A.trips[name] = nil
end

-- przelaczniki redstone polaczone z urzadzeniem (control.link) i "sterowane razem" (linkSync)
function A.linkedControls(cfg, name)
  local r = {}
  for i, c in ipairs((cfg or A.cfg or {}).controls or {}) do
    if c.link == name then r[#r + 1] = i end
  end
  return r
end

function A.syncLinked(name, on)
  local cfg = A.cfg
  if not cfg then return end
  for _, i in ipairs(A.linkedControls(cfg, name)) do
    local c = cfg.controls[i]
    if c.linkSync ~= false then
      if c.mode == "pulse" then
        D.setRedstone(c.target, c.side, true)
        sleep(0.3)
        D.setRedstone(c.target, c.side, false)
      elseif c.state ~= on then
        c.state = on
        D.setRedstone(c.target, c.side, on)
      end
    end
  end
  if A.onChange then A.onChange() end
end

-- reczny start reaktora (blokowany gdy zabezpieczenie zadzialalo)
function A.start(dev)
  if A.trips[dev.name] then return false, "Zabezpieczenie aktywne - zrob RESET" end
  if U.call(dev.p, "getStatus") then
    A.syncLinked(dev.name, true)
    return true
  end
  local ok, err = pcall(dev.p.activate)
  if not ok then return false, tostring(err) end
  logEvent("Start reaktora: " .. D.label(dev))
  A.syncLinked(dev.name, true)
  return true
end

function A.scram(dev, reason)
  if U.call(dev.p, "getStatus") then
    pcall(dev.p.scram)
    logEvent("SCRAM " .. D.label(dev) .. (reason and (": " .. reason) or ""), reason and "crit" or "info")
  end
  A.syncLinked(dev.name, false)
end

local function checkFission(cfg, cur)
  local f = cfg.alarms.fission
  for _, d in ipairs(D.byKind("fission")) do
    if D.formed(d) then
      local p = d.p
      local active = U.call(p, "getStatus")
      local temp = U.call(p, "getTemperature") or 0
      local dmg = U.call(p, "getDamagePercent") or 0
      local waste = (U.call(p, "getWasteFilledPercentage") or 0) * 100
      local cool = (U.call(p, "getCoolantFilledPercentage") or 1) * 100
      local heated = (U.call(p, "getHeatedCoolantFilledPercentage") or 0) * 100
      local reason
      if temp > f.maxTemp then reason = string.format("temperatura %.0fK", temp)
      elseif dmg > f.maxDamage then reason = string.format("uszkodzenie %d%%", math.floor(dmg))
      elseif waste > f.maxWaste then reason = string.format("odpady %.0f%%", waste)
      elseif cool < f.minCoolant then reason = string.format("chlodziwo %.0f%%", cool)
      elseif heated > f.maxHeated then reason = string.format("gorace chlodziwo %.0f%%", heated)
      end
      if reason and f.autoScram then
        if active then A.scram(d, reason) end
        A.trips[d.name] = A.trips[d.name] or reason
      end
      if A.trips[d.name] then
        raise(cur, cfg, "trip:" .. d.name, "crit", "SCRAM " .. D.label(d) .. ": " .. A.trips[d.name])
      elseif reason then
        raise(cur, cfg, "fis:" .. d.name, "crit", D.label(d) .. ": " .. reason)
      end
    end
  end
end

local function autoPower(cfg)
  local ap = cfg.alarms.autoPower
  if not ap.enabled then return end
  local frac = A.readEnergy(ap.source)
  if not frac then return end
  for _, d in ipairs(A.reactors(ap.reactor)) do
    if D.formed(d) and not A.trips[d.name] then
      local active = U.call(d.p, "getStatus")
      if not active and frac * 100 < ap.startBelow then
        if A.start(d) then logEvent("Auto: start (energia " .. U.pct(frac) .. ")") end
      elseif active and frac * 100 > ap.stopAbove then
        A.scram(d)
        logEvent("Auto: stop (energia " .. U.pct(frac) .. ")")
      end
    end
  end
end

local function checkStorage(cfg, cur)
  local sf = cfg.alarms.storageFull
  if not sf.enabled then return end
  for _, d in ipairs(D.byKind({ "me", "rs" })) do
    local used, max = U.call(d.p, "getUsedItemStorage"), U.call(d.p, "getMaxItemStorage")
    if type(used) == "number" and type(max) == "number" and max > 0 and used / max * 100 > sf.above then
      raise(cur, cfg, "full:" .. d.name, "warn", D.label(d) .. ": magazyn " .. U.pct(used / max))
    end
  end
end

local function checkTanks(cfg, cur)
  local tf = cfg.alarms.tankFull
  if not tf.enabled then return end
  for _, d in ipairs(D.byKind("dyntank")) do
    if D.formed(d) then
      local f = U.call(d.p, "getFilledPercentage")
      if type(f) == "number" and f * 100 > tf.above then
        raise(cur, cfg, "tank:" .. d.name, "warn", D.label(d) .. ": zbiornik " .. U.pct(f))
      end
    end
  end
end

-- poziomy promieniowania wg Mekanism (RadiationScale, Sv/h)
A.RAD_LEVELS = {
  { v = 0.00001, name = "LOW" },
  { v = 0.001, name = "MEDIUM" },
  { v = 0.1, name = "ELEVATED" },
  { v = 10, name = "HIGH" },
  { v = 100, name = "EXTREME" },
}

function A.radLevel(r)
  local name = "brak"
  for _, l in ipairs(A.RAD_LEVELS) do if r >= l.v then name = l.name end end
  return name
end

local function checkStress(cfg, cur)
  local sc = cfg.alarms.stress
  if not sc.enabled then return end
  for _, d in ipairs(D.byKind("stress")) do
    local s, c = U.call(d.p, "getStress"), U.call(d.p, "getStressCapacity")
    if type(s) == "number" and type(c) == "number" then
      if c > 0 and s > c then
        raise(cur, cfg, "stress:" .. d.name, "crit", D.label(d) .. ": PRZECIAZENIE Create")
      elseif c > 0 and s / c * 100 > sc.above then
        raise(cur, cfg, "stress:" .. d.name, "warn", D.label(d) .. ": obciazenie " .. U.pct(s / c))
      end
    end
  end
end

local function checkRadiation(cfg, cur)
  local rc = cfg.alarms.radiation
  if not rc.enabled then return end
  for _, d in ipairs(D.byKind("env")) do
    local r = U.call(d.p, "getRadiationRaw")
    if type(r) == "number" and r >= rc.above then
      raise(cur, cfg, "rad:" .. d.name, r >= 0.1 and "crit" or "warn",
        "Promieniowanie " .. U.sv(r) .. " (" .. A.radLevel(r) .. ") - " .. D.label(d))
    end
  end
end

local function flushChat(cfg)
  if #A.chatQueue == 0 then return end
  local boxes = D.byKind("chat")
  if #boxes == 0 then A.chatQueue = {} return end
  local ch = cfg.alarms.chat
  local opts = { prefix = ch.prefix ~= "" and ch.prefix or "Smart" }
  if ch.player and ch.player ~= "" then opts.player = ch.player end
  -- AP ma cooldown na chat boxie: wysylamy 1 wiadomosc na tick, przy bledzie probujemy pozniej
  local ok, res = pcall(boxes[1].p.sendMessage, A.chatQueue[1], opts)
  if ok and res then table.remove(A.chatQueue, 1) end
  while #A.chatQueue > 10 do table.remove(A.chatQueue) end
end

local function sound(cfg, cur)
  if not cfg.alarms.speaker then return end
  local crit, any = false, false
  for _, a in pairs(cur) do
    any = true
    if a.level == "crit" then crit = true end
  end
  if not any then return end
  for _, s in ipairs(D.byKind("speaker")) do
    pcall(s.p.playNote, crit and "bit" or "bell", crit and 3 or 1, crit and 18 or 12)
  end
end

function A.tick(cfg)
  A.cfg = cfg
  local cur = {}
  checkFission(cfg, cur)
  autoPower(cfg)

  local le = cfg.alarms.lowEnergy
  local frac = A.readEnergy("auto")
  A.energyFrac = frac
  if le.enabled and frac and frac * 100 < le.below then
    raise(cur, cfg, "lowenergy", "warn", "Niski poziom energii: " .. U.pct(frac))
  end
  checkStorage(cfg, cur)
  checkTanks(cfg, cur)
  checkStress(cfg, cur)
  checkRadiation(cfg, cur)

  for id, a in pairs(A.active) do
    if not cur[id] then logEvent("OK: " .. a.text, "ok") end
  end
  A.active = cur

  local rs = cfg.alarms.redstone
  if rs.enabled then D.setRedstone(rs.target, rs.side, next(cur) ~= nil) end
  sound(cfg, cur)
  flushChat(cfg)
end

function A.list()
  local r = {}
  for _, a in pairs(A.active) do r[#r + 1] = a end
  table.sort(r, function(a, b)
    if a.level ~= b.level then return a.level == "crit" end
    return a.text < b.text
  end)
  return r
end

-- przelaczniki redstone (panel sterowania)
function A.applyControls(cfg)
  for _, c in ipairs(cfg.controls) do
    if c.mode ~= "pulse" then D.setRedstone(c.target, c.side, c.state) end
  end
end

function A.toggleControl(cfg, i)
  local c = cfg.controls[i]
  if not c then return end
  if c.mode == "pulse" then
    D.setRedstone(c.target, c.side, true)
    sleep(0.3)
    D.setRedstone(c.target, c.side, false)
    logEvent("Impuls: " .. c.label)
  else
    c.state = not c.state
    D.setRedstone(c.target, c.side, c.state)
    logEvent((c.state and "ON: " or "OFF: ") .. c.label)
  end
end

return A
