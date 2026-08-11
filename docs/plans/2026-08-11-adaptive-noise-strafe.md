# Adaptive Noise-Path Strafe + 3-Phase Cycle + More Resolver Options — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans or superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Replace preset-mode strafe-switching with one adaptive procedural noise-path (hill-climbed to maximize the user's hit rate), grow the dynamic cycle to CHASE→STRAFE→BAIT, and expose the confidence-fusion tunables as sliders.

**Architecture:** Extends the strafe/resolver on branch `resolver-confidence-gate`. A `noiseOffset` generator + `adapt` hill-climb + a 3-phase `cycleStep` live in `Strafe.lua`; the two offset functions inject the noise-path when the dynamic cycle is on; UI swaps time sliders and drops the auto-mode controls.

**Tech Stack:** Luau (Roblox), PrimordialUI, module factories, build+bundle in-executor, tested via `roblox-executor-mcp` (client ko3l1_300).

## Global Constraints

- No local Lua runtime. Verify via executor: sync (robocopy) → build → load dist. Fallback = build must complete.
- Full/root bundle needs `bundle.lua` (inlines GUIVisuals); the `dist/` never has the Visuals sub-tab.
- New tunables in `Strafe.CONF`. Slider keys read live via `O("Name")`; toggles via `T("Flag")`.
- Do not fire at real players from probes (ops.md); live-fire deferred to user (burner).
- Math.random is blocked in the executor — use the module `rnd()` (LCG) for any randomness (phase seeds).
- `Strafe.CONF` after v3 = `{ …, revisitBonus=0.30, revisitMin=4, revisitScale=8, backtrackWindow=0.15, histMax=200 }`.
- Fire suppression already keys on `LIP.strafePhase=="bait"` in `Weapon.tickAuto` — the new "strafe" phase must NOT be "bait" so it keeps firing (it isn't).

---

## File Structure

| File | Responsibility |
|------|----------------|
| `Combat/Strafe.lua` | `noiseOffset`+phases; `adapt`+`adaptStep`; `cycleStep`→3 phases; offset-fn noise injection; tick wiring; remove `pickBestMode`/AutoMode; `CONF` keys |
| `UI.lua` | `StrafeTime` slider; remove `AutoMode`+3 thresholds; noise-bound + fusion-weight sliders |

Task order: 1 (Strafe: generator+adapt+CONF) → 2 (Strafe: cycleStep + offset injection + remove pickBestMode) → 3 (Strafe: tick wiring) → 4 (UI) → 5 (bundle).

---

### Task 1: Strafe.lua — noiseOffset generator, adapt state, CONF keys

**Files:** Modify `Combat/Strafe.lua`.

**Interfaces:**
- Produces: `Strafe.noiseOffset(t, amp, freq) -> Vector3`; `Strafe.adapt` table; `adaptStep(target)` (module-local); `CONF.{chaseAmp,chaseFreq,ampMin,ampMax,freqMin,freqMax,adaptInterval,adaptLrAmp,adaptLrFreq}`.

- [ ] **Step 1: Extend `Strafe.CONF`** — replace the closing of the CONF table:

```lua
                    revisitBonus = 0.30, revisitMin = 4, revisitScale = 8, backtrackWindow = 0.15, histMax = 200 }
```

with:

```lua
                    revisitBonus = 0.30, revisitMin = 4, revisitScale = 8, backtrackWindow = 0.15, histMax = 200,
                    chaseAmp = 10, chaseFreq = 2.5, ampMin = 6, ampMax = 30, freqMin = 0.5, freqMax = 4.0,
                    adaptInterval = 1.0, adaptLrAmp = 2.0, adaptLrFreq = 0.3 }
```

- [ ] **Step 2: Add the noise-path generator + adaptive hill-climb** — insert immediately after the `local function rndS() return rnd() * 2 - 1 end   -- signed [-1,1]` line:

```lua

    -- NOISE-PATH: camino orgánico suave alrededor de un centro. Suma de octavas de seno con fases LCG-seedeadas
    -- (Math.random bloqueado). amp = radio, freq = velocidad angular. Reemplaza el switch de modos preset.
    local NP = {}   -- 9 fases (3 ejes × 3 octavas), seedeadas una vez
    for i = 1, 9 do NP[i] = rnd() * 6.2831853 end
    function Strafe.noiseOffset(t, amp, freq)
        local function axis(o)
            return math.sin(freq * t + NP[o]) * 0.6
                 + math.sin(freq * 2.3 * t + NP[o + 1]) * 0.3
                 + math.sin(freq * 4.1 * t + NP[o + 2]) * 0.1
        end
        return Vector3.new(axis(1) * amp, axis(4) * amp * 0.5, axis(7) * amp)   -- Y media amplitud
    end

    -- ADAPTACIÓN (hill-climb): nudgea amp/freq hacia lo que MAXIMIZA tus hits (Strafe.hitAccuracy). Coordinate
    -- ascent: sigue la dirección mientras el hit-rate mejora, la reversa al empeorar. Corre en la fase STRAFE.
    local adapt = { amp = 14, freq = 1.5, dirA = 1, dirF = 1, lastAcc = 0, lastT = 0 }
    Strafe.adapt = adapt
    local function adaptStep(target)
        local C = Strafe.CONF
        local now = os.clock()
        if (now - adapt.lastT) < C.adaptInterval then return end
        adapt.lastT = now
        local acc = Strafe.hitAccuracy(target)
        if acc < adapt.lastAcc - 1e-3 then adapt.dirA = -adapt.dirA; adapt.dirF = -adapt.dirF end
        adapt.lastAcc = acc
        adapt.amp  = math.clamp(adapt.amp  + adapt.dirA * C.adaptLrAmp,  C.ampMin,  C.ampMax)
        adapt.freq = math.clamp(adapt.freq + adapt.dirF * C.adaptLrFreq, C.freqMin, C.freqMax)
    end
```

- [ ] **Step 3: Sync + build** — build → console. Expected: no syntax error for `Combat/Strafe.lua`.

- [ ] **Step 4: Probe generator** — load dist, `execute`:

```lua
local LIP=getgenv().LIP; local S=LIP.require("Combat.Strafe")
local v=S.noiseOffset(0.7, 14, 1.5)
print(("PROBE nt1 noiseOffset=(%.1f,%.1f,%.1f) mag=%.1f adapt.amp=%s"):format(v.X,v.Y,v.Z,v.Magnitude,tostring(S.adapt.amp)))
```

Expected: a finite Vector3, `mag` ≲ amp·1.1, `adapt.amp=14`.

- [ ] **Step 5: Commit**

```bash
git add Combat/Strafe.lua
git commit -m "feat(strafe): procedural noise-path generator + adaptive hill-climb (maximize hit rate)"
```

---

### Task 2: Strafe.lua — 3-phase cycleStep, offset injection, remove pickBestMode

**Files:** Modify `Combat/Strafe.lua`.

**Interfaces:**
- Consumes: `Strafe.noiseOffset` (Task 1), `LIP.strafeNoise`/`LIP.curStrafeAmp`/`LIP.curStrafeFreq` (set by Task 3).
- Produces: `cycleStep()` returns `"chase"`/`"strafe"`/`"bait"`; `orbitCF`/`weldOrbitOffset` emit the noise-path when `LIP.strafeNoise`.

- [ ] **Step 1: Inject noise-path into `orbitCF`** — replace:

```lua
    local function orbitCF(center, tLook, opts)
        local R, spd, h = opts.radius or 10, opts.speed or 4, opts.height or 0
```

with:

```lua
    local function orbitCF(center, tLook, opts)
        if LIP.strafeNoise then
            return CFrame.lookAt(center + Strafe.noiseOffset(os.clock(), LIP.curStrafeAmp or 12, LIP.curStrafeFreq or 1.5), center)
        end
        local R, spd, h = opts.radius or 10, opts.speed or 4, opts.height or 0
```

- [ ] **Step 2: Inject noise-path into `weldOrbitOffset`** — replace:

```lua
    local function weldOrbitOffset(opts)
        local R, spd, h = opts.radius or 10, opts.speed or 4, opts.height or 0
```

with:

```lua
    local function weldOrbitOffset(opts)
        if LIP.strafeNoise then
            return CFrame.new(Strafe.noiseOffset(os.clock(), LIP.curStrafeAmp or 12, LIP.curStrafeFreq or 1.5))
        end
        local R, spd, h = opts.radius or 10, opts.speed or 4, opts.height or 0
```

- [ ] **Step 3: Remove `pickBestMode`** — delete the whole block:

```lua
    -- AUTO-BEST-MODE (innovación): elige el modo de strafe según contexto, al entrar a CHASE. Se guarda en
    -- LIP.strafeMode; solo cambia en el borde del ciclo (LIP.strafeCycleNew) = histéresis natural.
    local function pickBestMode(dist, tvel, spoof)
        if spoof > (O("AutoSpoofThresh") or 0.40) then return "Spiral" end   -- target spoofea fuerte → 3D
        if tvel  > (O("AutoFastThresh")  or 40)   then return "Behind" end   -- rápido → pegado a su espalda
        if dist  > (O("AutoFarThresh")   or 60)   then return "Normal" end   -- lejos → órbita ancha
        return "Random"                                                       -- cerca+estático → máx jitter
    end
```

(leave a blank line where it was).

- [ ] **Step 4: Replace `cycleStep` with the 3-phase FSM** — replace the whole function:

```lua
    -- FSM del ciclo dinámico: CHASE (orbita la resuelta) aroundTime ↔ BAIT (fling void) voidTime. Los presets
    -- setean los timers. Marca LIP.strafeCycleNew al ENTRAR a un CHASE (lo usa el auto-mode para re-elegir).
    local function cycleStep()
        local now = os.clock()
        local preset = O("BaitPreset") or "Timed"
        local aT, vT
        if preset == "Micro" then
            local ping = 0.1; pcall(function() ping = LP:GetNetworkPing() end)
            aT, vT = ping + 0.02, O("VoidTime") or 0.5
        elseif preset == "Spam" then
            aT, vT = 0.06, 0.11
        else
            aT, vT = O("AroundTime") or 3.0, O("VoidTime") or 1.0   -- Timed
        end
        if not LIP.strafePhase or not LIP.strafePhaseUntil then
            LIP.strafePhase = "chase"; LIP.strafePhaseUntil = now + aT; LIP.strafeCycleNew = true
        elseif now >= LIP.strafePhaseUntil then
            if LIP.strafePhase == "chase" then
                LIP.strafePhase = "bait"; LIP.strafePhaseUntil = now + vT
            else
                LIP.strafePhase = "chase"; LIP.strafePhaseUntil = now + aT; LIP.strafeCycleNew = true
            end
        end
        return LIP.strafePhase
    end
```

with:

```lua
    -- FSM del ciclo dinámico de 3 FASES: CHASE (orbit tight + fire) → STRAFE (orbit ancho adaptativo + fire) →
    -- BAIT (fling void, no fire) → loop. Cada fase su timer (presets los setean).
    local function cycleStep()
        local now = os.clock()
        local preset = O("BaitPreset") or "Timed"
        local cT, sT, bT
        if preset == "Micro" then
            local ping = 0.1; pcall(function() ping = LP:GetNetworkPing() end)
            cT, sT, bT = ping + 0.02, O("StrafeTime") or 0.5, O("VoidTime") or 0.5
        elseif preset == "Spam" then
            cT, sT, bT = 0.06, 0.08, 0.11
        else
            cT, sT, bT = O("AroundTime") or 2.0, O("StrafeTime") or 2.0, O("VoidTime") or 1.0   -- Timed
        end
        if not LIP.strafePhase or not LIP.strafePhaseUntil then
            LIP.strafePhase = "chase"; LIP.strafePhaseUntil = now + cT
        elseif now >= LIP.strafePhaseUntil then
            if LIP.strafePhase == "chase" then
                LIP.strafePhase = "strafe"; LIP.strafePhaseUntil = now + sT
            elseif LIP.strafePhase == "strafe" then
                LIP.strafePhase = "bait"; LIP.strafePhaseUntil = now + bT
            else
                LIP.strafePhase = "chase"; LIP.strafePhaseUntil = now + cT
            end
        end
        return LIP.strafePhase
    end
```

- [ ] **Step 5: Sync + build** — build → console. Expected: no syntax error; no reference to the deleted `pickBestMode` remains (grep below).

```bash
grep -nE "pickBestMode" Combat/Strafe.lua
```

Expected: no matches.

- [ ] **Step 6: Commit**

```bash
git add Combat/Strafe.lua
git commit -m "feat(strafe): 3-phase cycle (chase->strafe->bait) + noise-path injection; remove pickBestMode"
```

---

### Task 3: Strafe.lua — tick wiring (per-phase amp/freq, run adaptStep)

**Files:** Modify `Combat/Strafe.lua` (`Strafe.tick`).

**Interfaces:**
- Consumes: `cycleStep` (Task 2), `adapt`/`adaptStep`/`noiseOffset` (Task 1), `Strafe.CONF.chaseAmp/chaseFreq`.
- Produces: `LIP.strafeNoise`, `LIP.curStrafeAmp`, `LIP.curStrafeFreq` set each tick.

- [ ] **Step 1: Replace the AutoMode block with noise-param setup** — replace:

```lua
        -- AUTO-MODE: al ENTRAR a un CHASE nuevo, re-elegir el mejor modo desde el contexto resuelto (histéresis).
        if T("AutoMode") and LIP.strafeCycleNew then
            LIP.strafeCycleNew = false
            local myR = myRoot()
            local dist = (myR and center) and (myR.Position - center).Magnitude or 0
            local rs = resState[target]
            local tvel = Strafe.targetVel(target).Magnitude
            local spoof = (rs and rs.method == "Cluster") and (1 - (rs.score or 0)) or (beh[target] and beh[target].voidFrac or 0)
            LIP.strafeMode = pickBestMode(dist, tvel, spoof)
        end
        if not T("AutoMode") then LIP.strafeMode = nil end
```

with:

```lua
        -- STRAFE PROPIO (noise-path adaptativo): reemplaza el switch de modos. amp/freq por fase — CHASE tight
        -- (CONF.chaseAmp/Freq), STRAFE ancho + adaptativo (adapt.amp/freq, corre el hill-climb sobre hit-rate).
        if T("DynStrafe") then
            LIP.strafeNoise = true
            if phase == "strafe" then
                adaptStep(target)
                LIP.curStrafeAmp, LIP.curStrafeFreq = adapt.amp, adapt.freq
            else
                LIP.curStrafeAmp, LIP.curStrafeFreq = Strafe.CONF.chaseAmp, Strafe.CONF.chaseFreq
            end
        else
            LIP.strafeNoise = false
        end
```

- [ ] **Step 2: Sync + build** — build → console. Expected: no syntax error for `Combat/Strafe.lua`.

- [ ] **Step 3: Probe cycle + wiring** — load dist, `execute` (drives the FSM directly and reads phase transitions is time-based; here just confirm no error and the fields exist):

```lua
local LIP=getgenv().LIP; local S=LIP.require("Combat.Strafe")
print(("PROBE nt3 chaseAmp=%s adaptInterval=%s strafeNoise=%s"):format(tostring(S.CONF.chaseAmp), tostring(S.CONF.adaptInterval), tostring(LIP.strafeNoise)))
```

Expected: `chaseAmp=10 adaptInterval=1 strafeNoise=<nil|false|true>` (no error).

- [ ] **Step 4: Commit**

```bash
git add Combat/Strafe.lua
git commit -m "feat(strafe): tick wires noise-path per phase + runs adaptStep in STRAFE phase"
```

---

### Task 4: UI.lua — StrafeTime slider, drop AutoMode controls, add noise/fusion sliders

**Files:** Modify `UI.lua`.

**Interfaces:**
- Consumes: `Strafe.CONF` (bound as `CONF` from resolver v3).
- Produces: `StrafeTime` option; removes `AutoMode`/`AutoSpoofThresh`/`AutoFastThresh`/`AutoFarThresh`; adds fusion-weight + noise-bound sliders.

- [ ] **Step 1: Add `StrafeTime` + drop the auto-mode block** — replace:

```lua
        dyn:AddSlider("AroundTime", { Text = "Chase Time", Min = 0.05, Max = 10, Default = 3, Decimals = 2, Suffix = "s" })
        dyn:AddSlider("VoidTime", { Text = "Bait Time", Min = 0.05, Max = 12, Default = 1, Decimals = 2, Suffix = "s" })
        dyn:AddToggle("AutoMode", { Text = "Auto Best-Mode", Default = false,
```

with:

```lua
        dyn:AddSlider("AroundTime", { Text = "Chase Time", Min = 0.05, Max = 10, Default = 2, Decimals = 2, Suffix = "s" })
        dyn:AddSlider("StrafeTime", { Text = "Strafe Time", Min = 0.05, Max = 10, Default = 2, Decimals = 2, Suffix = "s",
            Tooltip = "Duración de la fase STRAFE (noise-path adaptativo alrededor del target, dispara)." })
        dyn:AddSlider("VoidTime", { Text = "Bait Time", Min = 0.05, Max = 12, Default = 1, Decimals = 2, Suffix = "s" })
        do return end   -- PLACEHOLDER — reemplazar en Step 2 (borra el resto del bloque AutoMode)
        dyn:AddToggle("AutoMode", { Text = "Auto Best-Mode", Default = false,
```

Note: the `do return end` is a scaffold to make Step 1 self-contained; Step 2 removes it and the trailing AutoMode lines cleanly. (If editing in one pass, skip the placeholder and delete lines directly per Step 2.)

- [ ] **Step 2: Delete the AutoMode toggle + three threshold sliders** — remove this whole block (and the `do return end` placeholder if you added it):

```lua
        dyn:AddToggle("AutoMode", { Text = "Auto Best-Mode", Default = false,
            Tooltip = "Elige Spiral/Behind/Normal/Random por contexto al entrar a CHASE." })
        dyn:AddSlider("AutoSpoofThresh", { Text = "Spoof→Spiral", Min = 0, Max = 1, Default = 0.40, Decimals = 2,
            Callback = function() end })
        dyn:AddSlider("AutoFastThresh", { Text = "Fast→Behind", Min = 5, Max = 150, Default = 40, Suffix = "st/s",
            Callback = function() end })
        dyn:AddSlider("AutoFarThresh", { Text = "Far→Normal", Min = 10, Max = 200, Default = 60, Suffix = "st",
            Callback = function() end })
```

Read the exact current lines 187-194 of `UI.lua` first (the tooltips/callbacks may differ) and delete the full `AutoMode` toggle call plus the three `AutoSpoofThresh`/`AutoFastThresh`/`AutoFarThresh` slider calls in their entirety. Update the `DynStrafe` toggle tooltip to mention 3 phases:

```lua
        dyn:AddToggle("DynStrafe", { Text = "Dynamic Cycle", Default = false,
            Tooltip = "Ciclo CHASE (orbit tight) → STRAFE (noise-path adaptativo) → BAIT (fling void). Strafe propio, sin modos. No dispara en bait." })
```

- [ ] **Step 3: Add fusion-weight + noise-bound sliders** — after the `RRAccuracy` slider block in the resolver panel (`rm`), insert:

```lua
        rm:AddSlider("CwDom", { Text = "W: Dominance", Min = 0, Max = 1, Default = 0.45, Decimals = 2,
            Callback = function(v) if CONF then CONF.wDom = v end end })
        rm:AddSlider("CwStab", { Text = "W: Stability", Min = 0, Max = 1, Default = 0.35, Decimals = 2,
            Callback = function(v) if CONF then CONF.wStab = v end end })
        rm:AddSlider("CwResid", { Text = "W: Residual", Min = 0, Max = 1, Default = 0.20, Decimals = 2,
            Callback = function(v) if CONF then CONF.wResid = v end end })
        rm:AddSlider("CRevisit", { Text = "Revisit Bonus", Min = 0, Max = 1, Default = 0.30, Decimals = 2,
            Callback = function(v) if CONF then CONF.revisitBonus = v end end })
        rm:AddSlider("CPredMax", { Text = "Pred Max Speed", Min = 20, Max = 150, Default = 60, Suffix = "st/s",
            Callback = function(v) if CONF then CONF.predMaxSpeed = v end end })
        rm:AddSlider("NoiseAmpMax", { Text = "Strafe Amp Max", Min = 8, Max = 60, Default = 30, Suffix = "st",
            Callback = function(v) if CONF then CONF.ampMax = v end end })
        rm:AddSlider("NoiseFreqMax", { Text = "Strafe Freq Max", Min = 1, Max = 8, Default = 4, Decimals = 1,
            Callback = function(v) if CONF then CONF.freqMax = v end end })
```

- [ ] **Step 4: Sync + build + verify no dangling refs** — build → console. Then:

```bash
grep -nE "AutoMode|AutoSpoofThresh|AutoFastThresh|AutoFarThresh|StrafeTime" UI.lua Combat/Strafe.lua
```

Expected: `StrafeTime` in UI (+ read in Strafe cycleStep); NO `AutoMode`/`AutoSpoofThresh`/`AutoFastThresh`/`AutoFarThresh` anywhere.

- [ ] **Step 5: Commit**

```bash
git add UI.lua
git commit -m "feat(ui): Strafe Time slider + 3-phase cycle; drop AutoMode/thresholds; expose fusion-weight + noise-bound sliders"
```

---

### Task 5: Rebuild bundle + smoke test

**Files:** `dist/LifeInPrisonPrimordial.lua` (rebuilt, gitignored), `LifeInPrisonPrimordial.lua` (tracked).

- [ ] **Step 1: Full bundle** — ensure `GUIWorkspace/dist/Visuals.Primordial.lua` is in the Potassium workspace, then `execute`: `loadstring(readfile("LifeInPrisonPrimordial/bundle.lua"))()`. Expected: `[BUNDLE] escrito … compila=true`, bytes ~440k.

- [ ] **Step 2: Fresh load smoke** — `execute`: `loadstring(readfile("LifeInPrisonPrimordial/dist/LifeInPrisonPrimordial.lua"))()` → console. Expected: UI loads, no errors.

- [ ] **Step 3: Probe adapt + cycle** — `execute`:

```lua
local LIP=getgenv().LIP; local S=LIP.require("Combat.Strafe")
S.adapt.amp = 14; S.adapt.lastAcc = 0.9   -- simular hit-rate alto previo
print(("PROBE nt5 noiseOffset_ok=%s adapt.amp=%.1f freq=%.1f ampMax=%s"):format(
  tostring(pcall(S.noiseOffset, 1.0, 14, 1.5)), S.adapt.amp, S.adapt.freq, tostring(S.CONF.ampMax)))
```

Expected: `noiseOffset_ok=true`, finite amp/freq, `ampMax=30`.

- [ ] **Step 4: Copy bundle back + commit**

```bash
cp "/c/Users/trabajo/AppData/Local/Potassium/workspace/LifeInPrisonPrimordial/LifeInPrisonPrimordial.lua" "LifeInPrisonPrimordial.lua"
git add LifeInPrisonPrimordial.lua
git commit -m "build: bundle adaptive noise-path strafe + 3-phase cycle"
```

- [ ] **Step 5: Hand off live-fire** — user (burner): DynStrafe on → one organic self-strafe around the target (no mode switching); the 3 phases honor Chase/Strafe/Bait Time; amp/freq drift toward higher hit rate over ~seconds; fire suppressed only in bait.

---

## Self-Review

**Spec coverage:** §1 noise-path generator → Task 1 ✔; §2 adaptive hill-climb → Tasks 1,3 ✔; §3 three-phase cycle + per-phase amp/freq + offset injection → Tasks 2,3 ✔; §4 more resolver options (fusion weights + noise bounds sliders) → Task 4 ✔; remove pickBestMode/AutoMode → Tasks 2,3,4 ✔; bundle → Task 5 ✔.

**Type consistency:** `Strafe.noiseOffset(t,amp,freq)->Vector3` used in `orbitCF`/`weldOrbitOffset` (Task 2) and tick (Task 3). `Strafe.adapt.{amp,freq,dirA,dirF,lastAcc,lastT}` written in `adaptStep` (Task 1), read in tick (Task 3). `LIP.strafeNoise:bool`, `LIP.curStrafeAmp/curStrafeFreq:number` set in tick (Task 3), read in offset fns (Task 2). `cycleStep()->string` returns chase/strafe/bait (Task 2), consumed by tick's existing `phase` var. `CONF.{chaseAmp,chaseFreq,ampMin,ampMax,freqMin,freqMax,adaptInterval,adaptLrAmp,adaptLrFreq}` defined Task 1, read Tasks 1/3/4. Time keys `AroundTime`(chase)/`StrafeTime`(new)/`VoidTime`(bait) consistent between UI (Task 4) and `cycleStep` (Task 2).

**Placeholder scan:** Task 4 Step 1 uses a `do return end` scaffold explicitly documented as removed in Step 2 — not a stray placeholder; Step 2 also instructs reading the exact current UI lines before deleting because their tooltip/callback text was not fully re-verified during planning. All other steps carry exact Luau with runtime-probe verification.
