-- Test instalatora: aktualizacja pomija pobieranie, gdy zainstalowana wersja jest najnowsza
-- Uruchom z katalogu repo:  lua tests/installer_test.lua
local ROOT = arg and arg[0] and arg[0]:match("^(.*)/tests/") or "."
local TMP = os.getenv("SMART_TMP") or "/tmp/smart_installer_test"

colors = { white = 1, red = 16384, lime = 32, cyan = 512, yellow = 16 }
term = {
  isColor = function() return true end, setTextColor = function() end,
  getCursorPos = function() return 1, 1 end, setCursorPos = function() end, clearLine = function() end,
}
local out = {}
print = function(...) local t = table.pack(...) for i = 1, t.n do t[i] = tostring(t[i]) end out[#out + 1] = table.concat(t, " ") end
write = function(s) out[#out + 1] = tostring(s) end
read = function() return "n" end
os.reboot = function() error("REBOOT") end

local function hp(p) return TMP .. "/" .. p:gsub("^/+", "") end
fs = {
  exists = function(p) local f = io.open(hp(p)) if f then f:close() return true end return os.execute("test -e '" .. hp(p) .. "'") == true end,
  getDir = function(p) return p:match("^(.*)/[^/]*$") or "" end,
  makeDir = function(p) os.execute("mkdir -p '" .. hp(p) .. "'") end,
  delete = function(p) os.execute("rm -rf '" .. hp(p) .. "'") end,
  list = function() return {} end,
  open = function(p, mode)
    local f = io.open(hp(p), mode:sub(1, 1) == "r" and "rb" or "wb")
    if not f then return nil end
    return { readAll = function() return f:read("a") end, write = function(s) f:write(s) end, close = function() f:close() end }
  end,
}

local remoteVersion = "1.2.0"
local fileGets = 0
http = {
  get = function(url)
    local body
    if url:find("api.github.com", 1, true) then body = string.rep("a", 40)
    elseif url:find("manifest.lua", 1, true) then
      body = 'return { version = "' .. remoteVersion .. '", files = { "smart/main.lua", "startup/smart.lua" } }'
    else
      fileGets = fileGets + 1
      body = "-- plik"
    end
    return { getResponseCode = function() return 200 end, readAll = function() return body end, close = function() end }
  end,
}

local failures = {}
local function check(c, m) if not c then failures[#failures + 1] = m end end
local function run(...)
  out, fileGets = {}, 0
  local fn = assert(loadfile(ROOT .. "/install.lua"))
  local ok, err = pcall(fn, ...)
  return ok, err, table.concat(out, "\n")
end
local function setLocal(v)
  os.execute("rm -rf " .. TMP .. " && mkdir -p " .. TMP .. "/smart")
  if v then local f = io.open(TMP .. "/smart/version.txt", "w") f:write(v) f:close() end
end
local function localVer() local f = io.open(TMP .. "/smart/version.txt") if not f then return nil end local v = f:read("a") f:close() return v end

-- 1. ta sama wersja -> nic nie pobiera
setLocal("1.2.0"); remoteVersion = "1.2.0"
local ok, err, txt = run("update")
check(ok, "update (ta sama wersja) blad: " .. tostring(err))
check(fileGets == 0, "update pobral pliki mimo najnowszej wersji (" .. fileGets .. ")")
check(txt:find("Masz najnowsza wersje: 1.2.0", 1, true), "brak komunikatu o najnowszej wersji")

-- 2. nowsza na GitHubie -> pobiera i zapisuje wersje
setLocal("1.1.3"); remoteVersion = "1.2.0"
ok, err = run("update")
check(ok and fileGets == 2, "update nie pobral nowszej wersji (" .. fileGets .. ")")
check(localVer() == "1.2.0", "nie zapisano nowej wersji: " .. tostring(localVer()))

-- 3. porownanie liczbowe: 1.10.0 jest nowsza niz 1.9.0
setLocal("1.9.0"); remoteVersion = "1.10.0"
ok = run("update")
check(fileGets == 2, "1.10.0 nie uznane za nowsze niz 1.9.0")

-- 4. starsza na GitHubie -> nic nie pobiera
setLocal("1.2.0"); remoteVersion = "1.1.3"
ok, err, txt = run("update")
check(ok and fileGets == 0, "pobrano starsza wersje")
check(txt:find("starsza", 1, true), "brak informacji o starszej wersji na GitHubie")

-- 5. force -> pobiera mimo tej samej wersji
setLocal("1.2.0"); remoteVersion = "1.2.0"
ok = run("update", "force")
check(fileGets == 2, "update force nie pobral plikow")

-- 6. instalacja od zera (brak version.txt) -> pobiera
setLocal(nil); remoteVersion = "1.2.0"
ok = run("install")
check(fileGets == 2, "install nie pobral plikow")

-- 7. install version: informacja o dostepnej aktualizacji
setLocal("1.1.0"); remoteVersion = "1.2.0"
ok, err, txt = run("version")
check(txt:find("Dostepna aktualizacja", 1, true), "version: brak informacji o aktualizacji")

if #failures > 0 then
  io.stdout:write("BLEDY (" .. #failures .. "):\n - " .. table.concat(failures, "\n - ") .. "\n")
  os.exit(1)
end
io.stdout:write("OK - instalator: wszystkie testy przeszly\n")
