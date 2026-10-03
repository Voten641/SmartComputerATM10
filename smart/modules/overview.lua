-- Modul: Przeglad bazy – podsumowanie wszystkiego na jednym ekranie
local U = require("lib.util")
local D = require("lib.devices")
local M = require("lib.mod")
local UI = require("lib.ui")

local mod = {
  id = "overview",
  name = "Przeglad bazy",
  kinds = {},
  options = {},
}

function mod.update(ctx, m)
  local st = {}
  m.state = st
  local f, stored, cap = ctx.auto.readEnergy("auto")
  st.energy = f and { f = f, stored = stored, cap = cap } or nil

  st.reactors = {}
  for _, d in ipairs(D.byKind("fission")) do
    if D.formed(d) then
      st.reactors[#st.reactors + 1] = {
        label = D.label(d), on = U.call(d.p, "getStatus"), temp = U.call(d.p, "getTemperature"),
        burn = U.call(d.p, "getActualBurnRate"), trip = ctx.auto.trips[d.name],
      }
    end
  end
  st.gen = 0
  for _, d in ipairs(D.byKind("turbine")) do
    if D.formed(d) then st.gen = st.gen + (D.mekFE(U.call(d.p, "getProductionRate")) or 0) end
  end
  for _, d in ipairs(D.byKind("fusion")) do
    if D.formed(d) then st.gen = st.gen + (D.mekFE(U.call(d.p, "getProductionRate")) or 0) end
  end
  st.storages = {}
  for _, d in ipairs(D.byKind({ "me", "rs" })) do
    local fr = U.frac(U.call(d.p, "getUsedItemStorage"), U.call(d.p, "getMaxItemStorage"))
    st.storages[#st.storages + 1] = { label = D.label(d), f = fr, online = U.call(d.p, "isOnline") }
  end
  local pd = D.byKind("player")[1]
  st.players = pd and (U.call(pd.p, "getOnlinePlayers") or {}) or nil
end

function mod.draw(ctx, m, c)
  local st = m.state
  c:clear(colors.black)
  c:header(M.title(m, ctx.cfg.title), m.accent, textutils.formatTime(os.time("ingame"), true))
  local w, y = c.w - 2, 3
  local function section(t)
    if y > c.h then return false end
    c:text(2, y, t, colors.yellow, colors.black)
    y = y + 1
    return true
  end

  if st.energy and section("Energia") then
    local col = UI.levelColor(st.energy.f)
    c:bar(2, y, w, st.energy.f, col, colors.gray, U.pct(st.energy.f) .. "  " .. U.fmt(st.energy.stored, "FE"))
    y = y + 2
  end
  if st.gen > 0 and y <= c.h then
    c:kv(2, y - 1, w, "Generacja", U.fmt(st.gen, "FE/t"), colors.lightGray, colors.lime)
    y = y + 1
  end
  if #st.reactors > 0 and section("Reaktory") then
    for _, r in ipairs(st.reactors) do
      if y > c.h then break end
      local s, col = r.trip and "SCRAM" or r.on and "ON" or "OFF", r.trip and colors.red or r.on and colors.lime or colors.orange
      c:kv(2, y, w, r.label, s .. " " .. U.temp(r.temp), colors.white, col)
      y = y + 1
    end
    y = y + 1
  end
  if #st.storages > 0 and section("Magazyny") then
    for _, s in ipairs(st.storages) do
      if y > c.h then break end
      M.inlineBar(c, 2, y, w, s.label, s.f, UI.levelColor(s.f, true))
      y = y + 1
    end
    y = y + 1
  end
  if st.players and section("Gracze online: " .. #st.players) then
    if y <= c.h then
      c:text(2, y, U.trunc(table.concat(st.players, ", "), w), colors.white, colors.black)
      y = y + 2
    end
  end
  local alarms = ctx.auto.list()
  if y <= c.h then
    if #alarms == 0 then
      c:text(2, y, "Alarmy: brak", colors.lime, colors.black)
    else
      section("Alarmy")
      for _, a in ipairs(alarms) do
        if y > c.h then break end
        c:text(2, y, U.trunc(a.text, w), a.level == "crit" and colors.red or colors.orange, colors.black)
        y = y + 1
      end
    end
  end
end

return mod
