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
Jeśli masz już najnowszą wersję, nic nie jest pobierane (wersje porównywane liczbowo, np. 1.10 > 1.9).
`update force` wymusza ponowne pobranie wszystkich plików (np. naprawa uszkodzonej instalacji).
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
  Moduł **Menu konfiguracji** daje na monitorze dotykowym *dokładnie to samo menu* co na komputerze
  (z klawiaturą ekranową do wpisywania i opcjonalną blokadą PIN-em).
* **Na Pocket Computerze** – zakładka **Menu** w pilocie pokazuje pełne menu komputera bazy.

## Wygląd

*Ustawienia → Wygląd*: **nowoczesny** (domyślnie) albo **klasyczny** (dawne kolory CC).
Nowoczesny wygląd używa własnej palety kolorów i znaków rysujących CC (2×3 subpiksele na znak):
gładkie paski z zaokrąglonymi końcami, wykresy z siatką, okrągły wskaźnik energii, zaokrąglone przyciski
i karty, przełączniki WŁ/WYŁ, klawiatura ekranowa z odstępami. Dotyczy komputera, monitorów, paneli i pilota.

## Duży ekran komputera / pocketa

Rozmiar terminala ustawia się w configu CC: Tweaked (`term_sizes` → `computer` / `pocket_computer`),
nie da się go zmienić z programu – system sam go wykrywa. Monitory ten config nie dotyczy.

* **Komputer** – od 100 kolumn menu zajmuje kolumnę po lewej, a reszta ekranu to siatka **paneli z modułami**
  (domyślnie Energia, Alarmy, Przegląd bazy, Reaktor), działających na żywo i klikalnych jak monitory.
  *Ustawienia → Ekran komputera*: układ, liczba kolumn, szerokość menu, do 6 paneli.
* **Pocket** – zakładka Menu pobiera z bazy klatkę maks. 80×40 i rysuje ją na środku
  (pełne 240×135 to ~97 KB na każde odświeżenie przez rednet).
* Im większy terminal, tym mniejsze litery – CC mieści więcej znaków w tym samym oknie gry.

## Moduły ekranów

| Moduł | Co pokazuje |
|---|---|
| Przegląd bazy | energia, reaktory, magazyny, gracze, alarmy |
| Menu konfiguracji | pełne menu ustawień sterowane dotykiem; klawiatura ekranowa; blokada PIN-em pilota po bezczynności |
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

## Czat i AI (Ollama)

Wymaga **Chat Boxa** (Advanced Peripherals) podłączonego do komputera. *Menu → Czat i AI (Ollama)*.

Na czacie piszesz wiadomość zaczynającą się od słowa wyzwalającego (domyślnie `smart`):

| Wiadomość | Odpowiedź |
|---|---|
| `smart` / `smart pomoc` | lista komend |
| `smart status` | energia, reaktory, generacja, ME/RS, gracze, alarmy |
| `smart reaktor` | stan reaktorów fission |
| `smart alarmy` | aktywne alarmy |
| `smart <dowolne pytanie>` | odpowiedź AI z Ollamy (gdy włączona) |
| `$smart ...` | to samo, ale pytanie jest ukryte, a odpowiedź przychodzi tylko do ciebie |

Opcje: słowo wyzwalające, podpis odpowiedzi, „zawsze prywatnie”, lista graczy, którym bot odpowiada.

### Ollama

1. W menu: **AI włączone**, **Adres serwera** (np. `http://192.168.1.50:11434`), potem
   **Pobierz listę modeli / test połączenia** i wybierz **Model** (albo wpisz ręcznie).
2. Bot dołącza do pytania aktualne dane bazy (można wyłączyć), pamięta kilka ostatnich wymian z każdym graczem
   i odpowiada krótko po polsku. Długie odpowiedzi dzieli na kilka wiadomości (Chat Box ma 1 s przerwy między nimi).
3. **CC: Tweaked domyślnie blokuje adresy lokalne** (localhost, 192.168.x.x – reguła `$private`).
   W pliku `computercraft-server.toml` (config serwera, w świecie w `serverconfig/`) dodaj regułę
   **nad** regułą `$private` (pierwsza pasująca reguła wygrywa):

   ```toml
   [[http.rules]]
       host = "192.168.1.50"   # adres komputera z Ollama (albo "localhost", jeśli ta sama maszyna)
       action = "allow"
   ```

   i zrestartuj serwer. Jeśli Ollama działa na innym komputerze niż serwer, uruchom ją z `OLLAMA_HOST=0.0.0.0`.
4. Odpowiedź jest strumieniowana, więc nawet wolny model nie przekroczy limitu czasu CC (60 s bez danych).
   „Wyłącz myślenie” przyspiesza modele rozumujące (np. qwen3), a bloki `<think>` nigdy nie trafiają na czat.

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
4. Zakładka **Menu**: pełne menu komputera bazy – wszystko co na komputerze (monitory, urządzenia, alarmy,
   autocrafting, wyświetlacze, ustawienia, aktualizacja). Klikasz jak na komputerze, wpisujesz z klawiatury
   pocketa, **<< Pilot** wraca do zakładek. Każdy pocket ma własną sesję menu.

PIN chroni przed przypadkowym sterowaniem, ale wiadomości rednet nie są szyfrowane.
Ten sam PIN (najlepiej same cyfry) odblokowuje menu na monitorach z włączoną blokadą.

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
* Test instalatora (pomijanie aktualizacji przy najnowszej wersji, `force`, porównanie wersji):
  ```
  lua tests/installer_test.lua
  ```
