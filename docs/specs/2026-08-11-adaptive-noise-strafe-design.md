# Adaptive Noise-Path Strafe + 3-Phase Cycle + More Resolver Options — Design

**Date:** 2026-08-11
**Status:** Approved (brainstorm)
**Builds on:** resolver v1/v2/v3, same branch `resolver-confidence-gate`.

## Problem / Intent

The strafe currently switches between preset modes (Normal/Random/Behind/Spiral) via `pickBestMode`
(AutoMode). The user wants to **stop switching preset modes** and instead strafe in a **single
self-generated organic path** whose shape **adapts to maximize the user's own hit rate**. The dynamic
cycle should grow from 2 phases (CHASE↔BAIT) to **3 timed phases: CHASE → STRAFE → BAIT**. Also expose
**more resolver options** (the confidence-fusion tunables) as live sliders.

Decisions (user):
- Adaptation signal = **maximize your hits** (`Strafe.hitAccuracy`), offense-only.
- Generator = **procedural noise-path** (amplitude + frequency evolve by feedback).
- The **STRAFE phase orbits the TARGET and shoots** (same center as CHASE, wider + adaptive).

## Solution

### 1. Procedural noise-path generator

`noiseOffset(t, amp, freq) -> Vector3` — an organic offset around a center, built from a sum of sine
octaves per axis with **LCG-seeded phases** (Math.random is blocked in the executor; reuse the module
`rnd()`), so it is smooth, unpredictable, and deterministic per session:

```
axis(o) = sin(freq·t + P[o])·0.6 + sin(2.3·freq·t + P[o+1])·0.3 + sin(4.1·freq·t + P[o+2])·0.1
offset  = ( axis(1)·amp , axis(4)·amp·0.5 , axis(7)·amp )     -- Y half amplitude
```

`P[1..9]` are phase offsets seeded once from `rnd()`. `amp` (radius) and `freq` (angular speed) are the
adaptive parameters. This **replaces** the preset-mode branches in the two offset functions.

### 2. Adaptive hill-climb on hit rate

Module state `adapt = { amp, freq, dirA, dirF, lastAcc, lastT }`, exposed as `Strafe.adapt`.
`adaptStep(target)` runs during the STRAFE phase, at most every `CONF.adaptInterval`:

```
acc = Strafe.hitAccuracy(target)
if acc < lastAcc  → flip dirA and dirF          -- regression → reverse search direction
lastAcc = acc
amp  = clamp(amp  + dirA·CONF.adaptLrAmp,  CONF.ampMin,  CONF.ampMax)
freq = clamp(freq + dirF·CONF.adaptLrFreq, CONF.freqMin, CONF.freqMax)
```

A cheap coordinate-ascent: keep moving amp/freq while your hit rate improves, reverse when it drops.
Converges toward the path under which you land the most shots.

### 3. Three-phase cycle

`cycleStep` FSM grows to CHASE (`ChaseTime`) → STRAFE (`StrafeTime`) → BAIT (`BaitTime`) → loop.
Presets set the three timers (Timed 2/2/1, Micro ping+.02/.5/.5, Spam .06/.08/.11).

- **CHASE**: noise-path around the **resolved target pos**, tight (`CONF.chaseAmp`/`chaseFreq`), shoot.
- **STRAFE**: noise-path around the **resolved target pos**, wide + adaptive (`adapt.amp`/`adapt.freq`),
  shoot; `adaptStep` runs here.
- **BAIT**: void fling (unchanged), no shoot.

The tick sets `LIP.strafeNoise = true` while the dynamic cycle is on and stores the per-phase
`LIP.curStrafeAmp`/`LIP.curStrafeFreq`. The two offset functions inject the noise-path when
`LIP.strafeNoise` is set:

- `orbitCF` (desync path): `CFrame.lookAt(center + noiseOffset(t, curAmp, curFreq), center)`.
- `weldOrbitOffset` (connection-weld path): `CFrame.new(noiseOffset(t, curAmp, curFreq))`.

`pickBestMode` and the AutoMode auto-switch are removed. Preset `StrafeMode`/`StrafePreset` remain for
non-dynamic (DynStrafe off) manual use.

### 4. More resolver options (live sliders)

Expose the confidence-fusion tunables that today only live in `Strafe.CONF`: `wDom`, `wStab`,
`wResid`, `revisitBonus`, `predMaxSpeed`; plus the noise bounds `ampMin`/`ampMax`/`freqMin`/`freqMax`.

## Non-goals

- No change to the resolver core (Cluster/Density) or the v3 confidence/backtrack logic.
- No damage-avoidance signal (user chose hit-rate only).
- Preset strafe modes stay available (manual, DynStrafe off); only the auto mode-switch is removed.

## Files touched

| File | Change |
|------|--------|
| `Combat/Strafe.lua` | `noiseOffset` + `P` phases; `adapt` state + `adaptStep`; `cycleStep` → 3 phases; `orbitCF`/`weldOrbitOffset` noise injection; tick sets `strafeNoise`/`curStrafeAmp`/`curStrafeFreq` + runs `adaptStep`; remove `pickBestMode` + AutoMode block; new `CONF` keys |
| `UI.lua` | replace `AroundTime`/`VoidTime` with `ChaseTime`/`StrafeTime`/`BaitTime`; remove `AutoMode` + `AutoSpoofThresh`/`AutoFastThresh`/`AutoFarThresh`; add noise bound sliders + `wDom`/`wStab`/`wResid`/`revisitBonus`/`predMaxSpeed` sliders |
| `dist/…` | rebuilt |

## Tuning defaults (`Strafe.CONF`)

- `chaseAmp = 10`, `chaseFreq = 2.5`
- `ampMin = 6`, `ampMax = 30`, `freqMin = 0.5`, `freqMax = 4.0`
- `adaptInterval = 1.0`, `adaptLrAmp = 2.0`, `adaptLrFreq = 0.3`
- `adapt` init: `amp = 14`, `freq = 1.5`

## Testing

Via `roblox-executor-mcp` (client ko3l1_300), non-firing probes + build/load; live-fire deferred:
1. Build + load clean; bundle `compila=true`.
2. Probe: `Strafe.noiseOffset(0.5, 14, 1.5)` returns a finite Vector3; magnitude within amp bounds.
3. Probe: `cycleStep` cycles chase→strafe→bait (drive `os.clock`-based phases; read `LIP.strafePhase`
   over successive calls).
4. Probe: `Strafe.adapt` exists; `adaptStep` moves `amp`/`freq` within bounds after a scripted acc change.
5. Probe: `LIP.strafeNoise`/`curStrafeAmp` set when DynStrafe on.
6. Live-fire (user): one organic self-strafe (no mode switching); amp/freq drift toward higher hit
   rate; the 3 phases each honor their time slider.
