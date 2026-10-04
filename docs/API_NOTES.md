# Zweryfikowane API (źródła modów, nie pamięć)

Sprawdzone bezpośrednio w kodzie źródłowym tagów:

| Mod | Wersja / tag |
|---|---|
| CC: Tweaked | `v1.21.1-1.120.2` |
| Advanced Peripherals | `1.21.1-0.8.1a` (+ docs branch `0.8`) |
| CC:C Bridge | `v1.7.3-1.21.1` |
| Mekanism | `v1.21.1-10.7.19.85` |
| Create | `mc1.21.1/dev` (6.0.x) |

Gdy dokumentacja i kod się różnią, **obowiązuje kod**.

## CC: Tweaked 1.120.2

- Cobalt = Lua 5.2. **Nie ma** `//`, operatorów bitowych ani integer subtype (używaj `math.floor`, `bit32`). `goto` działa.
- `peripheral.getType(name)` zwraca wiele typów (główny + dodatkowe).
- Peryferia generyczne (dodatkowe typy): `energy_storage` (`getEnergy`, `getEnergyCapacity` – **int**, obcina do 2^31),
  `fluid_storage` (`tanks()` → `{[i]={name, amount}}`, brak pojemności), `inventory` (`size`, `list`, `getItemDetail`...).
  Główny typ = id block entity (np. `powah:energy_cell`).
- **Generyczne peryferia NIE są dodawane, jeśli blok ma własne peryferium** (np. maszyny Mekanism mają tylko API Mekanism).
- `redstone_relay` (od 1.114): `setOutput/getOutput/getInput/setAnalogOutput/getAnalogOutput/getAnalogInput/...bundled`.
  Strony: `top bottom left right front back`.
- Monitor `setTextScale`: wielokrotność 0.5 w zakresie 0.5–5.
- Speaker `playNote(instrument, volume 0–3, pitch 0–24)`, instrumenty m.in. `bell`, `pling`, `bit`, `chime`.
- Pliki startowe: `startup.lua` **oraz** wszystkie pliki z katalogu `startup/`.
- Rozmiar terminala: config `term_sizes.computer` / `term_sizes.pocket_computer` (width/height, znaki) oraz
  `term_sizes.monitor` (maks. rozmiar monitora w blokach). Z Lua nie da sie go zmienic – tylko `getSize()`.
- **HTTP**: domyslne reguly `http.rules`: `$private` = DENY (localhost, 10/8, 172.16/12, 192.168/16...), potem `*` = ALLOW.
  Reguly sprawdzane po kolei, **pierwsza pasujaca akcja wygrywa** (`PartialOptions.merge`); `host` to domena, IP
  albo CIDR. Plik: `computercraft-server.toml`. `http.get/post{ url, body, headers, timeout }` – timeout domyslnie
  30 s, maks. 60 s, liczony jako brak danych (ReadTimeoutHandler). Blad: `nil, komunikat, odpowiedz`.
- Ollama `/api/chat`: `tools = [{type="function", function={name, description, parameters}}]`; odpowiedz
  `message.tool_calls[].function.{name, arguments}` (arguments = obiekt, takze przy stream=true); wynik odsylamy
  jako `{role="tool", tool_name, content}` po wiadomosci asystenta z `tool_calls`. Model bez narzedzi zwraca blad
  "... does not support tools" (HTTP 400) – wtedy ponawiamy bez `tools`.
- `textutils.serialiseJSON(t, { unicode_strings = true })` – stringi traktowane jako UTF-8 (od 1.106);
  `unserialiseJSON` zamienia `\uXXXX` na UTF-8.
- `window.getLine(y)` → `text, fg, bg` (stringi blit, od 1.84) – uzywane do wysylania klatek menu na pilota.
- **Znaki rysujace 128–159** (sprawdzone na `term_font.png`): mozaika 2x3 subpikseli, znak = `128 + bity`,
  bity TL=1, TR=2, ML=4, MR=8, BL=16; prawy dolny subpiksel zawsze w kolorze tla (dla "zapalonego" trzeba
  zamienic kolory). Glif 6x9 px, wiec subpiksel = 3x3 px – kola sa okragle. Symbole: 16 ►, 17 ◄, 30 ▲, 31 ▼,
  7 •, 19 ‼, 26 →, 140 = linia pozioma, 149 = lewa polowa komorki.
- **Paleta**: `setPaletteColour(colour, 0xRRGGBB)` na terminalu/monitorze/oknie; `term.nativePaletteColour(c)`
  daje domyslny kolor. `window.create` kopiuje palete rodzica w chwili tworzenia i naklada ja przy redraw –
  palete ustawiamy na monitorze/terminalu przed tworzeniem okien.

## Advanced Peripherals 0.8.1

**Breaking względem 0.7:** typy w snake_case; **Redstone Integrator usunięty** (nie ma go w `APBlocks` – strona docs jest
nieaktualna) → używaj `redstone_relay` z CC:T; chatbox bez `sendMessageToPlayer` (opcja `player`).

Typy: `me_bridge`, `rs_bridge`, `player_detector`, `environment_detector`, `energy_detector`, `fluid_detector`,
`gas_detector`, `chat_box`, `geo_scanner`, `inventory_manager`, `block_reader`, `nbt_storage`, `colony_integrator`,
`distance_detector`, `smart_rail`.

Wyłączone w configu peryferium ma metodę `peripheralDisabled` (sprawdzaj czy istnieje).

### ME / RS Bridge (wspólne API)
Na brak połączenia zwraca `nil, "NOT_CONNECTED"`.
- `isConnected()`, `isOnline()` → bool
- `getItems(filter?)`, `getFluids(filter?)`, `getChemicals(filter?)` → lista stosów `{name, count, displayName, maxStackSize, nbt, tags, isCraftable, ...}`
- `getMaxItemStorage()`, `getUsedItemStorage()`, `getAvailableItemStorage()` (+ Fluid/Chemical; **AE2 = bajty, RS = sztuki/mB**)
- `get{Max,Used,Available}ExternalItemStorage/Count`, ... (w docs błędnie `Extern`)
- `getStoredEnergy()`, `getEnergyCapacity()`, `getEnergyUsage()`, `getAverageEnergyInput()` (w docs błędnie `getAvgPowerInjection`) – ME: jednostki AE
- `getCraftingTasks()`, `getCraftingTask(id)`, `craftItem(filter)`, `isCraftable(filter)`, `isCrafting(filter)`, `getPatterns()`, `getCells()`, `getDrives()`
- ME: `getCraftingCPUs()` → `{storage, coProcessors, isBusy, craftingJob, name, selectionMode}`; RS: `getCrafters()`
- eventy `me_crafting` / `rs_crafting` (error, id, message)

### Pozostałe
- Energy/Fluid/Gas Detector: `getTransferRate()`, `getTransferRateLimit()`, `setTransferRateLimit(n)`, `getMaxTransferRate()`
- Player Detector: `getOnlinePlayers()`, `getPlayersInRange(r)`, `getPlayer(name)` (dawne getPlayerPos), `isPlayersInRange(r)`...; eventy `player_join`, `player_leave`, `player_click`, `player_death`
- Environment Detector: `getBiome`, `getTime`, `getDimension`, `getMoon()` → `id, name`, `isRaining`, `isThunder`, `isSunny`, `isSlimeChunk`, `getRadiation()` / `getRadiationRaw()` (z Mekanism)
- Chat Box: `sendMessage(msg, {player=, prefix=, brackets=, bracketsColor=, range=, utf8=})` → `true` | `nil, err`;
  cooldown 1000 ms (`"... is on cooldown"`), maks. 1024 znakow (`chatBoxMessageSize`). `sendToast({title, message, player, prefix})`.
  Event `chat`: `uuid, username, message, isHidden, utf8Message`. Wiadomosc z `$` na poczatku: AP usuwa `$`,
  ustawia `isHidden = true` i ukrywa ja na czacie. Zasieg: `chatBoxMaxRange` (domyslnie -1 = wszedzie).
- Powah (generyczne, dodatkowy typ): `energy_cell`, `ender_cell`, `furnator`, `magmator`, `thermo`, `solar_panel`, `uraninite_reactor`.
  Metody: **`getStoredEnergy()`** (docs błędnie `getEnergy`), `getMaxEnergy()`; reaktor: `isRunning`, `getFuel`, `getCarbon`, `getRedstone`, `getTemperature` (procenty)
- Create (przez AP): `fluid_tank.info()`, `blaze_burner.info()`, `basin.inputTanks()/outputTanks()`

## Mekanism 10.7

- **Reactor Porty (`fissionReactorPort`, `fusionReactorPort`) NIE udostepniaja reaktora** – nadpisuja
  `exposesMultiblockToComputer()` na `false`, wiec maja tylko `getMode/setMode/incrementMode/decrementMode`
  (bez `isFormed`, temperatury, `scram`...). Dane i sterowanie reaktora: **wylacznie Logic Adapter**.
  Pozostale multibloki (zawory turbiny/boilera/tanku, Induction Port, SPS Port, Evaporation Valve) udostepniaja dane normalnie.
- Typy (camelCase): `fissionReactorLogicAdapter`, `fissionReactorPort`, `turbineValve`, `boilerValve`, `inductionPort`,
  `fusionReactorLogicAdapter`, `fusionReactorPort`, `dynamicValve`, `spsPort`, `thermalEvaporationValve`,
  `thermalEvaporationController`, `{basic,advanced,elite,ultimate,creative}EnergyCube`, `...ChemicalTank`, `...FluidTank`, `industrialAlarm`, `qioDriveArray`...
- **Energia w Joulach.** Konwersja: globalne `mekanismEnergyHelper.joulesToFE(j)` (kurs z configu, domyślnie 2.5 J = 1 FE).
- Wspólne: `getEnergy`, `getMaxEnergy`, `getEnergyNeeded`, `getEnergyFilledPercentage` (0–1), `getComparatorLevel`.
- Multibloki: `isFormed()`; **pozostałe metody multibloku istnieją tylko gdy struktura jest uformowana.**
  `getLength/getWidth/getHeight`, `getMinPos/getMaxPos` → `{x,y,z}` (do wykrywania duplikatów portów).
- Wrapper zbiorników: `getX()` (`{name, amount}`), `getXCapacity()`, `getXNeeded()`, `getXFilledPercentage()` (0–1).
- Fission: `getStatus()` (bool), `activate()`, `scram()`, `getTemperature()` (K), `getDamagePercent()` (0–100), `getBurnRate`,
  `setBurnRate(r)`, `getActualBurnRate`, `getMaxBurnRate`, `getHeatingRate`, `getEnvironmentalLoss`, `isForceDisabled`,
  zbiorniki `Fuel`, `Waste`, `HeatedCoolant`, `Coolant` (`getCoolantFilledPercentage`, ...).
  `activate` rzuca błąd gdy już działa, `scram` gdy wyłączony.
- Turbine: `getProductionRate`, `getMaxProduction` (J/t), `getFlowRate`, `getMaxFlowRate`, `getLastSteamInputRate`,
  `getDumpingMode()` (`IDLE`/`DUMPING_EXCESS`/`DUMPING`), `setDumpingMode`, `incrementDumpingMode`, `getBlades`, `getCoils`, `getVents`, zbiornik `Steam`.
- Boiler: `getTemperature`, `getBoilRate`, `getMaxBoilRate`, `getBoilCapacity`, `getSuperheaters`, zbiorniki `Water`, `Steam`, `HeatedCoolant`, `CooledCoolant`.
- Induction: `getLastInput`, `getLastOutput`, `getTransferCap` (J/t), `getInstalledCells`, `getInstalledProviders`.
- Fusion: `isIgnited`, `getPlasmaTemperature`, `getCaseTemperature`, `getInjectionRate`, `setInjectionRate`,
  `getProductionRate`, `getPassiveGeneration(bool)`, zbiorniki `Deuterium`, `Tritium`, `DTFuel`, `Water`, `Steam`.
- Dynamic Tank: `getStored()`, `getTankCapacity()`, `getChemicalTankCapacity()`, `getFilledPercentage()`.
- SPS: `getProcessRate`, `getCoils`, zbiorniki `Input`, `Output`. Evaporation: `getTemperature`, `getProductionAmount`, `getActiveSolars`, zbiorniki `Input`, `Output`.
- Setery wymagają publicznego security maszyny.

## Create 6 (wbudowane)
`Create_Stressometer` (`getStress`, `getStressCapacity`), `Create_Speedometer` (`getSpeed`),
`Create_RotationSpeedController` (`getTargetSpeed`, `setTargetSpeed`), `Create_CreativeMotor`, `Create_DisplayLink`,
`Create_StockTicker`, `Create_Station`, `Create_NixieTube`...

## CC:C Bridge 1.7.3
`create_source` (terminal dla wyświetlaczy Create), `create_target` (`getLine(y)`, `dump()`, `resize(w,h)`, `getSize()`),
`redrouter` (API jak redstone, strony względem bloku), `scroller` (`getValue`, `setValue`, `setLock`, `isLocked`,
`getLimit`, `setLimit`; event `scroller_changed`; w docs przykład błędnie `setLocked`), `animatronic`.

## Dodatkowo zweryfikowane (v1.1)

- AP crafting: `craftItem(filter[, cpuName])` – filtr `{name=, count=}`, zwraca obiekt joba lub `nil, "NOT_CRAFTABLE"`;
  `isCrafting(filter[, cpu])` – filtr generyczny: `{type="item", name=}` (bez `type` rozpoznaje po rejestrze);
  `getItem({name=})` → stos lub `nil, err` (pusty filtr = `EMPTY_FILTER`).
- AP `exportItem(target, filter)` – target: nazwa peryferium w sieci CC (`minecraft:chest_0`) albo `@up/@north/...`;
  zwraca liczbe przeniesionych sztuk lub `nil, "INVENTORY_NOT_FOUND"`. Domyslnie 64 szt. (pole `count`).
- Create: `Create_RotationSpeedController.setTargetSpeed(int)` – zakres `±maxRotationSpeed` (domyslnie 256), clamp w grze.
  Eventy: `overstressed(name)`, `stress_change(name, stress, capacity)`, `speed_change(name, speed)`.
- Detektory AP: `getTransferRate()`, `getTransferRateLimit()`, `setTransferRateLimit(long)`, `getMaxTransferRate()` (long).
  Typy: `energy_detector` (FE/t), `fluid_detector` (mB/t), `gas_detector` (mB/t).
- Promieniowanie: `environment_detector.getRadiationRaw()` → Sv/h (tylko z Mekanism). Skala Mekanism:
  `<1e-5` brak, `<1e-3` LOW, `<0.1` MEDIUM, `<10` ELEVATED, `<100` HIGH, wyzej EXTREME. Tlo = 1e-7.
- CC:C Bridge `create_source`: pelne `TermMethods` CC:T (write/setCursorPos/clear/clearLine/getSize/...), kolory ignorowane,
  rozmiar startowy 4x2 do czasu ustawienia przez Display Link, event `monitor_resize`.
- rednet (CC:T 1.120.2): `open(modem)`, `host(protocol, hostname)`, `lookup(protocol[, hostname[, timeout=2]])`,
  `send(id, msg, protocol)`, `receive(protocol, timeout)`; event `rednet_message(sender, message, protocol)`.
  BIOS uruchamia `rednet.run` rownolegle z shellem. Pocket computer: globalne API `pocket`.
