"""Builds the Wizard guide track: write your song over it in your music software.
   python tools/wizard_guide/make_guide.py <folder with wsfx_*.wav exported from the game>
Matches your Wizard song's 3-bar phrases (110 BPM, starts at 0:00 = DAW bar 1):
bars 1-3 intro (kalimba), then from bar 4 one pattern per phrase -- call bar, answer
bar, breather bar -- as many as fit in SONG_BARS, picked the same way the game does."""
import sys, os, re, wave, numpy as np

SR, BPM = 44100, 110.0
SPB = 60.0 / BPM
INTRO = 3          # bars before the first call
STEP = 3           # bars per pattern: call, answer, breather
SONG_BARS = 19     # how long the song is (your current one: 19 bars). Make it longer for more patterns.
HERE = os.path.dirname(os.path.abspath(__file__))
SFX = sys.argv[1]

# the call patterns, read straight from the game so the guide always matches
src = open(os.path.join(HERE, "..", "..", "scripts", "wizard_game.gd"), encoding="utf-8").read()
block = src[src.index("const PATTERNS := ["):]
block = block[:block.index("\n]\n")]
patterns = [[(float(b), k) for b, k in re.findall(r'\[([\d.]+), "(\w+)"\]', line)]
            for line in block.splitlines()[1:] if line.strip().startswith("[[")]

def load(name, db):
    w = wave.open(os.path.join(SFX, f"wsfx_{name}.wav"))
    a = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(float) / 32768
    if w.getnchannels() == 2: a = a.reshape(-1, 2).mean(1)
    if w.getframerate() != SR:
        a = np.interp(np.arange(0, len(a), w.getframerate() / SR), np.arange(len(a)), a)
    return a * 10 ** (db / 20)

def click(freq, db, dur=0.05):
    t = np.arange(int(dur * SR)) / SR
    return np.sin(2 * np.pi * freq * t) * np.exp(-t * 90) * 10 ** (db / 20)

first_call = INTRO
bars = SONG_BARS
room = max(1, min(len(patterns), (bars - first_call - 2) // STEP + 1))
if room < len(patterns):   # same even spread as the game (always first and last)
    patterns = [patterns[int(i * (len(patterns) - 1) / max(room - 1, 1) + 0.5)] for i in range(room)]
n = int((bars * 4 * SPB + 2.0) * SR)
clicks, cues = np.zeros(n), np.zeros(n)
def put(track, sound, t):
    i = int(round(t * SR)); j = min(n, i + len(sound)); track[i:j] += sound[:j - i]

snd = {k: load(k, db) for k, db in (("fire", -2), ("ice", -8), ("cast_fire", -4), ("cast_ice", -4))}
for b in range(bars * 4):                 # click: high on beat 1, low on 2-4
    put(clicks, click(1600 if b % 4 == 0 else 1000, -6 if b % 4 == 0 else -12), b * SPB)
lines = [f"Wizard guide track -- {BPM:g} BPM, 4/4, starts at 0:00. Bar numbers as your DAW counts them (bar 1 = 0:00).",
         f"Fire/ice whoosh = the wizard throws (call). Spell zap = you answer, same rhythm, one bar later.", ""]
lines.append(f"bars 1-{INTRO}: intro      (0:00.00)")
for p, pat in enumerate(patterns):
    cb = first_call + STEP * p
    for beat, kind in pat:
        put(cues, snd[kind], (cb * 4 + beat) * SPB)
        put(cues, snd["cast_" + kind], ((cb + 1) * 4 + beat) * SPB)
    counts = " ".join(f"{int(b) + 1}{'&' if b % 1 else ''}({k})" for b, k in pat)
    lines.append(f"bar {cb + 1:2d} call / bar {cb + 2:2d} answer / bar {cb + 3:2d} breather  ({cb * 4 * SPB:6.2f} s)   {counts}")
lines.append(f"song ends after bar {bars} ({bars * 4 * SPB:.1f} s)")

def save(name, a):
    a = a * min(1.0, 0.9 / max(np.abs(a).max(), 1e-9))   # leave headroom, never clip
    w = wave.open(os.path.join(HERE, name), "wb"); w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((np.repeat(a[:, None], 2, 1) * 32767).astype(np.int16).tobytes()); w.close()
save("wizard_guide.wav", clicks + cues)
save("wizard_guide_no_click.wav", cues)
save("wizard_click.wav", clicks)
open(os.path.join(HERE, "wizard_guide_map.txt"), "w", encoding="utf-8").write("\n".join(lines) + "\n")
print("\n".join(lines))
