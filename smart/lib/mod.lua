-- Smart System: wspolne elementy modulow ekranow
local U = require("lib.util")
local D = require("lib.devices")

local M = {}

function M.title(m, default)
  if m.cfg.title and m.cfg.title ~= "" then return m.cfg.title end
  return default
end

-- komunikat na srodku ekranu (brak urzadzenia itp.)
function M.message(c, m, title, lines)
  c:clear(colors.black)
  c:header(title, m.accent)
  local y = math.max(3, math.floor(c.h / 2) - #lines + 1)
  for i, l in ipairs(lines) do
    c:center(y + i - 1, l, i == 1 and colors.orange or colors.lightGray, colors.black)
  end
end

-- pasek potwierdzenia na dole ekranu: zielony = OK, czerwony = blad (m.flash = { text, untilT, ok })
function M.flash(c, m)
  local f = m.flash
  if not f or f.untilT <= os.clock() then return end
  local bg = f.ok and colors.green or colors.red
  c:rect(1, c.h, c.w, 1, bg)
  c:center(c.h, f.text, colors.white, bg)
end

-- podpowiedz gdy podlaczono Reactor Port zamiast Logic Adaptera
function M.portHint(lines, portKind)
  if #D.byKind(portKind) > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Wykryto Reactor Port - on NIE daje danych!"
    lines[#lines + 1] = "Postaw modem na Logic Adapterze."
  end
  return lines
end

-- pierwsze aktywne urzadzenie dla modulu jednego urzadzenia
function M.single(m, kinds)
  local list = D.sources(m.cfg.source, kinds)
  return list[1], #list
end

-- wiersz z paskiem: "Etykieta   45%" + pasek pod spodem (2 linie) lub jednoliniowy
function M.barRow(c, x, y, w, label, f, col, valueText)
  valueText = valueText or U.pct(f)
  c:kv(x, y, w, label, valueText, colors.lightGray, colors.white)
  c:bar(x, y + 1, w, f, col or colors.lime, colors.gray)
  return y + 2
end

-- kompaktowy wiersz paska w jednej linii: etykieta | pasek z wartoscia
function M.inlineBar(c, x, y, w, label, f, col, valueText)
  local lw = math.min(#label + 1, math.floor(w / 2))
  c:text(x, y, U.padRight(label, lw), colors.lightGray, colors.black)
  c:bar(x + lw, y, w - lw, f, col or colors.lime, colors.gray, valueText or U.pct(f), colors.black)
  return y + 1
end

-- wartosc z ostatnich probek (ladne wygladzanie)
function M.smooth(st, key, v, k)
  k = k or 0.3
  if type(v) ~= "number" then return st[key] end
  if st[key] == nil then st[key] = v else st[key] = st[key] * (1 - k) + v * k end
  return st[key]
end

function M.push(list, v, max)
  list[#list + 1] = v
  while #list > (max or 300) do table.remove(list, 1) end
end

return M
