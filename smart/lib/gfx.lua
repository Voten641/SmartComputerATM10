-- Smart System: grafika na znakach rysujacych CC (128-159 = mozaika 2x3 subpikseli).
-- Bity: TL=1, TR=2, ML=4, MR=8, BL=16; prawy dolny subpiksel ma zawsze kolor tla znaku.
-- Subpiksel to 3x3 piksele ekranu (glif 6x9), wiec kola sa naprawde okragle.
local G = {}

local HEX = {}
for i = 0, 15 do HEX[2 ^ i] = ("0123456789abcdef"):sub(i + 1, i + 1) end
G.HEX = HEX

---------------------------------------------------------------------------
-- Pixmapa: tablica pikseli w*h (kolor CC albo nil = przezroczysty -> kolor tla)
---------------------------------------------------------------------------
function G.pixmap(pw, ph)
  return { w = pw, h = ph, p = {} }
end

function G.set(pm, x, y, c)
  if x >= 0 and y >= 0 and x < pm.w and y < pm.h then pm.p[y * pm.w + x] = c end
end

function G.get(pm, x, y)
  return pm.p[y * pm.w + x]
end

function G.fillRect(pm, x, y, w, h, c)
  for yy = y, y + h - 1 do
    for xx = x, x + w - 1 do G.set(pm, xx, yy, c) end
  end
end

-- prostokat z zaokraglonymi rogami (promien 1 subpiksel)
function G.roundRect(pm, x, y, w, h, c)
  G.fillRect(pm, x, y, w, h, c)
  if w >= 3 and h >= 3 then
    G.set(pm, x, y, nil)
    G.set(pm, x + w - 1, y, nil)
    G.set(pm, x, y + h - 1, nil)
    G.set(pm, x + w - 1, y + h - 1, nil)
  end
end

-- rysuje pixmape na terminalu t od komorki (cx, cy); bg = kolor dla przezroczystych pikseli
function G.draw(t, cx, cy, pm, bg)
  local cw, ch = math.ceil(pm.w / 2), math.ceil(pm.h / 3)
  local tw, th = t.getSize()
  local px = {}
  for row = 0, ch - 1 do
    local y = cy + row
    if y >= 1 and y <= th then
      local txt, fgs, bgs = {}, {}, {}
      local x0 = cx
      for col = 0, cw - 1 do
        local bx, by = col * 2, row * 3
        px[1] = G.get(pm, bx, by) or bg
        px[2] = G.get(pm, bx + 1, by) or bg
        px[3] = G.get(pm, bx, by + 1) or bg
        px[4] = G.get(pm, bx + 1, by + 1) or bg
        px[5] = G.get(pm, bx, by + 2) or bg
        px[6] = G.get(pm, bx + 1, by + 2) or bg
        -- tlo znaku = kolor prawego dolnego; kolor znaku = najczestszy z pozostalych
        local back = px[6]
        local cnt, fore, best = {}, nil, 0
        for i = 1, 5 do
          local c = px[i]
          if c ~= back then
            cnt[c] = (cnt[c] or 0) + 1
            if cnt[c] > best then fore, best = c, cnt[c] end
          end
        end
        local ch1, fg = " ", back
        if fore then
          local bits = 0
          if px[1] == fore then bits = bits + 1 end
          if px[2] == fore then bits = bits + 2 end
          if px[3] == fore then bits = bits + 4 end
          if px[4] == fore then bits = bits + 8 end
          if px[5] == fore then bits = bits + 16 end
          ch1, fg = string.char(128 + bits), fore
        end
        txt[#txt + 1], fgs[#fgs + 1], bgs[#bgs + 1] = ch1, HEX[fg] or "0", HEX[back] or "f"
      end
      -- przyciecie do ekranu
      local s, f, b = table.concat(txt), table.concat(fgs), table.concat(bgs)
      if x0 < 1 then s, f, b = s:sub(2 - x0), f:sub(2 - x0), b:sub(2 - x0); x0 = 1 end
      local maxw = tw - x0 + 1
      if maxw > 0 then
        if #s > maxw then s, f, b = s:sub(1, maxw), f:sub(1, maxw), b:sub(1, maxw) end
        t.setCursorPos(x0, y)
        t.blit(s, f, b)
      end
    end
  end
end

---------------------------------------------------------------------------
-- Gotowe elementy
---------------------------------------------------------------------------

-- zaokraglone rogi prostokata komorek (rysuje tylko 4 komorki rogow)
function G.roundCorners(t, x, y, w, h, c, outer)
  if w < 2 or h < 1 then return end
  local function corner(cx, cy, lx, ly)
    local pm = G.pixmap(2, 3)
    G.fillRect(pm, 0, 0, 2, 3, c)
    G.set(pm, lx, ly, outer)
    G.draw(t, cx, cy, pm, c)
  end
  if h == 1 then
    -- pigulka: zaokraglone oba rogi z kazdej strony
    local pm = G.pixmap(2, 3)
    G.fillRect(pm, 0, 0, 2, 3, c)
    G.set(pm, 0, 0, outer); G.set(pm, 0, 2, outer)
    G.draw(t, x, y, pm, c)
    pm = G.pixmap(2, 3)
    G.fillRect(pm, 0, 0, 2, 3, c)
    G.set(pm, 1, 0, outer); G.set(pm, 1, 2, outer)
    G.draw(t, x + w - 1, y, pm, c)
    return
  end
  corner(x, y, 0, 0)
  corner(x + w - 1, y, 1, 0)
  corner(x, y + h - 1, 0, 2)
  corner(x + w - 1, y + h - 1, 1, 2)
end

-- plynny pasek (2x precyzja w poziomie, zaokraglone konce)
function G.bar(t, x, y, w, f, fill, track, outer)
  local pw = w * 2
  local pm = G.pixmap(pw, 3)
  local n = math.floor(f * pw + 0.5)
  for xx = 0, pw - 1 do
    local c = xx < n and fill or track
    G.set(pm, xx, 0, c); G.set(pm, xx, 1, c); G.set(pm, xx, 2, c)
  end
  if pw >= 4 then
    G.set(pm, 0, 0, nil); G.set(pm, 0, 2, nil)
    G.set(pm, pw - 1, 0, nil); G.set(pm, pw - 1, 2, nil)
  end
  G.draw(t, x, y, pm, outer)
  return n
end

-- przelacznik WL/WYL (pigulka z galka) – szerokosc w komorkach
function G.switch(t, x, y, w, on, onColor, offColor, knob, outer)
  local pw = w * 2
  local pm = G.pixmap(pw, 3)
  G.roundRect(pm, 0, 0, pw, 3, on and onColor or offColor)
  -- galka 2x3 przy krawedzi
  local kx = on and (pw - 3) or 1
  G.set(pm, kx, 0, knob); G.set(pm, kx + 1, 0, knob)
  G.set(pm, kx, 1, knob); G.set(pm, kx + 1, 1, knob)
  G.set(pm, kx, 2, knob); G.set(pm, kx + 1, 2, knob)
  -- lekkie zaokraglenie galki
  G.set(pm, kx, 0, on and onColor or offColor)
  G.set(pm, kx + 1, 2, on and onColor or offColor)
  G.draw(t, x, y, pm, outer)
end

local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

-- okragly wskaznik (luk 270 stopni od lewego dolu, zgodnie z ruchem wskazowek)
-- (x, y) = lewy gorny rog w komorkach, size = srednica w subpikselach
function G.gauge(t, x, y, size, f, fill, track, outer, thickness)
  local pw = size + (size % 2)
  local ph = math.ceil(size / 3) * 3
  local pm = G.pixmap(pw, ph)
  local cx, cy = (size - 1) / 2, (size - 1) / 2
  local r1 = size / 2
  local r0 = r1 - (thickness or math.max(2, math.floor(size / 7)))
  local lim = math.max(0, math.min(1, tonumber(f) or 0))
  for py = 0, ph - 1 do
    for px = 0, pw - 1 do
      local dx, dy = px - cx, py - cy
      local d = math.sqrt(dx * dx + dy * dy)
      if d <= r1 and d >= r0 then
        local a = math.deg(atan2(dy, dx)) -- 0 = prawo, 90 = dol
        local tt = (a - 135) % 360
        if tt <= 270 then
          G.set(pm, px, py, tt <= lim * 270 and fill or track)
        end
      end
    end
  end
  G.draw(t, x, y, pm, outer)
  return math.ceil(pw / 2), math.ceil(ph / 3)
end

-- wykres obszarowy: values 0..1, rozdzielczosc 2x3 na komorke, siatka co 25%
function G.area(t, x, y, w, h, values, lineColor, fillColor, bg, gridColor)
  local pw, ph = w * 2, h * 3
  local pm = G.pixmap(pw, ph)
  if gridColor then
    for _, q in ipairs({ 0.25, 0.5, 0.75 }) do
      local gy = ph - 1 - math.floor(q * (ph - 1) + 0.5)
      for gx = 0, pw - 1, 2 do G.set(pm, gx, gy, gridColor) end
    end
  end
  local n = #values
  if n > 0 then
    for px = 0, pw - 1 do
      -- probka dla kolumny (ostatnie probki po prawej)
      local idx = n - (pw - 1 - px)
      local v = values[idx]
      if v then
        v = math.max(0, math.min(1, v))
        local top = ph - 1 - math.floor(v * (ph - 1) + 0.5)
        local lc = type(lineColor) == "function" and lineColor(v) or lineColor
        local fc = type(fillColor) == "function" and fillColor(v) or fillColor
        for py = top + 1, ph - 1 do G.set(pm, px, py, fc) end
        G.set(pm, px, top, lc)
        if top + 1 < ph then G.set(pm, px, top + 1, lc) end
      end
    end
  end
  G.draw(t, x, y, pm, bg)
end

---------------------------------------------------------------------------
-- Font pikselowy 5x7 (cyfry, % i jednostki) – 3x3 komorki na znak przy skali 1
---------------------------------------------------------------------------
local FONT = {
  ["0"] = { "01110", "10001", "10011", "10101", "11001", "10001", "01110" },
  ["1"] = { "00100", "01100", "00100", "00100", "00100", "00100", "01110" },
  ["2"] = { "01110", "10001", "00001", "00010", "00100", "01000", "11111" },
  ["3"] = { "11110", "00001", "00001", "01110", "00001", "00001", "11110" },
  ["4"] = { "00010", "00110", "01010", "10010", "11111", "00010", "00010" },
  ["5"] = { "11111", "10000", "11110", "00001", "00001", "10001", "01110" },
  ["6"] = { "00110", "01000", "10000", "11110", "10001", "10001", "01110" },
  ["7"] = { "11111", "00001", "00010", "00100", "01000", "01000", "01000" },
  ["8"] = { "01110", "10001", "10001", "01110", "10001", "10001", "01110" },
  ["9"] = { "01110", "10001", "10001", "01111", "00001", "00010", "01100" },
  ["%"] = { "11001", "11001", "00010", "00100", "01000", "10011", "10011" },
  ["."] = { "000", "000", "000", "000", "000", "011", "011" },
  [":"] = { "000", "011", "011", "000", "011", "011", "000" },
  ["-"] = { "00000", "00000", "00000", "11111", "00000", "00000", "00000" },
  [" "] = { "000", "000", "000", "000", "000", "000", "000" },
  ["K"] = { "10001", "10010", "10100", "11000", "10100", "10010", "10001" },
  ["k"] = { "10000", "10000", "10010", "10100", "11000", "10100", "10010" },
  ["M"] = { "10001", "11011", "10101", "10101", "10001", "10001", "10001" },
  ["G"] = { "01110", "10001", "10000", "10111", "10001", "10001", "01111" },
  ["T"] = { "11111", "00100", "00100", "00100", "00100", "00100", "00100" },
  ["F"] = { "11111", "10000", "10000", "11110", "10000", "10000", "10000" },
  ["E"] = { "11111", "10000", "10000", "11110", "10000", "10000", "11111" },
  ["C"] = { "01110", "10001", "10000", "10000", "10000", "10001", "01110" },
  ["/"] = { "00001", "00010", "00010", "00100", "01000", "01000", "10000" },
  ["t"] = { "01000", "01000", "11100", "01000", "01000", "01001", "00110" },
}

function G.textWidth(s, scale)
  scale = scale or 1
  local w = 0
  for ch in s:gmatch(".") do
    local g = FONT[ch] or FONT[" "]
    w = w + (#g[1] + 1) * scale
  end
  return math.max(0, w - scale) -- w subpikselach
end

-- szerokosc/wysokosc napisu w komorkach
function G.textCells(s, scale)
  scale = scale or 1
  return math.ceil(G.textWidth(s, scale) / 2), math.ceil(7 * scale / 3)
end

function G.text(t, x, y, s, color, bg, scale)
  scale = scale or 1
  local pw = G.textWidth(s, scale)
  local ph = math.ceil(7 * scale / 3) * 3
  local pm = G.pixmap(pw + (pw % 2), ph)
  local ox = 0
  local oy = math.floor((ph - 7 * scale) / 2)
  for ch in s:gmatch(".") do
    local g = FONT[ch] or FONT[" "]
    for row = 1, 7 do
      local line = g[row]
      for col = 1, #line do
        if line:sub(col, col) == "1" then
          G.fillRect(pm, ox + (col - 1) * scale, oy + (row - 1) * scale, scale, scale, color)
        end
      end
    end
    ox = ox + (#g[1] + 1) * scale
  end
  G.draw(t, x, y, pm, bg)
  return math.ceil(pm.w / 2), ph / 3
end

return G
