-- Autostart Smart System (CC:Tweaked uruchamia wszystkie pliki z /startup/)
if not fs.exists("/smart/main.lua") then return end

while true do
  local ok = shell.run("/smart/main.lua")
  if ok then break end -- normalne wyjscie (menu > Wyjdz / Ctrl+T)
  printError("Smart System padl. Restart za 5s... (dowolny klawisz = anuluj)")
  local t = os.startTimer(5)
  local cancel = false
  while true do
    local e, id = os.pullEvent()
    if e == "timer" and id == t then break end
    if e == "key" then cancel = true break end
  end
  if cancel then break end
end
