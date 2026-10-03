-- Generuje manifest.lua (lista plikow pobieranych przez installer).
-- Uruchom z katalogu repo:  lua tools/make_manifest.lua 1.0.1 "opis zmiany" "kolejna zmiana"
local version = arg[1]
local changes = { table.unpack(arg, 2) }

if not version then
  local f = io.open("manifest.lua")
  if f then
    version = f:read("a"):match('version%s*=%s*"([^"]+)"')
    f:close()
  end
  version = version or "1.0.0"
end

local files = { "install.lua", "update.lua" }
local p = io.popen('find smart startup -type f -name "*.lua" -not -path "smart/data/*" | sort')
for line in p:lines() do files[#files + 1] = line end
p:close()

local out = { "-- Wygenerowane przez tools/make_manifest.lua - nie edytuj recznie", "return {",
  string.format("  version = %q,", version), "  files = {" }
for _, f in ipairs(files) do out[#out + 1] = string.format("    %q,", f) end
out[#out + 1] = "  },"
-- pliki dla Pocket Computera (pilot)
local pocketFiles = { "install.lua", "update.lua", "startup/smart.lua", "smart/lib/util.lua", "smart/lib/ui.lua", "smart/pocket.lua" }
out[#out + 1] = "  pocket = {"
for _, f in ipairs(pocketFiles) do out[#out + 1] = string.format("    %q,", f) end
out[#out + 1] = "  },"
if #changes > 0 then
  out[#out + 1] = "  changelog = {"
  for _, c in ipairs(changes) do out[#out + 1] = string.format("    %q,", c) end
  out[#out + 1] = "  },"
end
out[#out + 1] = "}"

local f = assert(io.open("manifest.lua", "w"))
f:write(table.concat(out, "\n") .. "\n")
f:close()
print("manifest.lua: wersja " .. version .. ", " .. #files .. " plikow")
