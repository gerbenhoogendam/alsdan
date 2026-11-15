// node --test web/test/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { EXAMPLES, exampleModel, encodeProgram, addDevice, addRule, newModel, TRIGGERS, STEPS, KINDS, wires, plan, WIRE_COLORS } from '../logic.js';

const ino = readFileSync(new URL('../../firmware/alsdan/alsdan.ino', import.meta.url), 'utf8');

test('knop en lampje wordt het programma dat de firmware verwacht', () => {
  const { text, rules, skipped } = encodeProgram(exampleModel(EXAMPLES[0]));
  assert.equal(text, 'PROG\nD 0 BTN 0\nD 1 LED 2\nR PRESS 0 ; SET 1 100 ; WAIT 1000 ; SET 1 0\nRUN\n');
  assert.equal(rules.length, 1);
  assert.deepEqual(skipped, []);
});

test('alle voorbeelden coderen zonder overgeslagen regels', () => {
  for (const ex of EXAMPLES) {
    const { text, skipped } = encodeProgram(exampleModel(ex));
    assert.deepEqual(skipped, [], ex.name);
    assert.match(text, /^PROG\n(D \d+ [A-Z]+( -?\d+)*\n)+(R [A-Z]+( \d+)* ; .+\n)+RUN\n$/, ex.name);
  }
});

test('ieder woord dat de app stuurt staat in de firmware', () => {
  for (const w of Object.keys(TRIGGERS)) assert.ok(ino.includes(`"${w}"`), w);
  const m = exampleModel(EXAMPLES[5]);
  const words = new Set(encodeProgram(m).text.split('\n').flatMap(l => l.startsWith('R ') ? l.slice(2).split(' ; ').map(s => s.split(' ')[0]) : []));
  for (const w of words) assert.ok(ino.includes(`"${w}"`), w);
  for (const k of Object.values(KINDS)) assert.ok(ino.includes(`"${k.type}"`), k.type);
});

test('een regel zonder stappen of met een verdwenen onderdeel gaat niet mee', () => {
  const m = newModel();
  const led = addDevice(m, 'led');
  const r1 = addRule(m);
  const r2 = addRule(m);
  r2.steps = [{ kind: 'on', dev: 'd99' }];
  const r3 = addRule(m);
  r3.trigger = { kind: 'EVERY', value: 0.5 };
  r3.steps = [{ kind: 'on', dev: led.id }, { kind: 'wait' }];
  const { text, rules, skipped } = encodeProgram(m);
  assert.deepEqual(skipped, [r1.id, r2.id]);
  assert.deepEqual(rules, [r3.id]);
  assert.ok(text.includes('R EVERY 500 ; SET 0 100 ; WAIT 1000\n'));
});

test('nieuwe onderdelen krijgen vrije pinnen', () => {
  const m = newModel();
  const a = addDevice(m, 'led'), b = addDevice(m, 'led'), mot = addDevice(m, 'motor'), btn = addDevice(m, 'button');
  assert.equal(a.pin, 2);
  assert.equal(b.pin, 25);
  assert.notEqual(mot.pin, mot.pin2);
  assert.equal(btn.pin, 0);
  assert.equal(b.name, 'Lampje 2');
  assert.ok(Object.values(STEPS).some(s => s.kinds && s.kinds.includes('lamp')));
});

test('elk draadje heeft twee kanten en een kleur', () => {
  const m = newModel();
  const pir = addDevice(m, 'pir'), ring = addDevice(m, 'ring'), tof = addDevice(m, 'tof'), btn = addDevice(m, 'button');
  assert.deepEqual(wires(pir).map(w => [w.esp, w.name]), [['VIN', 'rood'], ['D27', 'geel'], ['GND', 'zwart']]);
  assert.deepEqual(wires(ring).map(w => [w.esp, w.name]), [['3V3', 'oranje'], ['GND', 'rood'], ['RX2', 'wit']]);   // zoals gesoldeerd
  ring.colors = { 2: 'blauw', 0: 'bestaat-niet' };
  assert.deepEqual(wires(ring).map(w => w.name), ['oranje', 'rood', 'blauw']);
  assert.equal(wires(ring)[2].color, WIRE_COLORS.blauw);
  assert.deepEqual(wires(tof).map(w => w.esp), ['3V3', 'GND', 'D21', 'D22']);
  assert.notEqual(wires(tof)[2].color, wires(tof)[3].color);
  assert.equal(wires(btn)[0].color, null);   // BOOT: niets aansluiten
  assert.equal(wires(addDevice(m, 'speaker'))[0].inline, 'een weerstand van 220 Ω');
  for (const kind of Object.keys(KINDS)) for (const w of wires(addDevice(newModel(), kind))) assert.ok(w.lab && w.esp, kind);
});

test('de twee GND-pinnen worden verdeeld, daarna gedeeld', () => {
  const m = newModel();
  const pir = addDevice(m, 'pir'), ring = addDevice(m, 'ring'), led = addDevice(m, 'led'), tof = addDevice(m, 'tof');
  const { rows, users } = plan(m), gnd = d => rows.get(d.id).find(w => w.pin === 'GND').key;
  assert.equal(gnd(pir), 'GND:R');    // D27 zit van achteren gezien rechts
  assert.equal(gnd(ring), 'GND:L');   // RX2 links
  assert.equal(gnd(led), 'GND:L');    // D2 links, beide bezet: delen aan de eigen kant
  assert.deepEqual(users['GND:L'].map(d => d.id), [ring.id, led.id, tof.id]);
  assert.deepEqual(users['3V3'].map(d => d.id), [ring.id, tof.id]);
  assert.deepEqual(users.VIN.map(d => d.id), [pir.id]);
  assert.equal(rows.get(pir.id)[1].key, 27);
});

test('de microfoon: vaste pinnen, en wie daar zat verhuist', () => {
  const m = newModel();
  const btn = addDevice(m, 'button'), led = addDevice(m, 'led');
  btn.pin = 32; led.pin = 33;
  const mic = addDevice(m, 'mic'), r = addRule(m);
  assert.ok(![32, 33, 35].includes(btn.pin) && ![32, 33, 35].includes(led.pin) && btn.pin !== led.pin);
  r.trigger = { kind: 'LOUD', dev: mic.id, value: 55 };
  r.steps = [{ kind: 'on', dev: led.id }];
  const { text } = encodeProgram(m);
  assert.match(text, /^D 2 MIC 32 33 35$/m);
  assert.match(text, /^R LOUD 2 55 ; SET 1 100$/m);
  assert.deepEqual(wires(mic).map(w => [w.esp, w.name]), [['3V3', 'rood'], ['GND', 'zwart'], ['D35', 'geel'], ['D32', 'groen'], ['D33', 'blauw']]);
  assert.ok(!KINDS.led.pins.every(p => p !== 32) && addDevice(m, 'led').pin !== 32);   // een nieuw lampje krijgt geen pin van de microfoon
});
