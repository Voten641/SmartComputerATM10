-- Smart System: klient serwera Ollama (HTTP API: /api/chat, /api/tags)
-- Uwaga CC: Tweaked: domyslnie blokuje adresy prywatne ($private = localhost, 192.168.x.x...).
-- Dla Ollamy w sieci lokalnej trzeba dodac w configu serwera CC regule "allow" dla jej adresu (patrz README).
local O = {}

O.models = nil -- ostatnio pobrana lista modeli

local function baseUrl(url)
  url = tostring(url or ""):gsub("%s+", ""):gsub("/+$", "")
  if url ~= "" and not url:find("^https?://") then url = "http://" .. url end
  return url
end
O.baseUrl = baseUrl

local function json(t)
  -- unicode_strings: tekst z czatu jest w UTF-8, a nie w Latin-1
  return textutils.serialiseJSON(t, { unicode_strings = true })
end

O.lastError = nil -- ostatni blad (oryginalny komunikat CC/Ollamy) – widoczny w menu

-- komunikat bledu HTTP po ludzku + oryginalny tekst z CC (komunikaty: NetworkUtils CC:T)
function O.explain(err)
  err = tostring(err or "")
  local hint
  if err:find("Domain not permitted", 1, true) then
    hint = "CC blokuje adres: regula allow musi byc NAD $private, restart serwera"
  elseif err:find("refused", 1, true) then
    hint = "Ollama nie slucha pod tym adresem (OLLAMA_HOST=0.0.0.0, port 11434, firewall)"
  elseif err:find("Could not connect", 1, true) or err:find("connect", 1, true) then
    hint = "brak polaczenia (adres/port, firewall, OLLAMA_HOST=0.0.0.0)"
  elseif err:find("Timed out", 1, true) then
    hint = "przekroczono czas (zly adres/firewall albo model za wolny)"
  elseif err:find("Unknown host", 1, true) then
    hint = "nieznany host - sprawdz adres"
  elseif err:find("Invalid protocol", 1, true) then
    hint = "adres musi zaczynac sie od http://"
  end
  O.lastError = err
  return hint and (hint .. " [" .. err .. "]") or err
end

local function readError(resp)
  if not resp then return nil end
  local ok, body = pcall(resp.readAll)
  pcall(resp.close)
  if ok and body then
    local obj = textutils.unserialiseJSON(body)
    if type(obj) == "table" and obj.error then return tostring(obj.error) end
  end
  return nil
end

-- lista modeli: tabela nazw albo nil, blad
function O.listModels(url)
  local base = baseUrl(url)
  if base == "" then return nil, "brak adresu serwera" end
  local resp, err, failResp = http.get({ url = base .. "/api/tags", timeout = 8 })
  if not resp then return nil, readError(failResp) or O.explain(err) end
  O.lastError = nil
  local body = resp.readAll()
  resp.close()
  local obj = textutils.unserialiseJSON(body)
  if type(obj) ~= "table" or type(obj.models) ~= "table" then return nil, "nieprawidlowa odpowiedz serwera" end
  local names = {}
  for _, m in ipairs(obj.models) do if m.name then names[#names + 1] = m.name end end
  table.sort(names)
  O.models = names
  return names
end

-- usuwa bloki myslenia modeli rozumujacych i zbedne biale znaki
function O.clean(text)
  text = tostring(text or "")
  text = text:gsub("<think>.-</think>", ""):gsub("<think>.*$", "")
  text = text:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
  return text
end

local function request(base, body)
  return http.post({
    url = base .. "/api/chat",
    body = json(body),
    headers = { ["Content-Type"] = "application/json" },
    timeout = 60, -- limit CC (maks. 60 s) liczony od ostatnich danych; strumien utrzymuje polaczenie
  })
end

O.noTools = {} -- [model] = true gdy model nie obsluguje narzedzi (wtedy kontekst zamiast narzedzi)

-- jedno zapytanie /api/chat (strumien); zwraca tresc, wywolania narzedzi albo nil, blad
local function chatOnce(base, body)
  local resp, err, failResp = request(base, body)
  if not resp then
    local e = readError(failResp)
    if e then
      local low = e:lower()
      -- starsze wersje/modele bez obslugi "think": ponawiamy bez tego pola
      if low:find("think") and body.think ~= nil then
        body.think = nil
        return chatOnce(base, body)
      end
      -- model bez narzedzi: ponawiamy bez nich (wywolujacy dostanie informacje przez O.noTools)
      if low:find("tool") and body.tools then
        O.noTools[body.model] = true
        body.tools = nil
        return chatOnce(base, body)
      end
      return nil, e
    end
    return nil, O.explain(err)
  end
  local raw = resp.readAll()
  resp.close()
  -- NDJSON: kazda linia to { message = { content, tool_calls }, done }
  local parts, calls = {}, {}
  for line in raw:gmatch("[^\n]+") do
    local obj = textutils.unserialiseJSON(line)
    if type(obj) == "table" then
      if obj.error then return nil, tostring(obj.error) end
      local m = obj.message
      if type(m) == "table" then
        if m.content then parts[#parts + 1] = m.content end
        if type(m.tool_calls) == "table" then
          for _, tc in ipairs(m.tool_calls) do calls[#calls + 1] = tc end
        end
      end
    end
  end
  return table.concat(parts), calls
end

-- rozmowa: messages = { {role, content}, ... }
-- tools (opcjonalnie) = definicje narzedzi Ollamy, onTool(name, args) -> tekst wyniku
-- zwraca tekst odpowiedzi albo nil, blad
function O.chat(c, messages, tools, onTool)
  local base = baseUrl(c.url)
  if base == "" then return nil, "brak adresu serwera Ollama" end
  if not c.model or c.model == "" then return nil, "nie wybrano modelu" end
  local msgs = {}
  for i, m in ipairs(messages) do msgs[i] = m end
  for _ = 1, 5 do -- maks. 5 rund narzedzi na pytanie
    local body = {
      model = c.model,
      messages = msgs,
      -- strumien: Ollama wysyla odpowiedz kawalkami, wiec CC nie zrywa polaczenia przy dlugim generowaniu
      stream = true,
      options = { num_predict = c.maxTokens or 250 },
    }
    if c.think == false then body.think = false end
    if tools and onTool and not O.noTools[c.model] then body.tools = tools end
    local content, calls = chatOnce(base, body)
    if not content then return nil, calls end
    if #calls == 0 or not onTool then
      local text = O.clean(content)
      if text == "" then return nil, "pusta odpowiedz modelu" end
      return text
    end
    -- model chce uzyc narzedzi: wykonujemy je i odsylamy wyniki
    msgs[#msgs + 1] = { role = "assistant", content = content, tool_calls = calls }
    for _, tc in ipairs(calls) do
      local fn = type(tc["function"]) == "table" and tc["function"] or {}
      local name = tostring(fn.name or "")
      local args = type(fn.arguments) == "table" and fn.arguments or {}
      local ok, res = pcall(onTool, name, args)
      msgs[#msgs + 1] = { role = "tool", tool_name = name, content = ok and tostring(res) or ("blad: " .. tostring(res)) }
    end
  end
  return nil, "model wywolal za duzo narzedzi"
end

return O
