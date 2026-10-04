-- Smart System: menu konfiguracji – to samo menu na komputerze, monitorze dotykowym i pilocie (Pocket)
local U = require("lib.util")
local UI = require("lib.ui")
local GFX = require("lib.gfx")
local D = require("lib.devices")
local A = require("lib.auto")

local G = {}
local SCALES = { 0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5 }
local RAD_VALUES = { 0.00001, 0.001, 0.1, 10 }
local RAD_LABELS = { [0.00001] = "LOW (10 uSv/h)", [0.001] = "MEDIUM (1 mSv/h)", [0.1] = "ELEVATED (100 mSv/h)", [10] = "HIGH (10 Sv/h)" }

-- Instancja menu. opts:
--   localTerm = true  -> ekran komputera bazy (klawiatura, "Wyjdz do konsoli", aktualizacja na miejscu)
--   osk = true        -> klawiatura ekranowa przy wpisywaniu (monitor dotykowy)
-- Kazda instancja ma wlasny stos ekranow, wiec komputer, monitory i pilot nie przeszkadzaja sobie.
function G.new(ctx, opts)
  opts = opts or {}
  local inst = {}
  local stack = {}
  local canvas
  local message -- { text, color, untilT }
  local input   -- { title, value, onDone }
  local shift = false

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

  local function drawClassic()
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
    canvas:text(x0, 1, U.trunc(s.title, w - x0 - 6), colors.black, colors.cyan)
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
      canvas:text(2, h, U.trunc("Smart " .. ctx.version .. (opts.localTerm and "  Backspace=wstecz" or "  < = wstecz"), w - 2), colors.lightGray, colors.gray)
    end
  end

  -- nowoczesny wyglad: karty z zaokragleniami, przelaczniki, linie sekcji (znaki mozaikowe)
  local function drawModern()
    local s = stack[#stack]
    canvas:reset()
    canvas:clear(colors.black)
    local w, h = canvas.w, canvas.h
    local CH_RULE, CH_BAR = string.char(140), string.char(149)

    -- naglowek: karta na calej szerokosci, przycisk wstecz albo znacznik akcentu
    canvas:rect(1, 1, w, 1, colors.gray)
    canvas.bg = colors.gray
    local x0 = 3
    if #stack > 1 then
      canvas:button("back", 2, 1, 3, 1, string.char(17), colors.white, colors.blue)
      x0 = 6
    else
      canvas:text(1, 1, CH_BAR, colors.cyan, colors.gray)
    end
    local alarms = #A.list()
    local right = alarms > 0 and (string.char(19) .. " " .. alarms .. " ") or (string.char(7) .. " OK ")
    canvas:text(x0, 1, U.trunc(s.title, w - x0 - #right - 1), colors.white, colors.gray)
    canvas:right(1, right, alarms > 0 and colors.red or colors.lime, colors.gray)
    canvas.bg = colors.black

    local rows = s.rows()
    s.lastRows = rows
    local top, bottom = 3, h - 1
    local visible = bottom - top + 1
    local maxScroll = math.max(0, #rows - visible)
    s.scroll = U.clamp(s.scroll or 0, 0, maxScroll)
    local barW = maxScroll > 0 and 2 or 0
    local right0 = w - 1 - barW          -- prawa krawedz tresci
    local vw = math.min(24, math.floor(w * 0.42))
    for i = 1, visible do
      local idx = i + s.scroll
      local r = rows[idx]
      if not r then break end
      local y = top + i - 1
      if r.type ~= "header" and r.type ~= "info" then
        canvas:zone("row", 1, y, w - barW, 1, idx)
      end
      if r.type == "header" then
        -- naglowek sekcji: tekst + cienka linia do konca
        local label = r.label ~= "" and r.label:upper() or ""
        if label ~= "" then
          label = U.trunc(label, right0 - 3)
          canvas:text(2, y, label, colors.cyan, colors.black)
          local lx = 3 + #label
          if right0 >= lx then canvas:text(lx, y, string.rep(CH_RULE, right0 - lx + 1), colors.gray, colors.black) end
        end
      elseif r.type == "info" then
        canvas:kv(2, y, right0 - 1, r.label, U.trunc(valueText(r), vw), colors.lightGray, r.color or colors.white)
      elseif r.type == "action" then
        -- kolejne akcje tworza jedna karte (zaokraglona tylko na gorze i dole grupy)
        local prev, nxt = rows[idx - 1], rows[idx + 1]
        local first = i == 1 or not prev or prev.type ~= "action"
        local last = i == visible or not nxt or nxt.type ~= "action"
        canvas:rect(2, y, right0 - 1, 1, colors.gray)
        local function corner(cx, side)
          local pm = GFX.pixmap(2, 3)
          GFX.fillRect(pm, 0, 0, 2, 3, colors.gray)
          if first then GFX.set(pm, side, 0, nil) end
          if last then GFX.set(pm, side, 2, nil) end
          GFX.draw(canvas.t, cx, y, pm, colors.black)
        end
        if first or last then corner(2, 0); corner(right0, 1) end
        -- kolor akcji jako znacznik i kolor tekstu (zamiast pelnego tla)
        local accent = (r.bg and r.bg ~= colors.gray) and r.bg or nil
        -- kolor akcji ma pierwszenstwo (r.fg bywa czarny – byl dobrany pod kolorowe tlo w klasycznym)
        local fg = accent or r.fg or colors.white
        if accent then canvas:text(3, y, CH_BAR, accent, colors.gray) end
        local v = valueText(r)
        canvas:text(4, y, U.trunc(r.label, right0 - 6 - (v ~= "" and vw or 0)), fg, colors.gray)
        canvas:right(y, (v ~= "" and (U.trunc(v, vw) .. " ") or "") .. string.char(16) .. " ", r.vfg or colors.lightGray, colors.gray, right0)
      elseif r.type == "toggle" then
        canvas:text(2, y, U.trunc(r.label, right0 - 9), colors.white, colors.black)
        local on = r.get() and true or false
        canvas:text(right0 - 9, y, on and "WL " or "WYL", on and colors.lime or colors.lightGray, colors.black)
        canvas:switch("row", right0 - 5, y, on, idx, 5)
      elseif r.type == "number" then
        canvas:text(2, y, U.trunc(r.label, right0 - vw - 2), colors.white, colors.black)
        local vx = right0 - vw + 1
        canvas:button("dec", vx, y, 3, 1, "-", colors.white, colors.gray, idx)
        canvas:button("inc", right0 - 2, y, 3, 1, "+", colors.white, colors.gray, idx)
        canvas:center(y, U.trunc(valueText(r), vw - 8), colors.cyan, colors.black, vx + 4, vw - 8)
        canvas:zone("row", vx + 4, y, vw - 8, 1, idx)
      else
        -- choice / text: wartosc w zaokraglonej "pigulce"
        canvas:text(2, y, U.trunc(r.label, right0 - vw - 2), colors.white, colors.black)
        local cx = right0 - vw + 1
        canvas:card(cx, y, vw, 1, colors.gray)
        local icon = r.type == "choice" and string.char(31) or string.char(26)
        canvas:text(cx + 1, y, U.trunc(valueText(r), vw - 4), colors.white, colors.gray)
        canvas:text(cx + vw - 3, y, icon, colors.lightGray, colors.gray)
        canvas:zone("row", cx, y, vw, 1, idx)
      end
    end
    if maxScroll > 0 then
      -- cienki pasek przewijania
      local sx = w - 1
      for yy = top, bottom do canvas:text(sx, yy, CH_BAR, colors.gray, colors.black) end
      local thumbH = math.max(1, math.floor(visible * visible / #rows))
      local pos = top + math.floor((visible - thumbH) * s.scroll / maxScroll)
      for yy = pos, pos + thumbH - 1 do canvas:text(sx, yy, CH_BAR, colors.cyan, colors.black) end
      canvas:zone("up", sx - 1, top, 2, math.floor(visible / 2))
      canvas:zone("down", sx - 1, top + math.floor(visible / 2), 2, visible - math.floor(visible / 2))
    end
    -- stopka
    canvas:rect(1, h, w, 1, colors.gray)
    if message and os.clock() < message.untilT then
      canvas:text(1, h, CH_BAR, message.color, colors.gray)
      canvas:text(3, h, U.trunc(message.text, w - 3), message.color, colors.gray)
    else
      canvas:text(3, h, U.trunc("Smart " .. ctx.version .. (opts.localTerm and "   Backspace = wstecz" or ""), w - 3), colors.lightGray, colors.gray)
    end
  end

  local function draw()
    if UI.modern then return drawModern() end
    return drawClassic()
  end

  -- wpisywanie tekstu: nieblokujace (klawiatura komputera/pocketa albo klawiatura ekranowa na monitorze)
  local KB = { "1234567890", "qwertyuiop", "asdfghjkl:", "zxcvbnm_.-" }

  local function prompt(title, default, onDone)
    input = { title = title, value = default ~= nil and tostring(default) or "", onDone = onDone }
  end

  local function finishInput(ok)
    local inp = input
    input = nil
    if ok and inp and inp.onDone then inp.onDone(inp.value) end
  end

  local function drawInput()
    local w, h = canvas.w, canvas.h
    -- klawiatura z odstepami miedzy rzedami (klawisze nie zlewaja sie w paski), jesli jest miejsce
    local gap = (opts.osk and h >= 24) and 1 or 0
    local kbH = opts.osk and (5 + 4 * gap) or 0
    local bh = 5
    local by = opts.osk and math.max(2, h - kbH - bh) or math.max(2, math.floor((h - bh) / 2) + 1)
    local bx, bw = 2, w - 2
    local boxBg = UI.modern and colors.gray or colors.blue
    canvas:card(bx, by, bw, bh, boxBg)
    canvas.bg = boxBg
    canvas:text(bx + 2, by, U.trunc(input.title, bw - 4), UI.modern and colors.cyan or colors.white, boxBg)
    canvas:card(bx + 1, by + 1, bw - 2, 1, colors.black)
    local v = input.value
    if #v > bw - 5 then v = v:sub(-(bw - 5)) end
    canvas:text(bx + 2, by + 1, v .. "_", colors.white, colors.black)
    if not opts.osk then
      canvas:text(bx + 2, by + 2, U.trunc("Pisz z klawiatury, Enter = OK", bw - 4), UI.modern and colors.lightGray or colors.lightBlue, boxBg)
    end
    local third = math.floor((bw - 4) / 3)
    canvas:button("in_ok", bx + 1, by + 3, third, 1, "OK", colors.black, colors.lime)
    canvas:button("in_clear", bx + 2 + third, by + 3, third, 1, "Wyczysc", colors.white, colors.orange)
    canvas:button("in_cancel", bx + 3 + third * 2, by + 3, bw - 4 - third * 2, 1, "Anuluj", colors.white, colors.red)
    canvas.bg = colors.black
    if opts.osk then
      local ky = h - kbH + 1
      canvas:rect(1, ky - 1, w, kbH + 1, colors.black)
      local kw = math.max(1, math.floor((w - 1) / 10))
      local step = 1 + gap
      for r, row in ipairs(KB) do
        for i = 1, #row do
          local ch = row:sub(i, i)
          if shift then ch = ch:upper() end
          canvas:button("in_key", 2 + (i - 1) * kw, ky + (r - 1) * step, math.max(1, kw - (kw > 2 and 1 or 0)), 1, ch, colors.white, colors.gray, ch)
        end
      end
      local q = math.floor((w - 2) / 3)
      local ly = ky + 4 * step
      canvas:button("in_shift", 2, ly, q - 1, 1, shift and "abc" or "ABC", colors.black, colors.lightGray)
      canvas:button("in_key", 2 + q, ly, q - 1, 1, "spacja", colors.black, colors.lightGray, " ")
      canvas:button("in_bksp", 2 + q * 2, ly, w - 2 - q * 2, 1, "<-", colors.white, colors.orange)
    end
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
        prompt(r.label .. " (" .. (r.min or "-inf") .. ".." .. (r.max or "inf") .. ")", v, function(s)
          local n = tonumber(s)
          if not n then flash("To nie jest liczba", colors.red) return end
          if r.min then n = math.max(r.min, n) end
          if r.max then n = math.min(r.max, n) end
          r.set(U.round(n, 2))
        end)
        return
      end
      if r.min then v = math.max(r.min, v) end
      if r.max then v = math.min(r.max, v) end
      r.set(U.round(v, 2))
    elseif r.type == "text" then
      prompt(r.label, r.get(), function(s) r.set(s) end)
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
            type = "choice", label = "Polacz z urzadzeniem",
            labels = (function()
              local l = { none = "(brak)" }
              for _, d in ipairs(D.list) do l[d.name] = D.label(d) .. " - " .. D.kindLabel(d.kind) end
              return l
            end)(),
            choices = function()
              local Src = require("lib.sources")
              local r = { "none" }
              for _, d in ipairs(D.list) do if Src.isSource(ctx.cfg, d) then r[#r + 1] = d.name end end
              return r
            end,
            get = function() return c.link or "none" end,
            set = function(v) c.link = v ~= "none" and v or nil; changed() end,
          },
          {
            type = "toggle", label = "  steruj razem z urzadzeniem",
            get = function() return c.linkSync ~= false end,
            set = function(v) c.linkSync = v; changed() end,
          },
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
    if opts.localTerm then return G.runUpdate() end
    os.queueEvent("smart_update")
    flash("Aktualizacja startuje na komputerze bazy")
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
          cfgRow("choice", "Wyglad", cfg, "theme", { labels = require("lib.theme").LABELS,
            choices = function() return require("lib.theme").NAMES end }),
          cfgRow("toggle", "Dzwiek klikniecia (glosnik)", cfg, "clickSound"),
          { type = "action", label = "Ekran komputera (duzy terminal)", run = function() push(Screens.screen()) end },
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

  function Screens.screen()
    local sc = ctx.cfg.screen
    return {
      title = "Ekran komputera",
      rows = function()
        local ids, labels = { "none" }, { none = "(brak)" }
        for _, id in ipairs(ctx.moduleIds) do
          if ctx.modules[id] and id ~= "menu" then ids[#ids + 1] = id; labels[id] = ctx.modules[id].name end
        end
        local w, h = 0, 0
        if opts.localTerm then w, h = term.getSize() end
        local rows = {
          { type = "info", label = "Terminal (config CC)", value = opts.localTerm and (w .. "x" .. h) or "-" },
          { type = "info", label = "Panele od szerokosci", value = "100 kolumn" },
          cfgRow("choice", "Uklad", sc, "layout", { labels = { auto = "menu + panele", menu = "samo menu" },
            choices = function() return { "auto", "menu" } end }),
          cfgRow("number", "Kolumny paneli", sc, "cols", { min = 1, max = 4, step = 1 }),
          cfgRow("number", "Szerokosc menu (0=auto)", sc, "menuWidth", { min = 0, max = 200, step = 5 }),
          { type = "header", label = "Panele (moduly jak na monitorach)" },
        }
        for i = 1, 6 do
          rows[#rows + 1] = {
            type = "choice", label = "Panel " .. i, labels = labels,
            choices = function() return ids end,
            get = function() return sc.panels[i] or "none" end,
            set = function(v)
              sc.panels[i] = v
              -- bez dziur w liscie
              local packed = {}
              for k = 1, 6 do if sc.panels[k] and sc.panels[k] ~= "none" then packed[#packed + 1] = sc.panels[k] end end
              sc.panels = packed
              changed()
            end,
          }
        end
        return rows
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
            prompt("Fragment nazwy (puste = wszystko)", "", function(f) push(Screens.acPick(f or "")) end)
          end }
        rows[#rows + 1] = { type = "action", label = "+ Dodaj po ID (np. minecraft:iron_ingot)", bg = colors.green,
          run = function()
            prompt("ID przedmiotu", "", function(id)
              if id:match("^[%w_%.%-]+:[%w_%./%-]+$") then addAcItem(id)
              elseif id ~= "" then flash("Zly format ID", colors.red) end
            end)
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
          cfgRow("text", "PIN (cyfry)", rc, "pin"),
          { type = "info", label = "PIN dziala tez jako blokada menu na monitorach" },
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

  ---------------------------------------------------------------------------
  -- Czat i AI (Ollama)
  ---------------------------------------------------------------------------
  function Screens.chatbot()
    local cb = ctx.cfg.chatbot
    local ai = cb.ai
    local CBL = require("lib.chatbot")
    local O = require("lib.ollama")
    return {
      title = "Czat i AI (Ollama)",
      rows = function()
        local boxes = D.byKind("chat")
        local models = O.models or {}
        local choices = {}
        if ai.model ~= "" then choices[1] = ai.model end
        for _, m in ipairs(models) do if m ~= ai.model then choices[#choices + 1] = m end end
        local rows = {
          { type = "info", label = "Chat Box", value = #boxes > 0 and boxes[1].name or "BRAK",
            color = #boxes > 0 and colors.lime or colors.red },
          cfgRow("toggle", "Odpowiadaj na czacie", cb, "enabled"),
          cfgRow("text", "Slowo wyzwalajace", cb, "trigger"),
          cfgRow("text", "Podpis odpowiedzi", cb, "prefix"),
          cfgRow("toggle", "Zawsze prywatnie", cb, "private"),
          cfgRow("text", "Tylko gracze (puste=wszyscy)", cb, "allowed"),
          { type = "info", label = "Przyklad: " .. cb.trigger .. " status / $" .. cb.trigger .. " pomoc" },
          { type = "header", label = "AI - serwer Ollama" },
          cfgRow("toggle", "AI wlaczone", ai, "enabled"),
          cfgRow("text", "Adres serwera", ai, "url"),
          { type = "info", label = "Laczy z", value = O.baseUrl(ai.url) .. "/api" },
          {
            type = "choice", label = "Model",
            choices = function() return #choices > 0 and choices or { "" } end,
            labels = { [""] = "(najpierw pobierz liste)" },
            get = function() return ai.model end,
            set = function(v) ai.model = v; changed() end,
          },
          cfgRow("text", "Model (wpisz recznie)", ai, "model"),
          { type = "action", label = "Pobierz liste modeli / test polaczenia", bg = colors.blue,
            run = function()
              local list, err = O.listModels(ai.url)
              if list then
                flash("Polaczono: " .. #list .. " modeli", colors.lime)
                if ai.model == "" and list[1] then ai.model = list[1]; changed() end
              else
                flash("Ollama: " .. tostring(err), colors.red)
                A.logEvent("Ollama (" .. O.baseUrl(ai.url) .. "): " .. tostring(err), "warn")
              end
            end },
          cfgRow("number", "Maks. dlugosc (tokeny)", ai, "maxTokens", { min = 20, max = 2000, step = 50 }),
          cfgRow("number", "Pamiec rozmowy (wymiany)", ai, "memory", { min = 0, max = 10, step = 1 }),
          cfgRow("toggle", "Dane bazy w pytaniu", ai, "context"),
          {
            type = "toggle", label = "Wylacz myslenie (szybciej)",
            get = function() return ai.think == false end,
            -- false = wysylamy think:false; true = nie wysylamy pola (domyslne zachowanie modelu)
            set = function(v) ai.think = not v; changed() end,
          },
          cfgRow("text", "Wlasny prompt (puste=domyslny)", ai, "prompt"),
          cfgRow("choice", "Info 'mysle...'", ai, "placeholder", {
            labels = { chat = "na czacie", toast = "toast (powiadomienie)", off = "wylaczone" },
            choices = function() return { "chat", "toast", "off" } end }),
          cfgRow("text", "  tekst", ai, "placeholderText"),
          cfgRow("number", "  'nadal mysle' co (s, 0=wyl)", ai, "progressEvery", { min = 0, max = 120, step = 5 }),
          { type = "action", label = "Wyczysc pamiec rozmow", run = function() CBL.history = {}; flash("Wyczyszczono") end },
        }
        -- ostatni blad polaczenia (oryginalny tekst z CC) zaraz pod adresem
        if O.lastError then
          for i, r in ipairs(rows) do
            if r.label == "Laczy z" then
              table.insert(rows, i + 1, { type = "info", label = "Blad CC", value = O.lastError, color = colors.red })
              break
            end
          end
        end
        if CBL.last then
          rows[#rows + 1] = { type = "header", label = "Ostatnio" }
          rows[#rows + 1] = { type = "info", label = CBL.last.player .. ": " .. CBL.last.q }
          rows[#rows + 1] = { type = "info", label = "> " .. CBL.last.a }
        end
        rows[#rows + 1] = { type = "header", label = "Ollama w sieci lokalnej?" }
        rows[#rows + 1] = { type = "info", label = "CC blokuje adresy prywatne - dodaj regule" }
        rows[#rows + 1] = { type = "info", label = "allow w computercraft-server.toml (README)" }
        return rows
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
          { type = "action", label = "Czat i AI (Ollama)", run = function() push(Screens.chatbot()) end },
          { type = "action", label = "Dziennik zdarzen", run = function() push(Screens.log()) end },
          { type = "action", label = "Ustawienia i aktualizacja", run = function() push(Screens.settings()) end },
          { type = "action", label = "Uruchom ponownie", bg = colors.orange, fg = colors.black, run = function() os.reboot() end },
          opts.localTerm and { type = "action", label = "Wyjdz do konsoli", bg = colors.red, run = function() inst.exit = true end } or nil,
        }
      end,
    }
  end

  push(Screens.main())

  -- rysuje menu na podanym canvasie (UI.canvas na terminalu, oknie monitora lub oknie wirtualnym)
  function inst.draw(c)
    canvas = c
    draw()
    if input then drawInput() end
  end

  function inst.isInput() return input ~= nil end

  -- obsluga przycisku z canvas:hit()
  function inst.button(btn)
    if not btn then return end
    if input then
      local id = btn.id
      if id == "in_ok" then finishInput(true)
      elseif id == "in_cancel" then finishInput(false)
      elseif id == "in_clear" then input.value = ""
      elseif id == "in_bksp" then input.value = input.value:sub(1, -2)
      elseif id == "in_shift" then shift = not shift
      elseif id == "in_key" then input.value = input.value .. btn.data end
      return
    end
    local s = stack[#stack]
    if btn.id == "back" then pop()
    elseif btn.id == "up" then s.scroll = (s.scroll or 0) - 3
    elseif btn.id == "down" then s.scroll = (s.scroll or 0) + 3
    else
      local r = s.lastRows and s.lastRows[btn.data]
      if r then activate(r, btn.id) end
    end
  end

  function inst.click(x, y)
    if canvas then inst.button(canvas:hit(x, y)) end
  end

  function inst.scroll(dir)
    if input then return end
    local s = stack[#stack]
    s.scroll = (s.scroll or 0) + dir
  end

  function inst.char(ch)
    if input then input.value = input.value .. ch end
  end

  function inst.key(k)
    if input then
      if k == keys.backspace then input.value = input.value:sub(1, -2)
      elseif k == keys.enter or k == keys.numPadEnter then finishInput(true) end
      return
    end
    local s = stack[#stack]
    if k == keys.backspace then pop()
    elseif k == keys.up then s.scroll = (s.scroll or 0) - 1
    elseif k == keys.down then s.scroll = (s.scroll or 0) + 1
    elseif k == keys.pageUp then s.scroll = (s.scroll or 0) - 10
    elseif k == keys.pageDown then s.scroll = (s.scroll or 0) + 10 end
  end

  return inst
end

-- aktualizacja z GitHuba na ekranie komputera bazy
function G.runUpdate()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
  local function ver()
    if not fs.exists("/smart/version.txt") then return nil end
    local f = fs.open("/smart/version.txt", "r")
    local v = f.readAll()
    f.close()
    return v
  end
  local before = ver()
  local ok = shell.run("/install.lua", "update")
  print("")
  if ok and ver() == before then
    -- nic nie pobrano (najnowsza wersja) – bez restartu; powrot po 3 s albo klawiszu
    -- (aktualizacje mozna wywolac z pilota/monitora, wiec nie czekamy w nieskonczonosc)
    print("Powrot do menu za 3s...")
    local t = os.startTimer(3)
    repeat
      local e, id = os.pullEvent()
    until (e == "timer" and id == t) or e == "key"
  elseif ok then
    print("Aktualizacja zakonczona. Restart za 3s...")
    sleep(3)
    os.reboot()
  else
    printError("Aktualizacja nie powiodla sie.")
    print("Nacisnij dowolny klawisz...")
    os.pullEvent("key")
  end
end

---------------------------------------------------------------------------
-- Ekran komputera bazy. Przy duzym terminalu (config CC: term_sizes.computer) menu dostaje kolumne
-- po lewej, a reszta ekranu to siatka paneli z modulami (jak monitory, dzialaja na dotyk/klik).
---------------------------------------------------------------------------
local BIG_WIDTH = 100

local function layoutKey(ctx, w, h)
  local sc = ctx.cfg.screen
  return table.concat({ w, h, sc.layout, sc.cols, sc.menuWidth, table.concat(sc.panels, ","), tostring(ctx.cfg.theme) }, "|")
end

-- buduje okna: menu + panele; zwraca { menuWin, menuCanvas, panels = { {win, x, y, m} } }
local function buildLayout(ctx, root, old)
  local w, h = root.getSize()
  local sc = ctx.cfg.screen
  local L = { key = layoutKey(ctx, w, h), panels = {} }
  local ids = {}
  for _, id in ipairs(sc.panels) do
    if id ~= "none" and id ~= "menu" and ctx.modules[id] then ids[#ids + 1] = id end
  end
  local big = sc.layout ~= "menu" and w >= BIG_WIDTH and #ids > 0
  local menuW = w
  if big then
    menuW = sc.menuWidth > 0 and sc.menuWidth or math.floor(w * 0.3)
    menuW = U.clamp(menuW, 51, w - 40)
  end
  L.big = big
  L.menuW = menuW
  L.menuWin = window.create(root, 1, 1, menuW, h, true)
  L.menuCanvas = UI.canvas(L.menuWin)
  if not big then return L end

  -- siatka paneli w obszarze na prawo od menu (1 kolumna przerwy)
  local ax, aw = menuW + 2, w - menuW - 1
  local cols = U.clamp(sc.cols or 2, 1, #ids)
  local rows = math.ceil(#ids / cols)
  local pw = math.floor((aw - (cols - 1)) / cols)
  local ph = math.floor((h - (rows - 1)) / rows)
  for i, id in ipairs(ids) do
    local col = (i - 1) % cols
    local row = math.floor((i - 1) / cols)
    local x = ax + col * (pw + 1)
    local y = 1 + row * (ph + 1)
    local wdt = (col == cols - 1) and (w - x + 1) or pw
    local hgt = (row == rows - 1) and (h - y + 1) or ph
    local win = window.create(root, x, y, wdt, hgt, false)
    local mod = ctx.modules[id]
    -- stan modulu zachowujemy przy przebudowie (np. historia bilansu energii)
    local prev = old and old.panels[i] and old.panels[i].m
    local m = {
      name = "panel_" .. i,
      cfg = { module = id, source = "auto", title = "", opts = (prev and prev.cfg.module == id) and prev.cfg.opts or {} },
      state = (prev and prev.cfg.module == id) and prev.state or {},
      accent = colors.cyan,
      win = win,
      canvas = UI.canvas(win),
    }
    m.opts = m.cfg.opts
    for _, o in ipairs(mod.options or {}) do
      if m.opts[o.key] == nil then m.opts[o.key] = o.default end
    end
    L.panels[#L.panels + 1] = { x = x, y = y, w = wdt, h = hgt, m = m, mod = mod }
  end
  -- separatory miedzy menu a panelami
  root.setBackgroundColor(colors.gray)
  for yy = 1, h do
    root.setCursorPos(menuW + 1, yy)
    root.write(" ")
  end
  return L
end

local function drawPanel(ctx, p)
  local m = p.m
  m.win.setVisible(false)
  m.canvas:reset()
  local ok, err = pcall(p.mod.draw, ctx, m, m.canvas)
  if not ok then
    m.canvas:clear(colors.black)
    m.canvas:header("Blad: " .. p.mod.name, colors.red)
    m.canvas:text(2, 3, U.trunc(tostring(err), m.canvas.w - 2), colors.red, colors.black)
  end
  m.win.setVisible(true)
end

local function updatePanel(ctx, p)
  if p.mod.update then pcall(p.mod.update, ctx, p.m) end
end

-- menu na ekranie komputera bazy
function G.run(ctx)
  local inst = G.new(ctx, { localTerm = true })
  local root = term.current()
  local L
  local function relayout()
    UI.setTheme(ctx.cfg.theme)
    require("lib.theme").apply(root, ctx.cfg.theme)
    root.setBackgroundColor(colors.black)
    root.clear()
    L = buildLayout(ctx, root, L)
    for _, p in ipairs(L.panels) do updatePanel(ctx, p); drawPanel(ctx, p) end
  end
  local function drawMenu()
    L.menuWin.setVisible(false)
    inst.draw(L.menuCanvas)
    L.menuWin.setVisible(true)
  end
  relayout()
  drawMenu()
  local refresh = os.startTimer(1)
  while not inst.exit do
    local e, a, b, y = os.pullEvent()
    local menuEvent = true
    if e == "mouse_click" then
      if b <= L.menuW then
        inst.click(b, y)
      else
        menuEvent = false
        for _, p in ipairs(L.panels) do
          if b >= p.x and b < p.x + p.w and y >= p.y and y < p.y + p.h then
            local btn = p.m.canvas:hit(b - p.x + 1, y - p.y + 1)
            if btn and p.mod.touch then
              p.m.flash = nil
              local ok, err = pcall(p.mod.touch, ctx, p.m, btn)
              if not ok then p.m.flash = { text = tostring(err), untilT = os.clock() + 3, ok = false } end
              if ctx.feedback then ctx.feedback(not (p.m.flash and not p.m.flash.ok)) end
              updatePanel(ctx, p)
              drawPanel(ctx, p)
            end
          end
        end
      end
    elseif e == "mouse_scroll" then
      if b <= L.menuW then inst.scroll(a) end
    elseif e == "key" then
      inst.key(a)
    elseif e == "char" then
      inst.char(a)
    elseif e == "paste" then
      for ch in a:gmatch(".") do inst.char(ch) end
    elseif e == "smart_update" then
      G.runUpdate()
      relayout()
    elseif e == "term_resize" then
      relayout()
    elseif e == "smart_tick" then
      -- zmiana ustawien ekranu z menu -> przebudowa; inaczej odswiezenie paneli
      if layoutKey(ctx, root.getSize()) ~= L.key then
        relayout()
      else
        for _, p in ipairs(L.panels) do updatePanel(ctx, p); drawPanel(ctx, p) end
      end
    elseif e == "timer" and a == refresh then
      refresh = os.startTimer(1)
    end
    if menuEvent then drawMenu() end
  end
end

return G
