"""Placeholder demo song for the Wizard, built on the guide-track layout to try the
Rhythm Thief idea in-game: full band on call bars (hitting with the throws), thinned
out on answer bars, a near-silent get-ready bar. Not meant to be the real song.
   python tools/wizard_guide/make_demo.py   ->  audio/music/wizard_demo.ogg (needs ffmpeg)"""
import os, re, subprocess, wave, numpy as np

SR, BPM = 44100, 110.0
SPB = 60.0 / BPM
INTRO, READY, ENDING = 4, 1, 4
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
rng = np.random.default_rng(7)

src = open(os.path.join(ROOT, "scripts", "wizard_game.gd"), encoding="utf-8").read()
block = src[src.index("const PATTERNS := ["):]; block = block[:block.index("\n]\n")]
patterns = [[float(b) for b, k in re.findall(r'\[([\d.]+), "(\w+)"\]', l)]
            for l in block.splitlines()[1:] if l.strip().startswith("[[")]

first_call = INTRO + READY
bars = first_call + 2 * len(patterns) + ENDING
n = int((bars * 4 + 4) * SPB * SR)
mix = np.zeros(n)
def put(s, beat, db=0.0):
    i = int(round(beat * SPB * SR)); j = min(n, i + len(s)); mix[i:j] += s[:j - i] * 10 ** (db / 20)
def t_(d): return np.arange(int(d * SR)) / SR
def hz(m): return 440 * 2 ** ((m - 69) / 12)

def kick():
    t = t_(0.35); f = 45 + 80 * np.exp(-t * 30)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9)
def snare():
    t = t_(0.25); nz = rng.standard_normal(len(t)); nz = nz - np.convolve(nz, np.ones(4) / 4, 'same')
    return (0.7 * nz * np.exp(-t * 22) + 0.5 * np.sin(2 * np.pi * 190 * t) * np.exp(-t * 30)) * 0.8
def hat(d=0.05):
    t = t_(d); nz = np.diff(rng.standard_normal(len(t) + 1)); return nz * np.exp(-t * 70) * 0.25
def tick():
    t = t_(0.06); return np.sin(2 * np.pi * 1900 * t) * np.exp(-t * 120) * 0.35
def bass(m, d):
    t = t_(d); f = hz(m); env = np.minimum(1, t * 200) * np.exp(-t * 2.5)
    return sum(np.sin(2 * np.pi * f * k * t) / k for k in (1, 2, 3)) * env * 0.45
def stab(ms, d=0.22):
    t = t_(d); env = np.minimum(1, t * 300) * np.exp(-t * 14)
    return sum(np.sin(2 * np.pi * hz(m) * t) + 0.3 * np.sin(4 * np.pi * hz(m) * t) for m in ms) * env * 0.16
def pad(ms, d):
    t = t_(d); env = np.minimum(1, t * 4) * np.minimum(1, (d - t) * 6)
    return sum(np.sin(2 * np.pi * hz(m) * t) + 0.2 * np.sin(2 * np.pi * hz(m) * 1.003 * t) for m in ms) * env * 0.05

# D minor: Dm  Bb  C  A  (one chord per call/answer pair)
CHORDS = [(38, [62, 65, 69]), (34, [62, 65, 70]), (36, [64, 67, 72]), (33, [61, 64, 69])]

def full_bar(b, chord, stabs=None):
    root, notes = chord; s = b * 4
    for k in range(4):
        put(kick() if k % 2 == 0 else snare(), s + k, -3 if k % 2 == 0 else -6)
    for k in range(8): put(hat(), s + k / 2, -8 if k % 2 else -4)
    for k, m in enumerate([root, root, root + 7, root + 12]): put(bass(m, SPB * 0.9), s + k, -4)
    if stabs is None: put(pad(notes, 4 * SPB), s, 0)
    else:
        for x in stabs: put(stab(notes), s + x, 0)     # the band hits with each throw

def answer_bar(b, chord):
    root, notes = chord; s = b * 4
    put(kick(), s, -1)                                 # beat 1 always hits hard
    put(bass(root, SPB * 1.5), s, -3)
    for k in range(4): put(hat(0.03), s + k, -10)      # quiet pulse, room for your spells
    put(snare(), s + 3.5, -10)                         # pickup back into the band

for b in range(INTRO): full_bar(b, CHORDS[b % 4])
for k in range(4): put(tick(), INTRO * 4 + k, -2)      # get-ready bar: just ticks
for p, pat in enumerate(patterns):
    cb = first_call + 2 * p; ch = CHORDS[p % 4]
    full_bar(cb, ch, stabs=pat)
    answer_bar(cb + 1, ch)
for b in range(bars - ENDING, bars - 1): full_bar(b, CHORDS[(b - (bars - ENDING)) % 4])
put(kick(), (bars - 1) * 4, -1); put(pad(CHORDS[0][1], 3 * SPB), (bars - 1) * 4, 6); put(bass(38, 2.5), (bars - 1) * 4, -2)

mix = mix * (0.5 / np.abs(mix).max())                  # quiet master, lots of headroom (-6 dB peak)
tmp = os.path.join(HERE, "wizard_demo.wav")
w = wave.open(tmp, "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
w.writeframes((mix * 32767).astype(np.int16).tobytes()); w.close()
out = os.path.join(ROOT, "audio", "music", "wizard_demo.ogg")
subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", tmp, "-c:a", "libvorbis", "-q:a", "6", out], check=True)
print(f"{bars} bars, {len(mix)/SR:.1f} s, {len(patterns)} patterns -> {out}")
