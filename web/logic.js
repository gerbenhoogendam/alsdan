// Als-Dan: wat de app weet over de onderdelen, de triggers, de stappen en het
// protocol van de firmware (firmware/alsdan/alsdan.ino). Geen DOM hier, zodat
// test/logic.test.mjs dit onder node kan draaien.

export const OUT_PINS = [2, 4, 5, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 25, 26, 27, 32, 33];
export const IN_PINS = [...OUT_PINS, 34, 35, 36, 39];
export const TOUCH_PINS = [4, 2, 15, 13, 12, 14, 27, 33, 32];
const D = n => 'D' + n;

// Wat er op de pinnen van het ESP32 DevKit V1 (30 pinnen) staat, USB onder, antenne boven.
export const LEFT = ['EN', 36, 39, 34, 35, 32, 33, 25, 26, 27, 14, 12, 13, 'GND', 'VIN'];
export const RIGHT = [23, 22, 1, 3, 21, 19, 18, 5, 17, 16, 4, 2, 15, 'GND', '3V3'];
export const PIN_NAMES = { 36: 'VP', 39: 'VN', 1: 'TX0', 3: 'RX0', 17: 'TX2', 16: 'RX2' };
export const pinName = p => typeof p === 'number' ? (PIN_NAMES[p] || D(p)) : p;

export const KINDS = {
  led: { label: 'Lampje', color: '#f6b800', out: true, type: 'LED', pins: OUT_PINS, prefer: [2, 25, 26, 33, 32, 23, 19, 18, 13, 14, 27, 16, 17, 4],
    tests: [['on'], ['off']],
    wiring: d => [['Lange pootje', D(d.pin)], ['Korte pootje', 'GND']],
    note: 'Het lange pootje is de plus. Een weerstand hoeft niet: de pin staat op de zachtste stand. D2 is ook het blauwe lampje op het bordje zelf.' },
  lamp: { label: 'Grote lamp', color: '#ff7a00', out: true, type: 'LED', pins: OUT_PINS, prefer: [17, 16, 23, 19, 18],
    tests: [['on'], ['off']], needs: 'een MOSFET (IRLZ44N) en een weerstand van 2,2 Ω',
    wiring: d => [['Linker pootje van de MOSFET (gate)', D(d.pin)], ['Rechter pootje van de MOSFET (source)', 'GND'], ['Min van de lamp', 'het middelste pootje van de MOSFET'], ['Plus van de lamp', 'VIN', 'met de weerstand ertussen']],
    note: 'Deze lamp trekt veel te veel stroom voor een pin van de ESP32. Zonder MOSFET ertussen gaat de ESP32 kapot.' },
  ring: { label: 'Lichtring', color: '#e040fb', out: true, type: 'RING', pins: OUT_PINS, prefer: [16, 17, 13, 27, 14], count: 12,
    tests: [['color', '#ff0000'], ['rainbow'], ['ringoff']],
    colors: ['oranje', 'rood', 'wit'],   // zo zijn de draadjes aan Gerbens ring gesoldeerd: 5V oranje, GND rood, DI wit
    wiring: d => [['Plus', '3V3'], ['Min', 'GND'], ['Seintje', D(d.pin)]],
    note: 'De draadjes zitten al aan de ring vast. Let op: bij deze ring is het rode draadje de min.' },
  speaker: { label: 'Luidspreker', color: '#00b894', out: true, type: 'SPK', pins: OUT_PINS, prefer: [14, 27, 12, 13],
    tests: [['beep'], ['tada']],
    must: 'een weerstand van 220 Ω',
    wiring: d => [['Draadje 1', D(d.pin), null, 'een weerstand van 220 Ω'], ['Draadje 2', 'GND']],
    note: 'Zonder weerstand niet aansluiten: daar kan de pin van de ESP32 niet tegen. Welk draadje waar zit maakt niet uit.' },
  motor: { label: 'Motor', color: '#636e72', out: true, type: 'MOT', pins: OUT_PINS, two: true, prefer: [18, 19, 23, 5, 25, 26],
    tests: [['fwd', 60], ['stop']], needs: 'een motordriver',
    wiring: d => [['IN1 van de driver', D(d.pin)], ['IN2 van de driver', D(d.pin2)], ['VCC van de driver', 'VIN'], ['GND van de driver', 'GND'], ['De motor', 'de twee uitgangen van de driver']],
    note: 'De motor mag nooit rechtstreeks aan de ESP32. Er moet een motordriver tussen (DRV8833, L9110S of TB6612).' },
  button: { label: 'Knop', color: '#0984e3', type: 'BTN', pins: [0, ...IN_PINS], prefer: [0, 32, 35, 34, 26, 25], triggers: ['PRESS', 'RELEASE'],
    wiring: d => d.pin === 0 ? [['Niets aansluiten', 'BOOT', 'dit is het knopje op het bordje zelf']] : [['Het ene pootje', D(d.pin)], ['Het andere pootje', 'GND']],
    live: v => v ? 'Ingedrukt' : 'Los', note: 'Het knopje BOOT op het bordje is ook gewoon een knop.' },
  pir: { label: 'Bewegingsmelder', color: '#d63031', type: 'PIR', pins: IN_PINS, prefer: [27, 26, 25, 33, 32, 34, 35], triggers: ['MOTION', 'STILL'],
    wiring: d => [['Plus', 'VIN'], ['Seintje', D(d.pin)], ['Min', 'GND']],   // op VIN: het bordje van de melder maakt er zelf 3,3 volt van, en 3V3 blijft vrij
    live: v => v ? 'Beweging!' : 'Rustig', note: 'Na het aanzetten heeft hij een halve minuut nodig om wakker te worden.' },
  tof: { label: 'Afstandssensor', color: '#6c5ce7', type: 'TOF', pins: [], fixed: [21, 22], single: true, triggers: ['NEAR', 'FAR'],
    wiring: () => [['VIN (plus)', '3V3'], ['GND (min)', 'GND'], ['SDA (seintje)', D(21)], ['SCL (seintje)', D(22)]],
    live: v => v < 0 ? 'Niets in zicht' : v + ' cm', note: 'De lettertjes staan op het sensorbordje zelf. XSHUT en GPIO1 blijven leeg.' },
  mic: { label: 'Microfoon', color: '#e17055', type: 'MIC', pins: [], fixed: [32, 33, 35], single: true, fw: 2, triggers: ['LOUD'],
    wiring: () => [['VDD (plus)', '3V3'], ['GND (min)', 'GND'], ['SD', D(35)], ['SCK', D(32)], ['WS', D(33)]],
    live: v => 'Geluid ' + v, note: 'Alleen op 3V3, nooit op VIN: daar gaat de microfoon stuk van. Het pinnetje L/R blijft leeg.' },
  touch: { label: 'Toverdraadje', color: '#00a8ff', type: 'TCH', pins: TOUCH_PINS, prefer: [4, 13, 15, 12], triggers: ['TOUCH', 'UNTOUCH'],
    wiring: d => [['Het ene eind', D(d.pin), 'het andere eind raak je aan; met aluminiumfolie eraan heb je een groter raakvlak']],
    live: v => v ? 'Aangeraakt!' : 'Niet aangeraakt', note: 'De ESP32 voelt je vinger door het draadje. Staat het al op aangeraakt zonder dat je iets doet? Stuur het programma nog een keer, dan meet hij de ruststand opnieuw.' },
};

export const TRIGGERS = {
  START: { label: 'de ESP32 aangaat', enc: () => 'START' },
  EVERY: { label: 'er weer', param: { unit: 'seconden om zijn', default: 2, min: 0.1, max: 3600, step: 0.1 }, enc: (i, v) => `EVERY ${Math.round(v * 1000)}` },
  PRESS: { label: 'wordt ingedrukt', enc: i => `PRESS ${i}` },
  RELEASE: { label: 'wordt losgelaten', enc: i => `RELEASE ${i}` },
  MOTION: { label: 'ziet beweging', enc: i => `MOTION ${i}` },
  STILL: { label: 'ziet niets meer bewegen', enc: i => `STILL ${i}` },
  NEAR: { label: 'ziet iets dichterbij dan', param: { unit: 'cm', default: 20, min: 2, max: 400, step: 1 }, enc: (i, v) => `NEAR ${i} ${Math.round(v)}` },
  FAR: { label: 'ziet niets meer binnen', param: { unit: 'cm', default: 20, min: 2, max: 400, step: 1 }, enc: (i, v) => `FAR ${i} ${Math.round(v)}` },
  TOUCH: { label: 'wordt aangeraakt', enc: i => `TOUCH ${i}` },
  UNTOUCH: { label: 'wordt losgelaten', enc: i => `UNTOUCH ${i}` },
  LOUD: { label: 'hoort iets harder dan', param: { unit: '(van 0 tot 100)', default: 60, min: 5, max: 100, step: 5 }, enc: (i, v) => `LOUD ${i} ${Math.round(v)}` },
};

const rgb = hex => [1, 3, 5].map(k => parseInt(hex.slice(k, k + 2), 16)).join(' ');
export const STEPS = {
  on: { kinds: ['led', 'lamp'], label: 'gaat aan', enc: i => `SET ${i} 100` },
  off: { kinds: ['led', 'lamp'], label: 'gaat uit', enc: i => `SET ${i} 0` },
  blink: { kinds: ['led', 'lamp'], label: 'gaat knipperen', enc: i => `BLINK ${i} 400` },
  dim: { kinds: ['led', 'lamp'], label: 'gaat aan op', param: { unit: '%', default: 30, min: 0, max: 100, step: 5 }, enc: (i, v) => `SET ${i} ${Math.round(v)}` },
  color: { kinds: ['ring'], label: 'wordt', color: true, default: '#ff2d95', enc: (i, v) => `COLOR ${i} ${rgb(v)}` },
  spin: { kinds: ['ring'], label: 'draait rondjes in', color: true, default: '#00c8ff', enc: (i, v) => `SPIN ${i} ${rgb(v)}` },
  rainbow: { kinds: ['ring'], label: 'wordt een regenboog', enc: i => `RAINBOW ${i}` },
  ringoff: { kinds: ['ring'], label: 'gaat uit', enc: i => `COLOR ${i} 0 0 0` },
  beep: { kinds: ['speaker'], label: 'piept', enc: i => `BEEP ${i} 880 150` },
  tada: { kinds: ['speaker'], label: 'speelt tada', enc: i => `TUNE ${i} 0` },
  alarm: { kinds: ['speaker'], label: 'speelt alarm', enc: i => `TUNE ${i} 1` },
  siren: { kinds: ['speaker'], label: 'speelt sirene', enc: i => `TUNE ${i} 2` },
  oei: { kinds: ['speaker'], label: 'speelt oei', enc: i => `TUNE ${i} 3` },
  fwd: { kinds: ['motor'], label: 'draait vooruit op', param: { unit: '%', default: 100, min: 10, max: 100, step: 10 }, enc: (i, v) => `MOTOR ${i} ${Math.round(v)}` },
  back: { kinds: ['motor'], label: 'draait achteruit op', param: { unit: '%', default: 100, min: 10, max: 100, step: 10 }, enc: (i, v) => `MOTOR ${i} -${Math.round(v)}` },
  stop: { kinds: ['motor'], label: 'stopt', enc: i => `MOTOR ${i} 0` },
  wait: { label: 'wacht', param: { unit: 'seconden', default: 1, min: 0.1, max: 10, step: 0.1 }, enc: (i, v) => `WAIT ${Math.round(v * 1000)}` },
};

export const defaultValue = def => def.color ? def.default : def.param ? def.param.default : undefined;

// ---- model ----------------------------------------------------------------

export const newModel = () => ({ nextId: 1, devices: [], rules: [] });

export function usedPins(model, except) {
  const used = new Map();
  for (const d of model.devices) {
    if (d === except) continue;
    const pins = KINDS[d.kind].fixed || [d.pin, d.pin2];
    for (const p of pins) if (p != null) used.set(p, d);
  }
  return used;
}

export function freePin(model, kind, except, avoid = []) {
  const k = KINDS[kind], used = usedPins(model, except);
  return [...k.prefer || [], ...k.pins].find(p => !used.has(p) && !avoid.includes(p));
}

export function addDevice(model, kind) {
  const k = KINDS[kind];
  const same = model.devices.filter(d => d.kind === kind).length;
  const d = { id: 'd' + model.nextId++, kind, name: same ? `${k.label} ${same + 1}` : k.label };
  if (k.pins.length) d.pin = freePin(model, kind);
  if (k.two) d.pin2 = freePin(model, kind, null, [d.pin]);
  model.devices.push(d);
  // een onderdeel met vaste pinnen: wie daar al op zat verhuist naar een vrije pin
  for (const o of model.devices) for (const key of ['pin', 'pin2']) if (o !== d && (k.fixed || []).includes(o[key])) o[key] = freePin(model, o.kind, o, [o.pin, o.pin2]);
  return d;
}

export function addRule(model) {
  const r = { id: 'r' + model.nextId++, trigger: { kind: 'START' }, steps: [] };
  model.rules.push(r);
  return r;
}

// De kleuren van de jumperdraadjes.
export const WIRE_COLORS = { rood: '#e5484d', zwart: '#222222', geel: '#f2c200', groen: '#1faa59', blauw: '#2f7de1', wit: '#f7f7f7', oranje: '#f58a1f', bruin: '#8b5a2b', paars: '#8e44ad', grijs: '#9aa0a6' };

// Elk draadje van een onderdeel met zijn twee kanten: `lab` op het onderdeel, `esp` op het bordje (zoals het daar gedrukt staat).
// Kleur: wat de gebruiker koos, anders hoe het onderdeel gesoldeerd is, anders de gewoonte (rood = plus, zwart = min, geel en
// groen = seintjes). Zonder kleur gaat de regel niet naar de ESP32. `inline` is wat er in het draadje tussen moet.
export function wires(d) {
  const k = KINDS[d.kind];
  let signals = 0;
  return k.wiring(d).map(([lab, pin, hint, inline], i) => {
    const num = /^D\d+$/.test(pin) ? +pin.slice(1) : null;
    const usual = num != null ? ['geel', 'groen', 'blauw'][signals++ % 3] : pin === 'GND' ? 'zwart' : pin === '3V3' || pin === 'VIN' ? 'rood' : null;
    const name = usual && [d.colors?.[i], k.colors?.[i]].find(c => WIRE_COLORS[c]) || usual;
    return { i, lab, pin, hint, inline, num, esp: num != null ? pinName(num) : pin, name, color: name ? WIRE_COLORS[name] : null };
  });
}

// Welke pin op het bordje elk draadje krijgt (`key`: het pinnummer, '3V3', 'VIN', 'GND:L' of 'GND:R') en wie er op elke pin zit.
// Van achteren gezien staat de rij van D23 links. GND zit er twee keer op: een onderdeel krijgt de GND aan zijn eigen kant,
// is die bezet dan de andere, en pas als beide bezet zijn wordt er gedeeld (draadjes samen in een lasdop).
export function plan(model) {
  const taken = { L: 0, R: 0 }, rows = new Map(), users = {};
  for (const d of model.devices) {
    const mine = wires(d), own = mine.find(w => w.num != null);
    const side = own && !RIGHT.includes(own.num) ? 'R' : 'L', other = side === 'L' ? 'R' : 'L';
    rows.set(d.id, mine.map(w => {
      if (!w.color) return w;
      let key = w.num ?? w.pin;
      if (w.pin === 'GND') { const s = !taken[side] ? side : !taken[other] ? other : side; taken[s]++; key = 'GND:' + s; }
      (users[key] ||= []).push(d);
      return { ...w, key };
    }));
  }
  return { rows, users };
}

export const devicePins = d => KINDS[d.kind].fixed || (d.kind === 'ring' ? [d.pin, KINDS.ring.count] : d.kind === 'motor' ? [d.pin, d.pin2] : [d.pin]);

// Het programma zoals de firmware het leest. Regels zonder trigger of zonder
// geldige stappen gaan niet mee; `rules` zegt welke regel-ids wél gingen, in de
// volgorde die de firmware in `E <n>` gebruikt.
export function encodeProgram(model) {
  const index = id => model.devices.findIndex(d => d.id === id);
  const lines = ['PROG'];
  model.devices.forEach((d, i) => lines.push(`D ${i} ${KINDS[d.kind].type} ${devicePins(d).join(' ')}`.trimEnd()));
  const rules = [], skipped = [];
  for (const r of model.rules) {
    const t = TRIGGERS[r.trigger.kind];
    const ti = index(r.trigger.dev);
    const trig = t && (t.enc.length < 1 || r.trigger.kind === 'EVERY' || ti >= 0) ? t.enc(ti, r.trigger.value ?? defaultValue(t)) : null;
    const steps = r.steps.map(s => encodeStep(s, model, index)).filter(Boolean);
    if (!trig || !steps.length) { skipped.push(r.id); continue; }
    lines.push(`R ${trig} ; ${steps.join(' ; ')}`);
    rules.push(r.id);
  }
  lines.push('RUN');
  return { text: lines.join('\n') + '\n', rules, skipped };
}

export function encodeStep(s, model, index = id => model.devices.findIndex(d => d.id === id)) {
  const def = STEPS[s.kind];
  if (!def) return null;
  let i = -1;
  if (def.kinds) {
    i = index(s.dev);
    if (i < 0 || !def.kinds.includes(model.devices[i].kind)) return null;
  }
  return def.enc(i, s.value ?? defaultValue(def));
}

// ---- voorbeelden ----------------------------------------------------------
// devices: [kind, pin?, naam?]; rules: [[trigger, device-nummer?, waarde?], [[stap, device-nummer?, waarde?], ...]]

export const EXAMPLES = [
  { name: 'Knop en lampje', devices: [['button', 0, 'Knop BOOT'], ['led', 2, 'Blauw lampje']],
    rules: [[['PRESS', 0], [['on', 1], ['wait', null, 1], ['off', 1]]]] },
  { name: 'Knipperlicht', devices: [['led', 2, 'Blauw lampje']], rules: [[['START'], [['blink', 0]]]] },
  { name: 'Inbrekersalarm', devices: [['pir', 27], ['ring', 16], ['speaker', 14]],
    rules: [[['MOTION', 0], [['spin', 1, '#ff0000'], ['alarm', 2]]], [['STILL', 0], [['ringoff', 1]]]] },
  { name: 'Afstandsmeter', devices: [['tof'], ['ring', 16], ['speaker', 14]],
    rules: [[['NEAR', 0, 20], [['color', 1, '#ff6a00'], ['beep', 2]]], [['FAR', 0, 20], [['color', 1, '#00c853']]]] },
  { name: 'Klap voor licht', devices: [['mic'], ['ring', 16]],
    rules: [[['LOUD', 0, 60], [['rainbow', 1], ['wait', null, 3], ['ringoff', 1]]]] },
  { name: 'Toverstaf', devices: [['touch', 4], ['ring', 16], ['speaker', 14]],
    rules: [[['TOUCH', 0], [['rainbow', 1], ['tada', 2]]], [['UNTOUCH', 0], [['ringoff', 1]]]] },
  { name: 'Alles van de bestelling', devices: [['button', 0, 'Knop BOOT'], ['led', 2, 'Blauw lampje'], ['led', 25, 'Rood lampje'], ['led', 26, 'Groen lampje'], ['ring', 16], ['speaker', 14], ['pir', 27], ['tof'], ['touch', 4], ['motor', 18], ['lamp', 17]],
    rules: [[['PRESS', 0], [['on', 1], ['tada', 5], ['wait', null, 1], ['off', 1]]], [['MOTION', 6], [['on', 2]]], [['STILL', 6], [['off', 2]]], [['NEAR', 7, 30], [['color', 4, '#ff6a00']]], [['FAR', 7, 30], [['ringoff', 4]]], [['TOUCH', 8], [['on', 3], ['fwd', 9, 80], ['wait', null, 2], ['stop', 9], ['off', 3]]]] },
];

export function exampleModel(ex) {
  const m = newModel();
  const devs = ex.devices.map(([kind, pin, name]) => {
    const d = addDevice(m, kind);
    if (pin != null) { d.pin = pin; if (KINDS[kind].two) d.pin2 = pin + 1; }
    if (name) d.name = name;
    return d;
  });
  for (const [[tk, td, tv], steps] of ex.rules) {
    const r = addRule(m);
    r.trigger = { kind: tk, dev: td != null ? devs[td].id : undefined, value: tv };
    r.steps = steps.map(([sk, sd, sv]) => ({ kind: sk, dev: sd != null ? devs[sd].id : undefined, value: sv }));
  }
  return m;
}
