# Resolver Confidence Gate — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the autofire trigger respect a real, fused resolver confidence signal — scaling firerate by confidence and holding fire on shaky resolves — instead of firing at full rate whenever a target is cached.

**Architecture:** Add one fused `Strafe.fireConfidence(plr)` (cluster dominance + temporal stability + linear residual, zeroed in the void). Feed it into `Weapon.tickAuto` as a smoothstep rate multiplier gated by a floor read from the repurposed **Accuracy** slider. Guard `cacheHit` so aim never latches a void-ghost, and surface confidence + fire multiplier on the HUD. Cluster/Density resolution math is untouched.

**Tech Stack:** Luau (Roblox), PrimordialUI, module factories (`return function(require, LIP, Lib)`), build+bundle run inside the executor, tested via `roblox-executor-mcp`.

## Global Constraints

- No local Lua runtime. Verification runs inside the executor (Potassium workspace) via `roblox-executor-mcp`. Fallback when MCP is down: build must complete without error (build.lua skips missing modules, so a syntax error is the failure signal).
- Module convention: `return function(require, LIP, Lib) … return T end`. No global `require`; use the injected `require`. Cross-module access is lazily cached (pattern: `Strafe = Strafe or require("Combat.Strafe")`).
- Shared runtime state lives on the `LIP` table (e.g. `LIP.cachedHitPos`, `LIP.fireMult`).
- Build/load workflow (from `docs/ops.md`): sync Escritorio → executor workspace (robocopy), then `execute` → `loadstring(readfile("LifeInPrisonPrimordial/build.lua"))()`, then load `loadstring(readfile("LifeInPrisonPrimordial/dist/LifeInPrisonPrimordial.lua"))()`. `execute-file` with the dist path does NOT resolve — use loadstring+readfile.
- Confidence gate applies ONLY when the `Resolver` toggle is on. Resolver off → `m = 1` (today's behavior, unchanged).
- Do not touch Cluster/Density resolution math, silent-aim swap, wallbang, void-spam phase, or strafe orbit.
- Tuning defaults live in editable tables (`Strafe.CONF`) — no magic numbers inline in the gate.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `Combat/Strafe.lua` | NEW `Strafe.CONF`, `stab` state + `updateStability`, `Strafe.fireConfidence`, extend `resolverInfo` |
| `main.lua` | `cacheHit`: void guard, populate resState when Resolver on, `LIP.lastGoodHitPos` |
| `Combat/Weapon.lua` | `tickAuto`: confidence rate-scaling + hard-hold + stash `LIP.fireMult`; module-scope `Strafe` cache |
| `UI.lua` | Repurpose `RRAccuracy` slider (range/default/tooltip/callback) |
| `Visuals/CrosshairHUD.lua` | Show `Conf` + `Fire` in the active line |
| `dist/LifeInPrisonPrimordial.lua` | Rebuilt by the bundler (not hand-edited) |

Task order: 1 (Strafe) → 2 (main) → 3 (Weapon+UI) → 4 (HUD) → 5 (bundle+smoke). Task 3 consumes Task 1's `fireConfidence`; Task 4 consumes Task 1's `resolverInfo.confidence` + Task 3's `LIP.fireMult`.

---

### Task 1: Fused fire confidence in Strafe.lua

**Files:**
- Modify: `Combat/Strafe.lua` (add `Strafe.CONF` after `Strafe.DEN` ~line 117; add `stab`/`updateStability` and edit `resState` write ~lines 189/214; add `Strafe.fireConfidence` before `resolverInfo` ~line 250; edit `resolverInfo` ~lines 251-255)

**Interfaces:**
- Consumes: existing `resState[plr]` (`.pos`, `.score`), existing `Strafe.confidence(plr)` (linear residual 0–1).
- Produces:
  - `Strafe.CONF = { wDom=0.45, wStab=0.35, wResid=0.20, stabThresh=25, stabK=6, voidManhattan=7000 }`
  - `Strafe.fireConfidence(plr) -> number` (0..1); returns 0 when unresolved or resolved pos in void.
  - `resState[plr].stabFrames -> number` (0..stabK)
  - `Strafe.resolverInfo(plr)` now also returns `.confidence` (number 0..1).

- [ ] **Step 1: Add the `Strafe.CONF` tuning table**

Immediately after the `Strafe.DEN = { … }` line (~117):

```lua
    -- CONFIANZA DE DISPARO fusionada: pesos + umbrales (todo live-tuneable). wDom+wStab+wResid = 1.0.
    Strafe.CONF = { wDom = 0.45, wStab = 0.35, wResid = 0.20, stabThresh = 25, stabK = 6, voidManhattan = 7000 }
```

- [ ] **Step 2: Add stability state + updater** (just before `local resState = {}`, ~line 189)

```lua
    -- ESTABILIDAD TEMPORAL del ganador: cuántos frames seguidos la pos resuelta no saltó (> stabThresh studs).
    -- Un ganador que salta = void-spammer bueno = nunca acumula = confianza baja. Método-agnóstico.
    local stab = {}   -- [plr] = { lastPos, frames }
    local function updateStability(plr, pos)
        local C = Strafe.CONF
        local st = stab[plr]
        if not st then stab[plr] = { lastPos = pos, frames = 0 }; return 0 end
        if (pos - st.lastPos).Magnitude <= C.stabThresh then
            st.frames = math.min(st.frames + 1, C.stabK)
        else
            st.frames = 0
        end
        st.lastPos = pos
        return st.frames
    end
```

- [ ] **Step 3: Record `stabFrames` in the resState write** (~line 214)

Replace:

```lua
        resState[plr] = { pos = pos, didDef = didDef, method = method, score = score, clusters = cl, state = state, frameT = now }
```

with:

```lua
        local sf = updateStability(plr, pos)
        resState[plr] = { pos = pos, didDef = didDef, method = method, score = score, clusters = cl, state = state, frameT = now, stabFrames = sf }
```

- [ ] **Step 4: Add `Strafe.fireConfidence`** (just before `function Strafe.resolverInfo`, ~line 250)

```lua
    -- CONFIANZA DE DISPARO fusionada (0..1). La lee el gate del autofire (rate-scaling). 0 = aguanta fuego.
    -- dominancia del cluster (score) + estabilidad temporal + residual lineal; anulada a 0 si la pos cae en void.
    function Strafe.fireConfidence(plr)
        local C = Strafe.CONF
        local rs = resState[plr]
        if not rs or not rs.pos then return 0 end
        if (math.abs(rs.pos.X) + math.abs(rs.pos.Z)) >= C.voidManhattan then return 0 end
        local sDom   = rs.score or 0
        local sStab  = math.clamp((rs.stabFrames or 0) / C.stabK, 0, 1)
        local sResid = Strafe.confidence(plr)
        return math.clamp(C.wDom * sDom + C.wStab * sStab + C.wResid * sResid, 0, 1)
    end
```

- [ ] **Step 5: Extend `resolverInfo` to return `.confidence`** (~lines 251-255)

Replace the whole function with:

```lua
    function Strafe.resolverInfo(plr)
        local rs = resState[plr]
        if not rs then return { score = 0, state = "NORMAL", clusters = 0, method = O("ResolverMethod") or "Cluster", confidence = 0 } end
        return { score = rs.score or 0, state = rs.state or "NORMAL", clusters = rs.clusters or 0, method = rs.method or "Cluster", confidence = Strafe.fireConfidence(plr) }
    end
```

- [ ] **Step 6: Sync + build (syntax gate)**

Sync Escritorio → executor workspace (robocopy per `docs/ops.md`), then via `roblox-executor-mcp` `execute`:

```lua
loadstring(readfile("LifeInPrisonPrimordial/build.lua"))()
```

Then `get-console-output` (low limit). Expected: build log, no `[string ...]` syntax error for `Combat/Strafe.lua`.

- [ ] **Step 7: Probe `fireConfidence` returns a number**

`execute` (after loading the current dist and having a live enemy in-server, Resolver on):

```lua
local Players = game:GetService("Players")
for _,p in ipairs(Players:GetPlayers()) do
    if p ~= Players.LocalPlayer then
        print("fireConf", p.Name, getgenv().LIP and "LIP-ok" or "no-LIP")
    end
end
```

Then probe the function through the running module (the running script exposes `Strafe` via its closure; if not directly reachable, verify indirectly through the HUD in Task 4). Minimum gate here: **build clean, no runtime error on load**. Expected console: no errors, target names printed.

- [ ] **Step 8: Commit**

```bash
git add Combat/Strafe.lua
git commit -m "feat(resolver): fused Strafe.fireConfidence (dominance+stability+residual, void-zeroed) + resolverInfo.confidence"
```

---

### Task 2: Void guard + resState population in cacheHit (main.lua)

**Files:**
- Modify: `main.lua` (`cacheHit`, ~lines 61-100; no-target reset ~line 158)

**Interfaces:**
- Consumes: `Strafe.resolveAim(t, base) -> (pos, didDef)`, `Strafe.CONF.voidManhattan`, toggles `T.Resolver`, `T.FireResolved`.
- Produces: `LIP.lastGoodHitPos` (Vector3 or nil), `LIP.lastGoodUID` (number or nil); `LIP.cachedHitPos` never a void-ghost when a last-good exists; resState populated whenever Resolver is on (even if FireResolved off).

- [ ] **Step 1: Add target-change reset at the top of `cacheHit`**

After `local t = LIP.target` (~line 62), insert:

```lua
        if t and LIP.lastGoodUID ~= t.UserId then LIP.lastGoodHitPos = nil; LIP.lastGoodUID = t.UserId end
```

- [ ] **Step 2: Replace the base/resolved block** (~lines 70-77)

Replace:

```lua
            local base = part.Position
            if (T.Resolver and T.Resolver.Value) and (T.FireResolved and T.FireResolved.Value) then
                local resolved, didDef = Strafe.resolveAim(t, base)
                if didDef then LIP.cachedHitPos = resolved; LIP.didDefensive = true
                else LIP.cachedHitPos = base; LIP.didDefensive = false end
            else
                LIP.cachedHitPos = base; LIP.didDefensive = false
            end
```

with:

```lua
            local base = part.Position
            local resolveOn = T.Resolver and T.Resolver.Value
            local fireResOn = resolveOn and (T.FireResolved and T.FireResolved.Value)
            local voidMan = (Strafe.CONF and Strafe.CONF.voidManhattan) or 7000
            local inVoid = (math.abs(base.X) + math.abs(base.Z)) >= voidMan
            local resolved, didDef
            if resolveOn then resolved, didDef = Strafe.resolveAim(t, base) end   -- puebla resState (confianza) aunque FireResolved off
            if fireResOn and didDef and resolved then
                LIP.cachedHitPos = resolved; LIP.didDefensive = true
            elseif inVoid and LIP.lastGoodHitPos then
                LIP.cachedHitPos = LIP.lastGoodHitPos; LIP.didDefensive = false   -- guard anti-void: nunca latch al ghost
            else
                LIP.cachedHitPos = base; LIP.didDefensive = false
            end
            if not inVoid then LIP.lastGoodHitPos = base end
```

- [ ] **Step 3: Reset last-good on no-part branch** (~line 99)

Replace:

```lua
            LIP.cachedHitPos = nil; LIP.cachedOrigin = nil; LIP.didDefensive = false
```

with:

```lua
            LIP.cachedHitPos = nil; LIP.cachedOrigin = nil; LIP.didDefensive = false; LIP.lastGoodHitPos = nil
```

- [ ] **Step 4: Reset last-good on no-target branch** (~line 158)

Replace:

```lua
        if LIP.target then cacheHit() else LIP.cachedHitPart, LIP.cachedHitPos, LIP.didDefensive = nil, nil, false end
```

with:

```lua
        if LIP.target then cacheHit() else LIP.cachedHitPart, LIP.cachedHitPos, LIP.didDefensive, LIP.lastGoodHitPos = nil, nil, false, nil end
```

- [ ] **Step 5: Sync + build (syntax gate)**

`execute`: `loadstring(readfile("LifeInPrisonPrimordial/build.lua"))()` → `get-console-output`. Expected: no syntax error for `main.lua`.

- [ ] **Step 6: Probe the void guard**

With Resolver on, FireResolved off, and an enemy who spams to the void, load the dist and `execute`:

```lua
task.wait(2)
local hp = getgenv().LIP and getgenv().LIP.cachedHitPos
if hp then print("cachedHitPos manhattan", math.abs(hp.X)+math.abs(hp.Z)) else print("no cachedHitPos") end
```

Expected: printed manhattan `< 7000` (real pos / last-good), NOT millions — even while the target's raw head is in the void.

- [ ] **Step 7: Commit**

```bash
git add main.lua
git commit -m "feat(aim): void guard + lastGoodHitPos in cacheHit; populate resState whenever Resolver on"
```

---

### Task 3: Confidence rate-scaling in tickAuto + repurpose Accuracy slider

**Files:**
- Modify: `Combat/Weapon.lua` (module-scope `Strafe` decl ~line 21; `tickAuto` rate block ~lines 205-219)
- Modify: `UI.lua` (`RRAccuracy` slider ~lines 155-156)

**Interfaces:**
- Consumes: `Strafe.fireConfidence(plr)` (Task 1), `O("RRAccuracy")` (floor 0..1), `T("Resolver")`, `LIP.target`, existing `rate`/`LIP.fireAccum`/`lastTick`.
- Produces: `LIP.fireMult` (number 0..1) stashed each tick; effective firerate = `rate * m`; hard-hold (`return`) when `m < 0.02`.

- [ ] **Step 1: Declare a module-scope `Strafe` cache in Weapon.lua**

After `local Weapon = {}` (~line 21), insert:

```lua
    local Strafe   -- lazy-cached (require("Combat.Strafe")) para fireConfidence en el gate
```

- [ ] **Step 2: Insert the confidence gate** in `tickAuto`, immediately after `rate = math.min(rate, O("AutoFireRate") or 120)` (~line 211) and before `local dt = …` (~line 212):

```lua
        -- CONFIDENCE GATE (solo con Resolver on): escala el firerate efectivo por la confianza fusionada.
        -- conf < floor (slider Accuracy) → m=0 = aguanta fuego; floor..floor+0.3 → goteo eased (smoothstep); arriba → full.
        local m = 1
        if T("Resolver") and LIP.target then
            Strafe = Strafe or require("Combat.Strafe")
            local conf  = Strafe.fireConfidence(LIP.target)
            local floor = O("RRAccuracy") or 0.5
            local hi    = math.min(1, floor + 0.30)
            local u     = (hi > floor) and math.clamp((conf - floor) / (hi - floor), 0, 1) or (conf >= floor and 1 or 0)
            m = u * u * (3 - 2 * u)
            LIP.fireMult = m
            if m < 0.02 then LIP.fireAccum = 0; lastTick = now; return end
        else
            LIP.fireMult = 1
        end
```

- [ ] **Step 3: Apply the multiplier to the accumulator** (~line 214)

Replace:

```lua
        LIP.fireAccum = (LIP.fireAccum or 0) + dt * rate
```

with:

```lua
        LIP.fireAccum = (LIP.fireAccum or 0) + dt * rate * m
```

- [ ] **Step 4: Repurpose the Accuracy slider** in `UI.lua` (~lines 155-156)

Replace:

```lua
        rm:AddSlider("RRAccuracy", { Text = "Accuracy", Min = 0.4, Max = 3, Default = 1.35, Decimals = 2,
            Callback = function(v) if RParams then RParams.accuracy = v end end })
```

with:

```lua
        rm:AddSlider("RRAccuracy", { Text = "Accuracy", Min = 0, Max = 1, Default = 0.5, Decimals = 2,
            Tooltip = "Min resolver confidence to fire (0 = off, higher = holds fire on shaky resolves)",
            Callback = function() end })   -- leído en vivo por el gate del autofire: O('RRAccuracy')
```

Note: `RParams.accuracy` keeps its table default `1.35` in `Combat/Strafe.lua:111` (still gates the internal cluster `didDefensive`); it is simply no longer UI-tuned. If a saved Linoria config holds an old `RRAccuracy` (e.g. 1.35), it clamps to 1 after this change → resets/max-holds; re-set the slider once after updating.

- [ ] **Step 5: Sync + build (syntax gate)**

`execute`: `loadstring(readfile("LifeInPrisonPrimordial/build.lua"))()` → `get-console-output`. Expected: no syntax error for `Combat/Weapon.lua` or `UI.lua`.

- [ ] **Step 6: Probe fire-hold behavior**

Load dist. Resolver ON, AutoFire+TargetStrafe ON, Accuracy slider = 1.0 (max), against a hard-spamming target. `execute`:

```lua
task.wait(3)
print("fireMult", getgenv().LIP and getgenv().LIP.fireMult)
```

Expected: `fireMult` near 0 (holds) against a shaky target at floor=1.0. Then set Accuracy = 0 and re-probe → `fireMult` ~1 (fires like today). Confirms the slider now gates.

- [ ] **Step 7: Commit**

```bash
git add Combat/Weapon.lua UI.lua
git commit -m "feat(autofire): confidence-scaled firerate + hard-hold in tickAuto; repurpose Accuracy slider as confidence floor"
```

---

### Task 4: Show confidence + fire multiplier on the HUD (CrosshairHUD.lua)

**Files:**
- Modify: `Visuals/CrosshairHUD.lua` (`activeLine`, ~lines 59-65)

**Interfaces:**
- Consumes: `Strafe.resolverInfo(plr).confidence` (Task 1), `LIP.fireMult` (Task 3).
- Produces: HUD line renders `Conf` (0..1) and `Fire` (0..1).

- [ ] **Step 1: Add `confidence` to the fallback + swap the format string** (~lines 59-65)

Replace:

```lua
            local ri = (Strafe and Strafe.resolverInfo(LIP.target)) or { score = LIP.hudResolved or 0, state = "NORMAL", clusters = 0 }
            local hp = 0
            local tc = LIP.target and LIP.target.Character
            local th = tc and tc:FindFirstChildOfClass("Humanoid")
            if th then hp = math.floor(th.Health) end
            return ("killing: %s | Resolved: %.3f | %s | clusters: %d | HP: %d"):format(
                LIP.hudTargetName, ri.score, ri.state, ri.clusters, hp)
```

with:

```lua
            local ri = (Strafe and Strafe.resolverInfo(LIP.target)) or { score = LIP.hudResolved or 0, state = "NORMAL", clusters = 0, confidence = 0 }
            local hp = 0
            local tc = LIP.target and LIP.target.Character
            local th = tc and tc:FindFirstChildOfClass("Humanoid")
            if th then hp = math.floor(th.Health) end
            return ("killing: %s | Conf: %.2f | Fire: %.2f | %s | HP: %d"):format(
                LIP.hudTargetName, ri.confidence or 0, LIP.fireMult or 1, ri.state, hp)
```

- [ ] **Step 2: Sync + build (syntax gate)**

`execute`: `loadstring(readfile("LifeInPrisonPrimordial/build.lua"))()` → `get-console-output`. Expected: no syntax error for `Visuals/CrosshairHUD.lua`.

- [ ] **Step 3: Visual probe**

Load dist, Resolver ON, target selected. `screenshot-window` the Roblox client. Expected: HUD line reads `killing: <name> | Conf: 0.xx | Fire: 0.xx | <STATE> | HP: nn`, with Conf and Fire moving as the target moves/spams.

- [ ] **Step 4: Commit**

```bash
git add Visuals/CrosshairHUD.lua
git commit -m "feat(hud): show fused Conf + Fire multiplier in the crosshair readout"
```

---

### Task 5: Rebuild bundle + smoke test

**Files:**
- Modify: `dist/LifeInPrisonPrimordial.lua` (regenerated), plus the self-contained bundle output of `bundle.lua`.

**Interfaces:**
- Consumes: all prior tasks.
- Produces: a loadable `dist/` + self-contained bundle with the confidence gate live.

- [ ] **Step 1: Sync + full bundle**

Sync Escritorio → executor workspace. `execute`:

```lua
loadstring(readfile("LifeInPrisonPrimordial/bundle.lua"))()
```

Expected console: build log + no `[BUNDLE] marker de PrimordialUI NO encontrado` warning; bundle written.

- [ ] **Step 2: Fresh load smoke test**

`execute`:

```lua
loadstring(readfile("LifeInPrisonPrimordial/dist/LifeInPrisonPrimordial.lua"))()
```

Then `get-console-output` (low limit). Expected: UI loads, no errors.

- [ ] **Step 3: End-to-end gate check**

Resolver ON, AutoFire+TargetStrafe ON. Sweep Accuracy 0 → 1 against a live target while watching the HUD `Fire` value and the tracer volume. Expected: `Fire`→1 and steady fire at low Accuracy; `Fire`→0 and held fire at high Accuracy on a shaky/void-spamming target. Aim never snaps to void coords.

- [ ] **Step 4: Commit the rebuilt dist**

```bash
git add dist/LifeInPrisonPrimordial.lua LifeInPrisonPrimordial.lua
git commit -m "build: bundle resolver confidence gate"
```

- [ ] **Step 5: Hand off live-fire**

Live-fire confirmation in a real server is deferred to the user (burner account), consistent with project norm. Report the code-complete + load-verified state and the exact toggles/slider to exercise.

---

## Self-Review

**Spec coverage:**
- §1 `fireConfidence` (dominance+stability+residual+void-zero) → Task 1 ✔
- §2 rate scaling in `tickAuto` (smoothstep, hard-hold) → Task 3 ✔
- §3 repurpose Accuracy slider as floor; `RParams.accuracy` stays 1.35 internal → Task 3 ✔
- §4 void guard + `lastGoodHitPos` in `cacheHit` → Task 2 ✔
- §5 HUD shows confidence + fireMult (`LIP.fireMult` stashed in tickAuto) → Tasks 3+4 ✔
- Resolver-off = unchanged behavior (`m=1`) → Task 3 Step 2 ✔
- Bundle rebuild + smoke → Task 5 ✔

**Type consistency:** `Strafe.fireConfidence(plr)->number`, `resState.stabFrames->number`, `resolverInfo().confidence->number`, `LIP.fireMult->number`, `LIP.lastGoodHitPos->Vector3?`, `LIP.lastGoodUID->number?` — used identically across tasks. `Strafe.CONF.voidManhattan` referenced in Task 1 (definition) and Task 2 (guard) with a `or 7000` fallback. Slider key `RRAccuracy` consistent between UI (Task 3) and the gate read `O("RRAccuracy")` (Task 3).

**Placeholder scan:** No TBD/TODO; every code step has concrete Luau. Verification steps use runtime probes (no unit-test framework exists) with explicit expected console/visual output.
