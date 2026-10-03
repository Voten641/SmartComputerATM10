-- Smart System: autocrafting – utrzymywanie zapasow w ME/RS (Advanced Peripherals 0.8)
local U = require("lib.util")
local D = require("lib.devices")

local AC = {}
AC.status = {}   -- [name] = { count, state, msg }
AC.last = 0

function AC.bridge(cfg)
  local list = D.sources(cfg.autocraft.bridge, { "me", "rs" })
  return list[1]
end

-- ilosc przedmiotu w systemie (0 gdy brak)
function AC.count(p, name)
  local it = U.call(p, "getItem", { name = name })
  if type(it) == "table" then return U.itemCount(it) end
  return 0
end

local function checkItem(ctx, p, item)
  local st = AC.status[item.name] or {}
  AC.status[item.name] = st
  st.count = AC.count(p, item.name)
  if not item.enabled then st.state, st.msg = "off", "wylaczony" return end
  if st.count >= item.keep then st.state, st.msg = "ok", "OK" return end
  if U.call(p, "isCrafting", { type = "item", name = item.name }) then
    st.state, st.msg = "crafting", "craftowanie..."
    return
  end
  local amount = math.max(1, math.min(item.batch or 64, item.keep - st.count))
  local ok, job, err = pcall(p.craftItem, { name = item.name, count = amount })
  if ok and job then
    st.state, st.msg = "crafting", "zlecono " .. amount
    ctx.auto.logEvent("Autocraft: " .. (item.label ~= "" and item.label or U.prettyId(item.name)) .. " x" .. amount)
  else
    local reason = ok and tostring(err) or tostring(job)
    if reason == "NOT_CRAFTABLE" then reason = "brak wzoru" end
    st.state, st.msg = "error", reason
  end
end

function AC.tick(ctx)
  local cfg = ctx.cfg.autocraft
  if not cfg.enabled or #cfg.items == 0 then return end
  local now = U.now()
  if now - AC.last < (cfg.every or 10) then return end
  AC.last = now
  local d = AC.bridge(ctx.cfg)
  if not d or not U.call(d.p, "isOnline") then return end
  for _, item in ipairs(cfg.items) do
    local ok, err = pcall(checkItem, ctx, d.p, item)
    if not ok then AC.status[item.name] = { state = "error", msg = tostring(err), count = 0 } end
  end
end

return AC
