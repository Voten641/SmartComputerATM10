-- Smart System: menu konfiguracji na ekranie komputera (mysz + klawiatura)
local U = require("lib.util")
local UI = require("lib.ui")
local D = require("lib.devices")
local A = require("lib.auto")

local G = {}
local ctx
local stack = {}
local canvas
local message -- { text, color, untilT }

local SCALES = { 0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5 }
local RAD_VALUES = { 0.00001, 0.001, 0.1, 10 }
local RAD_LABELS = { [0.00001] = "LOW (10 uSv/h)", [0.001] = "MEDIUM (1 mSv/h)", [0.1] = "ELEVATED (100 mSv/h)", [10] = "HIGH (10 Sv/h)" }

local function changed()
  ctx.save()
  ctx.reload()
end

local function flash(text, color)
  message = { text = text, color = color or colors.lime, untilT = os.clock() + 3 }
end

local function push(screen)
  screen.scroll = 0
  stack[#stack + 1] = screen
end

local function pop()
  if #stack > 1 then table.remove(stack) end
end

---------------------------------------------------------------------------
-- Rysowanie
---------------------------------------------------------------------------
local function valueText(r)
  if r.type == "toggle" then return r.get() and "[WL]" or "[WYL]" end
  if r.type == "choice" then
    local v = r.get()
    return (r.labels and r.labels[v]) or tostring(v)
  end
  if r.type == "text" then
    local v = r.get()
    return (v == nil or v == "") and "(brak)" or tostring(v)
  end
  if r.type == "number" then return tostring(r.get()) end
  if r.value then return type(r.value) == "function" and tostring(r.value()) or tostring(r.value) end
  return ""
end

local function draw()
  local s = stack[#stack]
  canvas:reset()
  canvas:clear(colors.black)
  local w, h = canvas.w, canvas.h
  -- naglowek
  canvas:rect(1, 1, w, 1, colors.cyan)
  local x0 = 2
  if #stack > 1 then
    canvas:button("back", 1, 1, 3, 1, "<", colors.white, colors.blue)
    x0 = 5
  end
  canvas:text(x0, 1, U.trunc(s.title, w - x0 - 8), colors.black, colors.cyan)
  local alarms = #A.list()
  canvas:right(1, alarms > 0 and ("! " .. alarms .. " ") or "OK ", alarms > 0 and colors.red or colors.green, colors.cyan)

  local rows = s.rows()
  s.lastRows = rows
  local top, bottom = 3, h - 1
  local visible = bottom - top + 1
  local maxScroll = math.max(0, #rows - visible)
  s.scroll = U.clamp(s.scroll or 0, 0, maxScroll)
  local vw = math.min(22, math.floor(w * 0.45))
  local barW = maxScroll > 0 and 1 or 0
  for i = 1, visible do
    local idx = i + s.scroll
    local r = rows[idx]
    if not r then break end
    local y = top + i - 1
    -- caly wiersz klikalny (przyciski -/+ dodane pozniej maja pierwszenstwo)
    if r.type ~= "header" and r.type ~= "info" then
      canvas:zone("row", 1, y, w - barW, 1, idx)
    end
    if r.type == "header" then
      canvas:text(2, y, U.trunc(r.label, w - 3), colors.yellow, colors.black)
    elseif r.type == "info" then
      canvas:kv(2, y, w - 2 - barW, r.label, U.trunc(valueText(r), vw), colors.lightGray, r.color or colors.white)
    elseif r.type == "action" then
      local bg = r.bg or colors.gray
      canvas:rect(2, y, w - 2 - barW, 1, bg)
      local v = valueText(r)
      canvas:text(3, y, U.trunc(r.label, w - 5 - barW - (v ~= "" and vw or 0)), r.fg or colors.white, bg)
      if v ~= "" then canvas:right(y, U.trunc(v, vw) .. " ", r.vfg or colors.lightGray, bg, w - 1 - barW) end
    elseif r.type == "number" then
      canvas:text(2, y, U.trunc(r.label, w - 3 - vw), colors.white, colors.black)
      local vx = w - vw - barW
      canvas:button("dec", vx, y, 3, 1, "-", colors.white, colors.red, idx)
      canvas:button("row", vx + 4, y, vw - 8, 1, U.trunc(valueText(r), vw - 8), colors.black, colors.lightGray, idx)
      canvas:button("inc", vx + vw - 3, y, 3, 1, "+", colors.white, colors.green, idx)
    else
      canvas:text(2, y, U.trunc(r.label, w - 3 - vw), colors.white, colors.black)
      local v = U.trunc(valueText(r), vw)
      local col = colors.lightGray
      if r.type == "toggle" then col = r.get() and colors.lime or colors.red end
      canvas:button("row", w - vw - barW, y, vw, 1, v, colors.black, col, idx)
    end
  end
  if maxScroll > 0 then
    canvas:button("up", w, top, 1, 1, "^", colors.black, colors.lightGray)
    canvas:button("down", w, bottom, 1, 1, "v", colors.black, colors.lightGray)
    local pos = top + 1 + math.floor((visible - 3) * s.scroll / maxScroll)
    canvas:rect(w, pos, 1, 1, colors.cyan)
  end
  -- stopka
  canvas:rect(1, h, w, 1, colors.gray)
  if message and os.clock() < message.untilT then
    canvas:text(2, h, U.trunc(message.text, w - 2), message.color, colors.gray)
  else
    canvas:text(2, h, "Smart " .. ctx.version .. "  Backspace=wstecz", colors.lightGray, colors.gray)
  end
end

-- okno do wpisania tekstu
local function prompt(title, default)
  local w, h = term.getSize()
  local bw = math.min(w - 2, 40)
  local bx = math.floor((w - bw) / 2) + 1
  local by = math.floor(h / 2) - 2
  canvas:rect(bx, by, bw, 5, colors.blue)
  canvas:text(bx + 1, by, U.trunc(title, bw - 2), colors.white, colors.blue)
  canvas:text(bx + 1, by + 4, "Enter=OK  (puste=bez zmian)", colors.lightBlue, colors.blue)
  canvas:rect(bx + 1, by + 2, bw - 2, 1, colors.black)
  term.setCursorPos(bx + 1, by + 2)
  term.setTextColor(colors.white)
  term.setBackgroundColor(colors.black)
  local win = window.create(term.current(), bx + 1, by + 2, bw - 2, 1)
  local old = term.redirect(win)
  local ok, v = pcall(read, nil, nil, nil, default and tostring(default) or nil)
  term.redirect(old)
  if not ok then return nil end
  return v
end

local function choicePicker(r)
  push({
    title = r.label,
    rows = function()
      local out = {}
      local cur = r.get()
      for _, v in ipairs(r.choices()) do
        out[#out + 1] = {
          type = "action",
          label = (v == cur and "> " or "  ") .. ((r.labels and r.labels[v]) or tostring(v)),
          bg = v == cur and colors.blue or colors.gray,
          run = function() r.set(v); pop() end,
        }
      end
      return out
    end,
  })
end

local function activate(r, how)
  if r.type == "toggle" then
    r.set(not r.get())
  elseif r.type == "choice" then
    choicePicker(r)
  elseif r.type == "number" then
    local step = r.step or 1
    local v = r.get() or 0
    if how == "dec" then v = v - step
    elseif how == "inc" then v = v + step
    else
      local s = prompt(r.label .. " (" .. (r.min or "-inf") .. ".." .. (r.max or "inf") .. ")", v)
      v = tonumber(s) or v
    end
    if r.min then v = math.max(r.min, v) end
    if r.max then v = math.min(r.max, v) end
    r.set(U.round(v, 2))
  elseif r.type == "text" then
    local s = prompt(r.label, r.get())
    if s ~= nil then r.set(s) end
  elseif r.type == "action" and r.run then
    r.run()
  end
end

---------------------------------------------------------------------------
-- Ekrany
---------------------------------------------------------------------------
local Screens = {}

local function cfgRow(rowType, label, tbl, key, extra)
  local r = {
    type = rowType, label = label,
    get = function() return tbl[key] end,
    set = function(v) tbl[key] = v; changed() end,
  }
  for k, v in pairs(extra or {}) do r[k] = v end
  return r
end

local function deviceChoices(kinds, withAuto)
  local list = withAuto and { "auto" } or {}
  local labels = { auto = "auto (wszystkie)" }
  for _, d in ipairs(D.list) do
    for _, k in ipairs(kinds) do
      if d.kind == k and not d.dupOf then
        list[#list + 1] = d.name
        labels[d.name] = D.label(d)
      end
    end
  end
  return list, labels
end

function Screens.monitor(name)
  return {
    title = "Monitor: " .. name,
    rows = function()
      local mcfg = ctx.cfg.monitors[name]
      if not mcfg then return { { type = "info", label = "Monitor odlaczony" } } end
      local mod = ctx.modules[mcfg.module]
      local modIds, modLabels = { "none" }, { none = "(nieprzypisany)" }
      for _, id in ipairs(ctx.moduleIds) do
        if ctx.modules[id] then modIds[#modIds + 1] = id; modLabels[id] = ctx.modules[id].name end
      end
      local rows = {
        { type = "header", label = "Wyswietlanie" },
        {
          type = "choice", label = "Modul", labels = modLabels,
          choices = function() return modIds end,
          get = function() return mcfg.module end,
          set = function(v) if v ~= mcfg.module then mcfg.module = v; mcfg.opts = {}; mcfg.source = "auto" end; changed() end,
        },
      }
      if mod and mod.kinds and #mod.kinds > 0 then
        local list, labels = deviceChoices(mod.kinds, true)
        rows[#rows + 1] = cfgRow("choice", "Zrodlo danych", mcfg, "source", {
          labels = labels, choices = function() return list end,
        })
      end
      rows[#rows + 1] = cfgRow("choice", "Skala tekstu", mcfg, "scale", { choices = function() return SCALES end })
      rows[#rows + 1] = cfgRow("choice", "Kolor akcentu", mcfg, "accent", { choices = function() return UI.COLOR_NAMES end })
      rows[#rows + 1] = cfgRow("text", "Wlasny tytul", mcfg, "title")
      if mod and mod.options and #mod.options > 0 then
        rows[#rows + 1] = { type = "header", label = "Opcje modulu: " .. mod.name }
        for _, o in ipairs(mod.options) do
          local extra = { min = o.min, max = o.max, step = o.step, labels = o.labels }
          if o.choices then extra.choices = function() return o.choices end
          elseif o.choicesFn then extra.choices = o.choicesFn end
          rows[#rows + 1] = cfgRow(o.type, o.label, mcfg.opts, o.key, extra)
          if mcfg.opts[o.key] == nil then mcfg.opts[o.key] = o.default end
        end
      end
      rows[#rows + 1] = { type = "header", label = "" }
      rows[#rows + 1] = { type = "action", label = "Identyfikuj (pokaz nazwe na monitorze)", bg = colors.blue,
        run = function() ctx.identify(name) end }
      rows[#rows + 1] = { type = "action", label = "Wyczysc ustawienia monitora", bg = colors.red,
        run = function()
          ctx.cfg.monitors[name] = nil
          changed()
          pop()
          flash("Wyczyszczono " .. name)
        end }
      return rows
    end,
  }
end

function Screens.monitors()
  return {
    title = "Monitory",
    rows = function()
      local rows = { { type = "header", label = "Kliknij monitor aby ustawic co wyswietla" } }
      local names = {}
      for _, d in ipairs(D.list) do if d.kind == "monitor" then names[#names + 1] = d.name end end
      table.sort(names)
      for _, n in ipairs(names) do
        local mcfg = ctx.cfg.monitors[n]
        local mon = ctx.monitors[n]
        local size = ""
        if mon then size = string.format(" %dx%d", mon.canvas.w, mon.canvas.h) end
        rows[#rows + 1] = {
          type = "action", label = n .. size,
          value = ctx.moduleName(mcfg and mcfg.module),
          vfg = (mcfg and ctx.modules[mcfg.module]) and colors.lime or colors.orange,
          run = function() push(Screens.monitor(n)) end,
        }
      end
      if #names == 0 then
        rows[#rows + 1] = { type = "info", label = "Brak monitorow - podlacz je modemem" }
      else
        rows[#rows + 1] = { type = "header", label = "" }
        rows[#rows + 1] = { type = "action", label = "Identyfikuj wszystkie monitory", bg = colors.blue,
          run = function() for _, n in ipairs(names) do ctx.identify(n) end end }
      end
      return rows
    end,
  }
end

function Screens.methods(dev)
  return {
    title = "Metody: " .. dev.name,
    rows = function()
      local rows = {}
      local names = {}
      for k, v in pairs(dev.p or {}) do if type(v) == "function" then names[#names + 1] = k end end
      table.sort(names)
      for _, n in ipairs(names) do rows[#rows + 1] = { type = "info", label = n } end
      return rows
    end,
  }
end

function Screens.device(dev)
  return {
    title = "Urzadzenie",
    rows = function()
      local rows = {
        { type = "info", label = "Nazwa", value = dev.name },
        { type = "info", label = "Rodzaj", value = D.kindLabel(dev.kind) },
        { type = "info", label = "Typy", value = table.concat(dev.types, ", ") },
      }
      if dev.mek then rows[#rows + 1] = { type = "info", label = "Energia", value = "Mekanism J -> FE" } end
      if dev.dupOf then rows[#rows + 1] = { type = "info", label = "Duplikat portu", value = dev.dupOf, color = colors.orange } end
      if dev.disabled then rows[#rows + 1] = { type = "info", label = "Status", value = "wylaczone w configu AP", color = colors.red } end
      if D.MULTIBLOCK[dev.kind] then
        rows[#rows + 1] = { type = "info", label = "Uformowany", value = function() return D.formed(dev) and "tak" or "NIE" end }
      end
      rows[#rows + 1] = { type = "header", label = "" }
      rows[#rows + 1] = {
        type = "text", label = "Przyjazna nazwa",
        get = function() return ctx.cfg.aliases[dev.name] end,
        set = function(v) ctx.cfg.aliases[dev.name] = (v ~= "" and v or nil); changed() end,
      }
      local Src = require("lib.sources")
      rows[#rows + 1] = {
        type = "toggle", label = "Zrodlo energii (tag energia)",
        get = function() return Src.hasTag(ctx.cfg.tags[dev.name], Src.TAG) end,
        set = function(v)
          local t = Src.setTag(ctx.cfg.tags[dev.name], Src.TAG, v)
          ctx.cfg.tags[dev.name] = t ~= "" and t or nil
          changed()
        end,
      }
      rows[#rows + 1] = {
        type = "text", label = "Tagi (po przecinku)",
        get = function() return ctx.cfg.tags[dev.name] end,
        set = function(v) ctx.cfg.tags[dev.name] = (v ~= "" and v:lower() or nil); changed() end,
      }
      rows[#rows + 1] = {
        type = "toggle", label = "Ukryj (ignoruj)",
        get = function() return ctx.cfg.hidden[dev.name] == true end,
        set = function(v) ctx.cfg.hidden[dev.name] = v or nil; changed() end,
      }
      rows[#rows + 1] = { type = "action", label = "Pokaz liste metod", run = function() push(Screens.methods(dev)) end }
      return rows
    end,
  }
end

function Screens.devices()
  return {
    title = "Urzadzenia",
    rows = function()
      local rows = { { type = "header", label = #D.list .. " peryferiow w sieci" } }
      local list = {}
      for _, d in ipairs(D.list) do list[#list + 1] = d end
      table.sort(list, function(a, b)
        if a.kind ~= b.kind then return a.kind < b.kind end
        return a.name < b.name
      end)
      for _, d in ipairs(list) do
        local inactive = not D.isActive(d)
        rows[#rows + 1] = {
          type = "action", label = D.label(d), value = D.kindLabel(d.kind),
          fg = inactive and colors.lightGray or colors.white,
          vfg = inactive and colors.gray or colors.lightBlue,
          run = function() push(Screens.device(d)) end,
        }
      end
      return rows
    end,
  }
end

function Screens.alarms()
  local al = ctx.cfg.alarms
  return {
    title = "Alarmy i automatyka",
    rows = function()
      local reactors, rLabels = deviceChoices({ "fission" }, true)
      local sources, sLabels = deviceChoices({ "matrix", "cube", "energy" }, true)
      local targets = D.redstoneTargets()
      return {
        { type = "header", label = "Zabezpieczenie reaktora fission" },
        cfgRow("toggle", "Auto SCRAM", al.fission, "autoScram"),
        cfgRow("number", "Max temperatura (K)", al.fission, "maxTemp", { min = 300, max = 5000, step = 50 }),
        cfgRow("number", "Max uszkodzenie (%)", al.fission, "maxDamage", { min = 0, max = 100, step = 1 }),
        cfgRow("number", "Max odpady (%)", al.fission, "maxWaste", { min = 1, max = 100, step = 5 }),
        cfgRow("number", "Min chlodziwo (%)", al.fission, "minCoolant", { min = 0, max = 100, step = 5 }),
        cfgRow("number", "Max gorace chlodziwo (%)", al.fission, "maxHeated", { min = 1, max = 100, step = 5 }),
        { type = "action", label = "Reset zabezpieczen wszystkich reaktorow", bg = colors.orange, fg = colors.black,
          run = function() for n in pairs(A.trips) do A.reset(n) end flash("Zresetowano") end },
        { type = "header", label = "Auto sterowanie reaktorem wg energii" },
        cfgRow("toggle", "Wlaczone", al.autoPower, "enabled"),
        cfgRow("choice", "Reaktor", al.autoPower, "reactor", { labels = rLabels, choices = function() return reactors end }),
        cfgRow("choice", "Magazyn energii", al.autoPower, "source", { labels = sLabels, choices = function() return sources end }),
        cfgRow("number", "Start ponizej (%)", al.autoPower, "startBelow", { min = 0, max = 100, step = 5 }),
        cfgRow("number", "Stop powyzej (%)", al.autoPower, "stopAbove", { min = 0, max = 100, step = 5 }),
        { type = "header", label = "Alarmy" },
        cfgRow("toggle", "Niska energia", al.lowEnergy, "enabled"),
        cfgRow("number", "  ponizej (%)", al.lowEnergy, "below", { min = 0, max = 100, step = 5 }),
        cfgRow("toggle", "Pelny magazyn ME/RS", al.storageFull, "enabled"),
        cfgRow("number", "  powyzej (%)", al.storageFull, "above", { min = 0, max = 100, step = 5 }),
        cfgRow("toggle", "Pelny Dynamic Tank", al.tankFull, "enabled"),
        cfgRow("number", "  powyzej (%)", al.tankFull, "above", { min = 0, max = 100, step = 5 }),
        cfgRow("toggle", "Przeciazenie Create", al.stress, "enabled"),
        cfgRow("number", "  ostrzezenie od (%)", al.stress, "above", { min = 0, max = 100, step = 5 }),
        cfgRow("toggle", "Promieniowanie", al.radiation, "enabled"),
        cfgRow("choice", "  prog", al.radiation, "above", { labels = RAD_LABELS, choices = function() return RAD_VALUES end }),
        { type = "header", label = "Powiadomienia" },
        cfgRow("toggle", "Dzwiek (speaker)", al, "speaker"),
        cfgRow("toggle", "Chat Box", al.chat, "enabled"),
        cfgRow("text", "  tylko do gracza", al.chat, "player"),
        cfgRow("text", "  prefiks", al.chat, "prefix"),
        cfgRow("toggle", "Sygnal redstone przy alarmie", al.redstone, "enabled"),
        cfgRow("choice", "  wyjscie", al.redstone, "target", { choices = function() return targets end }),
        cfgRow("choice", "  strona", al.redstone, "side", { choices = function() return D.SIDES end }),
      }
    end,
  }
end

function Screens.control(i)
  return {
    title = "Przelacznik",
    rows = function()
      local c = ctx.cfg.controls[i]
      if not c then return {} end
      local targets = D.redstoneTargets()
      return {
        cfgRow("text", "Nazwa", c, "label"),
        cfgRow("choice", "Wyjscie", c, "target", { choices = function() return targets end }),
        cfgRow("choice", "Strona", c, "side", { choices = function() return D.SIDES end }),
        cfgRow("choice", "Tryb", c, "mode", { labels = { toggle = "przelacznik", pulse = "impuls" },
          choices = function() return { "toggle", "pulse" } end }),
        cfgRow("choice", "Kolor (WL)", c, "color", { choices = function() return UI.COLOR_NAMES end }),
        {
          type = "toggle", label = "W zrodlach energii (tag)",
          get = function() return require("lib.sources").hasTag(c.tags, "energia") end,
          set = function(v) c.tags = require("lib.sources").setTag(c.tags, "energia", v); changed() end,
        },
        cfgRow("text", "Tagi (po przecinku)", c, "tags"),
        { type = "header", label = "" },
        { type = "action", label = "Przelacz teraz", bg = colors.green,
          run = function() A.toggleControl(ctx.cfg, i); ctx.save() end },
        { type = "action", label = "Usun przelacznik", bg = colors.red,
          run = function() table.remove(ctx.cfg.controls, i); changed(); pop() end },
      }
    end,
  }
end

function Screens.controls()
  return {
    title = "Panel sterowania (redstone)",
    rows = function()
      local rows = { { type = "header", label = "Wyjscia: komputer / Redstone Relay / RedRouter" } }
      for i, c in ipairs(ctx.cfg.controls) do
        rows[#rows + 1] = {
          type = "action", label = c.label,
          value = c.mode == "pulse" and "impuls" or (c.state and "WL" or "WYL"),
          vfg = c.state and colors.lime or colors.lightGray,
          run = function() push(Screens.control(i)) end,
        }
      end
      rows[#rows + 1] = { type = "action", label = "+ Dodaj przelacznik", bg = colors.green,
        run = function()
          table.insert(ctx.cfg.controls, { label = "Wyjscie " .. (#ctx.cfg.controls + 1), target = "computer",
            side = "back", mode = "toggle", state = false, color = "lime" })
          changed()
          push(Screens.control(#ctx.cfg.controls))
        end }
      return rows
    end,
  }
end

function Screens.log()
  return {
    title = "Dziennik zdarzen",
    rows = function()
      local rows = {}
      for _, a in ipairs(A.list()) do
        rows[#rows + 1] = { type = "info", label = "AKTYWNY", value = a.text, color = a.level == "crit" and colors.red or colors.orange }
      end
      for _, e in ipairs(A.log) do
        rows[#rows + 1] = { type = "info", label = e.t .. " " .. e.text }
      end
      if #rows == 0 then rows[1] = { type = "info", label = "Brak zdarzen" } end
      return rows
    end,
  }
end

local function readRepo()
  if fs.exists("/.smartrepo") then
    local f = fs.open("/.smartrepo", "r")
    local s = f.readAll()
    f.close()
    return (s:gsub("%s+$", ""))
  end
  return "?"
end

local function runUpdate()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
  local ok = shell.run("/install.lua", "update")
  print("")
  if ok then
    print("Aktualizacja zakonczona. Restart za 3s...")
    sleep(3)
    os.reboot()
  else
    printError("Aktualizacja nie powiodla sie.")
    print("Nacisnij dowolny klawisz...")
    os.pullEvent("key")
  end
end

function Screens.settings()
  local cfg = ctx.cfg
  return {
    title = "Ustawienia",
    rows = function()
      return {
        cfgRow("text", "Nazwa bazy", cfg, "title"),
        cfgRow("number", "Odswiezanie (s)", cfg, "refresh", { min = 0.5, max = 10, step = 0.5 }),
        cfgRow("number", "Lista ME/RS co N odswiezen", cfg, "itemsEvery", { min = 1, max = 60, step = 1 }),
        { type = "header", label = "Historia (wykresy)" },
        cfgRow("number", "Probka co (s)", cfg.history, "interval", { min = 10, max = 600, step = 10 }),
        cfgRow("number", "Ilosc probek", cfg.history, "points", { min = 60, max = 4320, step = 60 }),
        { type = "info", label = "Zakres historii", value = function()
            return U.fmtTime(cfg.history.interval * cfg.history.points) end },
        { type = "action", label = "Wyczysc historie", bg = colors.red,
          run = function() local H = require("lib.history"); H.series = {}; pcall(H.save); flash("Wyczyszczono historie") end },
        { type = "header", label = "Aktualizacje" },
        { type = "info", label = "Wersja", value = ctx.version },
        {
          type = "text", label = "Repozytorium GitHub",
          get = readRepo,
          set = function(v)
            if v:match("^[%w%-_%.]+/[%w%-_%.]+$") then
              local f = fs.open("/.smartrepo", "w"); f.write(v); f.close()
              flash("Zapisano repo " .. v)
            else
              flash("Format: uzytkownik/repo", colors.red)
            end
          end,
        },
        { type = "action", label = "Aktualizuj teraz z GitHub", bg = colors.blue, run = runUpdate },
      }
    end,
  }
end

---------------------------------------------------------------------------
-- Autocrafting
---------------------------------------------------------------------------
local function acBridge()
  return require("lib.autocraft").bridge(ctx.cfg)
end

function Screens.acItem(i)
  return {
    title = "Autocraft: przedmiot",
    rows = function()
      local it = ctx.cfg.autocraft.items[i]
      if not it then return {} end
      local st = require("lib.autocraft").status[it.name] or {}
      return {
        { type = "info", label = "ID", value = it.name },
        { type = "info", label = "Stan", value = (st.count and (U.fmt(st.count) .. " szt., ") or "") .. (st.msg or "-") },
        cfgRow("text", "Etykieta", it, "label"),
        cfgRow("number", "Utrzymuj (szt.)", it, "keep", { min = 1, max = 10000000, step = 64 }),
        cfgRow("number", "Craftuj partiami po", it, "batch", { min = 1, max = 100000, step = 16 }),
        cfgRow("toggle", "Wlaczony", it, "enabled"),
        { type = "header", label = "" },
        { type = "action", label = "Usun z listy", bg = colors.red,
          run = function() table.remove(ctx.cfg.autocraft.items, i); changed(); pop() end },
      }
    end,
  }
end

local function addAcItem(name)
  for _, it in ipairs(ctx.cfg.autocraft.items) do
    if it.name == name then flash("Juz jest na liscie", colors.orange) return end
  end
  table.insert(ctx.cfg.autocraft.items, { name = name, label = "", keep = 64, batch = 64, enabled = true })
  changed()
  push(Screens.acItem(#ctx.cfg.autocraft.items))
end

function Screens.acPick(filter)
  local list
  return {
    title = "Wybierz przedmiot",
    rows = function()
      if not list then
        list = {}
        local d = acBridge()
        local items = d and U.call(d.p, "getItems", {}) or {}
        local f = (filter or ""):lower()
        for _, it in ipairs(type(items) == "table" and items or {}) do
          local n = U.itemName(it)
          if f == "" or n:lower():find(f, 1, true) or (it.name or ""):find(f, 1, true) then
            list[#list + 1] = { id = it.name, name = n, count = U.itemCount(it), craft = it.isCraftable }
          end
        end
        table.sort(list, function(a, b) return a.count > b.count end)
      end
      local rows = {}
      if #list == 0 then rows[1] = { type = "info", label = "Brak wynikow (lub brak ME/RS Bridge)" } end
      for k = 1, math.min(#list, 150) do
        local it = list[k]
        rows[#rows + 1] = {
          type = "action", label = it.name, value = U.fmt(it.count) .. (it.craft and " C" or ""),
          vfg = it.craft and colors.lime or colors.lightGray,
          run = function() pop(); addAcItem(it.id) end,
        }
      end
      return rows
    end,
  }
end

function Screens.autocraft()
  local ac = ctx.cfg.autocraft
  return {
    title = "Autocrafting",
    rows = function()
      local bridges, bLabels = deviceChoices({ "me", "rs" }, true)
      local status = require("lib.autocraft").status
      local rows = {
        cfgRow("toggle", "Wlaczony", ac, "enabled"),
        cfgRow("choice", "Bridge", ac, "bridge", { labels = bLabels, choices = function() return bridges end }),
        cfgRow("number", "Sprawdzaj co (s)", ac, "every", { min = 2, max = 600, step = 5 }),
        { type = "header", label = "Utrzymywane zapasy (C = ma wzor)" },
      }
      for i, it in ipairs(ac.items) do
        local st = status[it.name] or {}
        rows[#rows + 1] = {
          type = "action", label = it.label ~= "" and it.label or U.prettyId(it.name),
          value = (st.count and U.fmt(st.count) or "?") .. "/" .. U.fmt(it.keep),
          vfg = (st.state == "ok" and colors.lime) or (st.state == "error" and colors.red) or colors.yellow,
          fg = it.enabled and colors.white or colors.lightGray,
          run = function() push(Screens.acItem(i)) end,
        }
      end
      rows[#rows + 1] = { type = "action", label = "+ Dodaj z magazynu (szukaj)", bg = colors.green,
        run = function()
          local f = prompt("Fragment nazwy (puste = wszystko)", "")
          push(Screens.acPick(f or ""))
        end }
      rows[#rows + 1] = { type = "action", label = "+ Dodaj po ID (np. minecraft:iron_ingot)", bg = colors.green,
        run = function()
          local id = prompt("ID przedmiotu", "")
          if id and id:match("^[%w_%.%-]+:[%w_%./%-]+$") then addAcItem(id)
          elseif id and id ~= "" then flash("Zly format ID", colors.red) end
        end }
      return rows
    end,
  }
end

---------------------------------------------------------------------------
-- Wyswietlacze Create (CC:C Bridge Source Block)
---------------------------------------------------------------------------
function Screens.display(name)
  local DS = require("lib.displays")
  return {
    title = "Wyswietlacz: " .. name,
    rows = function()
      local dcfg = DS.config(ctx.cfg, name)
      local dev = D.get(name)
      local w, h = 0, 0
      if dev then w, h = U.call(dev.p, "getSize") end
      local ids, labels = {}, {}
      for _, p in ipairs(DS.PROVIDERS) do ids[#ids + 1] = p.id; labels[p.id] = p.label end
      local rows = {
        { type = "info", label = "Rozmiar (z Display Link)", value = tostring(w) .. "x" .. tostring(h) },
        cfgRow("choice", "Wyrownanie", dcfg, "align", { labels = { left = "do lewej", center = "srodek", right = "do prawej" },
          choices = function() return { "left", "center", "right" } end }),
        cfgRow("text", "Wlasny tekst", dcfg, "custom"),
        { type = "header", label = "Linie" },
      }
      for i = 1, math.max(4, h or 0) do
        rows[#rows + 1] = {
          type = "choice", label = "Linia " .. i, labels = labels,
          choices = function() return ids end,
          get = function() return dcfg.lines[i] or "none" end,
          set = function(v) dcfg.lines[i] = v; changed() end,
        }
      end
      return rows
    end,
  }
end

function Screens.displays()
  return {
    title = "Wyswietlacze Create",
    rows = function()
      local rows = { { type = "header", label = "Source Block (CC:C Bridge) + Display Link" } }
      for _, d in ipairs(D.list) do
        if d.kind == "csource" then
          rows[#rows + 1] = { type = "action", label = D.label(d), run = function() push(Screens.display(d.name)) end }
        end
      end
      if #rows == 1 then
        rows[#rows + 1] = { type = "info", label = "Brak Source Block w sieci" }
        rows[#rows + 1] = { type = "info", label = "Polacz: Source Block -> Display Link -> wyswietlacz" }
      end
      return rows
    end,
  }
end

---------------------------------------------------------------------------
-- Pilot (Pocket Computer)
---------------------------------------------------------------------------
function Screens.remote()
  local rc = ctx.cfg.remote
  local R = require("lib.remote")
  return {
    title = "Pilot (Pocket Computer)",
    rows = function()
      local mods = R.wirelessModems()
      return {
        cfgRow("toggle", "Wlaczony", rc, "enabled"),
        cfgRow("text", "PIN", rc, "pin"),
        { type = "info", label = "Modemy bezprzewodowe", value = #mods > 0 and table.concat(mods, ",") or "BRAK",
          color = #mods > 0 and colors.lime or colors.red },
        { type = "info", label = "Nazwa hosta", value = R.hostname or "-" },
        { type = "header", label = "Na Pocket Computerze (z Ender Modemem):" },
        { type = "info", label = "wget <link do install.lua> install.lua" },
        { type = "info", label = "install   (sam wykryje pocket)" },
        { type = "header", label = "Ender Modem = zasieg bez limitu, miedzy wymiarami" },
      }
    end,
  }
end

function Screens.main()
  return {
    title = "Smart System - " .. ctx.cfg.title,
    rows = function()
      local nMon, nAssigned = 0, 0
      for _, m in pairs(ctx.monitors) do
        nMon = nMon + 1
        if ctx.modules[m.cfg.module] then nAssigned = nAssigned + 1 end
      end
      local alarms = A.list()
      return {
        { type = "info", label = "Monitory (przypisane)", value = nAssigned .. "/" .. nMon,
          color = nAssigned < nMon and colors.orange or colors.lime },
        { type = "info", label = "Urzadzenia", value = #D.list },
        { type = "info", label = "Energia", value = A.energyFrac and U.pct(A.energyFrac) or "-" },
        { type = "info", label = "Alarmy", value = #alarms == 0 and "brak" or (alarms[1].text),
          color = #alarms == 0 and colors.lime or colors.red },
        { type = "header", label = "" },
        { type = "action", label = "Monitory  - co gdzie wyswietlac", run = function() push(Screens.monitors()) end },
        { type = "action", label = "Urzadzenia - nazwy, ukrywanie", run = function() push(Screens.devices()) end },
        { type = "action", label = "Alarmy i automatyka", run = function() push(Screens.alarms()) end },
        { type = "action", label = "Panel sterowania (redstone)", run = function() push(Screens.controls()) end },
        { type = "action", label = "Autocrafting (ME/RS)", run = function() push(Screens.autocraft()) end },
        { type = "action", label = "Wyswietlacze Create", run = function() push(Screens.displays()) end },
        { type = "action", label = "Pilot (Pocket Computer)", run = function() push(Screens.remote()) end },
        { type = "action", label = "Dziennik zdarzen", run = function() push(Screens.log()) end },
        { type = "action", label = "Ustawienia i aktualizacja", run = function() push(Screens.settings()) end },
        { type = "action", label = "Uruchom ponownie", bg = colors.orange, fg = colors.black, run = function() os.reboot() end },
        { type = "action", label = "Wyjdz do konsoli", bg = colors.red, run = function() G.exit = true end },
      }
    end,
  }
end

---------------------------------------------------------------------------
function G.run(c)
  ctx = c
  canvas = UI.canvas(term.current())
  stack = {}
  push(Screens.main())
  local refresh = os.startTimer(1)
  draw()
  while not G.exit do
    local e, a, b, y = os.pullEvent()
    local s = stack[#stack]
    if e == "mouse_click" then
      local btn = canvas:hit(b, y)
      if btn then
        if btn.id == "back" then pop()
        elseif btn.id == "up" then s.scroll = s.scroll - 3
        elseif btn.id == "down" then s.scroll = s.scroll + 3
        else
          local r = s.lastRows and s.lastRows[btn.data]
          if r then activate(r, btn.id) end
        end
      end
      draw()
    elseif e == "mouse_scroll" then
      s.scroll = (s.scroll or 0) + a
      draw()
    elseif e == "key" then
      if a == keys.backspace then pop()
      elseif a == keys.up then s.scroll = s.scroll - 1
      elseif a == keys.down then s.scroll = s.scroll + 1
      elseif a == keys.pageUp then s.scroll = s.scroll - 10
      elseif a == keys.pageDown then s.scroll = s.scroll + 10 end
      draw()
    elseif e == "timer" and a == refresh then
      refresh = os.startTimer(1)
      draw()
    elseif e == "smart_tick" or e == "term_resize" then
      draw()
    end
  end
end

return G
