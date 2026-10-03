-- Smart System: zrodla energii (odczyt + sterowanie) i tagi urzadzen/przelacznikow
-- Automatycznie: reaktory fission/fusion, turbiny, generatory Mekanism, Powah (reaktor, generatory).
-- Recznie: dowolne urzadzenie lub przelacznik redstone z tagiem "energia".
local U = require("lib.util")
local D = require("lib.devices")

local S = {}
S.TAG = "energia"

-- tagi zapisane jako tekst "energia, oswietlenie"
function S.tags(str)
  local r = {}
  for t in tostring(str or ""):gmatch("[^,%s]+") do r[#r + 1] = t:lower() end
  return r
end

function S.hasTag(str, tag)
  for _, t in ipairs(S.tags(str)) do if t == tag then return true end end
  return false
end

function S.setTag(str, tag, on)
  local out = {}
  for _, t in ipairs(S.tags(str)) do if t ~= tag then out[#out + 1] = t end end
  if on then out[#out + 1] = tag end
  return table.concat(out, ", ")
end

local function isMekGenerator(d)
  return d.mek and d.kind == "machine" and d.types[1]:lower():find("generator") ~= nil
end

local AUTO = { fission = true, fusion = true, turbine = true, powahreactor = true, generator = true }

function S.isSource(cfg, d)
  if not D.isActive(d) then return false end
  if S.hasTag(cfg.tags and cfg.tags[d.name], S.TAG) then return true end
  return AUTO[d.kind] or isMekGenerator(d)
end

-- przycisk WL/WYL przez tryb redstone Mekanism (DISABLED = zawsze pracuje, HIGH = stoi bez sygnalu)
local function redstoneButton(d, e)
  if not U.has(d.p, "getRedstoneMode") then return end
  local mode = U.call(d.p, "getRedstoneMode")
  e.mode = mode
  if mode == "DISABLED" then
    e.buttons[#e.buttons + 1] = { label = "WYLACZ", fg = colors.white, bg = colors.red, cmd = "rsmode", arg = "HIGH" }
  else
    e.buttons[#e.buttons + 1] = { label = "WLACZ", fg = colors.black, bg = colors.lime, cmd = "rsmode", arg = "DISABLED" }
  end
end

local function readFission(ctx, d, e)
  local p = d.p
  local on = U.call(p, "getStatus") == true
  local trip = ctx.auto.trips[d.name]
  e.status, e.scol = trip and "SCRAM" or (on and "PRACUJE" or "WYL"), trip and colors.red or (on and colors.lime or colors.orange)
  local temp, burn, actual = U.call(p, "getTemperature"), U.call(p, "getBurnRate"), U.call(p, "getActualBurnRate")
  e.info = string.format("%s  %.1f/%.1f mB/t", U.temp(temp), actual or 0, burn or 0)
  local fuel = U.call(p, "getFuelFilledPercentage") or 0
  e.bar = { f = fuel, col = colors.lime, text = "paliwo " .. U.pct(fuel) }
  if trip then
    e.buttons[#e.buttons + 1] = { label = "RESET", fg = colors.black, bg = colors.yellow, cmd = "reset" }
  elseif on then
    e.buttons[#e.buttons + 1] = { label = "WYLACZ", fg = colors.white, bg = colors.red, cmd = "scram" }
  else
    e.buttons[#e.buttons + 1] = { label = "WLACZ", fg = colors.black, bg = colors.lime, cmd = "start" }
  end
  e.buttons[#e.buttons + 1] = { label = "-1", fg = colors.white, bg = colors.gray, cmd = "burn", arg = -1 }
  e.buttons[#e.buttons + 1] = { label = "+1", fg = colors.white, bg = colors.gray, cmd = "burn", arg = 1 }
end

local function readFusion(d, e)
  local p = d.p
  local ign = U.call(p, "isIgnited") == true
  e.status, e.scol = ign and "ZAPLON" or "WYGASZONY", ign and colors.lime or colors.orange
  e.prod = D.mekFE(U.call(p, "getProductionRate"))
  e.info = "wtrysk " .. tostring(U.call(p, "getInjectionRate") or "?") .. " mB/t"
  local dt = U.call(p, "getDTFuelFilledPercentage") or 0
  e.bar = { f = dt, col = colors.purple, text = "D-T " .. U.pct(dt) }
  e.buttons[#e.buttons + 1] = { label = "wtrysk -2", fg = colors.white, bg = colors.gray, cmd = "inj", arg = -2 }
  e.buttons[#e.buttons + 1] = { label = "wtrysk +2", fg = colors.white, bg = colors.gray, cmd = "inj", arg = 2 }
end

local DUMP = { IDLE = "bez zrzutu", DUMPING_EXCESS = "zrzut nadmiaru", DUMPING = "zrzut" }

local function readTurbine(d, e)
  local p = d.p
  e.prod = D.mekFE(U.call(p, "getProductionRate"))
  e.status, e.scol = (e.prod or 0) > 0 and "PRACUJE" or "STOI", (e.prod or 0) > 0 and colors.lime or colors.orange
  local mode = U.call(p, "getDumpingMode")
  e.info = "para " .. U.pct(U.call(p, "getSteamFilledPercentage") or 0) .. ", " .. (DUMP[mode] or tostring(mode))
  local ef = U.call(p, "getEnergyFilledPercentage") or 0
  e.bar = { f = ef, col = colors.yellow, text = "bufor " .. U.pct(ef) }
  e.buttons[#e.buttons + 1] = { label = "tryb zrzutu", fg = colors.black, bg = colors.lightGray, cmd = "dump" }
end

local function readMekGenerator(d, e)
  local p = d.p
  e.prod = D.mekFE(U.call(p, "getProductionRate"))
  local max = D.mekFE(U.call(p, "getMaxOutput"))
  e.status, e.scol = (e.prod or 0) > 0 and "PRACUJE" or "STOI", (e.prod or 0) > 0 and colors.lime or colors.orange
  local sun = U.call(p, "canSeeSun")
  if sun ~= nil then e.info = sun and "widzi slonce" or "brak slonca" end
  local ef = U.call(p, "getEnergyFilledPercentage") or 0
  e.bar = { f = ef, col = colors.yellow, text = "bufor " .. U.pct(ef) .. (max and (" max " .. U.fmt(max, "FE/t")) or "") }
  redstoneButton(d, e)
end

local function readPowahReactor(d, e)
  local p = d.p
  local on = U.call(p, "isRunning") == true
  e.status, e.scol = on and "PRACUJE" or "STOI", on and colors.lime or colors.orange
  e.info = string.format("temp %d%%  wegiel %d%%", math.floor(U.call(p, "getTemperature") or 0), math.floor(U.call(p, "getCarbon") or 0))
  local fuel = (U.call(p, "getFuel") or 0) / 100
  e.bar = { f = fuel, col = colors.lime, text = "uraninit " .. U.pct(fuel) }
end

local function readGeneric(d, e)
  local p = d.p
  local burning = U.call(p, "isBurning")
  if burning ~= nil then
    e.status, e.scol = burning and "PRACUJE" or "STOI", burning and colors.lime or colors.orange
  end
  local sky = U.call(p, "canSeeSky")
  if sky ~= nil then e.info = sky and "widzi niebo" or "brak nieba" end
  local stored, max = D.energy(d)
  if stored and max and max > 0 then
    local f = stored / max
    e.bar = { f = f, col = colors.yellow, text = U.fmt(stored, "FE") .. " " .. U.pct(f) }
  end
  redstoneButton(d, e)
end

function S.read(ctx, d)
  local e = { name = d.name, label = D.label(d), kind = d.kind, kindLabel = D.kindLabel(d.kind), buttons = {} }
  if not D.formed(d) then
    e.status, e.scol = "nieuformowany", colors.red
    return e
  end
  if d.kind == "fission" then readFission(ctx, d, e)
  elseif d.kind == "fusion" then readFusion(d, e)
  elseif d.kind == "turbine" then readTurbine(d, e)
  elseif d.kind == "powahreactor" then readPowahReactor(d, e)
  elseif isMekGenerator(d) then readMekGenerator(d, e)
  else readGeneric(d, e) end
  return e
end

local MAIN_CMD = { start = true, scram = true, rsmode = true }

-- przelaczniki polaczone z urzadzeniem: dolaczamy je do jego bloku
local function attachControls(ctx, e, used)
  local hasMain = false
  for _, b in ipairs(e.buttons) do if MAIN_CMD[b.cmd] then hasMain = true end end
  local linked = {}
  for i, c in ipairs(ctx.cfg.controls) do
    if c.link == e.name then
      used[i] = true
      local on = c.state and c.mode ~= "pulse"
      linked[#linked + 1] = c.label .. (c.mode == "pulse" and "" or (on and " WL" or " WYL"))
      -- "steruj razem": glowny przycisk urzadzenia przelacza tez redstone, osobny przycisk zbedny
      if not (c.linkSync ~= false and hasMain) then
        e.buttons[#e.buttons + 1] = {
          label = c.label .. (c.mode == "pulse" and "" or (on and " [WL]" or " [WYL]")),
          fg = on and colors.black or colors.white, bg = on and (colors[c.color] or colors.lime) or colors.gray,
          cmd = "control", arg = i,
        }
      end
    end
  end
  if #linked > 0 then
    e.info = (e.info and (e.info .. "  ") or "") .. "+ " .. table.concat(linked, ", ")
  end
end

-- wszystkie zrodla + przelaczniki redstone z tagiem "energia"
function S.collect(ctx)
  local list, total = {}, 0
  local used = {}
  for _, d in ipairs(D.list) do
    if S.isSource(ctx.cfg, d) then
      local ok, e = pcall(S.read, ctx, d)
      if ok then
        attachControls(ctx, e, used)
        list[#list + 1] = e
        if type(e.prod) == "number" then total = total + e.prod end
      end
    end
  end
  -- Reactor Port zamiast Logic Adaptera: pokazujemy wpis z instrukcja
  for _, d in ipairs(D.byKind({ "fissionport", "fusionport" })) do
    list[#list + 1] = {
      name = d.name, label = D.label(d), kindLabel = D.kindLabel(d.kind), buttons = {},
      status = "BRAK DANYCH", scol = colors.red,
      info = "Reactor Port nie daje danych - uzyj Logic Adaptera",
    }
  end
  local controls = {}
  for i, c in ipairs(ctx.cfg.controls) do
    if not used[i] and S.hasTag(c.tags, S.TAG) then controls[#controls + 1] = { index = i, label = c.label, state = c.state, mode = c.mode, color = c.color } end
  end
  return list, controls, total
end

-- wykonuje akcje z przycisku; zwraca ok, komunikat (do paska i dzwieku potwierdzenia)
function S.action(ctx, cmd, name, arg)
  if cmd == "control" then
    local c = ctx.cfg.controls[arg]
    if not c then return false, "brak przelacznika" end
    ctx.auto.toggleControl(ctx.cfg, arg)
    ctx.save()
    if c.mode == "pulse" then return true, "Impuls: " .. c.label end
    return true, (c.state and "Wlaczono: " or "Wylaczono: ") .. c.label
  end
  local d = D.get(name)
  if not d then return false, "brak urzadzenia" end
  local p, label = d.p, D.label(d)
  local function res(ok, err, okText)
    if ok then return true, okText end
    return false, tostring(err)
  end
  if cmd == "start" then
    local ok, err = ctx.auto.start(d)
    return res(ok, err, "Wlaczono: " .. label)
  elseif cmd == "scram" then
    ctx.auto.scram(d)
    return true, "Wylaczono: " .. label
  elseif cmd == "reset" then
    ctx.auto.reset(name)
    return true, "Reset zabezpieczenia: " .. label
  elseif cmd == "burn" then
    local cur, max = U.call(p, "getBurnRate") or 0, U.call(p, "getMaxBurnRate") or 0
    local new = U.clamp(U.round(cur + arg, 1), 0, max)
    local ok, err = pcall(p.setBurnRate, new)
    return res(ok, err, string.format("Burn rate: %.1f mB/t", new))
  elseif cmd == "inj" then
    local cur = U.call(p, "getInjectionRate") or 0
    local new = U.clamp(cur + arg, 0, 98)
    local ok, err = pcall(p.setInjectionRate, new)
    return res(ok, err, "Wtrysk: " .. new .. " mB/t")
  elseif cmd == "dump" then
    local ok, err = pcall(p.incrementDumpingMode)
    return res(ok, err, "Zmieniono tryb zrzutu")
  elseif cmd == "rsmode" then
    -- wymaga publicznego security maszyny (Mekanism)
    local ok, err = pcall(p.setRedstoneMode, arg)
    if ok then
      ctx.auto.logEvent((arg == "DISABLED" and "WL: " or "WYL: ") .. label)
      ctx.auto.syncLinked(name, arg == "DISABLED")
    end
    return res(ok, err, (arg == "DISABLED" and "Wlaczono: " or "Wylaczono: ") .. label)
  end
  return false, "nieznana komenda"
end

return S
