-- Modul: Energia (Induction Matrix, Energy Cube, Powah, magazyny energy_storage)
local U = require("lib.util")
local D = require("lib.devices")
local M = require("lib.mod")

local KINDS = { "matrix", "cube", "energy" }

local mod = {
  id = "energy",
  name = "Energia",
  kinds = KINDS,
  options = {
    { key = "graph", label = "Wykres historii", type = "toggle", default = true },
    { key = "list", label = "Lista magazynow", type = "toggle", default = true },
    { key = "big", label = "Duzy procent", type = "toggle", default = true },
  },
}

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
end

function mod.draw(ctx, m, c)
  local st, o = m.state, m.opts
  local title = M.title(m, "Energia")
  if not st.cap or st.cap <= 0 then
    return M.message(c, m, title, { "Brak magazynow energii", "Podlacz Induction Port / Energy Cube", "lub magazyn energii przez modem" })
  end
  c:clear(colors.black)
  c:header(title, m.accent, U.pct(st.frac))
  local w, y = c.w, 3
  local col = require("lib.ui").levelColor(st.frac)

  if o.big and c.h >= 16 and c.w >= 18 then
    local s = string.format("%d%%", math.floor(st.frac * 100 + 0.5))
    c:bigCenter(y, s, col)
    y = y + 6
  end
  c:bar(2, y, w - 2, st.frac, col, colors.gray, U.fmt(st.stored, "FE") .. " / " .. U.fmt(st.cap, "FE"))
  y = y + 2

  local net = st.net or 0
  if st.inp then
    c:kv(2, y, w - 2, "Wejscie", U.fmt(st.inp, "FE/t"), colors.lightGray, colors.lime); y = y + 1
    c:kv(2, y, w - 2, "Wyjscie", U.fmt(st.out, "FE/t"), colors.lightGray, colors.orange); y = y + 1
  end
  c:kv(2, y, w - 2, "Bilans", (net >= 0 and "+" or "") .. U.fmt(net, "FE/t"), colors.lightGray, net >= 0 and colors.lime or colors.red)
  y = y + 1
  if net > 0.5 then
    c:kv(2, y, w - 2, "Do pelna", U.fmtTime((st.cap - st.stored) / net / 20), colors.lightGray, colors.white)
    y = y + 1
  elseif net < -0.5 then
    c:kv(2, y, w - 2, "Do rozladowania", U.fmtTime(st.stored / -net / 20), colors.lightGray, colors.red)
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

return mod
