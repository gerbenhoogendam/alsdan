// Als-Dan: hoe elk onderdeel eruitziet in het aansluitplaatje. Een foto van het echte onderdeel (web/parts/, uit Gerbens
// eigen foto's) of een tekening, in eigen maten (w × h), met in `pins` per draadje van KINDS[..].wiring, in dezelfde
// volgorde, het punt waar dat draadje begint. `marks` zijn punten met een naam, voor onderdelen die nog niet aan het
// bordje mogen. `hold` zegt hoe je het onderdeel moet houden om het plaatje te laten kloppen.

const leg = (x1, y1, x2, y2) => `<path d="M${x1} ${y1}L${x2} ${y2}" stroke="#a8adb5" stroke-width="6" stroke-linecap="round"/>`;
const TOF_PINS = ['VIN', 'GND', 'SCL', 'SDA', 'GPIO1', 'XSHUT'], tofY = name => 45 + TOF_PINS.indexOf(name) * 34;

export const ART = {
  // HW-740 (AM312), van de kant met de onderdeeltjes gezien: het pinnetje bij het zwarte blokje (de spanningsregelaar) is plus,
  // het middelste het seintje, dat bij het losse blokje (C1) min.
  pir: () => ({ w: 530, h: 280, img: 'parts/pir.jpg', pins: [[525, 157], [525, 108], [525, 57]],
    hold: 'Wit bolletje links, zwart blokje onderaan.' }),
  // De draadjes zijn al gesoldeerd en lopen rechts de foto uit: wit op DI, oranje op 5V, rood op GND.
  ring: () => ({ w: 660, h: 414, img: 'parts/ring.jpg', pins: [[660, 213], [660, 256], [660, 156]],
    hold: 'De draadjes zitten al aan de ring vast.' }),
  lamp: () => ({ w: 480, h: 420, img: 'parts/lamp.jpg', pins: [], marks: [[265, 82, 'plus'], [189, 334, 'min']],
    hold: 'Plus bij het plusje, min bij het minnetje.' }),
  // INMP441, de kant met de lettertjes, waar de pinnetjes uitsteken. Links L/R, WS, SCK; rechts GND (de opdruk is weggekrast),
  // VDD, SD. De foto is 41 graden gedraaid, zodat elk pinnetje op zijn eigen hoogte zit en de draadjes elkaar niet afdekken.
  mic: () => ({ w: 270, h: 270, img: 'parts/mic.jpg', pins: [[170, 159], [179, 110], [160, 207], [51, 186], [59, 139]],
    hold: 'De kant met de lettertjes naar je toe.' }),
  led: () => ({ w: 300, h: 180, pins: [[290, 70], [240, 112]],
    svg: `<path d="M75 40a50 50 0 0 0 0 100h45v-100z" fill="#ffd84d" stroke="#c9a400" stroke-width="3"/><rect x="118" y="32" width="12" height="116" rx="3" fill="#e0b82c"/>${leg(130, 70, 290, 70)}${leg(130, 112, 240, 112)}` }),
  speaker: () => ({ w: 300, h: 220, pins: [[285, 88], [285, 132]],
    svg: `<circle cx="110" cy="110" r="95" fill="#2b2f36"/><circle cx="110" cy="110" r="78" fill="#3d434d"/><circle cx="110" cy="110" r="34" fill="#1d2026"/><rect x="196" y="76" width="26" height="68" rx="4" fill="#c9a23f"/>${leg(215, 88, 285, 88)}${leg(215, 132, 285, 132)}` }),
  button: d => d.pin === 0 ? null : ({ w: 300, h: 200, pins: [[285, 78], [285, 122]],
    svg: `<rect x="60" y="40" width="130" height="120" rx="12" fill="#30343b"/><circle cx="125" cy="100" r="38" fill="#111"/><circle cx="125" cy="100" r="28" fill="#666"/>${leg(190, 78, 285, 78)}${leg(190, 122, 285, 122)}` }),
  touch: () => ({ w: 300, h: 160, pins: [[150, 80]],
    svg: `<rect x="30" y="30" width="120" height="100" rx="6" fill="#d7dbe0" stroke="#aab0b8" stroke-width="2"/><text x="90" y="86" text-anchor="middle" font-size="17" fill="#555">folie</text>` }),
  // shortcut: de volgorde van de gaatjes is die van de meeste VL53L1X-bordjes, niet nagekeken op dat van Gerben; de namen
  // staan erbij, vervang dit door een foto zodra die er is.
  tof: () => ({ w: 300, h: 260, pins: ['VIN', 'GND', 'SDA', 'SCL'].map(n => [232, tofY(n)]),
    hold: 'Zoek de lettertjes op het sensorbordje.',
    svg: `<rect x="60" y="20" width="190" height="220" rx="10" fill="#5b3fa8"/><rect x="85" y="100" width="56" height="44" rx="3" fill="#111"/>${TOF_PINS.map(n => `<circle cx="232" cy="${tofY(n)}" r="7" fill="#d9c47a" stroke="#333"/><text x="216" y="${tofY(n) + 5}" text-anchor="end" font-size="14" font-weight="700" fill="#fff">${n}</text>`).join('')}` }),
  motor: () => ({ w: 300, h: 180, pins: [],
    svg: `<rect x="50" y="50" width="150" height="80" rx="10" fill="#c7ccd4" stroke="#8d949e" stroke-width="3"/><rect x="200" y="62" width="34" height="56" rx="4" fill="#d6b24a"/><rect x="234" y="84" width="46" height="12" rx="3" fill="#8d949e"/>` }),
};
