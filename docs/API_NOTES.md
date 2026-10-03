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
- Chat Box: `sendMessage(msg, {player=, prefix=, brackets=, bracketsColor=, range=})` → `true` | `nil, err` (cooldown!); `sendToast({title, message, player, prefix})`
- Powah (generyczne, dodatkowy typ): `energy_cell`, `ender_cell`, `furnator`, `magmator`, `thermo`, `solar_panel`, `uraninite_reactor`.
  Metody: **`getStoredEnergy()`** (docs błędnie `getEnergy`), `getMaxEnergy()`; reaktor: `isRunning`, `getFuel`, `getCarbon`, `getRedstone`, `getTemperature` (procenty)
- Create (przez AP): `fluid_tank.info()`, `blaze_burner.info()`, `basin.inputTanks()/outputTanks()`

## Mekanism 10.7

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
