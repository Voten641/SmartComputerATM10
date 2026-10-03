-- Smart System: funkcje pomocnicze
local U = {}

-- Bezpieczne wywolanie metody peryferium. `names` moze byc lista
-- alternatywnych nazw (rozne wersje Advanced Peripherals / Mekanism).
function U.call(p, names, ...)
  if not p then return nil end
  if type(names) == "string" then names = { names } end
  for _, n in ipairs(names) do
    local f = p[n]
    if type(f) == "function" then
      local ok, a, b, c = pcall(f, ...)
      if ok then return a, b, c end
    end
  end
  return nil
end

function U.has(p, name)
  return p ~= nil and type(p[name]) == "function"
end

function U.clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

function U.round(v, d)
  local m = 10 ^ (d or 0)
  return math.floor(v * m + 0.5) / m
end

local SUFFIX = { "", "k", "M", "G", "T", "P", "E", "Z" }

-- 1234567 -> "1.23M"
function U.fmt(n, unit)
  unit = unit or ""
  if type(n) ~= "number" then return "?" .. unit end
  if n ~= n then return "NaN" end
  local neg = n < 0
  n = math.abs(n)
  local i = 1
  while n >= 1000 and i < #SUFFIX do
    n = n / 1000
    i = i + 1
  end
  local s
  if i == 1 and n == math.floor(n) then
    s = tostring(math.floor(n))
  elseif n >= 100 then
    s = string.format("%.0f", n)
  elseif n >= 10 then
    s = string.format("%.1f", n)
  else
    s = string.format("%.2f", n)
  end
  return (neg and "-" or "") .. s .. SUFFIX[i] .. unit
end

-- frakcja 0..1 -> "45.2%"
function U.pct(f)
  if type(f) ~= "number" then return "?%" end
  local p = f * 100
  if p >= 99.95 or p == 0 then return string.format("%d%%", math.floor(p + 0.5)) end
  return string.format("%.1f%%", p)
end

function U.frac(a, b)
  if type(a) ~= "number" or type(b) ~= "number" or b <= 0 then return 0 end
  return U.clamp(a / b, 0, 1)
end

-- sekundy -> "1h 05m" / "12m 30s" / "45s"
function U.fmtTime(s)
  if type(s) ~= "number" or s ~= s or s == math.huge or s < 0 then return "--" end
  s = math.floor(s)
  local f = math.floor
  if s >= 86400 then return string.format("%dd %02dh", f(s / 86400), f((s % 86400) / 3600)) end
  if s >= 3600 then return string.format("%dh %02dm", f(s / 3600), f((s % 3600) / 60)) end
  if s >= 60 then return string.format("%dm %02ds", f(s / 60), s % 60) end
  return s .. "s"
end

-- dawka promieniowania (Sv/h) w czytelnych jednostkach
function U.sv(r)
  if type(r) ~= "number" then return "?" end
  if r < 0.001 then return string.format("%.1f uSv/h", r * 1000000) end
  if r < 1 then return string.format("%.1f mSv/h", r * 1000) end
  return string.format("%.2f Sv/h", r)
end

function U.temp(k)
  if type(k) ~= "number" then return "?K" end
  return string.format("%.0fK", k)
end

-- normalizacja nazw typow: "fissionReactorLogicAdapter" / "me_bridge" -> "fissionreactorlogicadapter" / "mebridge"
function U.norm(s)
  return (tostring(s):lower():gsub("[_%s%-]", ""))
end

function U.deepcopy(t)
  if type(t) ~= "table" then return t end
  local r = {}
  for k, v in pairs(t) do r[k] = U.deepcopy(v) end
  return r
end

-- uzupelnia brakujace klucze w `t` wartosciami z `def`
function U.fill(t, def)
  for k, v in pairs(def) do
    if t[k] == nil then
      t[k] = U.deepcopy(v)
    elseif type(v) == "table" and type(t[k]) == "table" and #v == 0 then
      U.fill(t[k], v)
    end
  end
  return t
end

function U.trunc(s, w)
  s = tostring(s)
  if w <= 0 then return "" end
  if #s <= w then return s end
  if w <= 2 then return s:sub(1, w) end
  return s:sub(1, w - 1) .. "~"
end

function U.padRight(s, w) s = U.trunc(s, w) return s .. string.rep(" ", w - #s) end
function U.padLeft(s, w) s = U.trunc(s, w) return string.rep(" ", w - #s) .. s end

-- "minecraft:iron_ingot" -> "Iron Ingot"
function U.prettyId(id)
  if type(id) ~= "string" then return "?" end
  local n = id:match(":(.+)$") or id
  n = n:gsub("_", " ")
  return (n:gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end))
end

function U.itemName(it)
  local n = it.displayName or it.name
  if type(n) == "string" then n = n:gsub("^%[", ""):gsub("%]$", "") end
  if n == it.name then n = U.prettyId(n) end
  return n or "?"
end

function U.itemCount(it)
  return it.count or it.amount or 0
end

function U.sortedKeys(t)
  local r = {}
  for k in pairs(t) do r[#r + 1] = k end
  table.sort(r, function(a, b) return tostring(a) < tostring(b) end)
  return r
end

function U.indexOf(list, v)
  for i, x in ipairs(list) do if x == v then return i end end
  return nil
end

function U.now()
  return os.epoch("utc") / 1000
end

return U
