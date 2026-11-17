"""Measures the menu knob filter of the running game.

Turns VOL-L through SpiceAPI and reads from game memory what the filter passes on to the menus, so different frame
rates and patch versions can be compared with exactly the same input. Tests: constant speeds (including very slow
turns), starting from rest, reversing, small back-and-forth movement and single small nudges.

Only for soundvoltex.dll KFC-6ac4e43b_7ad8d8 (2026101300): the memory addresses below are from docs/逆向记录.md.
Needs spice2x started with -api <port> -apipass <password>. The password is read from the environment variable
SPICEAPI_PASS, or from spicetools.xml with --cfg. Python 3.8+, standard library only.

    python tools/knob-test.py --cfg <spicetools.xml> [--json out.json] [--quick]
    python tools/knob-test.py --port 1337 --wait 120 --json out.json      (password in SPICEAPI_PASS)
"""
import argparse
import ctypes
import ctypes.wintypes as W
import json
import logging
import math
import os
import socket
import sys
import time
import xml.etree.ElementTree as ET

log = logging.getLogger('knob-test')

# soundvoltex.dll 2026101300
PE_STAMP, PE_ENTRY = 0x6AC4E43B, 0x7AD8D8
KNOB_TABLE = 0x1277960        # 8 entries of 0x88 bytes, returned by 0x263b40, updated every frame by 0x266240
ENTRY_SIZE, ENTRIES = 0x88, 8
# offsets inside an entry: the filter state (0x262d90) starts at +0x40
OFF_PREV, OFF_LAST, OFF_STEP, OFF_IDLE, OFF_RESULT = 0x40, 0x60, 0x70, 0x7C, 0x80
FILTER_START, FILTER_GAIN = 0x262DD4, 0x262E7D
MODES = {  # first bytes of the filter's dt code -> what is installed
    '48B8DB34': 'original',
    '498D4001': 'PR #2 fixed 120 Hz clock',
    '807F2800': 'at most once every 1/120 s',
}
SWEEP = ([0.01, 0.02, 0.03, 0.05, 0.075] + [round(0.1 + 0.025 * i, 3) for i in range(17)]
         + [round(0.55 + 0.05 * i, 2) for i in range(10)] + [1.25, 1.5])
QUICK_SWEEP = [0.02, 0.1, 0.2, 0.3, 0.4, 0.6, 0.8, 1.0, 1.5]


# --- SpiceAPI: JSON messages ending in 0x00; with a password both directions go through one RC4 stream
class RC4:
    def __init__(self, key: bytes):
        s, j = list(range(256)), 0
        for i in range(256):
            j = (j + s[i] + key[i % len(key)]) & 0xFF
            s[i], s[j] = s[j], s[i]
        self.s, self.i, self.j = s, 0, 0

    def crypt(self, data: bytes) -> bytes:
        s, i, j, out = self.s, self.i, self.j, bytearray(data)
        for k in range(len(out)):
            i = (i + 1) & 0xFF
            j = (j + s[i]) & 0xFF
            s[i], s[j] = s[j], s[i]
            out[k] ^= s[(s[i] + s[j]) & 0xFF]
        self.i, self.j = i, j
        return bytes(out)


class SpiceAPI:
    def __init__(self, port: int, password: str, timeout: float = 3.0):
        self.sock = socket.create_connection(('127.0.0.1', port), timeout=timeout)
        self.sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        self.rc4 = RC4(password.encode('utf-8')) if password else None
        self.next_id = 0

    def call(self, module: str, function: str, *params):
        self.next_id += 1
        msg = json.dumps({'id': self.next_id, 'module': module, 'function': function, 'params': list(params)},
                         separators=(',', ':')).encode('utf-8') + b'\0'
        self.sock.sendall(self.rc4.crypt(msg) if self.rc4 else msg)
        buf = bytearray()
        while not buf.endswith(b'\0'):
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError('SpiceAPI closed the connection (wrong password?)')
            buf += self.rc4.crypt(chunk) if self.rc4 else chunk
        if len(buf) == 1:
            raise ConnectionError('SpiceAPI could not read the request (wrong password?)')
        res = json.loads(buf[:-1].decode('utf-8'))
        if res.get('id') != self.next_id:
            raise RuntimeError(f'SpiceAPI answered request {res.get("id")} instead of {self.next_id}')
        if res.get('errors'):
            raise RuntimeError(f'SpiceAPI {module}.{function}: {res["errors"]}')
        return res.get('data')

    def knob(self, value: float):
        self.call('analogs', 'write', ['VOL-L', value % 1.0])

    def close(self):
        self.sock.close()


# --- reading the game's memory
k32 = ctypes.WinDLL('kernel32', use_last_error=True)


class PROCESSENTRY32W(ctypes.Structure):
    _fields_ = [('dwSize', W.DWORD), ('cntUsage', W.DWORD), ('th32ProcessID', W.DWORD),
                ('th32DefaultHeapID', ctypes.c_size_t), ('th32ModuleID', W.DWORD), ('cntThreads', W.DWORD),
                ('th32ParentProcessID', W.DWORD), ('pcPriClassBase', W.LONG), ('dwFlags', W.DWORD),
                ('szExeFile', W.WCHAR * 260)]


class MODULEENTRY32W(ctypes.Structure):
    _fields_ = [('dwSize', W.DWORD), ('th32ModuleID', W.DWORD), ('th32ProcessID', W.DWORD),
                ('GlblcntUsage', W.DWORD), ('ProccntUsage', W.DWORD), ('modBaseAddr', ctypes.c_void_p),
                ('modBaseSize', W.DWORD), ('hModule', W.HMODULE), ('szModule', W.WCHAR * 256),
                ('szExePath', W.WCHAR * 260)]


k32.CreateToolhelp32Snapshot.restype = W.HANDLE
k32.CreateToolhelp32Snapshot.argtypes = [W.DWORD, W.DWORD]
for name, entry in (('Process32FirstW', PROCESSENTRY32W), ('Process32NextW', PROCESSENTRY32W),
                    ('Module32FirstW', MODULEENTRY32W), ('Module32NextW', MODULEENTRY32W)):
    getattr(k32, name).argtypes = [W.HANDLE, ctypes.POINTER(entry)]
    getattr(k32, name).restype = W.BOOL
k32.OpenProcess.restype = W.HANDLE
k32.OpenProcess.argtypes = [W.DWORD, W.BOOL, W.DWORD]
k32.ReadProcessMemory.argtypes = [W.HANDLE, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t,
                                  ctypes.POINTER(ctypes.c_size_t)]
k32.ReadProcessMemory.restype = W.BOOL
k32.CloseHandle.argtypes = [W.HANDLE]
INVALID_HANDLE = ctypes.c_void_p(-1).value


def snapshot(flags: int, pid: int, entry_type, first, nxt):
    h = k32.CreateToolhelp32Snapshot(flags, pid)
    if h == INVALID_HANDLE:
        raise OSError(ctypes.get_last_error(), 'CreateToolhelp32Snapshot failed')
    try:
        e = entry_type()
        e.dwSize = ctypes.sizeof(e)
        ok = first(h, ctypes.byref(e))
        while ok:
            yield e
            ok = nxt(h, ctypes.byref(e))
    finally:
        k32.CloseHandle(h)


class NotReady(Exception):
    """The game is not running yet or has not loaded the dll."""


class Game:
    def __init__(self, exe: str = 'spice64.exe', dll: str = 'soundvoltex.dll'):
        pids = [e.th32ProcessID for e in snapshot(0x2, 0, PROCESSENTRY32W, k32.Process32FirstW, k32.Process32NextW)
                if e.szExeFile.lower() == exe]
        if len(pids) != 1:
            raise NotReady(f'found {len(pids)} running {exe}')
        self.pid = pids[0]
        try:
            bases = [e.modBaseAddr for e in snapshot(0x18, self.pid, MODULEENTRY32W, k32.Module32FirstW,
                                                      k32.Module32NextW) if e.szModule.lower() == dll]
        except OSError as e:  # the process is still starting (ERROR_PARTIAL_COPY) or just exited
            raise NotReady(f'cannot list the modules of {exe}: {e}') from e
        if not bases:
            raise NotReady(f'{dll} is not loaded yet')
        self.base = bases[0]
        self.h = k32.OpenProcess(0x10 | 0x1000, False, self.pid)  # VM_READ | QUERY_LIMITED_INFORMATION
        if not self.h:
            raise OSError(ctypes.get_last_error(), 'OpenProcess failed (run this as the same user as the game)')
        self.buf = ctypes.create_string_buffer(0x1000)

    def read(self, rva: int, size: int) -> bytes:
        got = ctypes.c_size_t()
        if not k32.ReadProcessMemory(self.h, self.base + rva, self.buf, size, ctypes.byref(got)) or got.value != size:
            raise OSError(ctypes.get_last_error(), f'ReadProcessMemory at +{rva:#x} failed')
        return self.buf.raw[:size]

    def version(self):
        pe = int.from_bytes(self.read(0x3C, 4), 'little')
        head = self.read(pe, 0x30)
        return int.from_bytes(head[8:12], 'little'), int.from_bytes(head[0x28:0x2C], 'little')

    def mode(self) -> str:
        start = self.read(FILTER_START, 4).hex().upper()
        gain = 'gain without dt' if self.read(FILTER_GAIN, 4).hex().upper() == '0F1F4000' else 'gain x dt'
        return f'{MODES.get(start, "unknown " + start)}, {gain}'

    def entry(self, i: int):
        b = self.read(KNOB_TABLE + i * ENTRY_SIZE, ENTRY_SIZE)
        i32 = lambda o: int.from_bytes(b[o:o + 4], 'little', signed=True)  # noqa: E731
        return {'prev': i32(OFF_PREV), 'last': int.from_bytes(b[OFF_LAST:OFF_LAST + 8], 'little', signed=True),
                'step': i32(OFF_STEP), 'idle': i32(OFF_IDLE), 'result': i32(OFF_RESULT)}

    def close(self):
        k32.CloseHandle(self.h)


def wrap(d: int) -> int:
    return (d + 512) % 1024 - 512


class Probe:
    """Collects the output of one table entry, reading it once per run of the knob filter.

    frame_index: an entry of the untouched knob, whose idle counter counts frames; used to spot frame stalls.
    menu: (entry, step) of the same knob with real menu step sizes; their results are menu steps."""

    def __init__(self, game: Game, index: int, frame_index: int, menu=()):
        self.game, self.index, self.frame_index, self.menu = game, index, frame_index, list(menu)
        e = game.entry(index)
        self.prev, self.last = e['prev'], e['last']
        self.pending = None
        self.reset(0)

    def reset(self, sign: int):
        """sign: the direction the game should see (+1 / -1), 0 when the knob is not meant to go anywhere."""
        self.fsign = sign
        self.out = self.moved = self.runs = self.missed = self.plus = self.minus = 0
        self.menu_steps = {step: 0 for _, step in self.menu}  # menu steps in either direction
        self.frame, self.frame_t, self.max_gap = self.game.entry(self.frame_index)['idle'], time.perf_counter(), 0.0
        self.mark(sign)

    def mark(self, sign: int):
        """Starts timing the first output in direction sign (e.g. after reversing) without clearing the totals."""
        self.sign, self.t0, self.moved_mark = sign, time.perf_counter(), self.moved
        self.first_t = self.first_moved = None

    def poll(self):
        e = self.game.entry(self.index)
        now = time.perf_counter()
        frame = self.game.entry(self.frame_index)['idle']
        if frame != self.frame:
            self.max_gap = max(self.max_gap, now - self.frame_t)
            self.frame, self.frame_t = frame, now
        if self.pending is not None and now - self.pending >= 0.0002:
            # the result is written right after the filter returns, so read it a moment after its timestamp changed
            n = e['result']
            self.moved += wrap(e['prev'] - self.prev)  # adds up correctly even if a run was missed
            self.prev = e['prev']
            self.out += n
            self.runs += 1
            if self.fsign == 0 or n * self.fsign < 0:
                self.minus += abs(n)  # against the direction of reset(), or any output when it was 0
            else:
                self.plus += abs(n)
            for i, step in self.menu:  # updated in the same frame, right after this entry
                self.menu_steps[step] += abs(self.game.entry(i)['result'])
            if self.sign and n * self.sign > 0 and self.first_t is None:
                self.first_t, self.first_moved = now - self.t0, abs(self.moved - self.moved_mark)
            self.pending = None
        if e['last'] != self.last:
            if self.pending is not None:
                self.missed += 1  # two runs between polls: the first one's result is lost
            self.last = e['last']
            self.pending = now

    def run(self, seconds: float, step=None):
        end = time.perf_counter() + seconds
        while time.perf_counter() < end:
            if step:
                step(time.perf_counter())
            self.poll()

    def summary(self):
        ratio = self.out / self.moved if self.moved else None
        return {'moved': abs(self.moved), 'passed': abs(self.out), 'ratio': ratio, 'wrong': self.minus,
                'first_ms': None if self.first_t is None else round(self.first_t * 1000),
                'first_moved': self.first_moved, 'missed_runs': self.missed,
                'frame_gap_ms': round(self.max_gap * 1000, 1),
                'menu_steps': {str(k): v for k, v in self.menu_steps.items()}}

    def clean(self, max_gap_s: float = 0.015) -> bool:
        """No frame stall and no missed run since reset(): the measurement can be trusted."""
        return self.max_gap <= max_gap_s and not self.missed


class Knob:
    """Drives VOL-L like a 1000 Hz mouse would: one position update per millisecond."""

    def __init__(self, api: SpiceAPI, orient: int, span: int):
        self.api, self.orient, self.span = api, orient, span
        self.pos = 0.0          # in turns
        self.next_write = 0.0

    def driver(self, path, seconds: float):
        """path(t) -> offset in turns from the current position; returns a step function for Probe.run."""
        start = self.pos
        t0 = [None]

        def step(now):
            if t0[0] is None:
                t0[0] = now
            t = now - t0[0]
            if now >= self.next_write and t <= seconds:
                self.api.knob(start + path(t))
                self.next_write = now + 0.001
        return step, lambda: start + path(seconds)

    def move(self, probe: Probe, path, seconds: float, tail: float, sign: int, keep: bool = False):
        """keep: continue the totals of the previous move and only restart the first-output timing."""
        step, end = self.driver(path, seconds)
        if keep:
            probe.mark(sign * self.orient)
        else:
            probe.reset(sign * self.orient)
        probe.run(seconds + tail, step)
        self.pos = end() % 1.0
        self.api.knob(self.pos)


def frames_per_second(game: Game, index: int, seconds: float = 1.0) -> float:
    """The idle counter of an untouched knob entry goes up by one every frame."""
    a, t0 = game.entry(index)['idle'], time.perf_counter()
    time.sleep(seconds)
    return (game.entry(index)['idle'] - a) / (time.perf_counter() - t0)


def calibrate(game: Game, api: SpiceAPI, timeout: float = 30.0):
    """VOL-L entry with menu step 1 (its result is the filter output), VOL-R entry, orientation, positions per turn."""
    deadline = time.monotonic() + timeout
    values = (0.30, 0.35, 0.40, 0.45, 0.50)  # away from 0.0, where the game holds the knob at 1023 for a bit
    while True:
        api.knob(values[0])
        time.sleep(0.5)  # deliberate: let the filter pick up the start value
        seen = []
        for value in values:
            api.knob(value)
            time.sleep(0.25)  # deliberate: let a few runs of the filter pick the value up
            seen.append([game.entry(i) for i in range(ENTRIES)])
        steps = [[wrap(seen[k + 1][i]['prev'] - seen[k][i]['prev']) for k in range(len(values) - 1)]
                 for i in range(ENTRIES)]
        # every 0.05 turn should be about 50 positions in one direction; a stale read breaks that
        left = [i for i in range(ENTRIES) if all(30 <= abs(s) <= 80 for s in steps[i])
                and len({s > 0 for s in steps[i]}) == 1]
        right = [i for i in range(ENTRIES) if not any(steps[i])]
        if len(left) == ENTRIES // 2 and len(right) == ENTRIES // 2:
            break
        if time.monotonic() > deadline:
            raise SystemExit(f'Writing VOL-L through the API did not move the knob steadily: {steps}')
        log.info('knob did not follow the API steadily yet, retrying')
    index = min(left, key=lambda i: seen[-1][i]['step'])
    if seen[-1][index]['step'] != 1:
        log.warning('no VOL-L entry with menu step 1; using step %d', seen[-1][index]['step'])
    total = sum(abs(s) for s in steps[index])
    menu = [(i, seen[-1][i]['step']) for i in left if i != index]
    return index, right[0], menu, 1 if steps[index][0] > 0 else -1, round(total / (values[-1] - values[0]))


def enter_test_menu(api: SpiceAPI):
    """The attract screens stall for up to seconds while loading; the test menu runs at a steady frame rate."""
    api.call('buttons', 'write', ['Test', 1])
    time.sleep(0.3)  # deliberate: hold the button for a few frames
    api.call('buttons', 'write_reset')
    time.sleep(5)  # deliberate: let the scene change finish


def measured(probe: Probe, label: str, fn, tries: int = 3):
    """Runs one test again when a frame stall or a missed run spoiled it."""
    for attempt in range(1, tries + 1):
        r = fn()
        if probe.clean():
            break
        log.warning('  %s: frame gap %.0f ms, %d missed runs (try %d of %d)', label, probe.max_gap * 1000,
                    probe.missed, attempt, tries)
    r['tries'] = attempt
    r['clean'] = probe.clean()
    return r


def run_suite(game: Game, api: SpiceAPI, quick: bool, turn_s: float, pause_s: float,
              tests=('sweep', 'reverse', 'tremor', 'nudge'), tremor_amps=(1, 2, 4, 8), tremor_reps: int = 1):
    index, right, menu, orient, span = calibrate(game, api)
    probe = Probe(game, index, right, menu)
    knob = Knob(api, orient, span)
    api.knob(0.0)
    probe.run(1.5)
    probe.reset(0)
    probe.run(2.0)
    info = {'filter': game.mode(), 'runs_per_s': round(probe.runs / 2.0, 1), 'positions_per_turn': span,
            'fps': round(frames_per_second(game, right), 1)}
    log.info('filter: %s | %s FPS | filter runs %s/s | %d positions per turn', info['filter'], info['fps'],
             info['runs_per_s'], span)
    result = {'info': info, 'sweep': [], 'reverse': [], 'tremor': [], 'nudge': []}

    def sweep(speed, direction):
        probe.run(pause_s)
        knob.move(probe, lambda t: direction * speed * t, turn_s, 0.5, direction)
        return {'speed': speed, **probe.summary()}

    direction = 1
    for speed in (QUICK_SWEEP if quick else SWEEP) if 'sweep' in tests else ():  # constant speed from rest
        r = measured(probe, f'sweep {speed}', lambda: sweep(speed, direction))
        result['sweep'].append(r)
        log.info('  sweep %.3f turn/s  ratio %s  first output after %s ms / %s positions', speed,
                 'n/a' if r['ratio'] is None else f'{r["ratio"]:.2f}', r['first_ms'], r['first_moved'])
        direction = -direction

    def reverse(speed):  # turn one way, then straight back without stopping
        probe.run(pause_s)
        knob.move(probe, lambda t: speed * t, 1.5, 0.0, 1)
        forward = abs(probe.moved)
        knob.move(probe, lambda t: -speed * t, 1.5, 0.5, -1, keep=True)
        s = probe.summary()
        # forward steps beyond the forward turn: the menu went on in the old direction after reversing
        return {'speed': speed, 'forward_moved': forward, 'forward_passed': probe.plus,
                'back_moved': abs(probe.moved - probe.moved_mark), 'back_passed': probe.minus,
                'overshoot': max(0, probe.plus - forward), 'lost_ms': s['first_ms'],
                'lost_positions': s['first_moved'], 'frame_gap_ms': s['frame_gap_ms']}

    for speed in (0.2, 0.5, 1.0) if 'reverse' in tests else ():
        for rep in range(2):  # borderline timing: repeat and average in the report
            r = {**measured(probe, f'reverse {speed}', lambda: reverse(speed)), 'rep': rep}
            result['reverse'].append(r)
            log.info('  reverse %.1f turn/s  back: %s positions / %s ms before the first step, overshoot %d', speed,
                     r['lost_positions'], r['lost_ms'], r['overshoot'])

    def tremor(amp):  # hand tremor: 8 Hz back and forth around one spot, should pass nothing
        probe.run(pause_s)
        knob.move(probe, lambda t: amp / span * math.sin(2 * math.pi * 8 * t), 3.0, 0.5, 0)
        return {'amplitude': amp, **probe.summary()}

    for amp in tremor_amps if 'tremor' in tests else ():
        for rep in range(tremor_reps):
            r = {**measured(probe, f'tremor {amp}', lambda: tremor(amp)), 'rep': rep}
            result['tremor'].append(r)
            log.info('  tremor +-%d positions  steps out %d', amp, r['wrong'])  # sign 0: every step counts

    def nudge(size, ms):  # one push of a few positions, then still: a quick flick and a slower push
        probe.run(pause_s)
        knob.move(probe, lambda t: size / span * min(t / (ms / 1000), 1.0), ms / 1000 + 0.01, 1.0, 1)
        return {'positions': size, 'ms': ms, **probe.summary()}

    for ms in (50, 150) if 'nudge' in tests else ():
        for size in (4, 8, 16, 32, 64):
            for rep in range(3):  # it sits right on the game's direction-change delay, so it varies
                r = {**measured(probe, f'nudge {size}/{ms}ms', lambda: nudge(size, ms)), 'rep': rep}
                result['nudge'].append(r)
                log.info('  nudge %2d positions in %d ms  passed %d', size, ms, r['passed'])
    return result


def print_report(res):
    info = res['info']
    print(f'filter: {info["filter"]} | {info["fps"]} FPS | filter runs {info["runs_per_s"]}/s')
    print('speed(turn/s)  ratio  first output (ms / positions)  wrong-way')
    for r in res['sweep']:
        ratio = '  -  ' if r['ratio'] is None else f'{r["ratio"]:5.2f}'
        print(f'{r["speed"]:8.3f}      {ratio}   {r["first_ms"] if r["first_ms"] is not None else "-":>6} / '
              f'{r["first_moved"] if r["first_moved"] is not None else "-":<4}         {r["wrong"]}'
              + (f'  ({r["missed_runs"]} runs missed)' if r['missed_runs'] else ''))
    slow = [r['ratio'] or 0 for r in res['sweep'] if 0.05 <= r['speed'] < 0.4]
    mid = [r['ratio'] or 0 for r in res['sweep'] if 0.4 <= r['speed'] <= 1.0]
    dead = [r['speed'] for r in res['sweep'] if (r['ratio'] or 0) < 0.5]
    print(f'slow 0.05-0.4: {sum(slow) / len(slow):.2f}' if slow else 'slow: -', end='  ')
    print(f'medium 0.4-1.0: {sum(mid) / len(mid):.2f}' if mid else 'medium: -', end='  ')
    print(f'under 50%: {", ".join(f"{s:g}" for s in dead) or "-"}')
    for r in res['reverse']:
        print(f'reverse {r["speed"]} turn/s: back {r["lost_positions"]} positions / {r["lost_ms"]} ms before the '
              f'first step, overshoot {r["overshoot"]}, passed back {r["back_passed"]}/{r["back_moved"]}')
    print('tremor (+-positions: steps out): ' + ', '.join(f'{r["amplitude"]}: {r["wrong"]}' for r in res['tremor']))
    for ms in sorted({r['ms'] for r in res['nudge']}):
        print(f'nudge in {ms} ms (positions: passed): '
              + ', '.join(f'{r["positions"]}: {r["passed"]}' for r in res['nudge'] if r['ms'] == ms))


def connect(port: int, password: str, wait: float):
    """Waits until the game has loaded the dll, the knob table is running and the API answers."""
    deadline = time.monotonic() + wait
    while True:
        game = None
        try:
            game = Game()
            if game.version() != (PE_STAMP, PE_ENTRY):
                stamp, entry = game.version()
                raise SystemExit(f'This is KFC-{stamp:08x}_{entry:x}; the addresses here are only for '
                                 f'KFC-{PE_STAMP:08x}_{PE_ENTRY:x} (2026101300).')
            a = [game.entry(i)['last'] for i in range(ENTRIES)]
            time.sleep(0.5)
            if not any(x != y for x, y in zip(a, (game.entry(i)['last'] for i in range(ENTRIES)))):
                raise NotReady('the knob table is not running yet')
            return game, SpiceAPI(port, password)
        except (NotReady, ConnectionRefusedError, socket.timeout) as e:
            if game:
                game.close()
            if time.monotonic() > deadline:
                raise SystemExit(f'The game is not ready: {e}') from e
            log.info('waiting for the game: %s', e)
            time.sleep(2)  # polling interval while the game starts up


def main():
    logging.basicConfig(level=logging.INFO, format='%(message)s', stream=sys.stderr)
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--cfg', help='spicetools.xml to read API TCP Port / API Password from')
    ap.add_argument('--port', type=int, help='API TCP Port (password in the environment variable SPICEAPI_PASS)')
    ap.add_argument('--wait', type=float, default=0, help='seconds to wait for the game to come up')
    ap.add_argument('--settle', type=float, default=0, help='seconds to wait after that (boot screens stutter)')
    ap.add_argument('--test-menu', action='store_true',
                    help='press Test first: the attract screens stall while loading, the test menu does not')
    ap.add_argument('--quick', action='store_true', help='fewer speeds (about one minute)')
    ap.add_argument('--turn', type=float, default=2.5, help='turning time per speed in seconds')
    ap.add_argument('--pause', type=float, default=1.2, help='knob held still before each test')
    ap.add_argument('--json', help='also write all results to this file')
    ap.add_argument('--tests', default='sweep,reverse,tremor,nudge', help='which tests to run, comma separated')
    ap.add_argument('--tremor-amps', default='1,2,4,8', help='tremor amplitudes in positions')
    ap.add_argument('--tremor-reps', type=int, default=1, help='how often to repeat each tremor test')
    args = ap.parse_args()

    if args.port:
        port, password = args.port, os.environ.get('SPICEAPI_PASS', '')
    elif args.cfg:
        root = ET.parse(args.cfg).getroot()
        game_cfg = next((g for g in root.iter('game') if g.get('name') == 'Sound Voltex'), None)
        opts = {o.get('name'): o.get('value') for o in game_cfg.iter('option')} if game_cfg is not None else {}
        if not opts.get('api'):
            raise SystemExit(f'API TCP Port is not set for Sound Voltex in {args.cfg}')
        port, password = int(opts['api']), opts.get('apipass') or ''
    else:
        raise SystemExit('Give --cfg or --port.')

    game, api = connect(port, password, args.wait)
    if args.settle:
        log.info('game is up, waiting %g s before testing', args.settle)
        time.sleep(args.settle)  # deliberate: let the boot sequence finish so frame times are steady
    if args.test_menu:
        log.info('pressing Test to switch to the test menu')
        enter_test_menu(api)
    try:
        res = run_suite(game, api, args.quick, args.turn, args.pause, tests=set(args.tests.split(',')),
                        tremor_amps=[int(a) for a in args.tremor_amps.split(',')], tremor_reps=args.tremor_reps)
    finally:
        try:
            api.call('analogs', 'write_reset')
        finally:
            api.close()
            game.close()
    print_report(res)
    if args.json:
        with open(args.json, 'w', encoding='utf-8') as f:
            json.dump(res, f, ensure_ascii=False, indent=1)


if __name__ == '__main__':
    main()
