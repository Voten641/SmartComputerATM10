-- Autostart Smart System (CC:Tweaked uruchamia wszystkie pliki z /startup/)
-- Pocket Computer = pilot, komputer = pelny system
local program = pocket and "/smart/pocket.lua" or "/smart/main.lua"
if not fs.exists(program) then return end

while true do
  local ok = shell.run(program)
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
