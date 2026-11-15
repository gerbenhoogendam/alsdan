# Als-Dan

ALS dit, DAN dat: regels voor een ESP32 maken in de browser, zonder te typen. Voor Gerben en zijn zoon (10),
met de onderdelen van de TinyTronics-bestelling (nov 2026).

## Zo werkt het

1. Dubbelklik op `start.command` (start een webserver op http://localhost:8321 en opent Chrome; Safari en Firefox kunnen geen USB).
2. **Eerste keer:** ESP32 aan de USB, klik *Zet de firmware op de ESP32* (één keer; daarna nooit meer).
3. Klik *Verbind*, kies de poort. Maak regels, klik *Stuur naar ESP32*. De ESP32 bewaart de regels in flash en doet ze ook zonder computer.

De firmware op de ESP32 is een kleine regel-interpreter (`firmware/alsdan/alsdan.ino`). De app stuurt tekstregels over USB
(115200 baud, zie de kop van het .ino-bestand voor het protocol) en krijgt sensorwaarden terug, zodat je in de app live ziet wat
de knop, de bewegingsmelder, de afstandssensor en het toverdraadje doen, en welke regel afgaat.

## Pinnenplan (ESP32 DevKit V1, 30 pinnen)

| Onderdeel | Pin(nen) | Aansluiten | Let op |
| --- | --- | --- | --- |
| Lampje (LED) | D2 (ingebouwd blauw), D25, D26, D33, D32… | lange poot aan de pin (220 Ω ertussen is netjes), korte poot GND | lamp-pinnen staan op de zachtste stand (~5 mA), dus zonder weerstand kan |
| Lichtring SK6812 | RX2 (= D16, data) | 5V → 3V3, GND → GND, DI → RX2; DO blijft leeg | Gerbens ring is gesoldeerd met **oranje op 5V, rood op GND, wit op DI** (rood is hier dus de min) |
| Luidspreker 4 Ω | D14 | via 220 Ω aan de pin, andere draad GND | zacht maar veilig; harder = PAM8403 ertussen |
| Bewegingsmelder (HW-740, AM312) | D27 | plus → VIN, seintje → D27, min → GND | op VIN, zodat 3V3 vrij blijft; halve minuut opwarmen. Van de kant met het zwarte blokje gezien, pinnetjes omlaag: links plus, midden seintje, rechts min (afgelezen van de foto, niet doorgemeten) |
| Afstandssensor VL53L1X | D21 (SDA), D22 (SCL) | VIN → 3V3, GND, SDA, SCL | |
| Microfoon INMP441 | D32 (SCK), D33 (WS), D35 (SD), vast | VDD → 3V3, GND → GND, SD → D35, SCK → D32, WS → D33; L/R blijft leeg | **alleen 3V3, nooit VIN**; firmware 2 |
| Knop | BOOT-knopje (GPIO 0) of D32 met de andere poot aan GND | | |
| Toverdraadje (aanraking) | D4, D13 | één los draadje | |
| Motor N20 | D18 + D19 | **alleen via een motordriver** (DRV8833, L9110S, TB6612) | nog bestellen |
| Grote LED 700 mA | D17 | **alleen via een logic-level MOSFET** (IRLZ44N) + 2,2 Ω 2 W aan VIN | nog bestellen |

## De pagina

Alles staat op één scherm, zonder schuiven (vanaf ongeveer 1120 × 600; smaller of lager schuift de pagina gewoon). Drie
kolommen: **1 Onderdelen** (de lijst, met een klein plaatje), **2 Aansluiten** en **3 Regels**. Alleen de lijst met
onderdelen en de lijst met regels schuiven als ze lang worden. Geen emoji's (Gerben, 14 nov 2026).

**Aansluiten** is één plaatje: links het echte onderdeel, rechts de ESP32 van achteren gezien (waar de pinnetjes uitsteken
en je de draadjes opsteekt, dus gespiegeld ten opzichte van de opdruk aan de voorkant), en elk draadje ertussen in zijn
eigen kleur, met op het draadje wat het is (plus, min, seintje). Eronder per draadje een regel: de kleur (kies de kleur die
je echt gebruikt, dan klopt het plaatje), wat het is en naar welke pin het gaat; daar kies je ook een andere pin. Wijs een
regel aan en alleen dat draadje blijft helder. De plaatjes staan in `web/parts.js`: foto's uit Gerbens eigen foto's
(`web/parts/`: bewegingsmelder, lichtring met de gesoldeerde draadjes, grote LED) en tekeningen voor de rest. Een nieuw
onderdeel met een foto: de uitsnede in `web/parts/`, en in `parts.js` de maat en per draadje het punt waar het begint.

GND zit twee keer op het bordje: een onderdeel krijgt de GND aan zijn eigen kant, is die bezet de andere, en pas daarna
wordt er gedeeld (`plan()` in `logic.js`). Moeten er meer draadjes op één pin, dan zegt de pagina dat ze samen in een
lasdop moeten. De grote lamp en de motor krijgen geen draadjes naar het bordje getekend zolang de MOSFET of de driver er
niet is; bij de luidspreker staat de weerstand in het draadje getekend.

De pinnen zijn per onderdeel te veranderen; het plaatje volgt mee. Andere ESP32-bordjes (38 pinnen, C3, S3) hebben andere
pinnen en voor de C3/S3 een andere firmware-build.

## Firmware opnieuw bouwen

```
./scripts/build-firmware.sh          # arduino-cli, ESP32 core 3.3 (met ESP_I2S), Adafruit NeoPixel, Pololu VL53L1X
node --test web/test/                # de app-logica (protocol, voorbeelden, vrije pinnen)
```

Rechtstreeks uploaden zonder de webapp: `arduino-cli upload -p /dev/cu.usbserial-XXXX --fqbn esp32:esp32:esp32 firmware/alsdan`.
Meekijken: `screen /dev/cu.usbserial-XXXX 115200`, typ `HELLO`.

## Getest (7 nov 2026)

Gerbens bordje: klassieke ESP32-D0WD-V3 met een CP2102 USB-chip (`/dev/cu.usbserial-0001`), dus een DevKit V1-type.
`python3 scripts/test-firmware.py` draait 21 controles tegen het echte bordje (opstarten, HELLO, foutmeldingen, programma
laden en bewaren, EVERY-regel, sensorwaarden, testknoppen, BOOT-knopje nagebootst via DTR, herstart): alle 21 goed, ook
met de build waarin lamp-pinnen op de zachtste stand staan (`gpio_set_drive_capability`, ~5 mA).
Nog niet door een mens gezien: de lichtring, de luidspreker, de bewegingsmelder, de afstandssensor en het toverdraadje met
de echte onderdelen eraan; de app zelf in Chrome met de USB-verbinding (de logica is wel getest).

14 nov 2026, de pagina op één scherm met het aansluitplaatje: in de ingebouwde browser bekeken op 1440 × 820 en 1280 × 720
(niets schuift, bij alle elf onderdelen blijft de tekst binnen het vak), elk onderdeel van dichtbij, en kleur kiezen, pin
kiezen, aanwijzen, de venstertjes en hernoemen door een script. Niet nagekeken: welk pinnetje van de bewegingsmelder plus
is (afgeleid van waar de spanningsregelaar zit) en of het rode draadje van de ring echt op GND zit en niet ook DO of 5V
raakt (op de foto lopen de soldeerbolletjes in elkaar over). De firmware is niet veranderd.

### Microfoon (14 nov 2026, firmware 2)

De INMP441 (rond bordje, pinnen L/R, WS, SCK en SD, VDD, GND) is een onderdeel in de app: "ALS Microfoon hoort iets harder dan
60" (0 = stil, 100 = pijnlijk hard), met het voorbeeld *Klap voor licht*. De firmware leest hem via I2S zonder ergens op te
wachten, neemt per 20 ms de grootste uitslag van dal tot top en zet die op een decibelschaal; de app toont 4 keer per seconde
het hardste van dat moment, zodat je de grens zelf kunt kiezen. De ESP32 meldt zich nu als `HI alsdan 2`; staat er nog
versie 1 op en zit er een microfoon in het programma, dan vraagt de app om nieuwe firmware.

**Gebouwd, niet getest op het bordje:** de ESP32 zat niet aan de Mac. `web/firmware/` bevat firmware 2 (ook de knop *Zet de
firmware op de ESP32* zet die erop); `firmware/getest/alsdan-v1.bin` is de laatste die wel op het bordje getest is.
`scripts/test-firmware.py` heeft de controles voor de microfoon al (onderdeel wordt aangenomen, een tweede geeft een fout,
er komen waarden van 0 tot 100, een regel met grens 101 gaat niet af) en is nog niet gedraaid. De schaal komt uit het
gegevensblad (-26 dBFS bij 94 dB: praten op een meter rond 30, een klap vlakbij 75 of meer) en is niet nagemeten met de echte
microfoon. L/R blijft los: de firmware leest beide kanalen en neemt het hardste; werkt dat niet stabiel, verbind L/R dan
met GND.

## Als de poort niet verschijnt

Brandt het lampje op het bordje maar ziet de Mac niets (geen `cu.usbserial…`)? Dat was hier twee keer zo. Kijk of macOS een
melding "Accessoire toestaan?" toont (Apple-silicon-laptops geven een nieuw USB-apparaat pas data na goedkeuring:
Systeeminstellingen › Privacy en beveiliging › Sta accessoires toe om verbinding te maken), probeer een andere kabel (veel
micro-USB-kabels zijn alleen voor laden) en steek hem rechtstreeks in de Mac.

## Bekende beperking

- Een WAIT-stap blokkeert: tijdens het wachten reageren andere regels niet (hooguit 10 s).
