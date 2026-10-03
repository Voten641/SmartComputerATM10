-- Modul: Energia (Induction Matrix, Energy Cube, Powah, magazyny energy_storage)
local U = require("lib.util")
local D = require("lib.devices")
local M = require("lib.mod")
local S = require("lib.sources")
local UI = require("lib.ui")

local KINDS = { "matrix", "cube", "energy" }

local mod = {
  id = "energy",
  name = "Energia",
  kinds = KINDS,
  options = {
    { key = "graph", label = "Wykres historii", type = "toggle", default = true },
    { key = "list", label = "Lista magazynow", type = "toggle", default = true },
    { key = "big", label = "Duzy procent", type = "toggle", default = true },
    { key = "avg", label = "Usrednianie bilansu", type = "choice", default = 300,
      choices = { 30, 60, 300, 900, 1800 },
      labels = { [30] = "30 s", [60] = "1 min", [300] = "5 min", [900] = "15 min", [1800] = "30 min" } },
  },
}

local AVG_LABEL = { [30] = "30s", [60] = "1m", [300] = "5m", [900] = "15m", [1800] = "30m" }

-- sredni bilans z okna czasowego: roznica zgromadzonej energii miedzy najstarsza
-- a najnowsza probka (obejmuje wszystkie magazyny, nie skacze przy chwilowych zmianach)
local function averages(st, window)
  local s = st.samples
  local now = s[#s]
  local first
  for i = 1, #s do
    if now.t - s[i].t <= window then first = s[i] break end
  end
  if not first or now.t - first.t < 2 then return nil end
  local span = now.t - first.t
  local perSec = (now.e - first.e) / span
  local sumIn, sumOut, n = 0, 0, 0
  for i = 1, #s do
    if s[i].t >= first.t and s[i].inp then
      sumIn, sumOut, n = sumIn + s[i].inp, sumOut + s[i].out, n + 1
    end
  end
  return {
    net = perSec / 20,          -- FE/t (nominalnie 20 tickow/s)
    perSec = perSec,            -- FE/s czasu rzeczywistego (do liczenia czasu)
    span = span,
    full = span >= window * 0.9,
    inp = n > 0 and sumIn / n or nil,
    out = n > 0 and sumOut / n or nil,
  }
end

function mod.update(ctx, m)
  local st = m.state
  local stored, cap = 0, 0
  local inp, out, hasIO = 0, 0, false
  local list = {}
  for _, d in ipairs(D.sources(m.cfg.source, KINDS)) do
    if not D.formed(d) then
      list[#list + 1] = { label = D.label(d), bad = "nieuformowany" }
    else
      local e, mx = D.energy(d)
      if e and mx then
        stored, cap = stored + e, cap + mx
        list[#list + 1] = { label = D.label(d), f = U.frac(e, mx), e = e }
      end
      if d.kind == "matrix" then
        local li, lo = U.call(d.p, "getLastInput"), U.call(d.p, "getLastOutput")
        if type(li) == "number" then
          inp, out, hasIO = inp + D.mekFE(li), out + D.mekFE(lo or 0), true
        end
      end
    end
  end
  st.stored, st.cap, st.list = stored, cap, list
  st.frac = U.frac(stored, cap)

  -- bilans liczony z roznicy (FE/t), dziala dla kazdego magazynu
  local now = U.now()
  if st.prevT and now > st.prevT then
    local rate = (stored - st.prevE) / ((now - st.prevT) * 20)
    M.smooth(st, "rate", rate, 0.35)
  end
  st.prevT, st.prevE = now, stored
  if hasIO then
    st.inp, st.out = inp, out
    st.net = inp - out
  else
    st.inp, st.out = nil, nil
    st.net = st.rate
  end
  st.hist = st.hist or {}
  if cap > 0 then M.push(st.hist, st.frac, 400) end

  -- probki do usredniania (trzymamy maksymalne okno)
  st.samples = st.samples or {}
  if cap > 0 then
    st.samples[#st.samples + 1] = { t = now, e = stored, inp = st.inp, out = st.out }
    while #st.samples > 2 and now - st.samples[1].t > 1800 do table.remove(st.samples, 1) end
    st.avg = averages(st, m.opts.avg or 300)
  end

  -- zakladka zrodel: dane tylko gdy jest widoczna
  if (st.tab or "energy") == "sources" then
    st.sources, st.srcControls, st.srcTotal = S.collect(ctx)
  end
end

local TABS = { { id = "energy", label = "Energia" }, { id = "sources", label = "Zrodla" } }

local function drawTabs(c, m, active)
  local tw = math.floor(c.w / #TABS)
  for i, t in ipairs(TABS) do
    local on = t.id == active
    local w = i == #TABS and c.w - (i - 1) * tw or tw
    c:button("tab", 1 + (i - 1) * tw, 2, w, 1, t.label, on and colors.black or colors.white, on and m.accent or colors.gray, t.id)
  end
end

-- bloki do przewijania: zrodla, potem przelaczniki z tagiem "energia"
local function buildBlocks(st)
  local blocks = {}
  for _, e in ipairs(st.sources or {}) do
    local h = 2 + (e.bar and 1 or 0) + (#e.buttons > 0 and 1 or 0) + 1
    blocks[#blocks + 1] = { kind = "src", e = e, h = h }
  end
  if #(st.srcControls or {}) > 0 then
    blocks[#blocks + 1] = { kind = "hdr", h = 1 }
    for _, ctl in ipairs(st.srcControls) do blocks[#blocks + 1] = { kind = "ctl", c = ctl, h = 2 } end
  end
  return blocks
end

local function drawSources(ctx, m, c)
  local st = m.state
  local blocks = buildBlocks(st)
  if #blocks == 0 then
    c:center(math.floor(c.h / 2), "Brak zrodel energii", colors.lightGray, colors.black)
    c:center(math.floor(c.h / 2) + 1, "Dodaj tag 'energia' w Menu > Urzadzenia", colors.gray, colors.black)
    return
  end
  local w = c.w - 2
  c:kv(2, 3, w, "Produkcja razem", U.fmt(st.srcTotal or 0, "FE/t"), colors.lightGray, colors.lime)
  st.sOffset = U.clamp(st.sOffset or 0, 0, #blocks - 1)
  -- czy wszystko sie miesci?
  local total = 0
  for _, b in ipairs(blocks) do total = total + b.h end
  local scroll = total > c.h - 3
  if scroll then w = w - 4 else st.sOffset = 0 end
  local y = 4
  for i = 1 + st.sOffset, #blocks do
    local b = blocks[i]
    if y + b.h - 2 > c.h then break end
    if b.kind == "src" then
      local e = b.e
      c:kv(2, y, w, e.label, e.status or "", colors.yellow, e.scol or colors.white)
      c:kv(2, y + 1, w, e.info or e.kindLabel, e.prod and U.fmt(e.prod, "FE/t") or "", colors.lightGray, colors.lime)
      local yy = y + 2
      if e.bar then
        c:bar(2, yy, w, e.bar.f, e.bar.col, colors.gray, e.bar.text, colors.black)
        yy = yy + 1
      end
      if #e.buttons > 0 then
        local n = #e.buttons
        local bw = math.floor((w - (n - 1)) / n)
        for k, btn in ipairs(e.buttons) do
          local bx = 2 + (k - 1) * (bw + 1)
          local bwk = k == n and (w - (k - 1) * (bw + 1)) or bw
          c:button("src", bx, yy, bwk, 1, btn.label, btn.fg, btn.bg, { btn.cmd, e.name, btn.arg })
        end
      end
    elseif b.kind == "hdr" then
      c:text(2, y, "Przelaczniki (tag energia):", colors.yellow, colors.black)
    else
      local ctl = b.c
      local on = ctl.state and ctl.mode ~= "pulse"
      local txt = ctl.label .. (ctl.mode == "pulse" and "  (impuls)" or (on and "  [WL]" or "  [WYL]"))
      c:button("src", 2, y, w, 1, txt, on and colors.black or colors.white,
        on and UI.color(ctl.color, colors.lime) or colors.gray, { "control", nil, ctl.index })
    end
    y = y + b.h
  end
  if scroll then c:scrollButtons("slist", c.w - 3, 4, c.h - 3, m.accent) end
  if m.flash and m.flash.untilT > os.clock() then
    c:rect(1, c.h, c.w, 1, colors.red)
    c:center(c.h, m.flash.text, colors.white, colors.red)
  end
end

function mod.draw(ctx, m, c)
  local st, o = m.state, m.opts
  local title = M.title(m, "Energia")
  local tab = st.tab or "energy"
  if tab == "sources" then
    c:clear(colors.black)
    c:header(title, m.accent, st.cap and st.cap > 0 and U.pct(st.frac) or nil)
    drawTabs(c, m, tab)
    return drawSources(ctx, m, c)
  end
  if not st.cap or st.cap <= 0 then
    M.message(c, m, title, { "Brak magazynow energii", "Podlacz Induction Port / Energy Cube", "lub magazyn energii przez modem" })
    drawTabs(c, m, tab)
    return
  end
  c:clear(colors.black)
  c:header(title, m.accent, U.pct(st.frac))
  drawTabs(c, m, tab)
  local w, y = c.w, 4
  local col = require("lib.ui").levelColor(st.frac)

  if o.big and c.h >= 17 and c.w >= 18 then
    local s = string.format("%d%%", math.floor(st.frac * 100 + 0.5))
    c:bigCenter(y, s, col)
    y = y + 6
  end
  c:bar(2, y, w - 2, st.frac, col, colors.gray, U.fmt(st.stored, "FE") .. " / " .. U.fmt(st.cap, "FE"))
  y = y + 2

  local net = st.net or 0
  local avg = st.avg
  local win = AVG_LABEL[o.avg or 300] or "?"
  if st.inp then
    local ai, ao = avg and avg.inp or st.inp, avg and avg.out or st.out
    c:kv(2, y, w - 2, "Wejscie (sr. " .. win .. ")", U.fmt(ai, "FE/t"), colors.lightGray, colors.lime); y = y + 1
    c:kv(2, y, w - 2, "Wyjscie (sr. " .. win .. ")", U.fmt(ao, "FE/t"), colors.lightGray, colors.orange); y = y + 1
  end
  c:kv(2, y, w - 2, "Bilans teraz", (net >= 0 and "+" or "") .. U.fmt(net, "FE/t"), colors.lightGray, net >= 0 and colors.lime or colors.red)
  y = y + 1
  if avg then
    local an = avg.net
    local lbl = "Bilans sr. " .. (avg.full and win or (U.fmtTime(avg.span) .. "/" .. win))
    c:kv(2, y, w - 2, lbl, (an >= 0 and "+" or "") .. U.fmt(an, "FE/t"), colors.lightGray, an >= 0 and colors.lime or colors.red)
    y = y + 1
    -- czas liczony ze sredniego bilansu (FE na sekunde rzeczywista) – stabilny
    if avg.perSec > 0.5 then
      c:kv(2, y, w - 2, "Do pelna", U.fmtTime((st.cap - st.stored) / avg.perSec), colors.lightGray, colors.white)
      y = y + 1
    elseif avg.perSec < -0.5 then
      c:kv(2, y, w - 2, "Do rozladowania", U.fmtTime(st.stored / -avg.perSec), colors.lightGray, colors.red)
      y = y + 1
    else
      c:kv(2, y, w - 2, "Stan", "stabilny", colors.lightGray, colors.lime)
      y = y + 1
    end
  else
    c:kv(2, y, w - 2, "Bilans sredni", "zbieranie danych...", colors.lightGray, colors.gray)
    y = y + 1
  end

  if o.list and #st.list > 1 and c.h - y >= 4 then
    y = y + 1
    c:text(2, y, "Magazyny:", colors.yellow, colors.black)
    y = y + 1
    -- przy malej ilosci miejsca lista ma pierwszenstwo przed wykresem
    local maxRows = (o.graph and c.h - y >= 10) and math.floor((c.h - y) / 2) or (c.h - y + 1)
    for i = 1, math.min(#st.list, maxRows) do
      local it = st.list[i]
      if it.bad then
        c:kv(2, y, w - 2, it.label, it.bad, colors.lightGray, colors.red)
      else
        M.inlineBar(c, 2, y, w - 2, it.label, it.f, require("lib.ui").levelColor(it.f))
      end
      y = y + 1
    end
  end

  if o.graph and c.h - y >= 4 then
    y = y + 1
    c:graph(2, y, w - 2, c.h - y + 1, st.hist or {}, function(v) return require("lib.ui").levelColor(v) end, colors.black)
  end
end

function mod.touch(ctx, m, btn)
  local st = m.state
  if btn.id == "tab" then
    st.tab = btn.data
  elseif btn.id == "slist_up" then st.sOffset = (st.sOffset or 0) - 1
  elseif btn.id == "slist_down" then st.sOffset = (st.sOffset or 0) + 1
  elseif btn.id == "src" then
    local ok, err = S.action(ctx, btn.data[1], btn.data[2], btn.data[3])
    if not ok then m.flash = { text = tostring(err), untilT = os.clock() + 3 } end
  end
end

return mod
