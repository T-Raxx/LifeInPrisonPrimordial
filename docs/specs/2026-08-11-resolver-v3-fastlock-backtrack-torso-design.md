# Resolver v3 — Faster Void Lock + On-Shot Backtrack + Hist Cap/Torso-Aim — Design

**Date:** 2026-08-11
**Status:** Approved (brainstorm)
**Builds on:** resolver v1 (`…-resolver-confidence-gate-design.md`) + v2 (`…-resolver-v2-predict-opportunistic-design.md`), same branch `resolver-confidence-gate`.

## Context

Live-fire feedback: the resolver handles **void spam excellently** — it "learns" a real position that
is revisited in the same place and lands shots — but is **a little slow to lock**. Pure `math.random`
100-stud XYZ is mathematically unresolvable by position (centroid of 120 samples ≈ 9 studs off the
true center, verified live); the best available is a wide-forgiveness Density centroid + bullet spray.

Three improvements, all confirmed with the user:

1. **Faster void lock** — cross the fire threshold in fewer frames on a repeated void pattern.
2. **On-shot backtrack** — fire at the last reliable real position during the void frames *between*
   real flips, not only when the target is exposed.
3. **Hist cap + torso-aim** — more samples tighten the `math.random` centroid; aim the big hitbox
   (HRP) at random-strafers so the residual error lands.

All new tunables live in `Strafe.CONF`.

## Solution

### 1. Faster void lock

- **`stabK` 6 → 3** (`Strafe.CONF.stabK`): temporal stability saturates in 3 stable frames instead of
  6, so `sStab` (0.35 weight in `fireConfidence`) reaches 1 sooner.
- **Revisit bonus** — a cluster hit many times is the real void-spam anchor ("same place"). Carry the
  winning cluster's hit count into `resState.winCount` (Cluster: winner `.count`; Density: `bestCount`).
  `fireConfidence` adds `CONF.revisitBonus * clamp((winCount - CONF.revisitMin)/CONF.revisitScale, 0, 1)`
  to the fused confidence (then clamped 0..1). A frequently-revisited anchor crosses the floor faster.
  Defaults: `revisitBonus = 0.30`, `revisitMin = 4`, `revisitScale = 8`.

### 2. On-shot backtrack

The real body sits near its last real position even while the replicated position spams the void, so
during a *fresh* void frame we can fire at that last-good position without waiting for a full re-lock.

- `main.lua` stamps `LIP.lastGoodT = os.clock()` whenever it records `LIP.lastGoodHitPos` (non-void).
- `cacheHit` already points `cachedHitPos` at `lastGoodHitPos` during void when no confident resolve
  exists, so the aim target is already correct.
- `Weapon.tickAuto` (void path): compute a backtrack multiplier
  `btM = clamp(1 - (now - LIP.lastGoodT)/CONF.backtrackWindow, 0, 1)` when `lastGoodHitPos` exists and
  the last-good is fresh; fire with `m = max(gateM, btM)`. So a fresh backtrack fires even when the
  confidence gate would hold. Default `backtrackWindow = 0.15`.

This composes with opportunistic fire (exposed → m=1): exposed frames fire at full rate, fresh-void
frames fire via backtrack, stale-void frames fall back to the confidence gate.

### 3. Hist cap + torso-aim

- **`MAX` (hist cap) 120 → `CONF.histMax` (default 200)** — more samples tighten the centroid
  (error ∝ range/√N: 120→~9 studs, 200→~7, 400→~5 for a 200-stud range). ⚠️ Density is O(n²): 200²=40k
  comparisons/target/frame is fine; 400+ can cost FPS with several targets — tunable and documented.
- **Torso-aim** — aim the HRP (big hitbox) instead of the Head at a random-strafer so the ~5–9 stud
  centroid residual still overlaps the body.
  - `Strafe.isRandomStrafer(plr)` → true when in-map (`beh.voidFrac < 0.30`), unresolved
    (`resState.score < 0.30`), and unstable (`stabFrames < 2`) — the `math.random` signature.
  - `cacheHit` chooses the hit part: HRP when the **BigHitbox** toggle is on OR (Resolver on AND
    `isRandomStrafer`); otherwise Head (today's behavior). The choice reads the previous frame's
    `resState` (populated later in the same `cacheHit`), a negligible one-frame lag.

## Non-goals

- No dedicated Centroid/Average method (user keeps Density-forgiveness-as-centroid).
- No change to Cluster/Density core neighborhood math beyond surfacing `winCount`.
- No anti-delta work (deferred; insights parked separately).

## Files touched

| File | Change |
|------|--------|
| `Combat/Strafe.lua` | `CONF` keys (`stabK`=3, `revisitBonus/revisitMin/revisitScale`, `backtrackWindow`, `histMax`); `MAX`→`CONF.histMax` in `sample`; `winCount` from `resolveCluster`/`resolveDensity` into `resState`; revisit bonus in `fireConfidence`; `Strafe.isRandomStrafer` |
| `Combat/Weapon.lua` | backtrack multiplier merged into the void-path `m` in `tickAuto` |
| `main.lua` | `LIP.lastGoodT`; torso-aim hit-part choice in `cacheHit` |
| `UI.lua` | sliders `HistMax`, `BacktrackWindow`; toggle `BigHitbox` |
| `Visuals/CrosshairHUD.lua` | (optional) show hit part / random-strafer flag — skip unless trivial |
| `dist/…` | rebuilt |

## Tuning defaults (`Strafe.CONF`)

- `stabK = 3` (was 6)
- `revisitBonus = 0.30`, `revisitMin = 4`, `revisitScale = 8`
- `backtrackWindow = 0.15`
- `histMax = 200`

## Testing

Via `roblox-executor-mcp` (client ko3l1_300), non-firing probes + build/load; live-fire deferred to
user (burner):
1. Build + load clean; bundle `compila=true`.
2. Probe: `Strafe.CONF.stabK==3`, `histMax==200`; feed samples > 120 → hist grows to 200.
3. Probe: `resState.winCount` present; `fireConfidence` rises with a repeated (same-pos) sample stream
   faster than before (revisit bonus).
4. Probe: `Strafe.isRandomStrafer(plr)` returns a bool; true for a synthetic in-map random cloud.
5. Probe: `LIP.lastGoodT` stamped; backtrack multiplier > 0 within `backtrackWindow` of a real frame.
6. Live-fire (user): void-spam target locks/fires sooner; fire continues through void frames after a
   real flip; random-strafer aim moves to HRP; raising HistMax tightens the centroid (watch FPS).
