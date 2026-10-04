-- Smart System: planowanie craftingu na podstawie WZOROW (patterns) w ME/RS (Advanced Peripherals 0.8)
-- AP nie daje dostepu do receptur gry (JEI) ani symulacji craftingu – zrodlem sa tylko wzory w systemie:
--   AE2: { primaryOutput, outputs, inputs = { { primaryInput, multiplier, ... } }, patternType }
--   RS:  { primaryOutput, outputs, inputs = { { alternatywa1, alternatywa2, ... } }, patternType, id }
-- patternType: AE2 "crafting"/"processing"/"smithing"/"stonecutting", RS "CRAFTING"/"PROCESSING"/...
-- "processing" = potrzebna maszyna (wzor wysyla skladniki do maszyny przez Pattern Provider/Crafter).
local U = require("lib.util")
local D = require("lib.devices")

local P = {}

local MAX_DEPTH = 6
local MAX_NODES = 60

local function bridges()
  return D.byKind({ "me", "rs" })
end

-- stan magazynu: id -> ilosc (przedmioty i plyny), plus nazwy wyswietlane
local function loadStock()
  local stock, names = {}, {}
  for _, d in ipairs(bridges()) do
    for _, fn in ipairs({ "getItems", "getFluids", "getChemicals" }) do
      local list = U.call(d.p, fn, {})
      if type(list) == "table" then
        for _, it in ipairs(list) do
          if it.name then
            stock[it.name] = (stock[it.name] or 0) + U.itemCount(it)
            names[it.name] = names[it.name] or U.itemName(it)
          end
        end
      end
    end
    local craftable = U.call(d.p, "getCraftableItems", {})
    if type(craftable) == "table" then
      for _, it in ipairs(craftable) do
        if it.name then names[it.name] = names[it.name] or U.itemName(it) end
      end
    end
  end
  return stock, names
end

-- wzory, ktore wytwarzaja dany przedmiot (ze wszystkich bridge'y)
local function patternsFor(id, cache)
  if cache[id] ~= nil then return cache[id] end
  local out = {}
  for _, d in ipairs(bridges()) do
    local list = U.call(d.p, "getPatterns", { output = { name = id } })
    if type(list) == "table" then
      for _, p in ipairs(list) do out[#out + 1] = p end
    end
  end
  cache[id] = out
  return out
end

-- ile sztuk danego przedmiotu daje jeden przebieg wzoru
local function outputCount(p, id)
  for _, o in ipairs(type(p.outputs) == "table" and p.outputs or {}) do
    if o.name == id then return math.max(1, U.itemCount(o)) end
  end
  if type(p.primaryOutput) == "table" and p.primaryOutput.name == id then
    return math.max(1, U.itemCount(p.primaryOutput))
  end
  return 1
end

-- skladniki jednego przebiegu: { {id, amount}, ... } (RS: wybieramy alternatywe, ktorej jest najwiecej)
local function inputsOf(p, stock)
  local res = {}
  for _, inp in ipairs(type(p.inputs) == "table" and p.inputs or {}) do
    if type(inp) == "table" and inp.primaryInput then
      -- AE2: ilosc = ilosc w stosie * mnoznik
      local st = inp.primaryInput
      if st.name then res[#res + 1] = { id = st.name, amount = U.itemCount(st) * (tonumber(inp.multiplier) or 1) } end
    elseif type(inp) == "table" and inp[1] then
      -- RS: lista alternatyw
      local best = inp[1]
      for _, alt in ipairs(inp) do
        if alt.name and (stock[alt.name] or 0) > (stock[best.name] or 0) then best = alt end
      end
      if best.name then res[#res + 1] = { id = best.name, amount = math.max(1, U.itemCount(best)) } end
    end
  end
  -- scalamy powtarzajace sie skladniki (np. 4 sloty z tym samym przedmiotem)
  local merged, order = {}, {}
  for _, r in ipairs(res) do
    if not merged[r.id] then merged[r.id] = 0; order[#order + 1] = r.id end
    merged[r.id] = merged[r.id] + r.amount
  end
  local out = {}
  for _, id in ipairs(order) do out[#out + 1] = { id = id, amount = merged[id] } end
  return out
end

local function needsMachine(t)
  t = tostring(t or ""):lower()
  return t == "processing" or t == "external"
end

-- znajduje id przedmiotu po nazwie (angielskiej) albo id
function P.resolve(query)
  local stock, names = loadStock()
  query = tostring(query or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if query:find(":") then return query, names[query] or U.prettyId(query) end
  local q = query:lower()
  local exact, partial
  for id, name in pairs(names) do
    local n = name:lower()
    if n == q or id:lower():match(":(.+)$") == q:gsub(" ", "_") then exact = exact or id end
    if not partial and (n:find(q, 1, true) or id:lower():find((q:gsub(" ", "_")), 1, true)) then partial = id end
  end
  local id = exact or partial
  if not id then return nil end
  return id, names[id]
end

-- plan dla "amount" sztuk "id"; zwraca drzewo i podsumowanie
function P.plan(id, amount)
  local stock, names = loadStock()
  local left = {}
  for k, v in pairs(stock) do left[k] = v end
  local cache, nodes = {}, 0
  local summary = { raw = {}, machines = {}, cycles = {}, truncated = false }

  local function expand(item, need, depth, path)
    nodes = nodes + 1
    local node = { id = item, name = names[item] or U.prettyId(item), need = need, have = 0, missing = 0, children = {} }
    local use = math.min(left[item] or 0, need)
    left[item] = (left[item] or 0) - use
    node.have = use
    local missing = need - use
    if missing <= 0 then return node end
    node.missing = missing
    if path[item] then
      node.cycle = true
      summary.cycles[#summary.cycles + 1] = node.name
      return node
    end
    if depth >= MAX_DEPTH or nodes >= MAX_NODES then
      node.truncated = true
      summary.truncated = true
      return node
    end
    local pats = patternsFor(item, cache)
    if #pats == 0 then
      node.noPattern = true
      summary.raw[item] = (summary.raw[item] or 0) + missing
      return node
    end
    local p = pats[1]
    local per = outputCount(p, item)
    local runs = math.ceil(missing / per)
    node.pattern = tostring(p.patternType or "?")
    node.runs = runs
    if needsMachine(node.pattern) then summary.machines[#summary.machines + 1] = node.name end
    path[item] = true
    for _, inp in ipairs(inputsOf(p, left)) do
      node.children[#node.children + 1] = expand(inp.id, inp.amount * runs, depth + 1, path)
    end
    path[item] = nil
    return node
  end

  local root = expand(id, amount, 0, {})
  summary.names = names
  return root, summary
end

-- czytelny opis drzewa (dla AI i dla komendy na czacie)
function P.describe(root, summary, maxLines)
  local lines = {}
  local function walk(n, ind)
    if #lines >= (maxLines or 40) then return end
    local s = string.rep("  ", ind) .. "- " .. n.name .. " (" .. n.id .. ") potrzeba " .. math.floor(n.need)
      .. ", w magazynie " .. math.floor(n.have)
    if n.missing > 0 then
      s = s .. ", BRAKUJE " .. math.floor(n.missing)
      if n.pattern then
        s = s .. " -> wzor " .. n.pattern .. " x" .. n.runs .. (needsMachine(n.pattern) and " (MASZYNA)" or "")
      elseif n.noPattern then
        s = s .. " -> BRAK WZORU w ME/RS"
      elseif n.cycle then
        s = s .. " -> petla wzorow"
      elseif n.truncated then
        s = s .. " -> (dalej nie sprawdzano)"
      end
    end
    lines[#lines + 1] = s
    for _, c in ipairs(n.children) do walk(c, ind + 1) end
  end
  walk(root, 0)
  local out = { "Plan craftingu (na podstawie wzorow w ME/RS):" }
  for _, l in ipairs(lines) do out[#out + 1] = l end
  local raw = {}
  for id, cnt in pairs(summary.raw) do raw[#raw + 1] = (summary.names[id] or U.prettyId(id)) .. " x" .. math.floor(cnt) end
  table.sort(raw)
  if root.missing == 0 then
    out[#out + 1] = "Wszystko jest w magazynie - mozna od razu zlecic crafting."
  elseif #raw == 0 and #summary.cycles == 0 and not summary.truncated then
    out[#out + 1] = "Wszystkie brakujace rzeczy maja wzory - system moze to zrobic sam."
  end
  if #raw > 0 then out[#out + 1] = "Brakuje i NIE MA wzoru (trzeba zdobyc albo dodac wzor/maszyne): " .. table.concat(raw, ", ") end
  if #summary.machines > 0 then out[#out + 1] = "Wzory processing (potrzebne maszyny): " .. table.concat(summary.machines, ", ") end
  if #summary.cycles > 0 then out[#out + 1] = "Petle wzorow: " .. table.concat(summary.cycles, ", ") end
  if summary.truncated then out[#out + 1] = "Drzewo za duze - sprawdzono tylko czesc." end
  return table.concat(out, "\n")
end

-- krotkie podsumowanie na czat (bez AI)
function P.short(root, summary)
  if root.missing == 0 then
    return string.format("%s x%d: wszystko w magazynie (masz %d).", root.name, math.floor(root.need), math.floor(root.have))
  end
  local raw = {}
  for id, cnt in pairs(summary.raw) do raw[#raw + 1] = (summary.names[id] or U.prettyId(id)) .. " x" .. math.floor(cnt) end
  table.sort(raw)
  local s = string.format("%s x%d: brakuje %d.", root.name, math.floor(root.need), math.floor(root.missing))
  if root.noPattern then return s .. " Brak wzoru w ME/RS dla tego przedmiotu." end
  if #raw == 0 then s = s .. " Wszystko ma wzory - mozna zlecic crafting."
  else s = s .. " Brak surowcow bez wzoru: " .. table.concat(raw, ", ") .. "." end
  if #summary.machines > 0 then s = s .. " Maszyny (processing): " .. table.concat(summary.machines, ", ") .. "." end
  return s
end

return P
