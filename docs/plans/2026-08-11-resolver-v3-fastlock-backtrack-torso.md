# Resolver v3 — Faster Lock + Backtrack + Hist/Torso — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans or superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Lock faster on repeated void patterns, fire through fresh void frames via backtrack, and improve `math.random` hits with a bigger sample window + HRP (torso) aim on random-strafers.

**Architecture:** Extends resolver v1/v2 on branch `resolver-confidence-gate`. Confidence and sampling changes in `Strafe.lua`; a backtrack term in `Weapon.tickAuto`; `main.lua` stamps `lastGoodT` and picks the hit part; UI adds two sliders + a toggle.

**Tech Stack:** Luau (Roblox), PrimordialUI, module factories, build+bundle in-executor, tested via `roblox-executor-mcp` (client ko3l1_300).

## Global Constraints

- No local Lua runtime. Verify via executor: sync (robocopy) → `loadstring(readfile("LifeInPrisonPrimordial/build.lua"))()` → load dist. Fallback = build must complete.
- **The full/root bundle needs `bundle.lua`** (now inlines GUIVisuals World Visuals); the `dist/` never has the Visuals sub-tab. Test resolver logic from `dist/`, test the Visuals tab only from the root `LifeInPrisonPrimordial.lua`.
- New tunables live in `Strafe.CONF`. Slider option keys read live via `O("Name")`; toggle flags via `T.Flag.Value`.
- Do not fire at real players from probes (ops.md); live-fire deferred to user (burner).
- Do not touch Cluster/Density core neighborhood math beyond returning the winner count.
- `Strafe.CONF` after v2 = `{ wDom=0.45, wStab=0.35, wResid=0.20, stabThresh=25, stabK=6, voidManhattan=7000, predMaxSpeed=60, hcWindow=0.35, hcRate=0.10, hcRelax=0.40 }`.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `Combat/Strafe.lua` | `CONF` new keys; `histMax` cap; `winCount` in resState; revisit bonus in `fireConfidence`; `isRandomStrafer` |
| `Combat/Weapon.lua` | backtrack multiplier in `tickAuto` void path |
| `main.lua` | `LIP.lastGoodT`; torso-aim hit-part choice in `cacheHit` |
| `UI.lua` | sliders `HistMax`, `BacktrackWindow`; toggle `BigHitbox` |

Task order: 1 (Strafe) → 2 (main) → 3 (Weapon) → 4 (UI) → 5 (bundle). Weapon/main consume Strafe; do Strafe first.

---

### Task 1: Strafe.lua — CONF keys, histMax, winCount, revisit bonus, isRandomStrafer

**Files:** Modify `Combat/Strafe.lua`.

**Interfaces:**
- Produces: `Strafe.CONF.{stabK=3, revisitBonus, revisitMin, revisitScale, backtrackWindow, histMax}`; `resState.winCount`; `Strafe.isRandomStrafer(plr)->bool`; `fireConfidence` includes revisit bonus.

- [ ] **Step 1: Extend `Strafe.CONF`** — replace the two `Strafe.CONF = { … }` lines:

```lua
    Strafe.CONF = { wDom = 0.45, wStab = 0.35, wResid = 0.20, stabThresh = 25, stabK = 6, voidManhattan = 7000,
                    predMaxSpeed = 60, hcWindow = 0.35, hcRate = 0.10, hcRelax = 0.40 }
```

with:

```lua
    Strafe.CONF = { wDom = 0.45, wStab = 0.35, wResid = 0.20, stabThresh = 25, stabK = 3, voidManhattan = 7000,
                    predMaxSpeed = 60, hcWindow = 0.35, hcRate = 0.10, hcRelax = 0.40,
                    revisitBonus = 0.30, revisitMin = 4, revisitScale = 8, backtrackWindow = 0.15, histMax = 200 }
```

- [ ] **Step 2: Use `histMax` for the sample cap** — replace:

```lua
        if #h.s > MAX then table.remove(h.s, 1); table.remove(h.t, 1) end
```

with:

```lua
        if #h.s > (Strafe.CONF.histMax or MAX) then table.remove(h.s, 1); table.remove(h.t, 1) end
```

- [ ] **Step 3: Return the winner count from `resolveCluster`** — replace:

```lua
        local score = math.clamp(bestScore / (RP.accuracy * 2), 0, 1)
        return (didDefensive and best.pos) or hitbox, didDefensive, score, #t.list
```

with:

```lua
        local score = math.clamp(bestScore / (RP.accuracy * 2), 0, 1)
        return (didDefensive and best.pos) or hitbox, didDefensive, score, #t.list, (best and best.count or 0)
```

- [ ] **Step 4: Store `winCount` in resState** — in `resolveByMethod`, replace the Density branch:

```lua
        if method == "Density" then
            local p, dd, cnt = resolveDensity(plr, localPos)
            pos, didDef = p or rawPos, dd or false
            score = math.clamp(((cnt or 0) - Strafe.DEN.minMatches) / 8, 0, 1)
            cl = cnt or 0
            state = didDef and "LOCKED" or (p and "RESOLVING" or "VOID")
        else
            local p, dd, sc, n = resolveCluster(plr, rawPos, now, localPos)
            pos, didDef = p, dd
            score = sc or 0; cl = n or 0
            state = dd and "LOCKED" or ((cl > 0) and "RESOLVING" or "NORMAL")
        end
        local sf = updateStability(plr, pos)
        resState[plr] = { pos = pos, didDef = didDef, method = method, score = score, clusters = cl, state = state, frameT = now, stabFrames = sf }
```

with:

```lua
        local winCount = 0
        if method == "Density" then
            local p, dd, cnt = resolveDensity(plr, localPos)
            pos, didDef = p or rawPos, dd or false
            score = math.clamp(((cnt or 0) - Strafe.DEN.minMatches) / 8, 0, 1)
            cl = cnt or 0; winCount = cnt or 0
            state = didDef and "LOCKED" or (p and "RESOLVING" or "VOID")
        else
            local p, dd, sc, n, wc = resolveCluster(plr, rawPos, now, localPos)
            pos, didDef = p, dd
            score = sc or 0; cl = n or 0; winCount = wc or 0
            state = dd and "LOCKED" or ((cl > 0) and "RESOLVING" or "NORMAL")
        end
        local sf = updateStability(plr, pos)
        resState[plr] = { pos = pos, didDef = didDef, method = method, score = score, clusters = cl, state = state, frameT = now, stabFrames = sf, winCount = winCount }
```

- [ ] **Step 5: Add revisit bonus to `fireConfidence`** — replace:

```lua
        local sDom   = rs.score or 0
        local sStab  = math.clamp((rs.stabFrames or 0) / C.stabK, 0, 1)
        local sResid = Strafe.confidence(plr)
        return math.clamp(C.wDom * sDom + C.wStab * sStab + C.wResid * sResid, 0, 1)
```

with:

```lua
        local sDom   = rs.score or 0
        local sStab  = math.clamp((rs.stabFrames or 0) / C.stabK, 0, 1)
        local sResid = Strafe.confidence(plr)
        local base   = C.wDom * sDom + C.wStab * sStab + C.wResid * sResid
        -- BONUS por revisita: un cluster golpeado muchas veces = el ancla real del void spam → lock más rápido.
        local revisit = C.revisitBonus * math.clamp(((rs.winCount or 0) - C.revisitMin) / C.revisitScale, 0, 1)
        return math.clamp(base + revisit, 0, 1)
```

- [ ] **Step 6: Add `Strafe.isRandomStrafer`** — insert just before `function Strafe.resolverInfo`:

```lua
    -- FIRMA math.random: in-map (voidFrac bajo) + no resuelto (score bajo) + inestable (salta). Para torso-aim.
    function Strafe.isRandomStrafer(plr)
        local b, rs = beh[plr], resState[plr]
        if not (b and rs) then return false end
        return b.voidFrac < 0.30 and (rs.score or 0) < 0.30 and (rs.stabFrames or 0) < 2
    end

```

- [ ] **Step 7: Sync + build** — `loadstring(readfile("LifeInPrisonPrimordial/build.lua"))()` → console. Expected: no syntax error for `Combat/Strafe.lua`.

- [ ] **Step 8: Probe** — load dist, `execute`:

```lua
local LIP=getgenv().LIP; local S=LIP.require("Combat.Strafe")
print("PROBE v3t1 stabK="..S.CONF.stabK.." histMax="..S.CONF.histMax.." revisitBonus="..S.CONF.revisitBonus.." isRandomStrafer_type="..type(S.isRandomStrafer))
```

Expected: `stabK=3 histMax=200 revisitBonus=0.3 isRandomStrafer_type=function`.

- [ ] **Step 9: Commit**

```bash
git add Combat/Strafe.lua
git commit -m "feat(resolver): faster void lock (stabK 6->3 + revisit bonus), histMax cap, winCount, isRandomStrafer"
```

---

### Task 2: main.lua — lastGoodT + torso-aim

**Files:** Modify `main.lua` (`cacheHit`).

**Interfaces:**
- Consumes: `Strafe.isRandomStrafer` (Task 1), toggle `T.BigHitbox`, `T.Resolver`.
- Produces: `LIP.lastGoodT` (number); hit part = HRP when big-hitbox chosen.

- [ ] **Step 1: Torso-aim hit-part choice** — replace:

```lua
        local ch = t and t.Character
        local part = ch and (ch:FindFirstChild("Head") or ch:FindFirstChild("HumanoidRootPart"))
        LIP.cachedHitPart = part
```

with:

```lua
        local ch = t and t.Character
        -- TORSO-AIM: HRP (hitbox grande) si BigHitbox on O el resolver marca random-strafer (math.random) →
        -- el residual del centroide (~5-9 studs) igual pega el cuerpo. Si no, Head como siempre.
        local wantBig = ch and ((T.BigHitbox and T.BigHitbox.Value)
                        or ((T.Resolver and T.Resolver.Value) and Strafe.isRandomStrafer(t)))
        local part = ch and (wantBig and (ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Head"))
                             or (ch:FindFirstChild("Head") or ch:FindFirstChild("HumanoidRootPart")))
        LIP.cachedHitPart = part
```

- [ ] **Step 2: Stamp `LIP.lastGoodT`** — replace:

```lua
            if not inVoid then LIP.lastGoodHitPos = base end
            LIP.targetExposed = not inVoid   -- head crudo real/visible → habilita fire oportunista
```

with:

```lua
            if not inVoid then LIP.lastGoodHitPos = base; LIP.lastGoodT = os.clock() end
            LIP.targetExposed = not inVoid   -- head crudo real/visible → habilita fire oportunista
```

- [ ] **Step 3: Sync + build** — build → console. Expected: no syntax error for `main.lua`.

- [ ] **Step 4: Commit**

```bash
git add main.lua
git commit -m "feat(aim): stamp LIP.lastGoodT for backtrack; torso-aim (HRP) on random-strafers / BigHitbox"
```

---

### Task 3: Weapon.lua — on-shot backtrack in tickAuto

**Files:** Modify `Combat/Weapon.lua` (`tickAuto` void path).

**Interfaces:**
- Consumes: `LIP.lastGoodHitPos`, `LIP.lastGoodT` (Task 2), `Strafe.CONF.backtrackWindow`.
- Produces: void-path `m = max(confidence gate, backtrack)`.

- [ ] **Step 1: Merge backtrack into the void-path multiplier** — replace:

```lua
                local conf  = Strafe.fireConfidence(LIP.target)
                local floor = (O("RRAccuracy") or 0.5) * (1 - Strafe.CONF.hcRelax * Strafe.hitAccuracy(LIP.target))
                local hi    = math.min(1, floor + 0.30)
                local u     = (hi > floor) and math.clamp((conf - floor) / (hi - floor), 0, 1) or (conf >= floor and 1 or 0)
                m = u * u * (3 - 2 * u)
                LIP.fireMult = m
                if m < 0.02 then LIP.fireAccum = 0; lastTick = now; return end
```

with:

```lua
                local conf  = Strafe.fireConfidence(LIP.target)
                local floor = (O("RRAccuracy") or 0.5) * (1 - Strafe.CONF.hcRelax * Strafe.hitAccuracy(LIP.target))
                local hi    = math.min(1, floor + 0.30)
                local u     = (hi > floor) and math.clamp((conf - floor) / (hi - floor), 0, 1) or (conf >= floor and 1 or 0)
                local gateM = u * u * (3 - 2 * u)
                -- ON-SHOT BACKTRACK: el cuerpo real sigue ~en lastGood durante los void-frames frescos → dispara
                -- igual (cachedHitPos ya apunta a lastGoodHitPos en void). Fade por antigüedad de la última real.
                local btM, lgt = 0, (LIP.lastGoodT or 0)
                if LIP.lastGoodHitPos and (now - lgt) < Strafe.CONF.backtrackWindow then
                    btM = math.clamp(1 - (now - lgt) / Strafe.CONF.backtrackWindow, 0, 1)
                end
                m = math.max(gateM, btM)
                LIP.fireMult = m
                if m < 0.02 then LIP.fireAccum = 0; lastTick = now; return end
```

- [ ] **Step 2: Sync + build** — build → console. Expected: no syntax error for `Combat/Weapon.lua`.

- [ ] **Step 3: Commit**

```bash
git add Combat/Weapon.lua
git commit -m "feat(autofire): on-shot backtrack — fire at last-good pos during fresh void frames"
```

---

### Task 4: UI.lua — HistMax + BacktrackWindow sliders + BigHitbox toggle

**Files:** Modify `UI.lua`.

**Interfaces:**
- Produces: sliders `HistMax` (→ `CONF.histMax`), `BacktrackWindow` (→ `CONF.backtrackWindow`); toggle `BigHitbox`.

- [ ] **Step 1: Bind CONF and add the controls** — after the existing `local RParams = Strafe.RParams; local DEN = Strafe.DEN` line, add `CONF`:

```lua
        local RParams = Strafe.RParams; local DEN = Strafe.DEN
```

becomes:

```lua
        local RParams = Strafe.RParams; local DEN = Strafe.DEN; local CONF = Strafe.CONF
```

- [ ] **Step 2: Add the two sliders + toggle** — immediately after the `FireResolved` toggle block (the `rm:AddToggle("FireResolved", { … })` call, ~line 139-140), insert:

```lua
        rm:AddToggle("BigHitbox", { Text = "Big Hitbox (HRP)", Default = false,
            Tooltip = "Aima al HRP (hitbox grande) en vez del Head. Auto para random-strafers (math.random)." })
        rm:AddSlider("HistMax", { Text = "Sample Cap", Min = 60, Max = 500, Default = 200, Suffix = " smp",
            Tooltip = "Muestras del historial. Más = centroide de math.random más ajustado. ⚠️ Density O(n²): 400+ puede lagear.",
            Callback = function(v) if CONF then CONF.histMax = math.floor(v) end end })
        rm:AddSlider("BacktrackWindow", { Text = "Backtrack Win", Min = 0, Max = 0.5, Default = 0.15, Decimals = 2, Suffix = "s",
            Tooltip = "Ventana tras la última pos real donde el autofire dispara en void-frames (on-shot backtrack). 0 = off.",
            Callback = function(v) if CONF then CONF.backtrackWindow = v end end })
```

- [ ] **Step 3: Sync + build + verify no dangling refs** — build → console (no syntax error for `UI.lua`). Then:

```bash
grep -nE "BigHitbox|HistMax|BacktrackWindow" UI.lua main.lua Combat/Weapon.lua Combat/Strafe.lua
```

Expected: `BigHitbox` referenced in UI + main; `HistMax`/`BacktrackWindow` in UI; `CONF.histMax`/`CONF.backtrackWindow` in Strafe/Weapon.

- [ ] **Step 4: Commit**

```bash
git add UI.lua
git commit -m "feat(ui): Big Hitbox toggle + Sample Cap + Backtrack Window sliders"
```

---

### Task 5: Rebuild bundle + smoke test

**Files:** `dist/LifeInPrisonPrimordial.lua` (rebuilt, gitignored), `LifeInPrisonPrimordial.lua` (self-contained, tracked).

- [ ] **Step 1: Full bundle** — ensure `GUIWorkspace/dist/Visuals.Primordial.lua` is in the Potassium workspace, then `execute`: `loadstring(readfile("LifeInPrisonPrimordial/bundle.lua"))()`. Expected: `[BUNDLE] escrito … compila=true`, no missing-marker warning, bytes ~440k (World Visuals inlined).

- [ ] **Step 2: Fresh load smoke** — `execute`: `loadstring(readfile("LifeInPrisonPrimordial/dist/LifeInPrisonPrimordial.lua"))()` → console. Expected: UI loads, no errors.

- [ ] **Step 3: Probe backtrack + revisit** — with Resolver on and a live target, `execute`:

```lua
local LIP=getgenv().LIP; local S=LIP.require("Combat.Strafe")
local P=game:GetService("Players"); local t; for _,p in ipairs(P:GetPlayers()) do if p~=P.LocalPlayer and p.Character then t=p break end end
if not t then return print("PROBE v3t5 no target") end
local now=os.clock(); for i=1,20 do S.sampleAll(now+i*0.03) end
local hrp=t.Character:FindFirstChild("HumanoidRootPart"); if hrp then S.resolveAim(t, hrp.Position) end
local ri=S.resolverInfo(t)
print(("PROBE v3t5 winCount_via_conf conf=%.3f isRandomStrafer=%s"):format(S.fireConfidence(t), tostring(S.isRandomStrafer(t))))
```

Expected: prints a confidence number and a bool, no error.

- [ ] **Step 4: Copy bundle back + commit**

```bash
cp "/c/Users/trabajo/AppData/Local/Potassium/workspace/LifeInPrisonPrimordial/LifeInPrisonPrimordial.lua" "LifeInPrisonPrimordial.lua"
git add LifeInPrisonPrimordial.lua
git commit -m "build: bundle resolver v3 (faster lock, backtrack, hist cap, torso-aim)"
```

- [ ] **Step 5: Hand off live-fire** — user (burner): void-spam locks/fires sooner; fire continues through void frames after a real flip; random-strafer aim moves to HRP; raise Sample Cap to tighten the centroid (watch FPS).

---

## Self-Review

**Spec coverage:** §1 faster lock (stabK 3 + revisit bonus) → Task 1 ✔; §2 backtrack (lastGoodT + tickAuto btM) → Tasks 2,3 ✔; §3 hist cap + torso-aim (histMax + isRandomStrafer + HRP pick) → Tasks 1,2,4 ✔; UI controls → Task 4 ✔; bundle → Task 5 ✔.

**Type consistency:** `resolveCluster` 5th return `winCount:number` consumed as `wc` in Task 1 Step 4; `resState.winCount` read in `fireConfidence` (Task 1 Step 5). `Strafe.isRandomStrafer(plr)->bool` used in Task 2. `LIP.lastGoodT:number` stamped Task 2, read Task 3. `CONF.{histMax,backtrackWindow,revisitBonus,revisitMin,revisitScale,stabK}` defined Task 1, read Tasks 1/3/4. Slider keys `HistMax`/`BacktrackWindow` and toggle `BigHitbox` consistent between UI (Task 4) and reads (Tasks 1/2/3).

**Placeholder scan:** all steps carry exact Luau; verification via runtime probes with explicit expected output.
