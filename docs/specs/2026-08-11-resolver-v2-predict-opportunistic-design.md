# Resolver v2 — Predict Rework + Opportunistic Fire + Hit-Confirm — Design

**Date:** 2026-08-11
**Status:** Approved (brainstorm)
**Builds on:** `2026-08-11-resolver-confidence-gate-design.md` (same branch `resolver-confidence-gate`).

## Problem

The confidence gate (v1) fixed over-firing but introduced a regression: it killed the fast
opportunistic shots the resolver used to land when a void-spamming cheater flickered to their real
position, or when a target teleported to a weapon. Two causes:

1. **Stability weight (0.35)** — a void↔real flip or a TP makes the winning cluster *jump*, so
   `stabFrames` resets to 0, confidence drops, and the gate holds fire. But that transient real frame
   is exactly the shot window in HvH.
2. **Reject-vel pre-filter** — `sample()` drops any sample whose step velocity exceeds `rejectVel`
   (300). A TP-to-weapon is a fast *real* displacement, so its sample never enters history → the
   resolver never sees the real TP position → cannot shoot it.

Separately, the prediction model (`pos + vel * lead`, lead = ping-based or a manual `PredLead`) is
being replaced with a base + amplitude model the user prefers, and two new capabilities are wanted.

## Solution

Four changes on top of v1. All new tunables live in `Strafe.CONF`.

### 1. Remove reject-vel completely

Delete the velocity pre-filter and all its plumbing. The cluster/density resolvers plus the
void-manhattan check already reject void garbage; the pre-filter only suppressed legitimate fast
real movement (TPs).

- `Strafe.sample(plr, pos, now)` — remove the `rejectVel` parameter and the reject branch.
- `Strafe.sampleAll(now)` — remove the `rejectVel` parameter.
- `main.lua` sampleAll call — drop the `O.ResolverReject.Value` argument.
- `UI.lua` — remove the `ResolverReject` slider.

### 2. Prediction: base + amplitude×velocity

Replace the `lead` computation in `Strafe.resolveAim` **and** `Strafe.resolvedPeek` (tracer, must
match) with:

```
speedNorm = clamp(vel.Magnitude / CONF.predMaxSpeed, 0, 1)
pos = resolved + vel * (PredictBase + PredictAmp * speedNorm)
```

- `PredictBase` (default 0.10 s) — constant lead floor (ping compensation); applied even at rest.
- `PredictAmp` (default 0.15 s) — extra lead that scales in as the target moves faster.
- `CONF.predMaxSpeed` (default 60) — speed at which `speedNorm` saturates to 1.
- Keep the existing `vel.Magnitude > 200 → vel = 0` sanity clamp (never lead toward the void).
- UI: remove the `PredMode` dropdown and `PredLead` slider; add `PredictBase` and `PredictAmp` sliders.

### 3. Opportunistic fire (regression fix)

When the target's **raw head** is non-void (currently real / exposed), fire immediately at full rate,
bypassing the confidence gate entirely. When the raw head is in the void, fall back to the v1
confidence-scaled path on the resolver-recovered position.

- `cacheHit` (main.lua) already computes `inVoid` for `base` (the raw head). Set
  `LIP.targetExposed = not inVoid`. Reset to `false` alongside the other target-cleared fields.
- `Weapon.tickAuto`: if `LIP.targetExposed` → `m = 1` (snapshot; skip floor + stability). Else →
  the v1 confidence scaling (now with the hit-confirm relaxed floor from §4).

Rationale: if you can see them at their real position, shoot; the gate exists only to judge shots at
a *recovered* position while they hide in the void. No anti-flicker delay — the user wants the fast
transient shots back and accepts single-frame exposures as shootable.

### 4. Hit-confirm auto-tune

Track whether our shots are landing (HP drops shortly after we fire) and use the running accuracy to
relax the confidence floor — a resolver that is demonstrably landing shots is allowed to fire more
freely; one that is whiffing tightens up.

- `fireOne` (Weapon.lua) stamps `LIP.lastFireT = os.clock()` on each shot.
- `Strafe.updateHitConfirm(plr, now)` — called once per frame for the current target:
  - Track `hc[plr] = { lastHP, acc }`.
  - If the target's HP **dropped** since last frame and we fired within `CONF.hcWindow` (0.35 s) →
    register a hit (`hit = 1`); else if we fired within the window with no drop → miss (`hit = 0`);
    otherwise no update (we did not shoot).
  - EMA: `acc = acc + CONF.hcRate * (hit - acc)` (`hcRate` 0.10).
- `Strafe.hitAccuracy(plr) -> number` (0..1) — for the HUD and the floor relax.
- `Weapon.tickAuto` (void path only): `effFloor = floor * (1 - CONF.hcRelax * acc)` (`hcRelax` 0.40).
  High accuracy lowers the effective floor → fires more; low accuracy keeps it strict.

Attribution is approximate (another player could deal the damage), but the EMA smooths noise — same
approach as the symbol.lua hit-confirm meter.

### HUD

Extend the readout to show hit accuracy. `resolverInfo` already returns `confidence`; add
`hitAcc = Strafe.hitAccuracy(plr)`. CrosshairHUD appends `Hit: %.2f`.

## Non-goals

- No change to Cluster/Density resolution math.
- No strafe-oscillation predictor (the base+amplitude model was chosen instead).
- No anti-flicker debounce on the opportunistic path (intentional).

## Files touched

| File | Change |
|------|--------|
| `Combat/Strafe.lua` | remove reject-vel from `sample`/`sampleAll`; predict base+amp in `resolveAim`+`resolvedPeek`; `CONF` new keys; `hc` state + `updateHitConfirm` + `hitAccuracy`; extend `resolverInfo` with `hitAcc` |
| `Combat/Weapon.lua` | `fireOne` stamps `LIP.lastFireT`; `tickAuto` opportunistic `m=1` when exposed + hit-confirm relaxed floor on void path |
| `main.lua` | drop reject arg from sampleAll; `LIP.targetExposed`; call `Strafe.updateHitConfirm` for current target |
| `UI.lua` | remove `ResolverReject`, `PredMode`, `PredLead`; add `PredictBase`, `PredictAmp` |
| `Visuals/CrosshairHUD.lua` | show `Hit` accuracy |
| `dist/…` | rebuilt |

## Tuning defaults (`Strafe.CONF`)

- `predMaxSpeed = 60`
- `hcWindow = 0.35`, `hcRate = 0.10`, `hcRelax = 0.40`
- sliders: `PredictBase = 0.10`, `PredictAmp = 0.15`

## Testing

Via `roblox-executor-mcp` (client ko3l1_300), non-firing probes + build/load, live-fire deferred to
user (burner) per `docs/ops.md` risk rules:
1. Build + load clean; bundle `compila=true`.
2. Probe: `Strafe.sampleAll(now)` accepts one arg; a fast synthetic step no longer drops (history grows).
3. Probe predict: with a known `vel`, `resolveAim` returns `resolved + vel*(base+amp*speedNorm)`.
4. Probe: `LIP.targetExposed` true when raw head non-void, false when void.
5. Probe: `Strafe.hitAccuracy(plr)` returns a number; `updateHitConfirm` moves it after a scripted HP drop.
6. Live-fire (user): exposed target → fast shots return; pure-void target → gate still holds; Hit meter
   climbs when landing.
