-- Smart System: rysowanie na monitorach i terminalu
local U = require("lib.util")

local UI = {}

UI.COLOR_NAMES = {
  "white", "orange", "magenta", "lightBlue", "yellow", "lime", "pink", "gray",
  "lightGray", "cyan", "purple", "blue", "brown", "green", "red", "black",
}

function UI.color(name, fallback)
  return colors[name] or fallback or colors.white
end

-- kolor paska wg zapelnienia (dla energii: wysoko = dobrze)
function UI.levelColor(f, invert)
  if invert then f = 1 - f end
  if f < 0.15 then return colors.red end
  if f < 0.35 then return colors.orange end
  if f < 0.6 then return colors.yellow end
  return colors.lime
end

-- Font 3x5 dla duzych cyfr
local FONT = {
  ["0"] = { "###", "# #", "# #", "# #", "###" },
  ["1"] = { " # ", "## ", " # ", " # ", "###" },
  ["2"] = { "###", "  #", "###", "#  ", "###" },
  ["3"] = { "###", "  #", "###", "  #", "###" },
  ["4"] = { "# #", "# #", "###", "  #", "  #" },
  ["5"] = { "###", "#  ", "###", "  #", "###" },
  ["6"] = { "###", "#  ", "###", "# #", "###" },
  ["7"] = { "###", "  #", "  #", "  #", "  #" },
  ["8"] = { "###", "# #", "###", "# #", "###" },
  ["9"] = { "###", "# #", "###", "  #", "###" },
  [":"] = { " ", "#", " ", "#", " " },
  ["."] = { " ", " ", " ", " ", "#" },
  ["%"] = { "# #", "  #", " # ", "#  ", "# #" },
  ["-"] = { "   ", "   ", "###", "   ", "   " },
  [" "] = { " ", " ", " ", " ", " " },
  ["k"] = { "#  ", "# #", "## ", "# #", "# #" },
  ["M"] = { "# #", "###", "###", "# #", "# #" },
  ["G"] = { "###", "#  ", "# #", "# #", "###" },
  ["T"] = { "###", " # ", " # ", " # ", " # " },
  ["K"] = { "# #", "# #", "## ", "# #", "# #" },
  ["C"] = { "###", "#  ", "#  ", "#  ", "###" },
}

function UI.bigWidth(s)
  local w = 0
  for ch in s:gmatch(".") do
    local g = FONT[ch] or FONT[" "]
    w = w + #g[1] + 1
  end
  return math.max(0, w - 1)
end

---------------------------------------------------------------------------
-- Canvas: opakowanie terminala/okna z rejestrem przyciskow
---------------------------------------------------------------------------
local Canvas = {}
Canvas.__index = Canvas

function UI.canvas(t)
  local w, h = t.getSize()
  return setmetatable({ t = t, w = w, h = h, btns = {}, color = t.isColor and t.isColor() }, Canvas)
end

function Canvas:reset()
  self.w, self.h = self.t.getSize()
  self.btns = {}
end

function Canvas:clear(bg)
  self.t.setBackgroundColor(bg or colors.black)
  self.t.clear()
  self.btns = {}
end

function Canvas:text(x, y, s, fg, bg)
  if y < 1 or y > self.h then return end
  s = tostring(s)
  if x < 1 then s = s:sub(2 - x); x = 1 end
  if x > self.w then return end
  s = s:sub(1, self.w - x + 1)
  self.t.setCursorPos(x, y)
  if fg then self.t.setTextColor(fg) end
  if bg then self.t.setBackgroundColor(bg) end
  self.t.write(s)
end

function Canvas:center(y, s, fg, bg, x, w)
  x, w = x or 1, w or self.w
  s = U.trunc(s, w)
  self:text(x + math.floor((w - #s) / 2), y, s, fg, bg)
end

function Canvas:right(y, s, fg, bg, x2)
  x2 = x2 or self.w
  s = tostring(s)
  self:text(x2 - #s + 1, y, s, fg, bg)
end

function Canvas:rect(x, y, w, h, bg)
  if w <= 0 or h <= 0 then return end
  local line = string.rep(" ", w)
  self.t.setBackgroundColor(bg)
  for yy = y, y + h - 1 do
    if yy >= 1 and yy <= self.h then
      self:text(x, yy, line)
    end
  end
end

-- wiersz: klucz po lewej, wartosc po prawej
function Canvas:kv(x, y, w, k, v, kfg, vfg, bg)
  v = tostring(v)
  local kw = math.max(0, w - #v - 1)
  self:text(x, y, U.padRight(k, kw), kfg or colors.lightGray, bg or colors.black)
  self:text(x + w - #v, y, v, vfg or colors.white, bg or colors.black)
end

-- pasek postepu 0..1 z opcjonalnym napisem na srodku
function Canvas:bar(x, y, w, f, fg, bg, label, lfg)
  if w <= 0 then return end
  f = U.clamp(tonumber(f) or 0, 0, 1)
  fg = fg or colors.lime
  bg = bg or colors.gray
  local filled = math.floor(f * w + 0.5)
  label = label and U.trunc(label, w) or ""
  local lx = math.floor((w - #label) / 2) + 1
  for i = 1, w do
    local ch = " "
    if label ~= "" and i >= lx and i < lx + #label then ch = label:sub(i - lx + 1, i - lx + 1) end
    self.t.setCursorPos(x + i - 1, y)
    self.t.setBackgroundColor(i <= filled and fg or bg)
    self.t.setTextColor(lfg or colors.black)
    if y >= 1 and y <= self.h and x + i - 1 <= self.w and x + i - 1 >= 1 then self.t.write(ch) end
  end
end

-- pionowy pasek (rosnie od dolu)
function Canvas:vbar(x, y, w, h, f, fg, bg)
  f = U.clamp(tonumber(f) or 0, 0, 1)
  local filled = math.floor(f * h + 0.5)
  for i = 0, h - 1 do
    local yy = y + h - 1 - i
    self:rect(x, yy, w, 1, i < filled and fg or bg)
  end
end

-- naglowek z tytulem
function Canvas:header(title, accent, right)
  accent = accent or colors.cyan
  self:rect(1, 1, self.w, 1, accent)
  self:text(2, 1, U.trunc(title, self.w - 2 - (right and #right + 1 or 0)), colors.black, accent)
  if right then self:right(1, right .. " ", colors.black, accent) end
end

function Canvas:button(id, x, y, w, h, label, fg, bg, data)
  self:rect(x, y, w, h, bg or colors.gray)
  self:center(y + math.floor((h - 1) / 2), label, fg or colors.white, bg or colors.gray, x, w)
  self.btns[#self.btns + 1] = { id = id, x = x, y = y, w = w, h = h, data = data }
end

-- obszar klikalny bez rysowania
function Canvas:zone(id, x, y, w, h, data)
  self.btns[#self.btns + 1] = { id = id, x = x, y = y, w = w, h = h, data = data }
end

function Canvas:hit(x, y)
  for i = #self.btns, 1, -1 do
    local b = self.btns[i]
    if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then return b end
  end
  return nil
end

-- duzy tekst fontem 3x5
function Canvas:big(x, y, s, fg, bg)
  bg = bg or colors.black
  fg = fg or colors.white
  for ch in s:gmatch(".") do
    local g = FONT[ch] or FONT[" "]
    for row = 1, 5 do
      local line = g[row]
      for col = 1, #line do
        if line:sub(col, col) == "#" then
          self:rect(x + col - 1, y + row - 1, 1, 1, fg)
        end
      end
    end
    x = x + #g[1] + 1
  end
end

function Canvas:bigCenter(y, s, fg, bg, x, w)
  x, w = x or 1, w or self.w
  self:big(x + math.floor((w - UI.bigWidth(s)) / 2), y, s, fg, bg)
end

-- wykres kolumnowy wartosci 0..1
function Canvas:graph(x, y, w, h, values, fg, bg)
  bg = bg or colors.black
  self:rect(x, y, w, h, bg)
  local n = #values
  local start = math.max(1, n - w + 1)
  local col = x + w - (n - start + 1)
  for i = start, n do
    local v = U.clamp(values[i] or 0, 0, 1)
    local hh = v * h
    local full = math.floor(hh)
    local c = type(fg) == "function" and fg(v) or fg or colors.lime
    if full > 0 then self:rect(col, y + h - full, 1, full, c) end
    if hh - full >= 0.5 and full < h then
      self:text(col, y + h - full - 1, "_", c, bg)
    end
    col = col + 1
  end
end

-- przewijana lista; zwraca ilosc wierszy ktore sie zmiescily
function Canvas:scrollButtons(idPrefix, x, y, h, accent)
  self:button(idPrefix .. "_up", x, y, 3, 1, "^", colors.black, accent or colors.lightGray)
  self:button(idPrefix .. "_down", x, y + h - 1, 3, 1, "v", colors.black, accent or colors.lightGray)
end

UI.Canvas = Canvas

return UI
