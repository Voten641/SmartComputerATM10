-- Smart System: chatbot na czacie (Advanced Peripherals Chat Box + opcjonalnie Ollama)
-- Event AP 0.8: "chat", uuid, username, message, isHidden, utf8Message
--  - wiadomosc zaczynajaca sie od "$" jest ukryta (AP usuwa "$" i ustawia isHidden = true)
-- Wiadomosci "smart ..." (slowo wyzwalajace z ustawien) dostaja odpowiedz: komendy wbudowane albo AI.
local U = require("lib.util")
local D = require("lib.devices")
local O = require("lib.ollama")
local CP = require("lib.craftplan")

local CB = {}
CB.queue = {}      -- pytania czekajace na obsluge
CB.history = {}    -- [gracz] = { {role, content}, ... } (pamiec rozmowy z AI)
CB.busy = false
CB.last = nil      -- ostatnie pytanie/odpowiedz (do podgladu w menu)
CB.current = nil   -- pytanie przetwarzane teraz przez AI { player, hidden, started, lastPing }

CB.DEFAULT_PROMPT = "Jestes asystentem bazy w Minecraft (modpack All The Mods 10 To The Sky), "
  .. "sterowanej przez system Smart System na komputerach CC: Tweaked. Odpowiadaj krotko po polsku, "
  .. "maksymalnie 2-3 zdania, bez formatowania markdown. Jesli pytanie dotyczy bazy, korzystaj z aktualnych danych ponizej."

local MAX_CHUNK = 240

---------------------------------------------------------------------------
-- dzielenie dlugiej odpowiedzi na wiadomosci (po slowach, bez rozcinania znakow UTF-8)
function CB.split(text, max)
  max = max or MAX_CHUNK
  local out = {}
  for para in tostring(text):gmatch("[^\n]+") do
    local line = ""
    for w in para:gmatch("%S+") do
      local word = w
      while #word > max do
        -- bardzo dlugie "slowo": tniemy na granicy znaku UTF-8
        local cut = max
        while cut > 1 and word:byte(cut + 1) and word:byte(cut + 1) >= 128 and word:byte(cut + 1) < 192 do cut = cut - 1 end
        if line ~= "" then out[#out + 1] = line; line = "" end
        out[#out + 1] = word:sub(1, cut)
        word = word:sub(cut + 1)
      end
      if line == "" then line = word
      elseif #line + 1 + #word <= max then line = line .. " " .. word
      else out[#out + 1] = line; line = word end
    end
    if line ~= "" then out[#out + 1] = line end
  end
  return out
end

---------------------------------------------------------------------------
-- dane bazy (kontekst dla AI i komendy "status")
local function reactorsInfo(ctx)
  local r = {}
  for _, d in ipairs(D.byKind("fission")) do
    if D.formed(d) then
      local on = U.call(d.p, "getStatus")
      local trip = ctx.auto.trips[d.name]
      r[#r + 1] = string.format("%s: %s, %s, burn %.1f mB/t", D.label(d),
        trip and ("SCRAM (" .. trip .. ")") or (on and "pracuje" or "wylaczony"),
        U.temp(U.call(d.p, "getTemperature")), U.call(d.p, "getBurnRate") or 0)
    end
  end
  return r
end

function CB.baseStatus(ctx)
  local lines = {}
  local f, stored, cap = ctx.auto.readEnergy("auto")
  if f then lines[#lines + 1] = string.format("Energia: %s (%s / %s)", U.pct(f), U.fmt(stored, "FE"), U.fmt(cap, "FE")) end
  for _, r in ipairs(reactorsInfo(ctx)) do lines[#lines + 1] = "Reaktor " .. r end
  local gen = 0
  for _, d in ipairs(D.byKind({ "turbine", "fusion" })) do
    if D.formed(d) then gen = gen + (D.mekFE(U.call(d.p, "getProductionRate")) or 0) end
  end
  if gen > 0 then lines[#lines + 1] = "Generacja: " .. U.fmt(gen, "FE/t") end
  for _, d in ipairs(D.byKind({ "me", "rs" })) do
    local fr = U.frac(U.call(d.p, "getUsedItemStorage"), U.call(d.p, "getMaxItemStorage"))
    lines[#lines + 1] = (d.kind == "me" and "Magazyn ME: " or "Magazyn RS: ") .. U.pct(fr) .. " zajete"
  end
  local pd = D.byKind("player")[1]
  if pd then
    local online = U.call(pd.p, "getOnlinePlayers") or {}
    lines[#lines + 1] = "Gracze online: " .. (#online > 0 and table.concat(online, ", ") or "brak")
  end
  local al = ctx.auto.list()
  if #al == 0 then lines[#lines + 1] = "Alarmy: brak"
  else
    local t = {}
    for _, a in ipairs(al) do t[#t + 1] = a.text end
    lines[#lines + 1] = "Alarmy: " .. table.concat(t, "; ")
  end
  return lines
end

---------------------------------------------------------------------------
-- magazyn ME/RS dla AI: przedmioty, plyny i chemikalia ze wszystkich bridge'y (pamiec podreczna 10 s)
local stock = { t = -1000, list = {} }

local function loadStock()
  local now = U.now()
  if now - stock.t < 10 then return stock.list end
  local list = {}
  for _, d in ipairs(D.byKind({ "me", "rs" })) do
    local sys = d.kind == "me" and "ME" or "RS"
    for _, src in ipairs({ { "getItems", "przedmiot", "" }, { "getFluids", "plyn", " mB" }, { "getChemicals", "chemikalia", " mB" } }) do
      local res = U.call(d.p, src[1], {})
      if type(res) == "table" then
        for _, it in ipairs(res) do
          list[#list + 1] = {
            name = U.itemName(it), id = it.name or "?", count = U.itemCount(it),
            kind = src[2], unit = src[3], craft = it.isCraftable == true, sys = sys,
          }
        end
      end
    end
  end
  stock.t, stock.list = now, list
  return list
end

local function fmtStock(e)
  -- dokladna liczba (AI ma podac gracz dokladnie ile ma)
  return string.format("%s (%s): %s%s %s%s", e.name, e.id, tostring(math.floor(e.count)), e.unit,
    e.kind, e.craft and ", da sie scraftowac" or "")
end

-- wyszukiwanie: wszystkie slowa frazy musza wystapic w nazwie lub id (bez wielkosci liter)
function CB.searchStock(phrase, limit)
  local words = {}
  for w in tostring(phrase or ""):lower():gmatch("[%w_:]+") do words[#words + 1] = w end
  local out = {}
  for _, e in ipairs(loadStock()) do
    local hay = ((e.name .. " " .. e.id):lower():gsub("_", " "))
    local ok = #words > 0
    for _, w in ipairs(words) do
      local needle = (w:gsub("_", " "))
      if not hay:find(needle, 1, true) then ok = false break end
    end
    if ok then out[#out + 1] = e end
  end
  table.sort(out, function(a, b) return a.count > b.count end)
  local r = {}
  for i = 1, math.min(#out, limit or 15) do r[i] = out[i] end
  return r, #out
end

function CB.topStock(limit)
  local all = {}
  for _, e in ipairs(loadStock()) do all[#all + 1] = e end
  table.sort(all, function(a, b) return a.count > b.count end)
  local r = {}
  for i = 1, math.min(#all, limit or 20) do r[i] = all[i] end
  return r, #all
end

-- narzedzia dla modeli z obsluga tool calling (Ollama: tools / tool_calls)
CB.TOOLS = {
  {
    type = "function",
    ["function"] = {
      name = "szukaj_w_magazynie",
      description = "Szuka przedmiotow, plynow i chemikaliow w magazynie ME/RS bazy i zwraca ich ilosci. "
        .. "Nazwy w magazynie sa PO ANGIELSKU (np. diamond, iron ingot, redstone) - przetlumacz fraze na angielski. "
        .. "Uzywaj zawsze, gdy gracz pyta czy ma cos albo ile czegos ma.",
      parameters = {
        type = "object",
        properties = {
          fraza = { type = "string", description = "angielska nazwa lub jej fragment, np. 'diamond' albo 'iron ingot'" },
        },
        required = { "fraza" },
      },
    },
  },
  {
    type = "function",
    ["function"] = {
      name = "najwiecej_w_magazynie",
      description = "Zwraca przedmioty/plyny, ktorych w magazynie ME/RS jest najwiecej.",
      parameters = {
        type = "object",
        properties = {
          ile = { type = "number", description = "ile pozycji zwrocic (domyslnie 15)" },
        },
      },
    },
  },
}

CB.TOOLS[#CB.TOOLS + 1] = {
  type = "function",
  ["function"] = {
    name = "sprawdz_crafting",
    description = "Sprawdza, czy da sie zrobic przedmiot z tego, co jest w magazynie ME/RS, na podstawie WZOROW "
      .. "(patterns) w systemie. Rekurencyjnie sprawdza brakujace skladniki i ich wzory. Zwraca drzewo: czego "
      .. "brakuje, co ma wzor, co wymaga maszyny (wzor processing) i czego nie da sie zrobic (brak wzoru). "
      .. "Nazwa PO ANGIELSKU (np. 'logic processor') albo id (np. 'ae2:logic_processor').",
    parameters = {
      type = "object",
      properties = {
        nazwa = { type = "string", description = "angielska nazwa przedmiotu albo jego id" },
        ilosc = { type = "number", description = "ile sztuk (domyslnie 1)" },
      },
      required = { "nazwa" },
    },
  },
}

function CB.runTool(name, args)
  if name == "sprawdz_crafting" then
    if #D.byKind({ "me", "rs" }) == 0 then return "Brak ME/RS Bridge podlaczonego do systemu." end
    local id = CP.resolve(args.nazwa)
    if not id then
      return "Nie znaleziono przedmiotu '" .. tostring(args.nazwa) .. "' w magazynie ani wsrod rzeczy do scraftowania. "
        .. "Nie ma tez dla niego wzoru w ME/RS - przepis mozesz podac z wlasnej wiedzy, zaznaczajac, ze nie jest pewny."
    end
    local root, summary = CP.plan(id, math.max(1, math.floor(tonumber(args.ilosc) or 1)))
    return CP.describe(root, summary, 40)
  end
  if #D.byKind({ "me", "rs" }) == 0 then return "Brak ME/RS Bridge podlaczonego do systemu." end
  if name == "szukaj_w_magazynie" then
    local found, total = CB.searchStock(args.fraza, 15)
    if total == 0 then return "Nic nie znaleziono dla '" .. tostring(args.fraza) .. "' (0 sztuk w magazynie)." end
    local lines = {}
    for _, e in ipairs(found) do lines[#lines + 1] = fmtStock(e) end
    return "Znaleziono " .. total .. ":\n" .. table.concat(lines, "\n")
  elseif name == "najwiecej_w_magazynie" then
    local top, total = CB.topStock(math.max(1, math.min(40, math.floor(tonumber(args.ile) or 15))))
    local lines = {}
    for _, e in ipairs(top) do lines[#lines + 1] = fmtStock(e) end
    return "Rodzajow w magazynie: " .. total .. ". Najwiecej:\n" .. table.concat(lines, "\n")
  end
  return "nieznane narzedzie: " .. tostring(name)
end

-- kontekst magazynu dla modeli BEZ narzedzi: trafienia slow z pytania + najliczniejsze pozycje
local function stockContext(question)
  if #D.byKind({ "me", "rs" }) == 0 then return nil end
  local lines, seen = {}, {}
  for w in tostring(question):lower():gmatch("[%w_]+") do
    if #w >= 3 then
      for _, e in ipairs((CB.searchStock(w, 5))) do
        if not seen[e.id .. e.kind] then seen[e.id .. e.kind] = true; lines[#lines + 1] = fmtStock(e) end
      end
    end
  end
  local top = CB.topStock(20)
  local t = {}
  for _, e in ipairs(top) do t[#t + 1] = fmtStock(e) end
  local out = "Magazyn ME/RS (nazwy po angielsku)."
  if #lines > 0 then out = out .. "\nPasujace do pytania:\n- " .. table.concat(lines, "\n- ") end
  return out .. "\nNajwiecej w magazynie:\n- " .. table.concat(t, "\n- ")
end

---------------------------------------------------------------------------
-- komendy wbudowane (dzialaja bez AI)
local COMMANDS = {}

COMMANDS.pomoc = function(ctx, trig)
  local ai = ctx.cfg.chatbot.ai
  local t = trig .. " status | " .. trig .. " reaktor | " .. trig .. " alarmy | " .. trig .. " craft <nazwa> [ilosc] | " .. trig .. " pomoc"
  if ai.enabled then t = t .. " | albo zadaj dowolne pytanie (AI: " .. tostring(ai.model) .. ")" end
  return "Komendy: " .. t .. ". Dodaj $ na poczatku, zeby nikt nie widzial pytania."
end
COMMANDS.help = COMMANDS.pomoc

COMMANDS.status = function(ctx)
  return table.concat(CB.baseStatus(ctx), " | ")
end

COMMANDS.reaktor = function(ctx)
  local r = reactorsInfo(ctx)
  if #r == 0 then return "Brak reaktora fission (modem na Logic Adapterze?)." end
  return table.concat(r, " | ")
end
COMMANDS.reaktory = COMMANDS.reaktor

-- "smart craft logic processor 16" – plan craftingu z wzorow ME/RS (bez AI)
COMMANDS.craft = function(ctx, trig, arg)
  if not arg or arg == "" then return "Uzycie: " .. trig .. " craft <nazwa po angielsku albo id> [ilosc]" end
  if #D.byKind({ "me", "rs" }) == 0 then return "Brak ME/RS Bridge." end
  local name, n = arg:match("^(.-)%s+(%d+)$")
  if not name then name, n = arg, 1 end
  local id = CP.resolve(name)
  if not id then return "Nie znam '" .. name .. "' - nie ma go w magazynie ani wzorach (podaj angielska nazwe albo id)." end
  local root, summary = CP.plan(id, math.max(1, tonumber(n) or 1))
  return CP.short(root, summary)
end
COMMANDS.crafting = COMMANDS.craft

COMMANDS.alarmy = function(ctx)
  local al = ctx.auto.list()
  if #al == 0 then return "Brak aktywnych alarmow." end
  local t = {}
  for _, a in ipairs(al) do t[#t + 1] = a.text end
  return "Alarmy: " .. table.concat(t, "; ")
end

---------------------------------------------------------------------------
local function allowed(cfg, player)
  local list = tostring(cfg.allowed or "")
  if list:gsub("%s", "") == "" then return true end
  for name in list:gmatch("[^,%s]+") do
    if name:lower() == tostring(player):lower() then return true end
  end
  return false
end

-- "smart status" -> "status"; "smart" -> ""; inny tekst -> nil
function CB.matchTrigger(trigger, text)
  trigger = tostring(trigger or "smart"):lower()
  local t = tostring(text or ""):gsub("^%s+", "")
  local low = t:lower()
  if low:sub(1, #trigger) ~= trigger then return nil end
  local rest = t:sub(#trigger + 1)
  -- slowo musi sie konczyc (spacja, :, ,, ! ?) – "smartfon" nie jest komenda
  if rest ~= "" and not rest:match("^[%s:,!%?%.]") then return nil end
  return (rest:gsub("^[%s:,!%?%.]+", ""):gsub("%s+$", ""))
end

local function reply(ctx, q, text)
  local c = ctx.cfg.chatbot
  local private = q.hidden or c.private
  for _, part in ipairs(CB.split(text)) do
    ctx.auto.say({ text = part, player = private and q.player or nil, prefix = c.prefix ~= "" and c.prefix or "Smart", utf8 = true })
  end
end

-- zdarzenie "chat" z Chat Boxa -> kolejka pytan
function CB.onChat(ctx, uuid, player, message, hidden, utf8msg)
  local c = ctx.cfg.chatbot
  if not c.enabled then return end
  local text = (type(utf8msg) == "string" and utf8msg ~= "") and utf8msg or message
  local q = CB.matchTrigger(c.trigger, text)
  if q == nil then return end
  if not allowed(c, player) then return end
  CB.queue[#CB.queue + 1] = { player = player, text = q, hidden = hidden == true }
  while #CB.queue > 10 do table.remove(CB.queue, 1) end
  os.queueEvent("smart_chatbot")
end

-- krotka informacja dla pytajacego: na czacie albo jako toast (bez zasmiecania czatu)
local function notice(ctx, q, text)
  local c = ctx.cfg.chatbot
  local mode = c.ai.placeholder or "toast"
  if mode == "off" then return end
  local prefix = c.prefix ~= "" and c.prefix or "Smart"
  if mode == "toast" then
    ctx.auto.say({ toast = true, title = prefix .. " AI", text = text, player = q.player, prefix = prefix, utf8 = true })
  else
    ctx.auto.say({ text = text, player = (q.hidden or c.private) and q.player or nil, prefix = prefix, utf8 = true })
  end
end

-- wywolywane co odswiezenie: "nadal mysle" podczas dlugiego generowania
function CB.progress(ctx)
  local cur = CB.current
  if not cur then return end
  local every = tonumber(ctx.cfg.chatbot.ai.progressEvery) or 20
  if every <= 0 then return end
  local now = U.now()
  if now - cur.lastPing >= every then
    cur.lastPing = now
    local t = "Nadal mysle... (" .. math.floor(now - cur.started) .. " s)"
    if #CB.queue > 0 then t = t .. ", w kolejce: " .. #CB.queue end
    notice(ctx, cur, t)
  end
end

local function askAI(ctx, q)
  local ai = ctx.cfg.chatbot.ai
  local hist = CB.history[q.player] or {}
  local sys = (ai.prompt ~= "" and ai.prompt or CB.DEFAULT_PROMPT)
  if ai.context ~= false then
    sys = sys .. "\nAktualne dane bazy:\n- " .. table.concat(CB.baseStatus(ctx), "\n- ")
  end
  local useTools = not O.noTools[ai.model]
  if useTools then
    sys = sys .. "\nO zawartosc magazynu (przedmioty, plyny, ilosci) pytaj narzedziem szukaj_w_magazynie - "
      .. "nie zgaduj. Nazwy w magazynie sa po angielsku."
      .. "\nGdy gracz pyta jak cos zrobic / czy moze cos scraftowac, uzyj sprawdz_crafting. Wyjasnij czego brakuje, "
      .. "co system zrobi sam ze wzorow, co wymaga maszyny (wzor processing) i czego brakuje bez wzoru. "
      .. "Dla rzeczy BEZ wzoru mozesz podac przepis z wlasnej wiedzy o modach ATM10, ale zawsze zaznacz, "
      .. "ze to nie jest sprawdzone w grze (niech gracz potwierdzi w JEI)."
  else
    local sc = stockContext(q.text)
    if sc then sys = sys .. "\n" .. sc end
  end
  local messages = { { role = "system", content = sys } }
  for _, m in ipairs(hist) do messages[#messages + 1] = m end
  messages[#messages + 1] = { role = "user", content = q.player .. ": " .. q.text }
  local answer, err = O.chat(ai, messages, CB.TOOLS, CB.runTool)
  -- model okazal sie bez narzedzi: jeszcze raz z zawartoscia magazynu w kontekscie
  if useTools and O.noTools[ai.model] and answer then
    local sc = stockContext(q.text)
    if sc then
      messages[1].content = messages[1].content .. "\n" .. sc
      answer, err = O.chat(ai, messages)
    end
  end
  if not answer then return nil, err end
  -- pamiec rozmowy: ostatnie N wymian na gracza
  hist[#hist + 1] = { role = "user", content = q.player .. ": " .. q.text }
  hist[#hist + 1] = { role = "assistant", content = answer }
  local keep = math.max(0, math.floor(tonumber(ai.memory) or 3)) * 2
  while #hist > keep do table.remove(hist, 1) end
  CB.history[q.player] = hist
  return answer
end

function CB.handle(ctx, q)
  local c = ctx.cfg.chatbot
  local cmd, arg = q.text:match("^(%S+)%s*(.*)$")
  cmd = cmd and cmd:lower() or ""
  local answer
  if cmd == "" then
    answer = COMMANDS.pomoc(ctx, c.trigger)
  elseif (cmd == "craft" or cmd == "crafting") and not c.ai.enabled then
    answer = COMMANDS[cmd](ctx, c.trigger, arg)
  elseif COMMANDS[cmd] and arg == "" then
    answer = COMMANDS[cmd](ctx, c.trigger)
  elseif c.ai.enabled then
    -- od razu wiadomo, ze bot zyje: "mysle..." (+ pozycja w kolejce)
    local txt = (c.ai.placeholderText ~= "" and c.ai.placeholderText or "Mysle nad odpowiedzia...")
    if #CB.queue > 0 then txt = txt .. " (w kolejce za mna: " .. #CB.queue .. ")" end
    notice(ctx, q, txt)
    CB.current = { player = q.player, hidden = q.hidden, started = U.now(), lastPing = U.now() }
    local ok, res, err = pcall(askAI, ctx, q)
    CB.current = nil
    if not ok then res, err = nil, res end
    if res then
      answer = res
    else
      answer = "AI nie odpowiada: " .. tostring(err)
      ctx.auto.logEvent("Ollama: " .. tostring(err), "warn")
    end
  else
    answer = "Nie znam komendy '" .. cmd .. "'. Wpisz: " .. c.trigger .. " pomoc (AI/Ollama wylaczone)."
  end
  CB.last = { player = q.player, q = q.text, a = answer }
  reply(ctx, q, answer)
end

-- dwie korutyny: nasluch (szybki, nie gubi wiadomosci) i pracownik (moze dlugo czekac na Ollame)
function CB.listener(ctx)
  while true do
    local _, uuid, player, message, hidden, utf8msg = os.pullEvent("chat")
    local ok, err = pcall(CB.onChat, ctx, uuid, player, message, hidden, utf8msg)
    if not ok then ctx.auto.logEvent("Chatbot: " .. tostring(err), "warn") end
  end
end

function CB.worker(ctx)
  while true do
    if #CB.queue == 0 then os.pullEvent("smart_chatbot") end
    local q = table.remove(CB.queue, 1)
    if q then
      CB.busy = true
      local ok, err = pcall(CB.handle, ctx, q)
      CB.busy = false
      CB.current = nil
      if not ok then
        ctx.auto.logEvent("Chatbot: " .. tostring(err), "warn")
        -- uzytkownik nigdy nie zostaje bez odpowiedzi
        pcall(reply, ctx, q, "Blad bota: " .. tostring(err))
      end
    end
  end
end

return CB
