-- Smart System: chatbot na czacie (Advanced Peripherals Chat Box + opcjonalnie Ollama)
-- Event AP 0.8: "chat", uuid, username, message, isHidden, utf8Message
--  - wiadomosc zaczynajaca sie od "$" jest ukryta (AP usuwa "$" i ustawia isHidden = true)
-- Wiadomosci "smart ..." (slowo wyzwalajace z ustawien) dostaja odpowiedz: komendy wbudowane albo AI.
local U = require("lib.util")
local D = require("lib.devices")
local O = require("lib.ollama")

local CB = {}
CB.queue = {}      -- pytania czekajace na obsluge
CB.history = {}    -- [gracz] = { {role, content}, ... } (pamiec rozmowy z AI)
CB.busy = false
CB.last = nil      -- ostatnie pytanie/odpowiedz (do podgladu w menu)

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
-- komendy wbudowane (dzialaja bez AI)
local COMMANDS = {}

COMMANDS.pomoc = function(ctx, trig)
  local ai = ctx.cfg.chatbot.ai
  local t = trig .. " status | " .. trig .. " reaktor | " .. trig .. " alarmy | " .. trig .. " pomoc"
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

local function askAI(ctx, q)
  local ai = ctx.cfg.chatbot.ai
  local hist = CB.history[q.player] or {}
  local sys = (ai.prompt ~= "" and ai.prompt or CB.DEFAULT_PROMPT)
  if ai.context ~= false then
    sys = sys .. "\nAktualne dane bazy:\n- " .. table.concat(CB.baseStatus(ctx), "\n- ")
  end
  local messages = { { role = "system", content = sys } }
  for _, m in ipairs(hist) do messages[#messages + 1] = m end
  messages[#messages + 1] = { role = "user", content = q.player .. ": " .. q.text }
  local answer, err = O.chat(ai, messages)
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
  elseif COMMANDS[cmd] and arg == "" then
    answer = COMMANDS[cmd](ctx, c.trigger)
  elseif c.ai.enabled then
    local res, err = askAI(ctx, q)
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
      if not ok then ctx.auto.logEvent("Chatbot: " .. tostring(err), "warn") end
    end
  end
end

return CB
