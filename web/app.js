// Als-Dan: de pagina. Regels en onderdelen in het model (localStorage), het
// aansluitplaatje, en de USB-verbinding met de ESP32 (Web Serial, Chrome).
import { KINDS, TRIGGERS, STEPS, EXAMPLES, LEFT, RIGHT, WIRE_COLORS, pinName, addDevice, addRule, usedPins, exampleModel, encodeProgram, encodeStep, defaultValue, plan } from './logic.js?v=3';
import { ART } from './parts.js?v=3';

const $ = s => document.querySelector(s);
const esc = s => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const KEY = 'alsdan.v1';
const TEST_LABELS = { on: 'Aan', off: 'Uit', color: 'Rood', rainbow: 'Regenboog', ringoff: 'Uit', beep: 'Piep', tada: 'Tada', fwd: 'Vooruit', stop: 'Stop' };

let model = load() || exampleModel(EXAMPLES[0]);
let selected = model.devices[0]?.id;
let sent = null;   // het laatst verstuurde programma: regel-ids en onderdelen in de volgorde van de firmware
let dirty = true;

function load() { try { const m = JSON.parse(localStorage.getItem(KEY)); return m && m.devices ? m : null; } catch { return null; } }
function save() { try { localStorage.setItem(KEY, JSON.stringify(model)); } catch {} }
function changed() { dirty = true; save(); render(); }
const dev = id => model.devices.find(d => d.id === id);
const label = d => d.name;
const num = el => { const v = parseFloat(el.value); return isNaN(v) ? undefined : Math.min(Math.max(v, +el.min), +el.max); };

// ---- regels ---------------------------------------------------------------

function trigOptions() {
  const o = [['START|', TRIGGERS.START.label], ['EVERY|', TRIGGERS.EVERY.label]];
  for (const d of model.devices) for (const t of KINDS[d.kind].triggers || []) o.push([`${t}|${d.id}`, `${label(d)} ${TRIGGERS[t].label}`]);
  return o;
}
function stepOptions() {
  const o = [];
  for (const d of model.devices) for (const [k, s] of Object.entries(STEPS)) if (s.kinds && s.kinds.includes(d.kind)) o.push([`${k}|${d.id}`, `${label(d)} ${s.label}`]);
  o.push(['wait|', 'wacht']);
  return o;
}
function selectHtml(options, value, attr) {
  const known = options.some(([v]) => v === value);
  return `<select ${attr}>${known ? '' : '<option value="" selected>kies…</option>'}${options.map(([v, l]) => `<option value="${v}" ${v === value ? 'selected' : ''}>${esc(l)}</option>`).join('')}</select>`;
}
function paramHtml(def, value, attr) {
  if (def.color) return `<input type="color" value="${esc(value ?? def.default)}" ${attr} aria-label="Kleur">`;
  if (!def.param) return '';
  const p = def.param;
  return `<label class="param"><input type="number" value="${value ?? p.default}" min="${p.min}" max="${p.max}" step="${p.step}" ${attr}> ${esc(p.unit)}</label>`;
}
function firstStep() {
  const d = model.devices.find(d => KINDS[d.kind].out);
  if (!d) return { kind: 'wait', value: 1 };
  const k = Object.keys(STEPS).find(s => STEPS[s].kinds && STEPS[s].kinds.includes(d.kind));
  return { kind: k, dev: d.id, value: defaultValue(STEPS[k]) };
}
function newRule() {
  const r = addRule(model);
  const o = trigOptions().find(([v]) => v.includes('|d'));
  if (o) { const [kind, d] = o[0].split('|'); r.trigger = { kind, dev: d, value: defaultValue(TRIGGERS[kind]) }; }
  r.steps = [firstStep()];
}

function renderRules() {
  const to = trigOptions(), so = stepOptions(), enc = encodeProgram(model);
  $('#rules').innerHTML = model.rules.map((r, ri) => {
    const t = TRIGGERS[r.trigger.kind] || {};
    const steps = r.steps.map((s, si) => `<div class="step">${selectHtml(so, `${s.kind}|${s.dev || ''}`, `data-step="${ri}:${si}" aria-label="Stap"`)}${paramHtml(STEPS[s.kind] || {}, s.value, `data-stepval="${ri}:${si}"`)}<button class="x" data-delstep="${ri}:${si}" title="Stap weg">×</button></div>`).join('');
    const skipped = enc.skipped.includes(r.id);
    return `<div class="rule ${skipped ? 'skipped' : ''}" data-rule="${r.id}">
      <div class="row als"><span class="tag">ALS</span>${selectHtml(to, `${r.trigger.kind}|${r.trigger.dev || ''}`, `data-trig="${ri}" aria-label="Als"`)}${paramHtml(t, r.trigger.value, `data-trigval="${ri}"`)}</div>
      <div class="row dan"><span class="tag">DAN</span><div class="steps">${steps}<button class="add" data-addstep="${ri}">+ stap</button></div></div>
      <button class="x del" data-delrule="${ri}" title="Regel weg">×</button>
      ${skipped ? '<div class="warn">Deze regel gaat nog niet mee: kies een stap, en een onderdeel dat bestaat.</div>' : ''}
    </div>`;
  }).join('') || '<p class="empty">Nog geen regels. Klik op “Nieuwe regel” of kies een voorbeeld.</p>';
  $('#program').textContent = enc.text;
}

$('#rules').addEventListener('change', e => {
  const el = e.target, ds = el.dataset;
  if (ds.trig != null) { const [kind, d] = el.value.split('|'); model.rules[+ds.trig].trigger = { kind, dev: d || undefined, value: defaultValue(TRIGGERS[kind]) }; }
  else if (ds.trigval != null) model.rules[+ds.trigval].trigger.value = num(el);
  else if (ds.step != null) { const [ri, si] = ds.step.split(':'); const [kind, d] = el.value.split('|'); model.rules[ri].steps[si] = { kind, dev: d || undefined, value: defaultValue(STEPS[kind]) }; }
  else if (ds.stepval != null) { const [ri, si] = ds.stepval.split(':'); model.rules[ri].steps[si].value = el.type === 'color' ? el.value : num(el); }
  else return;
  changed();
});
$('#rules').addEventListener('click', e => {
  const b = e.target.closest('button'), ds = b && b.dataset;
  if (!b) return;
  if (ds.addstep != null) model.rules[+ds.addstep].steps.push(firstStep());
  else if (ds.delstep != null) { const [ri, si] = ds.delstep.split(':'); model.rules[ri].steps.splice(si, 1); }
  else if (ds.delrule != null) model.rules.splice(+ds.delrule, 1);
  else return;
  changed();
});
$('#btnAddRule').onclick = () => { newRule(); changed(); };

$('#examples').innerHTML += EXAMPLES.map((ex, i) => `<option value="${i}">${esc(ex.name)}</option>`).join('');
$('#examples').onchange = e => {
  const i = e.target.value;
  e.target.value = '';
  if (i === '' || (model.rules.length && !confirm('Dit vervangt je regels en onderdelen door het voorbeeld. Doorgaan?'))) return;
  model = exampleModel(EXAMPLES[+i]);
  selected = model.devices[0]?.id;
  changed();
};

// ---- onderdelen -----------------------------------------------------------

const art = d => ART[d.kind]?.(d) || null;
// Een klein plaatje van het onderdeel: dezelfde foto of tekening als in het aansluitplaatje.
function thumb(d) {
  const a = art(d);
  if (!a) return '<svg class="thumb" viewBox="0 0 40 40"><rect width="40" height="40" fill="#1f2a44"/><circle cx="20" cy="20" r="11" fill="#cfd6e6"/><circle cx="20" cy="20" r="6" fill="#444"/></svg>';   // het BOOT-knopje
  return `<svg class="thumb" viewBox="0 0 ${a.w} ${a.h}" preserveAspectRatio="xMidYMid ${a.img ? 'slice' : 'meet'}">${a.img ? `<image href="${a.img}" width="${a.w}" height="${a.h}"/>` : a.svg}</svg>`;
}

function renderDevices(p) {
  $('#addKind').innerHTML = '<option value="">+ Onderdeel erbij…</option>' + Object.entries(KINDS).map(([k, v]) =>
    `<option value="${k}" ${v.single && model.devices.some(d => d.kind === k) ? 'disabled' : ''}>${v.label}${v.needs ? ' (eerst nodig: ' + v.needs + ')' : ''}</option>`).join('');
  $('#devices').innerHTML = model.devices.map(d => {
    const pins = d.pin === 0 ? 'BOOT' : p.rows.get(d.id).filter(w => w.num != null).map(w => w.esp).join(' + ');
    return `<div class="dev ${d.id === selected ? 'sel' : ''}" data-dev="${d.id}" style="--c:${KINDS[d.kind].color}">
      ${thumb(d)}
      <div class="who"><input class="name" value="${esc(d.name)}" data-name="${d.id}" aria-label="Naam"><span class="small">op ${esc(pins)} <b class="live" data-live="${d.id}"></b></span></div>
      <button class="x" data-deldev="${d.id}" title="Onderdeel weg">×</button>
    </div>`;
  }).join('') || '<p class="empty">Nog geen onderdelen. Kies er een hierboven.</p>';
}

$('#addKind').onchange = e => {
  const kind = e.target.value;
  e.target.value = '';
  if (!kind) return;
  selected = addDevice(model, kind).id;
  changed();
};
$('#devices').addEventListener('change', e => {
  const id = e.target.dataset.name;
  if (!id) return;
  dev(id).name = e.target.value.trim() || KINDS[dev(id).kind].label;
  changed();
});
$('#devices').addEventListener('click', e => {
  const b = e.target.closest('button');
  if (b && b.dataset.deldev) {
    model.devices = model.devices.filter(d => d.id !== b.dataset.deldev);
    if (selected === b.dataset.deldev) selected = model.devices[0]?.id;
    return changed();
  }
  const card = e.target.closest('.dev');
  if (card && card.dataset.dev !== selected) { selected = card.dataset.dev; render(); }
});

// ---- aansluiten -----------------------------------------------------------
// Eén plaatje: links het echte onderdeel, rechts het bordje van achteren gezien (waar de pinnetjes uitsteken, dus links en
// rechts gespiegeld ten opzichte van de opdruk aan de voorkant), en elk draadje ertussen in zijn eigen kleur.

const VB = { w: 790, h: 600 }, BX = 560, BW = 150, TOP = 110, PITCH = 28, PART = { x: 10, w: 340, h: 470 };
const edge = c => c === WIRE_COLORS.wit ? '#8b93a1' : c;   // een wit draadje heeft een rand nodig op een witte ondergrond

function pinPos() {
  const pos = {};
  RIGHT.forEach((p, i) => pos[p === 'GND' ? 'GND:L' : p] = { p, x: BX, y: TOP + i * PITCH, side: 'L' });
  LEFT.forEach((p, i) => pos[p === 'GND' ? 'GND:R' : p] = { p, x: BX + BW, y: TOP + i * PITCH, side: 'R' });
  return pos;
}
function chip(x, y, text, color) {
  const w = text.length * 7.2 + 18;
  return `<rect x="${x}" y="${y - 11}" width="${w}" height="22" rx="11" fill="#fff" stroke="${edge(color)}" stroke-width="2.5"/><text x="${x + w / 2}" y="${y + 4.5}" text-anchor="middle" font-size="12.5" font-weight="700" fill="#1d2433">${esc(text)}</text>`;
}
const lines = (x, y, texts) => texts.map((t, i) => `<text x="${x}" y="${y + i * 22}" text-anchor="middle" font-size="15" fill="#4a5265">${esc(t)}</text>`).join('');

function wiringSvg(d, p) {
  const pos = pinPos(), k = d && KINDS[d.kind], a = d && art(d), rows = d ? p.rows.get(d.id) : [];
  const mine = new Set(k?.needs ? [] : rows.filter(w => w.key != null).map(w => String(w.key))), taken = {};
  for (const o of model.devices) if (o !== d) for (const w of p.rows.get(o.id)) if (w.key != null) (taken[w.key] ||= []).push(o);
  const all = Object.entries(pos).map(([key, at]) => ({ ...at, hit: mine.has(key), others: taken[key], text: pinName(at.p) + ({ GND: ' −', '3V3': ' +', VIN: ' +' }[at.p] || '') }));
  // de stipjes liggen onder de draadjes, de namen erboven. Rechts loopt een draadje over het bordje heen naar zijn pin:
  // de naam van die pin staat daarom buiten het bordje.
  const dots = all.map(({ x, y, others }) => `<circle cx="${x}" cy="${y}" r="${others ? 6.5 : 5}" fill="${others ? KINDS[others[0].kind].color : '#d9c47a'}" stroke="#333">${others ? `<title>${esc(others.map(label).join(', '))}</title>` : ''}</circle>`).join('');
  const names = all.map(({ x, y, side, hit, text }) => hit && side === 'R'
    ? `<text x="${x + 14}" y="${y + 5.5}" font-size="16" font-weight="800" fill="#1d2433">${text}</text>`
    : `<text x="${side === 'L' ? x + 13 : x - 13}" y="${y + (hit ? 5.5 : 4)}" text-anchor="${side === 'L' ? 'start' : 'end'}" font-size="${hit ? 16 : 11.5}" font-weight="${hit ? 800 : 400}" fill="${hit ? '#fff' : '#aebbd8'}" stroke="#1f2a44" stroke-width="3" paint-order="stroke">${text}</text>`).join('');

  const cx = PART.x + PART.w / 2;
  let part = '', drawn = '';
  if (!d) part = lines(cx, 290, ['Kies links een onderdeel.']);
  else if (!a) part = lines(cx, 270, ['Dit knopje zit al op het bordje,', 'aan de andere kant.', 'Je hoeft niets aan te sluiten.']);
  else {
    const s = Math.min(PART.w / a.w, PART.h / a.h), ox = PART.x + PART.w - a.w * s, oy = VB.h / 2 - a.h * s / 2;
    part = `<g transform="translate(${ox} ${oy}) scale(${s})">${a.img ? `<clipPath id="pc"><rect width="${a.w}" height="${a.h}" rx="${12 / s}"/></clipPath><image href="${a.img}" width="${a.w}" height="${a.h}" clip-path="url(#pc)"/>` : a.svg}</g>`
      + (a.hold ? lines(cx, oy + a.h * s + 26, [a.hold]) : '')
      + (a.marks || []).map(([x, y, t]) => `<circle cx="${ox + x * s}" cy="${oy + y * s}" r="16" fill="none" stroke="#fff" stroke-width="4"/><circle cx="${ox + x * s}" cy="${oy + y * s}" r="16" fill="none" stroke="#e5484d" stroke-width="2"/>${chip(ox + x * s + 22, oy + y * s, t, '#e5484d')}`).join('');
    if (!k.needs) {   // waar eerst iets tussen moet, tekenen we geen draadjes naar het bordje
      const live = rows.filter(w => w.key != null && a.pins[w.i]).sort((u, v) => a.pins[u.i][1] - a.pins[v.i][1]);
      let prevY = -99, prevShift = 0;
      drawn = live.map(w => {
        const x0 = ox + a.pins[w.i][0] * s, y0 = oy + a.pins[w.i][1] * s, b = pos[w.key], x1 = b.x - 18;
        const shift = y0 - prevY < 26 && !prevShift ? 1 : 0;   // labels die te dicht op elkaar zitten verspringen
        prevY = y0; prevShift = shift;
        const c1 = Math.max(x0 + 110, ox + a.w * s + 60), c2 = x1 - 110, path = `M${x0} ${y0}C${c1} ${y0},${c2} ${b.y},${x1} ${b.y}`;
        const lx = Math.max(x0 + 12, ox + a.w * s + 6) + shift * 78;   // het label staat naast het plaatje, ook als het pinnetje midden op de foto zit
        const cw = w.lab.length * 7.2 + 18, rx = lx + cw + 12;   // wat ertussen moet zit vlak achter het label
        const t = w.inline ? [...Array(41)].map((_, n) => n / 40).find(t => (1 - t) ** 3 * x0 + 3 * (1 - t) ** 2 * t * c1 + 3 * (1 - t) * t * t * c2 + t ** 3 * x1 >= rx + 40) ?? 0.5 : 0;
        const ry = (1 - t) ** 3 * y0 + 3 * (1 - t) ** 2 * t * y0 + 3 * (1 - t) * t * t * b.y + t ** 3 * b.y;
        return `<g class="w" data-w="${w.i}">
          <path d="${path}" fill="none" stroke="${['zwart', 'bruin', 'paars'].includes(w.name) ? '#fff' : '#1d2433'}" stroke-opacity=".7" stroke-width="10" stroke-linecap="round"/>
          <path d="${path}" fill="none" stroke="${w.color}" stroke-width="6.5" stroke-linecap="round"/>
          <circle cx="${x0}" cy="${y0}" r="6" fill="${w.color}" stroke="#fff" stroke-width="2"/>
          ${chip(lx, y0, w.lab, w.color)}
          ${w.inline ? `<rect x="${rx}" y="${ry - 11}" width="80" height="22" rx="8" fill="#e8d3a0" stroke="#7a6126" stroke-width="2"/><text x="${rx + 40}" y="${ry + 4.5}" text-anchor="middle" font-size="12.5" font-weight="700" fill="#4a3a12">weerstand</text>` : ''}
          <rect x="${x1 - 2}" y="${b.y - 6.5}" width="17" height="13" rx="3" fill="#222" stroke="#fff"/>
          <circle cx="${b.x}" cy="${b.y}" r="7.5" fill="${w.color}" stroke="#fff" stroke-width="2"/>
        </g>`;
      }).join('');
    }
  }
  const boot = d && d.pin === 0 ? `<circle cx="${BX + 24}" cy="534" r="17" fill="none" stroke="#ffd84d" stroke-width="4"/>` : '';
  const btn = (x, lab) => `<rect x="${x - 12}" y="522" width="24" height="24" rx="4" fill="none" stroke="#cfd6e6" stroke-dasharray="3 3"/><circle cx="${x}" cy="534" r="6" fill="none" stroke="#cfd6e6" stroke-dasharray="3 3"/><text x="${x}" y="562" text-anchor="middle" fill="#e8ecf7" font-size="10">${lab}</text>`;
  return `<svg viewBox="0 0 ${VB.w} ${VB.h}" xmlns="http://www.w3.org/2000/svg" font-family="system-ui, sans-serif" role="img" aria-label="Het onderdeel, de ESP32 van achteren gezien, en de draadjes ertussen">
    <text x="${BX + BW / 2}" y="20" text-anchor="middle" fill="#667" font-size="13">achterkant van de ESP32</text>
    <rect x="${BX}" y="30" width="${BW}" height="540" rx="8" fill="#1f2a44"/>
    <rect x="${BX + 30}" y="40" width="${BW - 60}" height="48" rx="4" fill="#2d3a5c" stroke="#8fa3d9" stroke-dasharray="4 3"/><text x="${BX + BW / 2}" y="69" fill="#b7c4ea" text-anchor="middle" font-size="11">antenne</text>
    <rect x="${BX + BW / 2 - 18}" y="556" width="36" height="24" rx="3" fill="#9aa5b8"/><text x="${BX + BW / 2}" y="596" text-anchor="middle" fill="#666" font-size="11">USB</text>
    ${btn(BX + 24, 'BOOT')}${btn(BX + BW - 24, 'EN')}${boot}
    ${dots}${part}${drawn}${names}</svg>`;
}

function pinSelect(d, key) {
  const used = usedPins(model, d), other = key === 'pin' ? d.pin2 : d.pin;
  return `<select class="pin" data-pin="${d.id}:${key}" aria-label="Pin op de ESP32">${KINDS[d.kind].pins.map(p => {
    const u = used.get(p);
    return `<option value="${p}" ${p === d[key] ? 'selected' : ''} ${u || p === other ? 'disabled' : ''}>${p === 0 ? 'BOOT-knopje' : pinName(p)}${u ? ' (' + esc(u.name) + ')' : ''}</option>`;
  }).join('')}</select>`;
}

function renderWiring(p) {
  const d = dev(selected);
  $('#boardSvg').innerHTML = wiringSvg(d, p);
  if (!d) { $('#whead').innerHTML = '<h2><span class="n">2</span> Aansluiten</h2>'; $('#wiring').innerHTML = ''; return; }
  const k = KINDS[d.kind], rows = p.rows.get(d.id);
  $('#whead').innerHTML = `<h2><span class="n">2</span> Zo sluit je ${esc(label(d))} aan</h2><button class="x help" data-help title="Wat is plus, min en een seintje?">?</button><span class="spacer"></span>`
    + (k.out ? '<span class="small">Probeer:</span>' + k.tests.map(([s, v]) => `<button class="test" data-test="${d.id}|${s}|${v ?? ''}">${TEST_LABELS[s]}</button>`).join('')
             : `<span class="small">Nu:</span> <b class="live" data-live="${d.id}" style="color:${k.color}">–</b>`);
  const shared = rows.filter(w => w.key != null && w.num == null && p.users[w.key].length > 1)
    .map(w => `<b>${esc(w.esp)}</b> met ${esc(p.users[w.key].filter(o => o !== d).map(label).join(' en '))}`);
  $('#wiring').innerHTML = (k.needs ? `<p class="needs">Nog niet aansluiten. Eerst nodig: ${esc(k.needs)}.</p>` : k.must ? `<p class="needs">Hiervoor heb je ${esc(k.must)} nodig. Zonder niet aansluiten.</p>` : '')
    + rows.map(w => {
      if (w.pin === 'BOOT') return `<div class="wrow">${esc(w.lab)}: ${esc(w.hint)}.</div>`;
      if (!w.color) return `<div class="wrow"><span><b>${esc(w.lab)}</b> gaat naar <b>${esc(w.pin)}</b></span></div>`;
      const key = !k.pins.length ? null : w.num === d.pin ? 'pin' : w.num === d.pin2 ? 'pin2' : null;
      return `<div class="wrow" data-wire="${w.i}"><span class="sw" style="background:${w.color}"></span>
        <select data-wcolor="${d.id}:${w.i}" aria-label="Kleur van het draadje">${Object.keys(WIRE_COLORS).map(c => `<option ${c === w.name ? 'selected' : ''}>${c}</option>`).join('')}</select>
        <span>draadje: <b>${esc(w.lab)}</b> gaat naar</span> ${key ? pinSelect(d, key) : `<b class="to">${esc(w.esp)}</b>`}
        ${w.inline ? `<span class="small">met ${esc(w.inline)} ertussen</span>` : ''}${w.hint ? `<span class="small">${esc(w.hint)}</span>` : ''}</div>`;
    }).join('')
    + (shared.length && !k.needs ? `<p class="share">Delen: ${shared.join(', ')}. Op een pinnetje past maar één draadje: maak ze samen vast in een lasdop, met één draadje naar de pin.</p>` : '')
    + `<p class="note">${esc(k.note)}</p>`;
}

$('#wiring').addEventListener('change', e => {
  const el = e.target, ds = el.dataset;
  if (ds.wcolor) { const [id, i] = ds.wcolor.split(':'); dev(id).colors = { ...dev(id).colors, [i]: el.value }; }
  else if (ds.pin) { const [id, key] = ds.pin.split(':'); dev(id)[key] = +el.value; }
  else return;
  changed();
});
// Wijs een regel aan en alleen dat draadje blijft helder.
function highlight(i) { for (const g of document.querySelectorAll('#boardSvg .w')) g.classList.toggle('dim', i != null && g.dataset.w !== i); }
$('#wiring').addEventListener('mouseover', e => highlight(e.target.closest('[data-wire]')?.dataset.wire));
$('#wiring').addEventListener('mouseleave', () => highlight());
$('#whead').addEventListener('click', async e => {
  const b = e.target.closest('button');
  if (!b) return;
  if (b.dataset.help != null) return $('#help').hidden = false;
  const [id, kind, value] = b.dataset.test.split('|');
  if (await ensureSent()) send('X ' + encodeStep({ kind, dev: id, value: value === '' ? undefined : isNaN(value) ? value : +value }, model));
});

function render() { const p = plan(model); renderRules(); renderDevices(p); renderWiring(p); }

// ---- de ESP32 -------------------------------------------------------------

let port, writer, reader, closing = false, toastTimer, fw = 0;   // fw: de versie die de ESP32 meldt (HI alsdan <versie>)

function toast(text, bad) {
  const t = $('#toast');
  t.textContent = text;
  t.className = 'toast ' + (bad ? 'bad' : 'good');
  t.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.hidden = true, bad ? 6000 : 2500);
}
function setConn(text) {
  $('#conn').textContent = text || 'Niet verbonden';
  $('#conn').className = 'conn ' + (text ? 'on' : '');
  $('#btnConnect').textContent = port ? 'Verbreek' : 'Verbind';
}

async function connect() {
  if (port) return disconnect();
  if (!navigator.serial) return toast('Dit werkt alleen in Chrome of Edge.', true);
  try { port = await navigator.serial.requestPort(); } catch { return; }
  openPort();
}
async function openPort() {
  try {
    await port.open({ baudRate: 115200 });
    await port.setSignals({ dataTerminalReady: false, requestToSend: false });  // anders blijft het bordje in reset hangen
  } catch (e) { toast('Poort openen lukt niet: ' + e.message, true); port = null; return setConn(null); }
  writer = port.writable.getWriter();
  dirty = true;
  fw = 0;
  setConn('Verbonden, even wachten…');
  readLoop();
  setTimeout(() => send('HELLO'), 1200);
}
async function readLoop() {
  const dec = new TextDecoder();
  let buf = '';
  reader = port.readable.getReader();
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      buf += dec.decode(value, { stream: true });
      let i;
      while ((i = buf.indexOf('\n')) >= 0) { handle(buf.slice(0, i).trim()); buf = buf.slice(i + 1); }
    }
  } catch {}  // kabel eruit
  reader.releaseLock();
  reader = null;
  if (!closing) { try { writer.releaseLock(); await port.close(); } catch {} port = writer = null; setConn(null); }
}
async function disconnect() {
  closing = true;
  try { await reader?.cancel(); await new Promise(r => setTimeout(r, 50)); writer?.releaseLock(); await port?.close(); } catch {}
  port = writer = reader = null;
  closing = false;
  setConn(null);
}
async function send(text) {
  if (!writer) return false;
  await writer.write(new TextEncoder().encode(text.endsWith('\n') ? text : text + '\n'));
  return true;
}
function handle(line) {
  const [w, ...a] = line.split(' ');
  if (w === 'HI') { fw = +a[1] || 1; setConn(`Verbonden met de ESP32 (${a[2] || 'ESP32'})`); localStorage.setItem('alsdan.connected', '1'); $('#setup').hidden = true; }
  else if (w === 'OK') { if (a.length) { dirty = false; toast('Staat erop!'); } }
  else if (w === 'ERR') toast('De ESP32 zegt: ' + a.join(' '), true);
  else if (w === 'L') toast(a.join(' '), true);
  else if (w === 'S' && sent) {
    const d = sent.devices[+a[0]];
    if (d) for (const el of document.querySelectorAll(`[data-live="${d.id}"]`)) el.textContent = KINDS[d.kind].live(+a[1]);
  } else if (w === 'E' && sent) {
    const el = document.querySelector(`[data-rule="${sent.rules[+a[0]]}"]`);
    if (el) { el.classList.remove('fired'); void el.offsetWidth; el.classList.add('fired'); }
  }
}

async function upload() {
  if (!writer) { $('#setup').hidden = false; return toast('Verbind eerst met de ESP32 (knop Verbind).', true); }
  const old = model.devices.find(d => fw && KINDS[d.kind].fw > fw);   // fw 0: nog niet gemeld, dan zegt de ESP32 het zelf wel
  if (old) { $('#setup').hidden = false; return toast(`Voor ${old.name} moet er nieuwe firmware op de ESP32. Klik op “Zet de firmware op de ESP32”.`, true); }
  const enc = encodeProgram(model);
  sent = { rules: enc.rules, devices: model.devices.map(d => ({ id: d.id, kind: d.kind })) };
  await send(enc.text);
  if (enc.skipped.length) toast(`${enc.skipped.length} regel(s) nog niet af, die gaan niet mee.`, true);
}
async function ensureSent() {
  if (!writer) { await upload(); return false; }
  if (dirty) { await upload(); await new Promise(r => setTimeout(r, 400)); }
  return true;
}

$('#btnConnect').onclick = connect;
$('#btnSend').onclick = upload;
$('#btnSetup').onclick = () => $('#setup').hidden = false;
// een venstertje sluit met zijn knop of met een klik ernaast
document.addEventListener('click', e => { const m = e.target.closest('.modal'); if (m && (e.target === m || e.target.closest('[data-close]'))) m.hidden = true; });
$('#setup').addEventListener('click', e => { if (e.target.closest('esp-web-install-button')) { disconnect(); setTimeout(() => $('#setup').hidden = true); } }, true);  // de flasher heeft de poort zelf nodig, en zijn eigen venster mag niet achter het onze vallen
$('#setup').hidden = !!localStorage.getItem('alsdan.connected');

render();
if (navigator.serial) navigator.serial.getPorts().then(ports => { if (ports.length === 1) { port = ports[0]; openPort(); } });
