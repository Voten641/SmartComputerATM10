-- Modul: Zbiorniki (Mekanism Dynamic Tank, Create Fluid Tank przez AP, generyczne fluid_storage)
local U = require("lib.util")
local D = require("lib.devices")
local M = require("lib.mod")

local KINDS = { "dyntank", "fluid" }

local mod = {
  id = "tanks",
  name = "Zbiorniki",
  kinds = KINDS,
  options = {},
}

local function hasType(dev, t)
  for _, x in ipairs(dev.types) do if x == t then return true end end
  return false
end

local function readTank(d)
  local p = d.p
  if d.kind == "dyntank" then
    if not D.formed(d) then return { label = D.label(d), bad = "nieuformowany" } end
    local s = U.call(p, "getStored")
    local f = U.call(p, "getFilledPercentage") or 0
    local name = type(s) == "table" and s.name and s.name ~= "minecraft:empty" and U.prettyId(s.name) or "pusty"
    return { label = D.label(d), content = name, amount = type(s) == "table" and s.amount or 0, f = f }
  end
  -- Create Fluid Tank przez AP: info() zna pojemnosc
  if hasType(d, "fluid_tank") and U.has(p, "info") then
    local i = U.call(p, "info")
    if type(i) == "table" then
      local fl = i.fluid or {}
      local amt = fl.count or 0
      return {
        label = D.label(d),
        content = amt > 0 and (fl.displayName or U.prettyId(fl.name)) or "pusty",
        amount = amt, f = U.frac(amt, i.capacity), cap = i.capacity,
      }
    end
  end
  -- generyczne fluid_storage: tylko ilosci (CC:T nie podaje pojemnosci)
  local tanks = U.call(p, "tanks")
  if type(tanks) == "table" then
    local total, name = 0, nil
    for _, t in pairs(tanks) do
      total = total + (t.amount or 0)
      if not name and t.name then name = U.prettyId(t.name) end
    end
    return { label = D.label(d), content = name or "pusty", amount = total }
  end
  return { label = D.label(d), bad = "brak danych" }
end

function mod.update(ctx, m)
  local list = {}
  for _, d in ipairs(D.sources(m.cfg.source, KINDS)) do list[#list + 1] = readTank(d) end
  m.state.list = list
end

function mod.draw(ctx, m, c)
  local list = m.state.list or {}
  local title = M.title(m, "Zbiorniki")
  if #list == 0 then return M.message(c, m, title, { "Brak zbiornikow", "Dynamic Tank / Create Fluid Tank / inne" }) end
  c:clear(colors.black)
  c:header(title, m.accent, #list .. " szt.")
  local w, y = c.w - 2, 3
  for _, t in ipairs(list) do
    if y + 1 > c.h then break end
    if t.bad then
      c:kv(2, y, w, t.label, t.bad, colors.lightGray, colors.red)
      y = y + 2
    else
      c:kv(2, y, w, t.label, t.content, colors.white, colors.lightBlue)
      if t.f then
        c:bar(2, y + 1, w, t.f, colors.blue, colors.gray, U.fmt(t.amount, "mB") .. "  " .. U.pct(t.f), colors.white)
      else
        c:text(2, y + 1, U.fmt(t.amount, "mB"), colors.lightGray, colors.black)
      end
      y = y + 3
    end
  end
end

return mod
