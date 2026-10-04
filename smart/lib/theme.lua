-- Smart System: motywy kolorow (paleta terminala/monitora przez setPaletteColour)
-- Uwaga: okna (window API) kopiuja palete rodzica przy tworzeniu, wiec palete ustawiamy
-- na monitorze/terminalu ZANIM utworzymy na nim okna.
local T = {}

-- "nowoczesny": ciemne, stonowane tlo i miekkie kolory akcentow. Nazwy kolorow zostaja te same,
-- wiec caly kod rysujacy (colors.lime, colors.gray...) dziala bez zmian.
T.PALETTES = {
  modern = {
    [colors.white] = 0xE6E9EF,
    [colors.orange] = 0xF59E0B,
    [colors.magenta] = 0xD946EF,
    [colors.lightBlue] = 0x7DD3FC,
    [colors.yellow] = 0xFACC15,
    [colors.lime] = 0x4ADE80,
    [colors.pink] = 0xF472B6,
    [colors.gray] = 0x262C38,      -- karty, przyciski
    [colors.lightGray] = 0x8D96A8, -- tekst drugorzedny
    [colors.cyan] = 0x22D3EE,      -- akcent
    [colors.purple] = 0xA78BFA,
    [colors.blue] = 0x3B82F6,
    [colors.brown] = 0x7C4A12,
    [colors.green] = 0x15803D,
    [colors.red] = 0xEF4444,
    [colors.black] = 0x0F1218,     -- tlo
  },
}

T.NAMES = { "modern", "classic" }
T.LABELS = { modern = "nowoczesny", classic = "klasyczny (kolory CC)" }

function T.isModern(name)
  return name ~= "classic"
end

-- ustawia palete na terminalu/monitorze
function T.apply(t, name)
  if not t or not t.setPaletteColour then return end
  local pal = T.PALETTES[name or "modern"]
  if not pal then return T.reset(t) end
  for c, hex in pairs(pal) do pcall(t.setPaletteColour, c, hex) end
end

-- przywraca domyslne kolory CC
function T.reset(t)
  if not t or not t.setPaletteColour then return end
  for i = 0, 15 do
    local c = 2 ^ i
    local ok, r, g, b = pcall(term.nativePaletteColour, c)
    if ok and r then pcall(t.setPaletteColour, c, r, g, b) end
  end
end

return T
