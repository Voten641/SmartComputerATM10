-- Modul: Wyszukiwarka ME/RS z klawiatura ekranowa i wydawaniem przedmiotow do skrzyni (exportItem)
local U = require("lib.util")
local D = require("lib.devices")
local M = require("lib.mod")

local function targets()
  local r = {}
  for _, d in ipairs(D.list) do
    if d.kind == "inventory" then r[#r + 1] = d.name end
  end
  for _, s in ipairs({ "@up", "@down", "@north", "@south", "@east", "@west" }) do r[#r + 1] = s end
  return r
end

local mod = {
  id = "mesearch",
  name = "Wyszukiwarka ME/RS",
  kinds = { "me", "rs" },
  single = true,
  options = {
    { key = "target", label = "Wydawaj do", type = "choice", default = "@up", choicesFn = targets },
  },
}

local ROWS = { "QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM" }
local AMOUNTS = { 1, 16, 64, 576 }

function mod.update(ctx, m)
  local st = m.state
  local d = M.single(m, mod.kinds)
  st.dev = d
  st.query = st.query or ""
  if not d then return end
  local now = U.now()
  if not st.cache or now - (st.cacheT or 0) > 5 or st.dirty then
    local items = U.call(d.p, "getItems", {})
    if type(items) == "table" then st.cache, st.cacheT = items, now end
    st.dirty = false
  end
  local q = st.query:lower()
  local res = {}
  for _, it in ipairs(st.cache or {}) do
    local name = U.itemName(it)
    if q == "" or name:lower():find(q, 1, true) or (it.name or ""):find(q, 1, true) then
      res[#res + 1] = { id = it.name, name = name, count = U.itemCount(it) }
    end
  end
  table.sort(res, function(a, b) return a.count > b.count end)
  st.results = res
end

function mod.draw(ctx, m, c)
  local st = m.state
  local title = M.title(m, "Szukaj w ME/RS")
  if not st.dev then return M.message(c, m, title, { "Brak ME/RS Bridge" }) end
  c:clear(colors.black)
  c:header(title, m.accent, #(st.results or {}) .. " wynikow")
  -- pole wyszukiwania
  c:rect(2, 2, c.w - 2, 1, colors.white)
  c:text(3, 2, U.trunc(st.query ~= "" and st.query or "dotknij liter...", c.w - 4), st.query ~= "" and colors.black or colors.gray, colors.white)

  local kbH = 4
  local barH = st.sel and 2 or 0
  local listTop, listBottom = 3, c.h - kbH - barH
  local rows = listBottom - listTop + 1
  local res = st.results or {}
  local maxOff = math.max(0, #res - rows)
  st.offset = U.clamp(st.offset or 0, 0, maxOff)
  local lw = c.w - 2 - (maxOff > 0 and 4 or 0)
  for i = 1, rows do
    local r = res[i + st.offset]
    if not r then break end
    local y = listTop + i - 1
    local sel = st.sel == r.id
    local bg = sel and colors.blue or colors.black
    local cnt = U.fmt(r.count)
    c:rect(2, y, lw, 1, bg)
    c:text(2, y, U.padRight(r.name, lw - #cnt - 1), colors.white, bg)
    c:text(2 + lw - #cnt, y, cnt, colors.yellow, bg)
    c:zone("item", 2, y, lw, 1, r.id)
  end
  if maxOff > 0 and rows >= 2 then c:scrollButtons("list", c.w - 3, listTop, rows, m.accent) end

  -- pasek wydawania
  if st.sel then
    local y = listBottom + 1
    local label = st.msg or ("Wydaj do " .. tostring(m.opts.target) .. ":")
    c:text(2, y, U.trunc(label, c.w - 2), st.msgErr and colors.red or colors.lightGray, colors.black)
    local n = #AMOUNTS + 1
    local bw = math.floor((c.w - 1 - n) / n)
    for i, a in ipairs(AMOUNTS) do
      c:button("give", 2 + (i - 1) * (bw + 1), y + 1, bw, 1, tostring(a), colors.black, colors.lime, a)
    end
    c:button("unsel", 2 + #AMOUNTS * (bw + 1), y + 1, c.w - 2 - #AMOUNTS * (bw + 1), 1, "X", colors.white, colors.red)
  end

  -- klawiatura
  local ky = c.h - kbH + 1
  local kw = math.max(1, math.floor((c.w - 1) / 10))
  for r, keys in ipairs(ROWS) do
    for i = 1, #keys do
      local ch = keys:sub(i, i)
      c:button("key", 1 + (i - 1) * kw + 1, ky + r - 1, kw - (kw > 2 and 1 or 0), 1, ch, colors.white, colors.gray, ch:lower())
    end
  end
  local last = ky + 3
  local third = math.floor((c.w - 2) / 3)
  c:button("space", 2, last, third - 1, 1, "spacja", colors.black, colors.lightGray)
  c:button("back", 2 + third, last, third - 1, 1, "<-", colors.white, colors.orange)
  c:button("clear", 2 + third * 2, last, c.w - 2 - third * 2, 1, "wyczysc", colors.white, colors.red)
end

function mod.touch(ctx, m, btn)
  local st = m.state
  st.query = st.query or ""
  local id = btn.id
  if id == "key" then st.query = st.query .. btn.data; st.offset = 0
  elseif id == "space" then st.query = st.query .. " "
  elseif id == "back" then st.query = st.query:sub(1, -2)
  elseif id == "clear" then st.query = ""; st.offset = 0
  elseif id == "list_up" then st.offset = (st.offset or 0) - 5
  elseif id == "list_down" then st.offset = (st.offset or 0) + 5
  elseif id == "item" then st.sel = btn.data; st.msg = nil
  elseif id == "unsel" then st.sel = nil; st.msg = nil
  elseif id == "give" and st.sel and st.dev then
    local target = m.opts.target or "@up"
    local ok, moved, err = pcall(st.dev.p.exportItem, target, { name = st.sel, count = btn.data })
    if ok and type(moved) == "number" then
      st.msg, st.msgErr = "Wydano " .. moved .. "x " .. U.prettyId(st.sel), moved == 0
      if moved == 0 then st.msg = "Nic nie wydano (pelna skrzynia?)" end
      st.dirty = true
    else
      st.msg, st.msgErr = "Blad: " .. tostring(ok and err or moved), true
    end
  end
end

return mod
