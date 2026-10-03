-- Modul: Wszystkie urzadzenia – lista z kluczowym parametrem kazdego peryferium
local U = require("lib.util")
local D = require("lib.devices")
local M = require("lib.mod")
local UI = require("lib.ui")

local mod = {
  id = "machines",
  name = "Urzadzenia (lista)",
  kinds = {},
  options = {
    { key = "inv", label = "Pokaz inwentarze", type = "toggle", default = false },
    { key = "mek", label = "Pokaz maszyny Mekanism", type = "toggle", default = true },
  },
}

local function hasType(dev, t)
  for _, x in ipairs(dev.types) do if x == t then return true end end
  return false
end

-- zwraca: tekst, frakcja(0-1 lub nil), kolor
local function metric(d)
  local p, k = d.p, d.kind
  if D.MULTIBLOCK[k] and not D.formed(d) then return "nieuformowany", nil, colors.red end
  if k == "fission" then
    local on = U.call(p, "getStatus")
    return (on and "ON " or "OFF ") .. U.temp(U.call(p, "getTemperature")), nil, on and colors.lime or colors.orange
  elseif k == "turbine" then
    return U.fmt(D.mekFE(U.call(p, "getProductionRate")), "FE/t"), U.call(p, "getEnergyFilledPercentage"), colors.lime
  elseif k == "boiler" then
    return U.fmt(U.call(p, "getBoilRate"), "mB/t"), U.call(p, "getWaterFilledPercentage"), colors.blue
  elseif k == "fusion" then
    return U.call(p, "isIgnited") and "zaplon" or "wygaszony", U.call(p, "getDTFuelFilledPercentage"), colors.purple
  elseif k == "sps" then
    return U.fmt(U.call(p, "getProcessRate"), "mB/t"), U.call(p, "getInputFilledPercentage"), colors.magenta
  elseif k == "evap" then
    return U.fmt(U.call(p, "getProductionAmount"), "mB/t"), U.call(p, "getInputFilledPercentage"), colors.lightBlue
  elseif k == "dyntank" then
    return U.pct(U.call(p, "getFilledPercentage")), U.call(p, "getFilledPercentage"), colors.blue
  elseif k == "powahreactor" then
    local on = U.call(p, "isRunning")
    return (on and "ON " or "OFF ") .. "T " .. U.round(U.call(p, "getTemperature") or 0) .. "%", (U.call(p, "getFuel") or 0) / 100, colors.lime
  elseif k == "stress" then
    local s, cap = U.call(p, "getStress"), U.call(p, "getStressCapacity")
    local f = U.frac(s, cap)
    return U.fmt(s, "su") .. "/" .. U.fmt(cap, "su"), f, UI.levelColor(f, true)
  elseif k == "speed" then
    return U.fmt(U.call(p, "getSpeed"), " RPM"), nil, colors.white
  elseif k == "flowdet" then
    local unit = hasType(d, "energy_detector") and "FE/t" or "mB/t"
    return U.fmt(U.call(p, "getTransferRate"), unit), nil, colors.yellow
  elseif k == "me" or k == "rs" then
    local f = U.frac(U.call(p, "getUsedItemStorage"), U.call(p, "getMaxItemStorage"))
    return U.pct(f), f, UI.levelColor(f, true)
  elseif k == "ctarget" then
    return U.call(p, "getLine", 1) or "", nil, colors.white
  elseif k == "scroller" then
    return tostring(U.call(p, "getValue")), nil, colors.white
  elseif k == "relay" then
    local on = {}
    for _, s in ipairs(D.SIDES) do if U.call(p, "getOutput", s) then on[#on + 1] = s end end
    return #on > 0 and table.concat(on, ",") or "wyl", nil, colors.red
  elseif k == "inventory" then
    local l, size = U.call(p, "list"), U.call(p, "size")
    local used = 0
    if type(l) == "table" then for _ in pairs(l) do used = used + 1 end end
    local f = U.frac(used, size)
    return used .. "/" .. tostring(size or "?") .. " slotow", f, UI.levelColor(f, true)
  end
  local e, mx = D.energy(d)
  if e and mx and mx > 0 then
    local f = U.frac(e, mx)
    return U.fmt(e, "FE"), f, UI.levelColor(f)
  end
  local tanks = U.call(p, "tanks")
  if type(tanks) == "table" then
    local t = 0
    for _, x in pairs(tanks) do t = t + (x.amount or 0) end
    return U.fmt(t, "mB"), nil, colors.lightBlue
  end
  return "-", nil, colors.gray
end

function mod.update(ctx, m)
  local rows = {}
  for _, d in ipairs(D.list) do
    if D.isActive(d) and not D.UTILITY[d.kind]
      and (m.opts.inv or d.kind ~= "inventory")
      and (m.opts.mek or not (d.kind == "machine" and d.mek)) then
      local ok, txt, f, col = pcall(metric, d)
      if not ok then txt, f, col = "blad", nil, colors.red end
      rows[#rows + 1] = { label = D.label(d), kind = D.kindLabel(d.kind), txt = tostring(txt), f = f, col = col }
    end
  end
  m.state.rows = rows
end

function mod.draw(ctx, m, c)
  local st = m.state
  local rows = st.rows or {}
  local title = M.title(m, "Urzadzenia")
  if #rows == 0 then return M.message(c, m, title, { "Brak urzadzen", "Podlacz maszyny modemami" }) end
  c:clear(colors.black)
  c:header(title, m.accent, #rows .. " szt.")
  local perRow = c.w >= 40 and 1 or 2
  local visible = math.floor((c.h - 2) / perRow)
  local maxOff = math.max(0, #rows - visible)
  st.offset = U.clamp(st.offset or 0, 0, maxOff)
  local w = c.w - 2 - (maxOff > 0 and 4 or 0)
  local y = 3
  for i = 1, visible do
    local r = rows[i + st.offset]
    if not r then break end
    if perRow == 1 then
      local lw = math.floor(w * 0.4)
      c:text(2, y, U.padRight(r.label, lw), colors.white, colors.black)
      local rest = w - lw
      if r.f then
        c:bar(2 + lw, y, rest, r.f, r.col, colors.gray, r.txt, colors.black)
      else
        c:text(2 + lw, y, U.padLeft(r.txt, rest), r.col, colors.black)
      end
      y = y + 1
    else
      c:kv(2, y, w, r.label, r.kind, colors.white, colors.gray)
      if r.f then
        c:bar(2, y + 1, w, r.f, r.col, colors.gray, r.txt, colors.black)
      else
        c:text(2, y + 1, U.padLeft(r.txt, w), r.col, colors.black)
      end
      y = y + 2
    end
  end
  if maxOff > 0 then c:scrollButtons("list", c.w - 3, 3, c.h - 2, m.accent) end
end

function mod.touch(ctx, m, btn)
  local st = m.state
  local step = math.max(1, math.floor((m.canvas.h - 2) / 2))
  if btn.id == "list_up" then st.offset = (st.offset or 0) - step
  elseif btn.id == "list_down" then st.offset = (st.offset or 0) + step end
end

return mod
