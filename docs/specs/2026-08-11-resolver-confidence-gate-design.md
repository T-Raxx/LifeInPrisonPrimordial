# Resolver Confidence Gate — Design

**Date:** 2026-08-11
**Status:** Approved (brainstorm)
**Scope:** Single implementation plan.

## Problem

The autofire fires at the weapon's full firerate whenever a valid `cachedHitPart` exists.
Fire authorization is **decoupled from resolution quality**. Confidence signals are computed
but only feed the HUD; they never throttle the trigger.

Concrete wiring today:

- `Strafe.confidence(plr)` (linear-residual, 0–1) and the cluster `score` are **HUD-only**.
- The **Accuracy** slider (`RRAccuracy`, 0.4–3, default 1.35) sets `RParams.accuracy`,
  which gates only `didDefensive` (`Strafe.lua:183`).
- `didDefensive` does two things and **neither stops a shot**:
  - `main.lua:71-74`: pick resolved pos vs raw head (when `FireResolved` on).
  - `Weapon.lua:185`: `not didDefensive` → apply range gate; `didDefensive=true` → **bypass** range.
- `Weapon.tickAuto` fires at `rate` unconditionally once a `cachedHitPart` is cached.

Result — all four reported symptoms trace to this one root cause:
1. Confidence does nothing (never gates).
2. Fires when it shouldn't (target spamming / resolver still calibrating).
3. Fires and misses (commits to a shaky resolve).
4. Aims at the void (raw head can be a void ghost; no guard).

Threat model (confirmed with user): **other cheaters void-spamming** their position to break
prediction. The Cluster (juju void-spam) / Density (sakura) machinery is the correct method and
stays. Only the confidence→trigger link is missing.

## Solution — Confidence-scaled firerate (Approach A)

Keep the resolution methods untouched. Add one fused confidence signal, feed it into the trigger
as a rate multiplier, and repurpose the existing **Accuracy** slider as the confidence floor.

### 1. `Strafe.fireConfidence(plr)` → 0..1

Fuses signals already being computed, plus one new cheap one (temporal stability):

- **`sDom`** — winning-cluster dominance. Reuse `resState[plr].score` (already normalized 0–1 for
  both Cluster and Density).
- **`sStab`** — temporal stability (NEW). Track the winning resolved `pos` frame-to-frame. While it
  moves less than `STAB_THRESH` studs it is "the same cluster": increment a counter; on a jump, reset.
  `sStab = clamp(stableFrames / STAB_K, 0, 1)`. This is what defeats a *good* void-spammer: a winner
  that keeps jumping never accumulates stability → confidence stays low.
- **`sResid`** — `Strafe.confidence(plr)` (linear residual), secondary factor for clean motion.
- **`voidPen`** — if the current best resolved pos is in the void
  (`|x|+|z| >= voidManhattan`, 7000) → confidence is forced to **0**. Otherwise `voidPen = 1`.

Fusion (weights tunable, live in a `Strafe.CONF` table so they can be adjusted without edits):

```
conf = voidPen * ( wDom*sDom + wStab*sStab + wResid*sResid )
     with wDom=0.45, wStab=0.35, wResid=0.20   (sum = 1.0)
```

Stability state (`stab[plr] = { lastPos, frames }`) is updated **once per real resolve**, inside the
non-cached branch of `resolveByMethod` (the single ingestion point; it already early-returns on the
per-frame cache, so no double counting). Method-agnostic: uses the resolved `pos` of whichever method
ran. `STAB_THRESH ≈ mergeR`-scale (default 25 studs), `STAB_K = 6`.

### 2. Rate scaling in `Weapon.tickAuto`

Replace "fire at `rate` always" with a confidence multiplier on the accumulator increment:

```
floor = O("RRAccuracy")                    -- repurposed slider (0..1)
hi    = math.min(1, floor + 0.30)          -- full rate reachable band
m     = smoothstep(floor, hi, conf)        -- 0 below floor, 1 at/above hi, eased between
if m < 0.02 then LIP.fireAccum = 0; lastTick = now; return end   -- hard hold: no queued shot
...
LIP.fireAccum = LIP.fireAccum + dt * rate * m
```

- `conf = Strafe.fireConfidence(LIP.target)`.
- `conf < floor` → `m = 0` → **holds fire** (fixes symptoms 2 & 3).
- `floor <= conf < hi` → **dribble** proportional to confidence (Option 2 chosen by user).
- `conf >= hi` → full rate.
- The rate cap (`AutoFireRate`) and observed-firerate logic are unchanged; `m` scales the *effective*
  rate underneath the cap.

`smoothstep(a,b,x) = t*t*(3-2*t)` where `t = clamp((x-a)/(b-a), 0, 1)`; guard `a==b`.

### 3. Repurpose the Accuracy slider

`UI.lua` `RRAccuracy`:

- **Before:** `Min=0.4, Max=3, Default=1.35`, callback → `RParams.accuracy`.
- **After:** `Min=0, Max=1, Default=0.5, Decimals=2`, Text stays `"Accuracy"`, add Tooltip
  ("min resolver confidence to fire; higher = holds fire on shaky resolves").
  The callback no longer writes `RParams.accuracy`; the floor is read live in `tickAuto` via
  `O("RRAccuracy")`.
- `RParams.accuracy` keeps its **table default 1.35** for the internal `didDefensive` cluster gate
  (still used for aim-source selection and range bypass) — decoupled from the slider, no longer tuned
  from UI. Not exposed as a new slider (YAGNI).

Now raising Accuracy visibly holds fire → the slider finally does something.

### 4. Void guard in `cacheHit` (`main.lua`)

`base = part.Position` can itself be a void ghost when the enemy spams their char to the void.

- If `base` in void (`|x|+|z| >= 7000`):
  - If `FireResolved` on and the resolver returned a **non-void** resolved pos → use it (current path).
  - Else → set `cachedHitPos = LIP.lastGoodHitPos` (last non-void pos for this target) if available,
    and let confidence (≈0 here) hold the trigger. If no last-good → keep raw but confidence gate
    stops the shot anyway.
- If `base` not in void → store it as `LIP.lastGoodHitPos` and use normally.

`lastGoodHitPos` is reset when the target changes/dies.

### 5. HUD

Extend `Strafe.resolverInfo(plr)` to also return `confidence` (the fused 0–1). The fire multiplier
`m` is computed in `tickAuto`; it stashes the last value to `LIP.fireMult` for display.
`Visuals/CrosshairHUD.lua` (lines 59–65) reads `confidence` from `resolverInfo` and `LIP.fireMult`
so the user watches confidence and the resulting fire multiplier move in real time.

## Non-goals

- No change to Cluster/Density resolution math (method is correct for the threat).
- No new resolver method, no resolver rewrite (Approach B rejected — YAGNI).
- No change to silent-aim swap, wallbang, void-spam phase, or strafe orbit logic.

## Files touched

| File | Change |
|------|--------|
| `Combat/Strafe.lua` | `Strafe.fireConfidence`, `stab` state + stability update in `resolveByMethod`, `Strafe.CONF` weights, extend `resolverInfo` |
| `Combat/Weapon.lua` | confidence rate-scaling + hard-hold in `tickAuto` |
| `main.lua` | void guard + `lastGoodHitPos` in `cacheHit` |
| `UI.lua` | repurpose `RRAccuracy` slider (range/default/tooltip, callback) |
| `Visuals/CrosshairHUD.lua` | show `confidence` + `fireMult` |
| `dist/…` | rebuild via bundler |

## Testing

No local Lua. Verify via `roblox-executor-mcp`:
1. Load bundle → console clean, no errors.
2. HUD shows `confidence`/`fireMult` updating on a live target.
3. Accuracy slider at 1.0 → fire holds (m≈0) unless a rock-steady cluster; at 0 → fires like today.
4. Void-spam target → confidence drops, rate dribbles/holds; aim never snaps to void coords.
5. Live-fire confirmation deferred to user (burner), consistent with project norm.

## Tuning defaults (all live-adjustable via `Strafe.CONF` / `Strafe.DEN` / `RParams`)

- `wDom=0.45, wStab=0.35, wResid=0.20`
- `STAB_THRESH=25, STAB_K=6`
- floor band `+0.30`, hold epsilon `0.02`
- slider `RRAccuracy` default `0.5`
