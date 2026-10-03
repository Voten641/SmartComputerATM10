# Smart System ATM10

System monitoringu i sterowania bazą dla **CC: Tweaked** w paczce **All The Mods 10 – To The Sky**.
Wiele monitorów, każdy z własnym ekranem, klikalne menu konfiguracji na komputerze, automatyka reaktora,
alarmy oraz aktualizacja z GitHuba jedną komendą.

Zweryfikowane z kodem źródłowym: CC: Tweaked 1.120.2, Advanced Peripherals 0.8.1, Mekanism 10.7,
Create 6, CC:C Bridge 1.7.3 – szczegóły w [docs/API_NOTES.md](docs/API_NOTES.md).

## Instalacja (w grze)

Potrzebny jest **Advanced Computer** (kolorowy ekran + mysz) oraz **Advanced Monitory**.

```
wget https://raw.githubusercontent.com/Voten641/SmartComputerATM10/main/install.lua install.lua
install
```

Po restarcie komputera program uruchamia się sam (`startup/smart.lua`).

### Aktualizacja

```
update
```

Pobiera najnowszą wersję z GitHuba. Konfiguracja w `/smart/data/` zostaje nienaruszona.
Można też kliknąć *Ustawienia i aktualizacja → Aktualizuj teraz z GitHub* w menu.

Inne komendy instalatora: `install version`, `install repo <użytkownik/repo> [gałąź]`, `install uninstall`.

## Podłączenie

Wszystko łączysz **Wired Modemami** i kablem sieciowym (modem na bloku → prawy klik, aby go włączyć).
Każdy monitor i każda maszyna pojawią się automatycznie.

## Konfiguracja

* **Na komputerze** – menu klikane myszą:
  * *Monitory* – dla każdego monitora wybierasz moduł, źródło danych (konkretne urządzenie albo wszystkie),
    skalę tekstu, kolor, tytuł i opcje modułu. *Identyfikuj* pokazuje na monitorze jego nazwę.
  * *Urządzenia* – przyjazne nazwy, ukrywanie, lista metod peryferium.
  * *Alarmy i automatyka* – auto‑SCRAM reaktora, auto start/stop reaktora wg poziomu energii, alarmy,
    powiadomienia (Chat Box, speaker, sygnał redstone).
  * *Panel sterowania* – przełączniki redstone (strony komputera, Redstone Relay, RedRouter z CC:C Bridge).
* **Na monitorze** – nowy, nieprzypisany monitor pokazuje listę modułów: dotknij jednego, żeby go przypisać.

## Moduły ekranów

| Moduł | Co pokazuje |
|---|---|
| Przegląd bazy | energia, reaktory, magazyny, gracze, alarmy |
| Energia | Induction Matrix, Energy Cube, Powah, inne magazyny FE – bilans, czas do pełna, wykres |
| Reaktor fission | stan, temperatura, paliwo/chłodziwo/odpady, START/SCRAM, burn rate z monitora |
| Turbina / Boiler / Reaktor fusion | Mekanism Generators, przełączanie trybu zrzutu, wtrysk fusion |
| Magazyn ME/RS | AE2/RS przez ME/RS Bridge: zajętość, energia, CPU, przewijana lista przedmiotów z filtrem |
| Zbiorniki | Dynamic Tank, Create Fluid Tank, inne zbiorniki |
| Urządzenia (lista) | wszystko co podłączone: Powah, Create Stressometer, detektory, SPS, maszyny… |
| Gracze | Player Detector – kto online, kto w bazie |
| Zegar / pogoda | czas gry/rzeczywisty, pogoda, księżyc, biom, promieniowanie |
| Panel sterowania | duże przyciski przełączników redstone |
| Alarmy i dziennik | aktywne alarmy + historia zdarzeń |

## Zabezpieczenie reaktora

Gdy reaktor przekroczy limit (temperatura, uszkodzenie, odpady, chłodziwo, gorące chłodziwo), system robi
**SCRAM** i blokuje ponowny start do ręcznego **RESET** (przycisk na monitorze reaktora albo w menu alarmów).
Domyślnie SCRAM następuje przy jakimkolwiek uszkodzeniu lub temperaturze > 1000 K.

## Dla dewelopera

* Po zmianach wygeneruj manifest (lista plików pobieranych przez installer) i wypchnij na GitHuba:
  ```
  lua tools/make_manifest.lua 1.0.1 "Opis zmian"
  ```
* Test integracyjny (makieta API CC:T + fałszywe peryferia, symuluje dotyk monitorów i klikanie GUI):
  ```
  lua tests/harness.lua
  ```
