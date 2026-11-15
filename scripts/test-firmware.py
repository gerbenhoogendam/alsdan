#!/usr/bin/env python3
# Test de Als-Dan-firmware op een aangesloten ESP32 over de seriële poort, zonder pyserial.
#   python3 scripts/test-firmware.py [/dev/cu.usbserial-0001]
# Het bordje wordt gereset via RTS en het BOOT-knopje wordt "ingedrukt" via DTR (de auto-reset-schakeling van het DevKit).
import fcntl, os, select, struct, sys, termios, time

PORT = sys.argv[1] if len(sys.argv) > 1 else '/dev/cu.usbserial-0001'
GOOD = """PROG
D 0 BTN 0
D 1 LED 2
D 2 RING 16 12
D 3 SPK 14
D 4 MOT 18 19
D 5 TOF 21 22
D 6 TCH 4
D 7 PIR 27
D 8 MIC 32 33 35
R EVERY 700 ; SET 1 100 ; WAIT 100 ; SET 1 0
R PRESS 0 ; TUNE 3 0
R NEAR 5 20 ; COLOR 2 255 0 0
R LOUD 8 101 ; SET 1 100
RUN
"""
fails = 0


class Port:
    def __init__(self, path):
        self.fd = os.open(path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
        a = termios.tcgetattr(self.fd)
        a[0] = a[1] = a[3] = 0
        a[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
        a[4] = a[5] = termios.B115200
        a[6][termios.VMIN] = 0
        a[6][termios.VTIME] = 0
        termios.tcsetattr(self.fd, termios.TCSANOW, a)
        self.buf = b''

    def sig(self, dtr=None, rts=None):
        for flag, on in ((termios.TIOCM_DTR, dtr), (termios.TIOCM_RTS, rts)):
            if on is not None:
                fcntl.ioctl(self.fd, termios.TIOCMBIS if on else termios.TIOCMBIC, struct.pack('I', flag))

    def reset(self):
        self.sig(dtr=False, rts=True)
        time.sleep(0.1)
        self.sig(rts=False)

    def send(self, text):
        os.write(self.fd, (text if text.endswith('\n') else text + '\n').encode())

    def lines(self, seconds):
        end, out = time.time() + seconds, []
        while time.time() < end:
            if select.select([self.fd], [], [], 0.05)[0]:
                try:
                    self.buf += os.read(self.fd, 4096)
                except BlockingIOError:
                    pass
            while b'\n' in self.buf:
                line, self.buf = self.buf.split(b'\n', 1)
                out.append(line.decode('utf-8', 'replace').strip())
        return out

    def close(self):
        os.close(self.fd)


def check(name, cond, info=''):
    global fails
    fails += not cond
    print(('OK   ' if cond else 'FAIL ') + name + (f'  [{info}]' if info else ''))


def has(lines, prefix):
    return [l for l in lines if l.startswith(prefix)]


p = Port(PORT)
p.reset()
boot = p.lines(4)
check('HI na reset', bool(has(boot, 'HI alsdan 2')), ' | '.join(has(boot, 'HI')))
p.send('HELLO')
check('HELLO -> HI', bool(has(p.lines(1), 'HI alsdan 2')))
p.send('BLA')
check('onbekende regel -> ERR', bool(has(p.lines(1), 'ERR onbekend: BLA')))

p.send('PROG\nD 0 LED 2\nR WHATEVER 0 ; SET 0 100\nRUN\n')
check('fout in programma -> ERR regel 2', bool(has(p.lines(1.5), 'ERR regel 2')))

p.send('PROG\nD 0 MIC 32 33 35\nD 1 MIC 25 26 34\nRUN\n')
check('een tweede microfoon -> ERR regel 2', bool(has(p.lines(2), 'ERR regel 2')))

p.send(GOOD)
got = p.lines(3)
check('TOF zonder sensor meldt zich', bool(has(got, 'L afstandssensor niet gevonden')))
check('programma -> OK 9 onderdelen, 4 regels', 'OK 9 onderdelen, 4 regels' in got, ' | '.join(has(got, 'OK') + has(got, 'ERR')))

got = p.lines(2.5)
check('EVERY 700 vuurt ~3x in 2,5 s (E 0)', 2 <= len(has(got, 'E 0')) <= 4, f'{len(has(got, "E 0"))}x')
check('sensorwaarden komen binnen (S)', len(has(got, 'S ')) >= 8, f'{len(has(got, "S "))} regels')
check('knop los (S 0 0)', bool(has(got, 'S 0 0')))
check('afstand zonder sensor is -1 (S 5 -1)', bool(has(got, 'S 5 -1')))
check('toverdraadje in rust (S 6 0)', bool(has(got, 'S 6 0')))
mic = [int(l.split()[2]) for l in has(got, 'S 8 ')]
check('microfoon meldt hoe hard het is, 0 tot 100 (S 8 n)', len(mic) >= 4 and all(0 <= v <= 100 for v in mic), ' '.join(map(str, mic)))
check('regel LOUD met een grens van 101 gaat niet af (geen E 3)', not has(got, 'E 3'))

for cmd in ('X SET 1 100', 'X COLOR 2 0 255 0', 'X MOTOR 4 50', 'X BEEP 3 880 100', 'X RAINBOW 2', 'X MOTOR 4 0'):
    p.send(cmd)
    check(cmd + ' -> OK', 'OK' in p.lines(0.8))
p.send('X FOO 1')
got = p.lines(0.8)
check('onbekende stap -> L melding + OK', bool(has(got, 'L onbekende stap: FOO')) and 'OK' in got)

p.lines(0.3)
p.sig(dtr=True, rts=False)   # BOOT "ingedrukt" (IO0 laag via de reset-schakeling)
got = p.lines(1.5)
p.sig(dtr=False)
got += p.lines(1)
check('BOOT ingedrukt -> S 0 1 en regel 1 vuurt (E 1)', bool(has(got, 'S 0 1')) and bool(has(got, 'E 1')), ' | '.join(has(got, 'E ') + has(got, 'S 0 ')))
check('BOOT losgelaten -> S 0 0', bool(has(got[-6:], 'S 0 0')))

p.close()
time.sleep(0.3)
p = Port(PORT)
p.reset()
boot = p.lines(4)
check('na herstart staat het programma er nog (OK 9 onderdelen, 4 regels voor HI)',
      'OK 9 onderdelen, 4 regels' in boot and bool(has(boot, 'HI alsdan 2')), ' | '.join(has(boot, 'OK') + has(boot, 'HI')))
p.close()
print('KLAAR,', 'alles goed' if not fails else f'{fails} mislukt')
sys.exit(1 if fails else 0)
