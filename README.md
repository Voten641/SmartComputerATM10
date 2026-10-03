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
| Energia | zakładka **Energia**: magazyny FE, bilans chwilowy i **uśredniony** (okno 30 s–30 min), stabilny czas do pełna/rozładowania, wykres; zakładka **Źródła**: wszystkie źródła energii ze stanem, produkcją i przyciskami (reaktory WŁ/WYŁ/RESET + burn rate, fusion wtrysk, turbina tryb zrzutu, generatory Mekanism WŁ/WYŁ, Powah) oraz przełączniki redstone z tagiem `energia` |
| Reaktor fission | stan, temperatura, paliwo/chłodziwo/odpady, START/SCRAM, burn rate z monitora |
| Turbina / Boiler / Reaktor fusion | Mekanism Generators, przełączanie trybu zrzutu, wtrysk fusion |
| Magazyn ME/RS | AE2/RS przez ME/RS Bridge: zajętość, energia, CPU, przewijana lista przedmiotów z filtrem |
| Wyszukiwarka ME/RS | klawiatura na monitorze, wyszukiwanie i **wydawanie przedmiotów do skrzyni** (1/16/64/576) |
| Autocrafting | stan utrzymywanych zapasów (ile jest / ile ma być / craftowanie / brak wzoru) |
| Create (stres / RPM) | Stressometer, Speedometer, sterowanie Rotation Speed Controller z monitora |
| Przepływy | Energy / Fluid / Gas Detector – przepływ, limit, zmiana limitu z monitora |
| Promieniowanie | poziom wg skali Mekanism (LOW…EXTREME), wykres 6h w skali logarytmicznej |
| Wykresy historii | energia, generacja, ME/RS, stres Create, promieniowanie, temp. reaktora – 1h/6h/24h, zapisane na dysku |
| Zbiorniki | Dynamic Tank, Create Fluid Tank, inne zbiorniki |
| Urządzenia (lista) | wszystko co podłączone: Powah, Create Stressometer, detektory, SPS, maszyny… |
| Gracze | Player Detector – kto online, kto w bazie |
| Zegar / pogoda | czas gry/rzeczywisty, pogoda, księżyc, biom, promieniowanie |
| Panel sterowania | duże przyciski przełączników redstone |
| Alarmy i dziennik | aktywne alarmy + historia zdarzeń |

## Tagi

Urządzeniom i przełącznikom redstone można nadać tagi (*Menu → Urządzenia* / *Panel sterowania*).
Tag `energia` sprawia, że urządzenie lub przełącznik pojawia się w zakładce **Źródła** na ekranie energii
(np. przełącznik włączający generatory redstonem albo magazyn, który nie został rozpoznany automatycznie).

### Łączenie przełącznika z urządzeniem

W *Menu → Panel sterowania → (przełącznik)* ustaw **Połącz z urządzeniem** (np. reaktor). Na zakładce
**Źródła** przełącznik pokazuje się w bloku tego urządzenia, a nie osobno. Przy włączonym
**steruj razem z urządzeniem** przycisk WŁĄCZ/WYŁĄCZ urządzenia przełącza też redstone – również przy
automatycznym SCRAM i auto start/stop. Bez tej opcji przełącznik ma własny przycisk w bloku urządzenia.

### Potwierdzenie kliknięcia

Po dotknięciu przycisku na monitorze glośnik (Speaker w sieci) gra wysoki dźwięk przy sukcesie i niski przy
błędzie, a na dole ekranu pojawia się zielony/czerwony pasek z opisem (np. „Wlaczono: Reaktor”).
Dźwięk można wyłączyć w *Ustawieniach*.

Generatory i maszyny Mekanism są włączane/wyłączane przez tryb redstone (WŁ = „ignoruj redstone”,
WYŁ = „wymaga sygnału”); wymaga to publicznego trybu security maszyny.

## Autocrafting

*Menu → Autocrafting (ME/RS)*: dodajesz przedmioty (wyszukiwanie w magazynie albo po ID), ustawiasz ile ma być
w magazynie i jaką partią craftować. System co kilka sekund sprawdza stan i zleca crafting, jeśli brakuje
i nic się już nie craftuje. Wymaga wzorów (patterns) w AE2/RS.

## Wyświetlacze Create

Postaw **Source Block** (CC:C Bridge) przy modemie, połącz go **Display Linkiem** z Flap Display / Nixie Tube /
innym wyświetlaczem Create. W *Menu → Wyświetlacze Create* wybierasz, co pokazuje każda linia
(energia, reaktor, generacja, ME, stres, gracze, promieniowanie, alarmy, czas, własny tekst).

## Pilot – Pocket Computer

1. Na komputerze bazy: modem bezprzewodowy (najlepiej **Ender Modem**) + *Menu → Pilot*: włącz i ustaw PIN.
2. Na Advanced Pocket Computer z Ender Modemem wpisz te same komendy instalacji co na komputerze –
   instalator sam wykryje Pocket i zainstaluje tylko pilota.
3. Pilot: stan bazy, START/SCRAM/RESET i burn rate reaktorów, przełączniki redstone, alarmy.

PIN chroni przed przypadkowym sterowaniem, ale wiadomości rednet nie są szyfrowane.

## Reaktor: podłącz Logic Adapter, nie Reactor Port

W Mekanism 10.7 **Fission/Fusion Reactor Port** nie udostępnia komputerowi danych reaktora (tylko tryb portu).
Modem musi stać na **Reactor Logic Adapterze**. System wykrywa podłączony port i wyświetla podpowiedź.

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
