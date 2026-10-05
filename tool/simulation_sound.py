# Usage: python tool/simulation_sound.py assets/sounds/simulation.wav  (needs numpy)
"""Synthesises assets/sounds/simulation.wav to follow the simulation view's
timeline: soft blips while each course grows, a low buzz when it fails, a
rush of ticks while the counter races, a two-note chime for the answer."""
import sys, wave
import numpy as np

RATE = 22050
out = np.zeros(int(RATE * 6.9))
rng = np.random.default_rng(4)

def add(at, samples):
    i = int(at * RATE)
    n = min(len(samples), len(out) - i)
    out[i:i + n] += samples[:n]

def env(n, attack=0.004, release=0.6):
    t = np.arange(n) / RATE
    a = np.clip(t / attack, 0, 1)
    r = np.exp(-t / (release * n / RATE))
    return a * r

def blip(freq, dur=0.04, amp=0.22):
    n = int(dur * RATE)
    t = np.arange(n) / RATE
    return amp * np.sin(2 * np.pi * freq * t) * env(n, release=0.35)

def buzz(freq=98, dur=0.22, amp=0.2):
    n = int(dur * RATE)
    t = np.arange(n) / RATE
    wave_ = sum(np.sin(2 * np.pi * freq * k * t) / k for k in (1, 3, 5, 7))
    return amp * wave_ * env(n, attack=0.002, release=0.5)

def tick(amp=0.1):
    n = int(0.008 * RATE)
    return amp * rng.uniform(-1, 1, n) * env(n, attack=0.0005, release=0.3)

intro, runs, fast, chosen, growing = 0.7, [1.1, 0.9, 0.75, 0.6], 1.4, 1.3, 0.7
# Start-up: a short rising sweep.
n = int(0.5 * RATE)
t = np.arange(n) / RATE
add(0.05, 0.12 * np.sin(2 * np.pi * (300 * t + 900 * t * t)) * env(n, attack=0.05, release=0.5))

start = intro
for length in runs:
    # A blip per level of the tree, rising, then the failure.
    for level in range(3):
        add(start + length * growing * level / 3, blip(700 + 260 * level + rng.uniform(-40, 40)))
    add(start + length * growing, buzz())
    start += length

# The counter races: ticks closer and closer together.
at = start
while at < start + fast:
    progress = (at - start) / fast
    add(at, tick(0.06 + 0.08 * progress))
    at += 0.09 - 0.07 * progress

# The chosen course, and the answer.
for level in range(3):
    add(start + fast + chosen * growing * level / 3, blip(880 + 220 * level, amp=0.25))
answer = start + fast + chosen * growing
add(answer, blip(880, dur=0.3, amp=0.22))
add(answer + 0.12, blip(1320, dur=0.45, amp=0.2))

out = np.clip(out, -1, 1)
with wave.open(sys.argv[1], "wb") as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(RATE)
    f.writeframes((out * 32767).astype("<i2").tobytes())
