-- Modul: Magazyn ME (AE2) / RS (Refined Storage) przez Advanced Peripherals 0.8
local U = require("lib.util")
local D = require("lib.devices")
local M = require("lib.mod")
local UI = require("lib.ui")

local mod = {
  id = "storage",
  name = "Magazyn ME/RS",
  kinds = { "me", "rs" },
  single = true,
  options = {
    { key = "items", label = "Lista przedmiotow", type = "toggle", default = true },
    { key = "filter", label = "Filtr nazwy", type = "text", default = "" },
    { key = "sort", label = "Sortowanie", type = "choice", default = "count", choices = { "count", "name" } },
  },
}

function mod.update(ctx, m)
  local d = M.single(m, mod.kinds)
  local st = m.state
  st.dev = d
  if not d then return end
  local p = d.p
  st.isME = d.kind == "me"
  st.online = U.call(p, "isOnline")
  st.connected = U.call(p, "isConnected")
  if not st.connected then return end
  st.usedI, st.maxI = U.call(p, "getUsedItemStorage"), U.call(p, "getMaxItemStorage")
  st.usedF, st.maxF = U.call(p, "getUsedFluidStorage"), U.call(p, "getMaxFluidStorage")
  st.energy, st.energyMax = U.call(p, "getStoredEnergy"), U.call(p, "getEnergyCapacity")
  st.usage = U.call(p, "getEnergyUsage")
  local tasks = U.call(p, "getCraftingTasks")
  st.tasks = type(tasks) == "table" and #tasks or nil
  if st.isME then
    local cpus = U.call(p, "getCraftingCPUs")
    if type(cpus) == "table" then
      local busy = 0
      for _, cpu in ipairs(cpus) do if cpu.isBusy then busy = busy + 1 end end
      st.cpus, st.cpusBusy = #cpus, busy
    end
  end

  -- lista przedmiotow jest ciezka: pobieramy co N odswiezen
  st.tick = (st.tick or 0) + 1
  if m.opts.items and (st.items == nil or st.tick % math.max(1, ctx.cfg.itemsEvery) == 1) then
    local items = U.call(p, "getItems", {})
    if type(items) == "table" then
      local f = (m.opts.filter or ""):lower()
      local list = {}
      for _, it in ipairs(items) do
        local name = U.itemName(it)
        if f == "" or name:lower():find(f, 1, true) or (it.name or ""):find(f, 1, true) then
          list[#list + 1] = { name = name, count = U.itemCount(it), craft = it.isCraftable }
        end
      end
      if m.opts.sort == "name" then
        table.sort(list, function(a, b) return a.name < b.name end)
      else
        table.sort(list, function(a, b) return a.count > b.count end)
      end
      st.items, st.types = list, #items
    end
  end
end

function mod.draw(ctx, m, c)
  local st = m.state
  local title = M.title(m, "Magazyn")
  if not st.dev then
    return M.message(c, m, title, { "Brak ME/RS Bridge", "Podlacz ME Bridge lub RS Bridge", "(Advanced Peripherals)" })
  end
  title = M.title(m, D.label(st.dev))
  if not st.connected then
    return M.message(c, m, title, { "Bridge nie jest podlaczony", "do sieci ME/RS" })
  end
  c:clear(colors.black)
  c:header(title, m.accent, st.online and "ONLINE" or "OFFLINE")
  local w, y = c.w - 2, 3
  local unit = st.isME and "B" or ""
  local fi = U.frac(st.usedI, st.maxI)
  y = M.inlineBar(c, 2, y, w, "Przedmioty", fi, UI.levelColor(fi, true), U.fmt(st.usedI, unit) .. "/" .. U.fmt(st.maxI, unit))
  if (st.maxF or 0) > 0 then
    local ff = U.frac(st.usedF, st.maxF)
    y = M.inlineBar(c, 2, y, w, "Plyny", ff, UI.levelColor(ff, true), U.fmt(st.usedF, st.isME and "B" or "mB") .. "/" .. U.fmt(st.maxF, st.isME and "B" or "mB"))
  end
  if st.isME and (st.energyMax or 0) > 0 then
    local fe = U.frac(st.energy, st.energyMax)
    y = M.inlineBar(c, 2, y, w, "Energia AE", fe, UI.levelColor(fe), U.fmt(st.energy, "AE"))
    c:kv(2, y, w, "Zuzycie", U.fmt(st.usage, "AE/t"), colors.lightGray, colors.white); y = y + 1
  end
  local info = {}
  if st.types then info[#info + 1] = st.types .. " typow" end
  if st.tasks then info[#info + 1] = "craft: " .. st.tasks end
  if st.cpus then info[#info + 1] = string.format("CPU %d/%d", st.cpusBusy, st.cpus) end
  if #info > 0 then c:text(2, y, U.trunc(table.concat(info, "  "), w), colors.lightGray, colors.black); y = y + 1 end

  if m.opts.items and st.items and c.h - y >= 3 then
    y = y + 1
    local rows = c.h - y + 1
    local maxOff = math.max(0, #st.items - rows)
    st.offset = U.clamp(st.offset or 0, 0, maxOff)
    local listW = w - (maxOff > 0 and 4 or 0)
    for i = 1, rows do
      local it = st.items[i + st.offset]
      if not it then break end
      local cnt = U.fmt(it.count)
      c:text(2, y, U.padRight(it.name, listW - #cnt - 1), it.craft and colors.cyan or colors.white, colors.black)
      c:text(2 + listW - #cnt, y, cnt, colors.yellow, colors.black)
      y = y + 1
    end
    if maxOff > 0 then
      c:scrollButtons("list", c.w - 3, c.h - rows + 1, rows, m.accent)
    end
  end
end

function mod.touch(ctx, m, btn)
  local st = m.state
  local step = math.max(1, math.floor(m.canvas.h / 2))
  if btn.id == "list_up" then st.offset = (st.offset or 0) - step
  elseif btn.id == "list_down" then st.offset = (st.offset or 0) + step end
end

return mod
