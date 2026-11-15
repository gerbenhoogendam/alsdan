// Als-Dan firmware: een regel-interpreter voor de ESP32 (Arduino core 3.x).
// De browser-app stuurt onderdelen en regels over USB-serieel (115200 baud).
// De ESP32 voert ze uit en bewaart ze in flash, dus ook zonder computer blijft
// hij ze doen. Eén keer flashen, daarna nooit meer compileren.
//
// Naar de ESP32 (iedere regel eindigt op \n):
//   HELLO                          -> HI alsdan 2 <chip>   (2: met de microfoon)
//   PROG                           begin van een nieuw programma
//   D <i> <TYPE> <pinnen...>       onderdeel i: LED p | RING p n | PIR p | TOF sda scl | SPK p | MOT a b | BTN p | TCH p | MIC sck ws sd
//   R <ALS> ; <DAN> ; <DAN> ...    regel: eerst de trigger, dan de stappen gescheiden door ;
//   RUN                            programma toepassen en bewaren  -> OK ... of ERR ...
//   X <DAN>                        één stap nu uitvoeren (testknop)
// ALS:  START | EVERY ms | PRESS d | RELEASE d | MOTION d | STILL d | NEAR d cm | FAR d cm | TOUCH d | UNTOUCH d | LOUD d n
// DAN:  SET d pct | BLINK d ms | COLOR d r g b | RAINBOW d | SPIN d r g b | BEEP d hz ms | TUNE d n | MOTOR d speed | WAIT ms
// Van de ESP32:  S <d> <waarde> (sensorwaarden, 4x per seconde; microfoon: het hardste sinds de vorige keer, 0-100)   E <regel> (regel ging af)   L <tekst> (melding)

#include <Preferences.h>
#include <Wire.h>
#include <Adafruit_NeoPixel.h>
#include <VL53L1X.h>
#include <ESP_I2S.h>
#include "driver/gpio.h"

#define MAX_DEV 16
#define MAX_RULES 32
#define PROG_SIZE 3900  // shortcut: NVS bewaart hooguit ~4000 bytes per sleutel; langer -> ERR, splitsen als dat ooit gebeurt

enum Type : uint8_t { NONE, LED, RING, PIR, TOF, SPK, MOT, BTN, TCH, MIC };
enum Trig : uint8_t { T_START, T_EVERY, T_PRESS, T_RELEASE, T_MOTION, T_STILL, T_NEAR, T_FAR, T_TOUCH, T_UNTOUCH, T_LOUD };

struct Dev {
  Type type = NONE;
  int8_t pin = -1, pin2 = -1;
  int32_t val = 0, prev = 0;  // BTN/PIR/TCH: 0/1, TOF: cm of -1, MIC: hoe hard 0-100
  int32_t raw = 0;            // BTN: vorige ruwe knopstand (ontdender); MIC: het hardste sinds de vorige melding
  uint32_t base = 0;          // TCH: ruststand
  uint8_t mode = 0;           // LED: 0 vast 1 knipper; RING: 0 vast 1 regenboog 2 draai
  uint16_t period = 500;
  uint8_t r = 0, g = 0, b = 0;
  uint32_t t0 = 0;
  bool on = false;
  Adafruit_NeoPixel* ring = nullptr;
  VL53L1X* tof = nullptr;
};

struct Rule {
  Trig trig;
  uint8_t dev;
  int32_t arg;
  uint32_t last;
  bool state, primed;
  const char* actions;
};

static Dev dev[MAX_DEV];
static Rule rules[MAX_RULES];
static int nRules = 0;
static char incoming[PROG_SIZE];  // wordt ontvangen
static size_t inLen = 0;
static bool receiving = false;
static char prog[PROG_SIZE];      // actief programma (in stukken geknipt)
static bool pendingStart = false;
static Preferences prefs;
static I2SClass i2s;  // de microfoon; de ESP32 heeft één ingang die we hiervoor gebruiken
static bool micOn = false;

// ---- uitvoer --------------------------------------------------------------

static Dev* devOf(int i, Type t) {
  if (i < 0 || i >= MAX_DEV || dev[i].type != t) return nullptr;
  return &dev[i];
}

static void setLed(Dev& d, int pct) {
  pct = constrain(pct, 0, 100);
  ledcWrite(d.pin, pct * 255 / 100);
}

static void setMotor(Dev& d, int speed) {
  speed = constrain(speed, -100, 100);
  ledcWrite(d.pin, speed > 0 ? speed * 255 / 100 : 0);
  ledcWrite(d.pin2, speed < 0 ? -speed * 255 / 100 : 0);
}

static void tickOutputs() {
  uint32_t now = millis();
  for (Dev& d : dev) {
    if (d.type == LED && d.mode == 1 && now - d.t0 >= d.period) {
      d.t0 = now;
      d.on = !d.on;
      setLed(d, d.on ? 100 : 0);
    } else if (d.type == RING && d.ring && d.mode && now - d.t0 >= 30) {
      d.t0 = now;
      int n = d.ring->numPixels();
      for (int i = 0; i < n; i++) {
        if (d.mode == 1) {
          d.ring->setPixelColor(i, d.ring->ColorHSV((uint16_t)(now * 20 + i * 65536 / n)));
        } else {
          int head = (now / 60) % n, back = (i - head + n) % n;  // staart van drie achter de kop
          int div = back == 0 ? 1 : back == n - 1 ? 4 : back == n - 2 ? 16 : 0;
          d.ring->setPixelColor(i, div ? d.ring->Color(d.r / div, d.g / div, d.b / div) : 0);
        }
      }
      d.ring->show();
    }
  }
}

static void wait(uint32_t ms) {
  uint32_t t = millis();
  if (ms > 10000) ms = 10000;
  while (millis() - t < ms) { tickOutputs(); delay(2); }
}

static void tune(Dev& d, int n) {
  static const uint16_t tada[] = { 523, 659, 784, 1047 }, alarm[] = { 880, 440, 880, 440, 880, 440 }, oei[] = { 784, 659, 523, 392 };
  const uint16_t* notes = n == 1 ? alarm : n == 3 ? oei : tada;
  int count = n == 1 ? 6 : 4;
  if (n == 2) {  // sirene: op en neer
    for (int f = 400; f < 1200; f += 25) { ledcWriteTone(d.pin, f); wait(8); }
    for (int f = 1200; f > 400; f -= 25) { ledcWriteTone(d.pin, f); wait(8); }
  } else {
    for (int i = 0; i < count; i++) { ledcWriteTone(d.pin, notes[i]); wait(n == 1 ? 150 : 120); }
  }
  ledcWriteTone(d.pin, 0);
}

static void runActions(const char* s) {
  while (s && *s) {
    const char* end = strchr(s, ';');
    char buf[64];
    size_t len = end ? (size_t)(end - s) : strlen(s);
    if (len >= sizeof(buf)) len = sizeof(buf) - 1;
    memcpy(buf, s, len);
    buf[len] = 0;
    s = end ? end + 1 : nullptr;

    char w[12];
    int a = 0, b = 0, c = 0, e = 0;
    if (sscanf(buf, "%11s %d %d %d %d", w, &a, &b, &c, &e) < 1) continue;
    Dev* d;
    if (!strcmp(w, "WAIT")) wait(a);
    else if (!strcmp(w, "SET") && (d = devOf(a, LED))) { d->mode = 0; setLed(*d, b); }
    else if (!strcmp(w, "BLINK") && (d = devOf(a, LED))) { d->mode = 1; d->period = max(b, 50); d->t0 = millis(); d->on = true; setLed(*d, 100); }
    else if (!strcmp(w, "COLOR") && (d = devOf(a, RING)) && d->ring) { d->mode = 0; d->ring->fill(d->ring->Color(b, c, e)); d->ring->show(); }
    else if (!strcmp(w, "RAINBOW") && (d = devOf(a, RING))) { d->mode = 1; d->t0 = 0; }
    else if (!strcmp(w, "SPIN") && (d = devOf(a, RING))) { d->mode = 2; d->r = b; d->g = c; d->b = e; d->t0 = 0; }
    else if (!strcmp(w, "BEEP") && (d = devOf(a, SPK))) { ledcWriteTone(d->pin, b); wait(c); ledcWriteTone(d->pin, 0); }
    else if (!strcmp(w, "TUNE") && (d = devOf(a, SPK))) tune(*d, b);
    else if (!strcmp(w, "MOTOR") && (d = devOf(a, MOT))) setMotor(*d, b);
    else Serial.printf("L onbekende stap: %s\n", buf);
  }
}

// ---- invoer ---------------------------------------------------------------

// Hoe hard het geluid is, van 0 (stil) tot 100 (pijnlijk hard), uit de uitslag van de microfoon (INMP441, de bovenste 16
// van zijn 24 bits). Een decibelschaal: 8,5 punt erbij is een twee keer zo grote uitslag. Volgens het gegevensblad
// (-26 dBFS bij 94 dB) is praten op een meter rond 30 en een klap vlakbij 75 of meer; met de echte microfoon nog niet nagemeten.
static int loudness(int32_t amp) {
  if (amp < 10) return 0;
  return constrain((int)((20.0f * log10f((float)amp) - 20.0f) * 1.42f), 0, 100);
}

// Leest wat de microfoon sinds de vorige keer opnam en geeft de hardste uitslag terug. Beide kanalen tellen mee, zodat het
// pinnetje L/R van de microfoon los mag blijven. Wacht nergens op: wat er nog niet is, komt de volgende keer.
static int micLevel() {
  static int32_t buf[480];  // één blok van de driver: 240 metingen links en rechts, 15 ms
  int32_t amp = 0;
  for (int k = 0; k < 8; k++) {
    size_t n = 0;
    i2s_channel_read(i2s.rxChan(), buf, sizeof(buf), &n, 0);
    if (n < 8) break;
    for (size_t ch = 0; ch < 2; ch++) {
      int32_t lo = INT32_MAX, hi = INT32_MIN;
      for (size_t i = ch; i < n / 4; i += 2) { int32_t v = buf[i] >> 16; if (v < lo) lo = v; if (v > hi) hi = v; }
      if (hi > lo && (hi - lo) / 2 > amp) amp = (hi - lo) / 2;  // van dal tot top: zo telt een scheve nullijn niet mee
    }
  }
  return loudness(amp);
}

static void readSensors() {
  for (Dev& d : dev) {
    switch (d.type) {
      case BTN: { int v = !digitalRead(d.pin); if (v == d.raw) d.val = v; d.raw = v; break; }  // twee gelijke metingen = echt
      case PIR: d.val = digitalRead(d.pin); break;
#if SOC_TOUCH_SENSOR_SUPPORTED
      case TCH: { uint32_t v = touchRead(d.pin); d.val = (v < d.base * 6 / 10 || v > d.base * 16 / 10); break; }
#endif
      case TOF:
        if (d.tof && d.tof->dataReady()) {
          d.tof->read(false);
          d.val = d.tof->ranging_data.range_status == VL53L1X::RangeValid ? d.tof->ranging_data.range_mm / 10 : -1;
        }
        break;
      case MIC:
        d.val = micOn ? micLevel() : 0;
        if (millis() - d.t0 < 500) d.val = 0;  // de eerste halve seconde na het aanzetten geeft de microfoon nog onzin
        if (d.val > d.raw) d.raw = d.val;
        break;
      default: break;
    }
  }
}

static void checkRules() {
  uint32_t now = millis();
  for (int i = 0; i < nRules; i++) {
    Rule& r = rules[i];
    Dev& d = dev[r.dev];
    bool fire = false, cond;
    switch (r.trig) {
      case T_START: fire = pendingStart; break;
      case T_EVERY: if (now - r.last >= (uint32_t)r.arg) { r.last = now; fire = true; } break;
      case T_PRESS: case T_MOTION: case T_TOUCH: fire = d.val && !d.prev; break;
      case T_RELEASE: case T_STILL: case T_UNTOUCH: fire = !d.val && d.prev; break;
      case T_NEAR: case T_FAR:
        cond = d.val >= 0 && d.val < r.arg;
        if (r.trig == T_FAR) cond = !cond;
        fire = r.primed && cond && !r.state;
        r.state = cond;
        r.primed = true;
        break;
      case T_LOUD:
        cond = d.val >= r.arg;
        fire = r.primed && cond && !r.state && now - r.last >= 300;  // een klap telt één keer, ook als hij nagalmt
        if (fire) r.last = now;
        r.state = cond;
        r.primed = true;
        break;
    }
    if (fire) { Serial.printf("E %d\n", i); runActions(r.actions); }
  }
  pendingStart = false;
  for (Dev& d : dev) d.prev = d.val;
}

// ---- programma ------------------------------------------------------------

static void teardown() {
  for (Dev& d : dev) {
    switch (d.type) {
      case LED: case SPK: ledcWrite(d.pin, 0); ledcDetach(d.pin); break;
      case MOT: setMotor(d, 0); ledcDetach(d.pin); ledcDetach(d.pin2); break;
      case RING: if (d.ring) { d.ring->clear(); d.ring->show(); delete d.ring; } break;
      case TOF: if (d.tof) { d.tof->stopContinuous(); delete d.tof; } Wire.end(); break;
      case MIC: if (micOn) { i2s.end(); micOn = false; } break;
      default: break;
    }
    d = Dev();
  }
  nRules = 0;
}

static bool setupDev(int i, const char* w, int a, int b, int c) {
  if (i < 0 || i >= MAX_DEV) return false;
  Dev& d = dev[i];
  d.pin = a; d.pin2 = b;
  if (!strcmp(w, "LED")) { d.type = LED; ledcAttach(a, 5000, 8); ledcWrite(a, 0); gpio_set_drive_capability((gpio_num_t)a, GPIO_DRIVE_CAP_0); }  // zachtste stand (~5 mA): een losse LED zonder weerstand kan dan geen kwaad
  else if (!strcmp(w, "SPK")) { d.type = SPK; ledcAttach(a, 2000, 8); ledcWrite(a, 0); }
  else if (!strcmp(w, "MOT")) { d.type = MOT; ledcAttach(a, 1000, 8); ledcAttach(b, 1000, 8); setMotor(d, 0); }
  else if (!strcmp(w, "BTN")) { d.type = BTN; pinMode(a, INPUT_PULLUP); }
  else if (!strcmp(w, "PIR")) { d.type = PIR; pinMode(a, INPUT); }
  else if (!strcmp(w, "RING")) {
    d.type = RING;
    d.ring = new Adafruit_NeoPixel(b > 0 ? b : 12, a, NEO_GRB + NEO_KHZ800);
    d.ring->begin();
    d.ring->setBrightness(60);  // ring aan 3V3: zo blijft de stroom onder wat de USB-poort en de regelaar aankunnen
    d.ring->clear();
    d.ring->show();
  } else if (!strcmp(w, "TOF")) {
    d.type = TOF;
    Wire.begin(a > 0 ? a : 21, b > 0 ? b : 22);
    d.tof = new VL53L1X();
    d.tof->setTimeout(500);
    if (!d.tof->init()) { Serial.println("L afstandssensor niet gevonden, kijk de vier draadjes na"); delete d.tof; d.tof = nullptr; d.val = -1; }
    else { d.tof->setDistanceMode(VL53L1X::Long); d.tof->setMeasurementTimingBudget(50000); d.tof->startContinuous(50); }
  }
  else if (!strcmp(w, "MIC")) {
    if (micOn || c < 0) return false;  // één microfoon, en hij heeft drie pinnen nodig: klok, woordklok, data
    d.type = MIC;
    d.t0 = millis();
    i2s.setPins(a, b, -1, c);
    micOn = i2s.begin(I2S_MODE_STD, 16000, I2S_DATA_BIT_WIDTH_32BIT, I2S_SLOT_MODE_STEREO);
    if (!micOn) Serial.println("L de microfoon start niet");
  }
#if SOC_TOUCH_SENSOR_SUPPORTED
  else if (!strcmp(w, "TCH")) {
    d.type = TCH;
    uint32_t sum = 0;
    for (int k = 0; k < 16; k++) { sum += touchRead(a); delay(5); }
    d.base = sum / 16 ? sum / 16 : 1;
  }
#endif
  else return false;
  return true;
}

static bool parseTrigger(Rule& r, const char* s) {
  char w[12];
  int d = 0, arg = 0;
  if (sscanf(s, "%11s %d %d", w, &d, &arg) < 1) return false;
  static const char* names[] = { "START", "EVERY", "PRESS", "RELEASE", "MOTION", "STILL", "NEAR", "FAR", "TOUCH", "UNTOUCH", "LOUD" };
  for (int i = 0; i < (int)(sizeof(names) / sizeof(*names)); i++) {
    if (strcmp(w, names[i])) continue;
    r.trig = (Trig)i;
    if (i == T_EVERY) { arg = max(d, 50); d = 0; }  // EVERY heeft geen onderdeel: het getal is de tijd
    if (d < 0 || d >= MAX_DEV) return false;
    r.dev = d; r.arg = arg; r.last = millis(); r.state = false; r.primed = false;
    return true;
  }
  return false;
}

static void apply(bool save) {
  teardown();
  if (save) prefs.putString("prog", incoming);
  memcpy(prog, incoming, inLen + 1);
  int nDev = 0, lineNo = 0;
  char* line = prog;
  while (line && *line) {
    char* nl = strchr(line, '\n');
    if (nl) *nl = 0;
    lineNo++;
    bool ok = true;
    if (line[0] == 'D') {
      char w[12]; int i = 0, a = -1, b = -1, c = -1;
      ok = sscanf(line + 2, "%d %11s %d %d %d", &i, w, &a, &b, &c) >= 2 && setupDev(i, w, a, b, c);
      if (ok) nDev++;
    } else if (line[0] == 'R' && nRules < MAX_RULES) {
      char* semi = strchr(line, ';');
      if (semi) *semi = 0;
      ok = parseTrigger(rules[nRules], line + 2);
      if (ok) rules[nRules++].actions = semi ? semi + 1 : "";
    }
    if (!ok) { Serial.printf("ERR regel %d: %s\n", lineNo, line); break; }
    line = nl ? nl + 1 : nullptr;
  }
  pendingStart = true;
  Serial.printf("OK %d onderdelen, %d regels\n", nDev, nRules);
}

static void handleLine(char* l) {
  if (!strcmp(l, "HELLO")) Serial.printf("HI alsdan 2 %s\n", ESP.getChipModel());
  else if (!strcmp(l, "PROG")) { inLen = 0; incoming[0] = 0; receiving = true; }
  else if (!strcmp(l, "RUN")) { receiving = false; apply(true); }
  else if (receiving && (l[0] == 'D' || l[0] == 'R')) {
    size_t len = strlen(l);
    if (inLen + len + 2 > PROG_SIZE) { Serial.println("ERR programma te lang"); receiving = false; return; }
    memcpy(incoming + inLen, l, len);
    inLen += len;
    incoming[inLen++] = '\n';
    incoming[inLen] = 0;
  }
  else if (l[0] == 'X' && l[1] == ' ') { runActions(l + 2); Serial.println("OK"); }
  else if (l[0]) Serial.printf("ERR onbekend: %s\n", l);
}

void setup() {
  Serial.setRxBufferSize(4096);  // een heel programma kan binnenkomen terwijl een WAIT loopt
  Serial.begin(115200);
  prefs.begin("alsdan");
  String saved = prefs.getString("prog", "");
  inLen = min(saved.length(), (unsigned)PROG_SIZE - 1);
  memcpy(incoming, saved.c_str(), inLen);
  incoming[inLen] = 0;
  apply(false);
  Serial.printf("HI alsdan 2 %s\n", ESP.getChipModel());
}

void loop() {
  static char line[400];
  static size_t len = 0;
  static uint32_t lastSense = 0, lastReport = 0;

  while (Serial.available()) {
    char c = Serial.read();
    if (c == '\r') continue;
    if (c == '\n') { line[len] = 0; handleLine(line); len = 0; }
    else if (len < sizeof(line) - 1) line[len++] = c;
  }
  uint32_t now = millis();
  if (now - lastSense >= 20) {
    lastSense = now;
    readSensors();
    checkRules();
  }
  if (now - lastReport >= 250) {
    lastReport = now;
    for (int i = 0; i < MAX_DEV; i++)
      if (dev[i].type == BTN || dev[i].type == PIR || dev[i].type == TCH || dev[i].type == TOF) Serial.printf("S %d %d\n", i, dev[i].val);
      else if (dev[i].type == MIC) { Serial.printf("S %d %d\n", i, dev[i].raw); dev[i].raw = 0; }
  }
  tickOutputs();
  delay(2);
}
