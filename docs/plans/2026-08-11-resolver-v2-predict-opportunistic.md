# Resolver v2 — Predict Rework + Opportunistic Fire + Hit-Confirm — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Remove the reject-vel pre-filter, replace prediction with a base+amplitude model, restore fast opportunistic shots on exposed/TP targets, and auto-tune the confidence floor from live hit-rate.

**Architecture:** Extends the v1 confidence gate on branch `resolver-confidence-gate`. Prediction and sampling change in `Strafe.lua`; the trigger gains an opportunistic (exposed→fire) path and a hit-confirm-relaxed floor in `Weapon.tickAuto`; `main.lua` feeds exposure + hit-confirm; UI swaps sliders.

**Tech Stack:** Luau (Roblox), PrimordialUI, module factories, build+bundle in-executor, tested via `roblox-executor-mcp` (client ko3l1_300).

## Global Constraints

- No local Lua runtime. Verify via executor: sync (robocopy) → `loadstring(readfile("LifeInPrisonPrimordial/build.lua"))()` → load dist. Fallback = build must complete (a syntax error fails the whole dist loadstring).
- Module convention `return function(require, LIP, Lib)`; shared state on `LIP`; cross-module `Strafe = Strafe or require("Combat.Strafe")`.
- New tunables live in `Strafe.CONF` (already exists from v1). Slider option keys read live via `O("Name")`.
- Do not fire at real players from probes (ops.md risk rules); live-fire deferred to user (burner).
- Do not touch Cluster/Density resolution math.
- `Strafe.CONF` after v1 = `{ wDom=0.45, wStab=0.35, wResid=0.20, stabThresh=25, stabK=6, voidManhattan=7000 }`.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `Combat/Strafe.lua` | reject-vel removal; base+amp predict; `CONF` new keys; hit-confirm state/fns; `resolverInfo.hitAcc` |
| `Combat/Weapon.lua` | `fireOne` timestamp; opportunistic + relaxed-floor gate in `tickAuto` |
| `main.lua` | sampleAll arg; `LIP.targetExposed`; `updateHitConfirm` call |
| `UI.lua` | remove ResolverReject/PredMode/PredLead; add PredictBase/PredictAmp |
| `Visuals/CrosshairHUD.lua` | show `Hit` accuracy |

Task order: 1 (Strafe predict+sampling+CONF) → 2 (Strafe hit-confirm) → 3 (Weapon) → 4 (main) → 5 (UI) → 6 (HUD) → 7 (bundle+smoke). Weapon/main consume Strafe fns; do Strafe first.

---

### Task 1: Strafe.lua — remove reject-vel + base+amplitude prediction

**Files:**
- Modify: `Combat/Strafe.lua` (`sample`, `sampleAll`, `Strafe.CONF`, `resolveAim` lead block, `resolvedPeek` lead block)

**Interfaces:**
- Produces: `Strafe.sample(plr, pos, now)`, `Strafe.sampleAll(now)` (arity dropped by one); `Strafe.CONF.predMaxSpeed`; predict = `resolved + vel*(PredictBase + PredictAmp*speedNorm)`.

- [ ] **Step 1: Add predict/hit-confirm keys to `Strafe.CONF`**

Replace the `Strafe.CONF = { … }` line with:

```lua
    Strafe.CONF = { wDom = 0.45, wStab = 0.35, wResid = 0.20, stabThresh = 25, stabK = 6, voidManhattan = 7000,
                    predMaxSpeed = 60, hcWindow = 0.35, hcRate = 0.10, hcRelax = 0.40 }
```

- [ ] **Step 2: Strip reject-vel from `sample`**

Replace:

```lua
    local function sample(plr, pos, now, rejectVel)
        local h = hist[plr]; if not h then h = { s = {}, t = {} }; hist[plr] = h end
        local n = #h.s
        if n > 0 then
            local dt = now - h.t[n]
            if dt > 0 and (pos - h.s[n]).Magnitude / dt > (rejectVel or 300) then return end  -- fling/tp spoof
        end
        h.s[#h.s + 1] = pos; h.t[#h.t + 1] = now
```

with:

```lua
    local function sample(plr, pos, now)
        local h = hist[plr]; if not h then h = { s = {}, t = {} }; hist[plr] = h end
        -- SIN reject-vel: el clustering + void-manhattan rechazan basura; el pre-filtro tapaba TPs reales.
        h.s[#h.s + 1] = pos; h.t[#h.t + 1] = now
```

- [ ] **Step 3: Strip reject-vel from `sampleAll`**

Replace:

```lua
    function Strafe.sampleAll(now, rejectVel)
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP then
                local c = plr.Character
                local hrp = c and c:FindFirstChild("HumanoidRootPart")
                local hum = c and c:FindFirstChildOfClass("Humanoid")
                if hrp and hum and hum.Health > 0 then sample(plr, hrp.Position, now, rejectVel) end
            end
        end
    end
```

with:

```lua
    function Strafe.sampleAll(now)
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP then
                local c = plr.Character
                local hrp = c and c:FindFirstChild("HumanoidRootPart")
                local hum = c and c:FindFirstChildOfClass("Humanoid")
                if hrp and hum and hum.Health > 0 then sample(plr, hrp.Position, now) end
            end
        end
    end
```

- [ ] **Step 4: Base+amplitude predict in `resolveAim`**

Replace the lead block:

```lua
        local lead
        if (O("PredMode") or "Auto") == "Auto" then
            local ping = 0.1; pcall(function() ping = LP:GetNetworkPing() end)
            lead = ping * 2                       -- ≡ ping_ms/500 de juju (GetNetworkPing = segundos)
        else
            lead = O("PredLead") or 0.12
        end
        pos = pos + vel * lead
        return pos, didDefensive
```

with:

```lua
        -- PREDICT base + amplitud×velocidad: base = lead constante (comp ping, aún quieto); amp escala con
        -- la velocidad normalizada del target (rápido = más lead). Reemplaza el vel*lead ping/manual.
        local base = O("PredictBase") or 0.10
        local amp  = O("PredictAmp")  or 0.15
        local speedNorm = math.clamp(vel.Magnitude / Strafe.CONF.predMaxSpeed, 0, 1)
        pos = pos + vel * (base + amp * speedNorm)
        return pos, didDefensive
```

- [ ] **Step 5: Base+amplitude predict in `resolvedPeek` (tracer parity)**

Replace:

```lua
        if v and v.vel and v.vel.Magnitude <= 200 then
            local lead
            if (O("PredMode") or "Auto") == "Auto" then
                local ping = 0.1; pcall(function() ping = LP:GetNetworkPing() end)
                lead = ping * 2
            else
                lead = O("PredLead") or 0.12
            end
            pos = pos + v.vel * lead
        end
```

with:

```lua
        if v and v.vel and v.vel.Magnitude <= 200 then
            local base = O("PredictBase") or 0.10
            local amp  = O("PredictAmp")  or 0.15
            local speedNorm = math.clamp(v.vel.Magnitude / Strafe.CONF.predMaxSpeed, 0, 1)
            pos = pos + v.vel * (base + amp * speedNorm)
        end
```

- [ ] **Step 6: Sync + build (syntax gate)**

Sync (robocopy), then `execute`: `loadstring(readfile("LifeInPrisonPrimordial/build.lua"))()` → `get-console-output`. Expected: `[build] dist … escrito`, no syntax error for `Combat/Strafe.lua`.

- [ ] **Step 7: Probe sampleAll arity + predict**

Load dist, `execute`:

```lua
local LIP = getgenv().LIP; local Strafe = LIP.require("Combat.Strafe")
local ok = pcall(function() Strafe.sampleAll(os.clock()) end)
print("PROBE v2t1 sampleAll(1arg) ok:", ok, "predMaxSpeed:", Strafe.CONF.predMaxSpeed)
```

Expected: `ok: true predMaxSpeed: 60`.

- [ ] **Step 8: Commit**

```bash
git add Combat/Strafe.lua
git commit -m "feat(resolver): remove reject-vel pre-filter; base+amplitude prediction (PredictBase+PredictAmp)"
```

---

### Task 2: Strafe.lua — hit-confirm meter

**Files:**
- Modify: `Combat/Strafe.lua` (add `hc` state + `updateHitConfirm` + `hitAccuracy` near the confidence fns; extend `resolverInfo`)

**Interfaces:**
- Consumes: `LIP.lastFireT` (Task 3 stamps it; read defensively with `or 0`).
- Produces: `Strafe.updateHitConfirm(plr, now)`, `Strafe.hitAccuracy(plr) -> number`; `resolverInfo(plr).hitAcc`.

- [ ] **Step 1: Add hit-confirm state + functions** (just after `Strafe.fireConfidence`, before `Strafe.resolverInfo`)

```lua
    -- HIT-CONFIRM: acc EMA por target. HP baja & disparamos < hcWindow → hit; disparamos sin baja → miss.
    -- Atribución aproximada (otro jugador podría pegar); el EMA suaviza. Relaja el piso del gate (Weapon).
    local hc = {}   -- [plr] = { lastHP, acc }
    function Strafe.updateHitConfirm(plr, now)
        local C = Strafe.CONF
        local ch = plr and plr.Character
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        if not hum then hc[plr] = nil; return end
        local h = hc[plr]; if not h then hc[plr] = { lastHP = hum.Health, acc = 0 }; return end
        local fired = (now - (LIP.lastFireT or 0)) <= C.hcWindow
        if fired then
            local hit = (hum.Health < h.lastHP - 0.01) and 1 or 0
            h.acc = h.acc + C.hcRate * (hit - h.acc)
        end
        h.lastHP = hum.Health
    end
    function Strafe.hitAccuracy(plr)
        local h = hc[plr]; return h and h.acc or 0
    end
```

- [ ] **Step 2: Add `hitAcc` to `resolverInfo`**

Replace the `resolverInfo` return lines:

```lua
        if not rs then return { score = 0, state = "NORMAL", clusters = 0, method = O("ResolverMethod") or "Cluster", confidence = 0 } end
        return { score = rs.score or 0, state = rs.state or "NORMAL", clusters = rs.clusters or 0, method = rs.method or "Cluster", confidence = Strafe.fireConfidence(plr) }
```

with:

```lua
        if not rs then return { score = 0, state = "NORMAL", clusters = 0, method = O("ResolverMethod") or "Cluster", confidence = 0, hitAcc = Strafe.hitAccuracy(plr) } end
        return { score = rs.score or 0, state = rs.state or "NORMAL", clusters = rs.clusters or 0, method = rs.method or "Cluster", confidence = Strafe.fireConfidence(plr), hitAcc = Strafe.hitAccuracy(plr) }
```

- [ ] **Step 3: Sync + build (syntax gate)**

`execute` build → console. Expected: no syntax error for `Combat/Strafe.lua`.

- [ ] **Step 4: Probe hit-confirm**

Load dist, `execute`:

```lua
local LIP = getgenv().LIP; local Strafe = LIP.require("Combat.Strafe")
local Players = game:GetService("Players"); local tgt
for _,p in ipairs(Players:GetPlayers()) do if p~=Players.LocalPlayer and p.Character then tgt=p break end end
if not tgt then return print("PROBE v2t2 no target") end
local now = os.clock()
Strafe.updateHitConfirm(tgt, now); Strafe.updateHitConfirm(tgt, now+0.05)
print("PROBE v2t2 hitAccuracy type:", type(Strafe.hitAccuracy(tgt)), "val:", Strafe.hitAccuracy(tgt))
```

Expected: `type: number val: 0` (no fire recorded → stays 0).

- [ ] **Step 5: Commit**

```bash
git add Combat/Strafe.lua
git commit -m "feat(resolver): hit-confirm meter (HP-drop EMA per target) + resolverInfo.hitAcc"
```

---

### Task 3: Weapon.lua — opportunistic fire + relaxed floor + fire timestamp

**Files:**
- Modify: `Combat/Weapon.lua` (`fireOne` ~line 138-158; `tickAuto` confidence-gate block)

**Interfaces:**
- Consumes: `LIP.targetExposed` (Task 4), `Strafe.hitAccuracy` (Task 2), `Strafe.fireConfidence` (v1), `O("RRAccuracy")`.
- Produces: `LIP.lastFireT` stamped per shot; `LIP.fireMult`; opportunistic `m=1` when exposed.

- [ ] **Step 1: Stamp `LIP.lastFireT` in `fireOne`**

After the `LIP.shotsFired = (LIP.shotsFired or 0) + 1` line (~158), add:

```lua
        LIP.lastFireT = os.clock()   -- hit-confirm: marca de disparo para atribuir HP-drop
```

- [ ] **Step 2: Rework the confidence-gate block in `tickAuto`**

Replace the v1 block:

```lua
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

with:

```lua
        local m = 1
        if T("Resolver") and LIP.target then
            Strafe = Strafe or require("Combat.Strafe")
            if LIP.targetExposed then
                -- FIRE OPORTUNISTA: target real/visible (head no-void) → snapshot, saltea piso+estabilidad.
                m = 1; LIP.fireMult = 1
            else
                -- VOID: dispara a la pos recuperada, gateada por confianza. Piso relajado por hit-rate en vivo.
                local conf  = Strafe.fireConfidence(LIP.target)
                local floor = (O("RRAccuracy") or 0.5) * (1 - Strafe.CONF.hcRelax * Strafe.hitAccuracy(LIP.target))
                local hi    = math.min(1, floor + 0.30)
                local u     = (hi > floor) and math.clamp((conf - floor) / (hi - floor), 0, 1) or (conf >= floor and 1 or 0)
                m = u * u * (3 - 2 * u)
                LIP.fireMult = m
                if m < 0.02 then LIP.fireAccum = 0; lastTick = now; return end
            end
        else
            LIP.fireMult = 1
        end
```

- [ ] **Step 3: Sync + build (syntax gate)**

`execute` build → console. Expected: no syntax error for `Combat/Weapon.lua`.

- [ ] **Step 4: Commit**

```bash
git add Combat/Weapon.lua
git commit -m "feat(autofire): opportunistic fire on exposed target + hit-confirm relaxed floor; stamp lastFireT"
```

---

### Task 4: main.lua — exposure flag + hit-confirm call + sampleAll arg

**Files:**
- Modify: `main.lua` (sampleAll call ~line 162; `cacheHit` exposure; no-target reset; add `updateHitConfirm` call)

**Interfaces:**
- Consumes: `Strafe.updateHitConfirm` (Task 2).
- Produces: `LIP.targetExposed` (bool), set in `cacheHit`, reset when target cleared.

- [ ] **Step 1: Drop reject arg from the sampleAll call** (~line 162)

Replace:

```lua
        if needAim or (T.Resolver and T.Resolver.Value) then Strafe.sampleAll(os.clock(), O.ResolverReject.Value) end
```

with:

```lua
        if needAim or (T.Resolver and T.Resolver.Value) then Strafe.sampleAll(os.clock()) end
```

- [ ] **Step 2: Set `LIP.targetExposed` in `cacheHit`**

The v1 `cacheHit` computes `inVoid`. Immediately after the `if not inVoid then LIP.lastGoodHitPos = base end` line, add:

```lua
            LIP.targetExposed = not inVoid   -- head crudo real/visible → habilita fire oportunista
```

- [ ] **Step 3: Reset exposure on no-part branch**

Replace:

```lua
            LIP.cachedHitPos = nil; LIP.cachedOrigin = nil; LIP.didDefensive = false; LIP.lastGoodHitPos = nil
```

with:

```lua
            LIP.cachedHitPos = nil; LIP.cachedOrigin = nil; LIP.didDefensive = false; LIP.lastGoodHitPos = nil; LIP.targetExposed = false
```

- [ ] **Step 4: Reset exposure on no-target branch + call hit-confirm**

Replace:

```lua
        if LIP.target then cacheHit() else LIP.cachedHitPart, LIP.cachedHitPos, LIP.didDefensive, LIP.lastGoodHitPos = nil, nil, false, nil end
```

with:

```lua
        if LIP.target then
            cacheHit()
            Strafe.updateHitConfirm(LIP.target, os.clock())   -- hit-confirm auto-tune (HP-drop → acc)
        else
            LIP.cachedHitPart, LIP.cachedHitPos, LIP.didDefensive, LIP.lastGoodHitPos, LIP.targetExposed = nil, nil, false, nil, false
        end
```

- [ ] **Step 5: Sync + build (syntax gate)**

`execute` build → console. Expected: no syntax error for `main.lua`.

- [ ] **Step 6: Probe exposure flag**

Load dist, Resolver ON, a target selected via any needAim toggle NOT firing (e.g. leave AutoFire off; the resolver samples with Resolver on). Simpler direct probe:

```lua
local LIP = getgenv().LIP
task.wait(1.5)
print("PROBE v2t4 targetExposed:", tostring(LIP.targetExposed), "target:", LIP.target and LIP.target.Name or "nil")
```

Expected: prints `true`/`false`/`nil` without error (value depends on whether a target is cached and in void).

- [ ] **Step 7: Commit**

```bash
git add main.lua
git commit -m "feat(aim): LIP.targetExposed for opportunistic fire; call updateHitConfirm; drop reject arg"
```

---

### Task 5: UI.lua — swap sliders

**Files:**
- Modify: `UI.lua` (remove `ResolverReject` ~line 131, `PredMode` ~137, `PredLead` ~139; add `PredictBase`, `PredictAmp`)

**Interfaces:**
- Produces: options `PredictBase` (0..0.4, def 0.10), `PredictAmp` (0..0.4, def 0.15). Removes `ResolverReject`, `PredMode`, `PredLead`.

- [ ] **Step 1: Remove the ResolverReject slider** (~line 131)

Delete:

```lua
        rm:AddSlider("ResolverReject", { Text = "Reject Vel", Min = 50, Max = 1000, Default = 300, Suffix = "st/s",
```
…through the end of that `AddSlider({ … })` call. (Read the exact 2-3 lines in the file and remove the whole call.)

- [ ] **Step 2: Replace PredMode + PredLead with PredictBase + PredictAmp** (~lines 137-139)

Read the exact current `PredMode` dropdown and `PredLead` slider calls in `UI.lua` and replace both with:

```lua
        rm:AddSlider("PredictBase", { Text = "Predict Base", Min = 0, Max = 0.4, Default = 0.10, Decimals = 2, Suffix = "s",
            Tooltip = "Lead constante (comp de ping), aplicado aún quieto" })
        rm:AddSlider("PredictAmp", { Text = "Predict Amp", Min = 0, Max = 0.4, Default = 0.15, Decimals = 2, Suffix = "s",
            Tooltip = "Lead extra que escala con la velocidad del target" })
```

Ensure no other code references `O("PredMode")`, `O("PredLead")`, or `O.ResolverReject` remain (grep after editing; Tasks 1 and 4 already removed the Strafe/main uses).

- [ ] **Step 3: Sync + build + verify no dangling refs**

`execute` build → console (no syntax error for `UI.lua`). Then locally:

```bash
grep -rnE "PredMode|PredLead|ResolverReject" --include=*.lua Combat/ main.lua UI.lua
```

Expected: no matches.

- [ ] **Step 4: Commit**

```bash
git add UI.lua
git commit -m "feat(ui): replace ResolverReject/PredMode/PredLead with PredictBase + PredictAmp sliders"
```

---

### Task 6: CrosshairHUD.lua — show hit accuracy

**Files:**
- Modify: `Visuals/CrosshairHUD.lua` (`activeLine` format)

**Interfaces:**
- Consumes: `resolverInfo(plr).hitAcc` (Task 2).

- [ ] **Step 1: Add `Hit` to the readout**

Replace:

```lua
            return ("killing: %s | Conf: %.2f | Fire: %.2f | %s | HP: %d"):format(
                LIP.hudTargetName, ri.confidence or 0, LIP.fireMult or 1, ri.state, hp)
```

with:

```lua
            return ("killing: %s | Conf: %.2f | Fire: %.2f | Hit: %.2f | %s | HP: %d"):format(
                LIP.hudTargetName, ri.confidence or 0, LIP.fireMult or 1, ri.hitAcc or 0, ri.state, hp)
```

- [ ] **Step 2: Sync + build (syntax gate)**

`execute` build → console. Expected: no syntax error for `Visuals/CrosshairHUD.lua`.

- [ ] **Step 3: Commit**

```bash
git add Visuals/CrosshairHUD.lua
git commit -m "feat(hud): show Hit accuracy in the crosshair readout"
```

---

### Task 7: Rebuild bundle + smoke test

**Files:**
- Modify: `dist/LifeInPrisonPrimordial.lua` (rebuilt, gitignored), `LifeInPrisonPrimordial.lua` (self-contained, tracked).

- [ ] **Step 1: Full bundle**

Sync, `execute`: `loadstring(readfile("LifeInPrisonPrimordial/bundle.lua"))()`. Expected: `[BUNDLE] escrito … compila=true`, no missing-marker warning.

- [ ] **Step 2: Fresh load smoke**

`execute`: `loadstring(readfile("LifeInPrisonPrimordial/dist/LifeInPrisonPrimordial.lua"))()` → `get-console-output`. Expected: UI loads, no errors.

- [ ] **Step 3: Copy bundle back + commit**

```bash
cp "/c/Users/trabajo/AppData/Local/Potassium/workspace/LifeInPrisonPrimordial/LifeInPrisonPrimordial.lua" "LifeInPrisonPrimordial.lua"
git add LifeInPrisonPrimordial.lua
git commit -m "build: bundle resolver v2 (predict base+amp, opportunistic fire, hit-confirm)"
```

- [ ] **Step 4: Hand off live-fire**

Report code-complete + load-verified. User exercises on burner: exposed target → fast shots return; pure-void target → gate still holds (relaxed by Hit meter); tune PredictBase/PredictAmp + Accuracy live.

---

## Self-Review

**Spec coverage:**
- §1 remove reject-vel (sample/sampleAll/main/UI) → Tasks 1,4,5 ✔
- §2 base+amp predict (resolveAim + resolvedPeek + sliders) → Tasks 1,5 ✔
- §3 opportunistic fire (`LIP.targetExposed` + tickAuto exposed→m=1) → Tasks 3,4 ✔
- §4 hit-confirm (fireOne stamp, updateHitConfirm, hitAccuracy, relaxed floor, HUD) → Tasks 2,3,4,6 ✔
- HUD hitAcc → Tasks 2,6 ✔
- bundle → Task 7 ✔

**Type consistency:** `Strafe.sample(plr,pos,now)` / `Strafe.sampleAll(now)` arity dropped consistently (caller updated Task 4). `Strafe.updateHitConfirm(plr,now)`, `Strafe.hitAccuracy(plr)->number`, `LIP.lastFireT->number`, `LIP.targetExposed->bool`, `resolverInfo().hitAcc->number`, `Strafe.CONF.{predMaxSpeed,hcWindow,hcRate,hcRelax}` — used identically across tasks. Slider keys `PredictBase`/`PredictAmp` consistent between UI (Task 5) and reads in Strafe (Task 1).

**Placeholder scan:** Tasks 1-4,6,7 carry exact code. Task 5 Steps 1-2 instruct reading the exact current dropdown/slider lines before removal because their multi-line bodies were not re-read in full during planning — the replacement text is concrete; only the delete-anchor is read at execution.
