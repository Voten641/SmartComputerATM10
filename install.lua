-- Smart System ATM10 – instalator / aktualizator
-- Uzycie:
--   install              instalacja (lub naprawa)
--   install update       aktualizacja z GitHuba (konfiguracja zostaje)
--   install repo <uzytkownik/repo> [galaz]   zmiana repozytorium
--   install version      pokaz wersje lokalna i zdalna
--   install uninstall    usuniecie programu (pyta o konfiguracje)

local DEFAULT_REPO = "Voten641/SmartComputerATM10"
local DEFAULT_BRANCH = "main"
local REPO_FILE = "/.smartrepo"
local FILES_LIST = "/smart/.files"
local VERSION_FILE = "/smart/version.txt"

local args = { ... }
local cmd = args[1] or "install"

local function color(c)
  if term.isColor() then term.setTextColor(c) end
end

local function say(c, ...)
  color(c)
  print(...)
  color(colors.white)
end

local function readFile(path)
  if not fs.exists(path) then return nil end
  local f = fs.open(path, "r")
  local s = f.readAll()
  f.close()
  return s
end

local function writeFile(path, data)
  local dir = fs.getDir(path)
  if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
  local f = fs.open(path, "wb")
  f.write(data)
  f.close()
end

local function getRepo()
  local s = readFile(REPO_FILE)
  local repo, branch = DEFAULT_REPO, DEFAULT_BRANCH
  if s then
    s = s:gsub("%s+", "")
    local r, b = s:match("^([^@]+)@(.+)$")
    if r then repo, branch = r, b elseif s ~= "" then repo = s end
  end
  return repo, branch
end

local function httpGet(url, headers)
  local h, err = http.get(url, headers, true)
  if not h then return nil, err end
  local code = h.getResponseCode()
  local data = h.readAll()
  h.close()
  if code ~= 200 then return nil, "HTTP " .. code end
  return data
end

-- SHA ostatniego commita (raw.githubusercontent cache'uje galezie ~5 min, SHA omija cache)
local function resolveRef(repo, branch)
  local data = httpGet("https://api.github.com/repos/" .. repo .. "/commits/" .. branch,
    { ["Accept"] = "application/vnd.github.sha" })
  if data and data:match("^%x+$") and #data >= 40 then return data:sub(1, 40) end
  return branch
end

local function fetchManifest(base)
  local src, err = httpGet(base .. "manifest.lua")
  if not src then return nil, "Nie mozna pobrac manifest.lua: " .. tostring(err) end
  local fn, perr = load(src, "manifest", "t", {})
  if not fn then return nil, "Bledny manifest: " .. tostring(perr) end
  local ok, man = pcall(fn)
  if not ok or type(man) ~= "table" or type(man.files) ~= "table" then
    return nil, "Bledny manifest"
  end
  return man
end

local function localVersion()
  local v = readFile(VERSION_FILE)
  return v and v:gsub("%s+$", "") or nil
end

local function install(isUpdate)
  if not http then
    say(colors.red, "HTTP API jest wylaczone w configu CC:Tweaked!")
    return false
  end
  local repo, branch = getRepo()
  say(colors.cyan, "Smart System ATM10 - " .. (isUpdate and "aktualizacja" or "instalacja"))
  print("Repo: " .. repo .. " (" .. branch .. ")")
  local ref = resolveRef(repo, branch)
  local base = "https://raw.githubusercontent.com/" .. repo .. "/" .. ref .. "/"
  local man, err = fetchManifest(base)
  if not man then
    say(colors.red, err)
    return false
  end
  local old = localVersion()
  print("Wersja: " .. tostring(old or "-") .. " -> " .. tostring(man.version))
  -- Pocket Computer dostaje tylko pilota
  local files = man.files
  if pocket and type(man.pocket) == "table" then
    files = man.pocket
    print("Wykryto Pocket Computer - instaluje pilota")
  end

  -- najpierw pobieramy wszystko do pamieci, zapisujemy dopiero gdy sie udalo
  local data = {}
  for i, path in ipairs(files) do
    local x, y = term.getCursorPos()
    term.setCursorPos(1, y)
    term.clearLine()
    write(string.format("[%d/%d] %s", i, #files, path))
    local body, ferr = httpGet(base .. path)
    if not body then
      print("")
      say(colors.red, "Blad pobierania " .. path .. ": " .. tostring(ferr))
      say(colors.red, "Przerwano - nic nie zostalo zmienione.")
      return false
    end
    data[path] = body
  end
  print("")

  -- usuwamy pliki ktorych nie ma w nowej wersji (nigdy /smart/data)
  local oldList = readFile(FILES_LIST)
  if oldList then
    local keep = {}
    for _, p in ipairs(files) do keep[p] = true end
    for p in oldList:gmatch("[^\n]+") do
      if not keep[p] and fs.exists("/" .. p) and not p:find("^smart/data/") then fs.delete("/" .. p) end
    end
  end

  for _, path in ipairs(files) do writeFile("/" .. path, data[path]) end
  writeFile(FILES_LIST, table.concat(files, "\n"))
  writeFile(VERSION_FILE, tostring(man.version))
  if not fs.exists("/smart/data") then fs.makeDir("/smart/data") end

  say(colors.lime, "Gotowe! Zainstalowano wersje " .. tostring(man.version))
  if man.changelog then
    say(colors.yellow, "Zmiany:")
    for _, l in ipairs(man.changelog) do print(" - " .. l) end
  end
  if not isUpdate then
    print("")
    print("Komendy:  update  - aktualizacja z GitHuba")
    print("Program startuje automatycznie po restarcie.")
    write("Uruchomic ponownie teraz? (t/n) ")
    local a = read()
    if a == "t" or a == "T" or a == "y" then os.reboot() end
  end
  return true
end

local function uninstall()
  write("Usunac Smart System? (t/n) ")
  if read() ~= "t" then return end
  write("Usunac tez konfiguracje? (t/n) ")
  local cfgToo = read() == "t"
  local list = readFile(FILES_LIST)
  if list then
    for p in list:gmatch("[^\n]+") do
      if fs.exists("/" .. p) and p ~= "install.lua" then fs.delete("/" .. p) end
    end
  end
  if cfgToo then
    if fs.exists("/smart") then fs.delete("/smart") end
    if fs.exists(REPO_FILE) then fs.delete(REPO_FILE) end
  else
    for _, p in ipairs(fs.list("/smart")) do
      if p ~= "data" then fs.delete("/smart/" .. p) end
    end
  end
  say(colors.lime, "Usunieto.")
end

if cmd == "install" then
  local ok = install(false)
  if not ok then error("Instalacja nieudana", 0) end
elseif cmd == "update" then
  local ok = install(true)
  if not ok then error("Aktualizacja nieudana", 0) end
elseif cmd == "repo" then
  if not args[2] or not args[2]:match("^[%w%-_%.]+/[%w%-_%.]+$") then
    print("Uzycie: install repo <uzytkownik/repo> [galaz]")
    print("Aktualnie: " .. table.concat({ getRepo() }, " @ "))
    return
  end
  writeFile(REPO_FILE, args[2] .. (args[3] and ("@" .. args[3]) or ""))
  say(colors.lime, "Repozytorium ustawione na " .. args[2] .. " (" .. (args[3] or DEFAULT_BRANCH) .. ")")
elseif cmd == "version" then
  local repo, branch = getRepo()
  print("Lokalna: " .. tostring(localVersion() or "-"))
  local base = "https://raw.githubusercontent.com/" .. repo .. "/" .. resolveRef(repo, branch) .. "/"
  local man = fetchManifest(base)
  print("Zdalna:  " .. tostring(man and man.version or "?"))
elseif cmd == "uninstall" then
  uninstall()
else
  print("Uzycie: install [update|repo|version|uninstall]")
end
