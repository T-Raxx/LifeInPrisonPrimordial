# Resolver v3 + Target Strafe dinámico + Section propia — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (o subagent-driven-development) para implementar task-by-task. Steps usan checkbox (`- [ ]`).

**Goal:** Agregar el método Density (sakura) + Auto-método al resolver de LiP, un Target Strafe dinámico de ciclo (chase→bait→auto-mode), y moverlo todo a una Section propia en el sidebar de Rage.

**Architecture:** Todo el resolver/strafe vive en `Combat/Strafe.lua`. Un `resolveByMethod` centraliza el ruteo Cluster/Density/Auto y llena un `resState[plr]` único (lo leen peek/info/aim/orbit). El ciclo dinámico (`cycleStep`) se ejecuta dentro de `Strafe.tick`, alterna CHASE (orbita resuelta) ↔ BAIT (fling void) por timers, y re-elige el modo (`pickBestMode`) al entrar a CHASE. UI = nueva Section.

**Tech Stack:** Luau, PrimordialUI (Section=sidebar), executor MCP.

## Global Constraints
- **Sin tests unitarios** (Lua cheat). Verificación por task = `luau-lsp analyze` sobre el bundle (0 SyntaxErrors — los `TypeError: Unknown global` de executor son esperados) + **MCP live probe** (cliente LiP place 72659788689464). Live-fire real = usuario.
- Convención módulo: `return function(require, LIP, Lib)`. Helpers `O(f)`/`T(f)` ya existen en Strafe.lua. `LIP.*` sobrevive reload (getgenv).
- Contrato del resolver INTACTO: `Strafe.resolveAim(plr, rawHitboxPos) -> pos, didDefensive` alimenta cacheHit (main.lua:72) + Fire on Resolved + tracer. No romperlo.
- Params (verbatim del spec): Cluster `{posWeight 1.5, voidWeight 0.2, forget 80, distPenalty 2.0, accuracy 1.35, lerp 0.1}`; Density `{forgiveness 14.4, outOfVoidBonus 13, distPenalty 3.2, minMatches 3, window 3.0, voidManhattan 7000}`; void detect Euclid ≥9e5 (cluster) / Manhattan ≥7000 (density); lead Auto = ping·2.
- Rebuild: `& "C:\Users\trabajo\.claude\jobs\be669aee\tmp\build_bundle.ps1"` (PowerShell tool). Gist `1552e7e4cb41aee0d826f644689838e2` vía `gh gist edit`.
- Reload MCP: `loadstring(game:HttpGet(<hashed raw_url>))()` (State.lua auto-unloada).

## File Structure
- `Combat/Strafe.lua` — TODO el resolver/strafe (density, auto-método, resState, cycle FSM, auto-mode, void bait). Archivo central.
- `Combat/Weapon.lua` — fire gate (suprimir en bait).
- `UI.lua` — nueva Section "Resolver" (migra controles + nuevos).
- `main.lua` — sin cambios de lógica (el ciclo lee flags solo; strafeOpts ya pasa lo necesario).

---

### Task 1: Density method + behavior sampling

**Files:** Modify `Combat/Strafe.lua` (hist L52-63, tras `Strafe.RParams` L~200)

**Interfaces:**
- Produces: `resolveDensity(plr, localPos) -> Vector3|nil, boolean`; `Strafe.DEN` (tabla params); `beh[plr] = {voidFrac, flipRate, prevVoid}` (comportamiento EMA).

- [ ] **Step 1: Subir el cap del log + agregar tabla de comportamiento**

En `Combat/Strafe.lua` L53, cambiar `local MAX = 16` → `local MAX = 120` (ventana 3s a ~40Hz). Tras la línea `local hist = {}` (L52), agregar:
```lua
    local beh = {}    -- [player] = { voidFrac, flipRate, prevVoid } — EMA para el Auto-método
```

- [ ] **Step 2: Alimentar el comportamiento en `sample`**

En `sample(plr, pos, now, rejectVel)` (L54-63), antes del `end` final de la función (tras el cap del log), agregar:
```lua
        local b = beh[plr]; if not b then b = { voidFrac = 0, flipRate = 0, prevVoid = false }; beh[plr] = b end
        local isVoid = (math.abs(pos.X) + math.abs(pos.Z)) >= 7000
        b.voidFrac = b.voidFrac + 0.15 * ((isVoid and 1 or 0) - b.voidFrac)
        b.flipRate = b.flipRate + 0.15 * (((isVoid ~= b.prevVoid) and 1 or 0) - b.flipRate)
        b.prevVoid = isVoid
```

- [ ] **Step 3: Agregar `Strafe.DEN` + `resolveDensity`**

Tras `Strafe.RParams = RP` (L~200, después del bloque del cluster), agregar:
```lua
    -- DENSITY (sakura / Unnamed Enhancements): batch O(n²) sobre el log, cuenta vecinos dentro de un radio
    -- CHICO (studs). El void (millones de studs entre sí) nunca clusteriza. Radio encoge con la distancia.
    Strafe.DEN = { forgiveness = 14.4, outOfVoidBonus = 13, distPenalty = 3.2, minMatches = 3, window = 3.0, voidManhattan = 7000 }
    local function resolveDensity(plr, localPos)
        local D = Strafe.DEN
        local h = hist[plr]; local n = h and #h.s or 0
        if n < D.minMatches + 1 then return nil, false end
        local now = os.clock()
        local bestPos, bestCount = nil, D.minMatches - 1
        for i = 1, n do
            if now - h.t[i] <= D.window then
                local p1 = h.s[i]
                local inMap = (math.abs(p1.X) + math.abs(p1.Z)) < D.voidManhattan
                local forg = D.forgiveness + (inMap and D.outOfVoidBonus or 0)
                if localPos then forg = forg - ((localPos - p1).Magnitude / 100) * D.distPenalty end
                forg = math.clamp(forg, 1, 1000)
                local count, sum = 0, p1
                for j = 1, n do
                    if i ~= j and (now - h.t[j] <= D.window) and (p1 - h.s[j]).Magnitude <= forg then
                        count = count + 1; sum = sum + h.s[j]
                    end
                end
                if count >= D.minMatches and count > bestCount then
                    bestCount = count; bestPos = sum / (count + 1)
                end
            end
        end
        local didDef = bestPos ~= nil and bestCount >= (D.minMatches + 1)
        return bestPos, didDef, bestCount
    end
```

- [ ] **Step 4: Rebuild + verify estructural**

Rebuild bundle (PowerShell). `luau-lsp analyze` sobre el bundle → 0 SyntaxErrors.
```bash
cd "C:/Users/trabajo/OneDrive/Escritorio" && ./luau-lsp.exe analyze "Scripts/LifeInPrisonPrimordial/LifeInPrisonPrimordial.lua" 2>&1 | grep -c SyntaxError
```
Expected: `0`.

- [ ] **Step 5: Verify MCP (funcional)**

Reload en cliente. Probe: alimentar hist con real+void alternado vía `Strafe.sampleAll` no aplica (usa players reales) → probar `resolveDensity` inyectando en `hist` directo no es accesible (local). En su lugar, verificar vía el flujo real en Task 2 (resolveByMethod expuesto por resolveAim). Este task: solo estructural (Step 4). Marcar OK si 0 SyntaxErrors.

- [ ] **Step 6: Commit**
```bash
git add Combat/Strafe.lua && git commit -m "feat(resolver): metodo Density (sakura) + behavior sampling (voidFrac/flipRate)"
```

---

### Task 2: Ruteo unificado (resolveByMethod + resState + Auto)

**Files:** Modify `Combat/Strafe.lua` (resolveCluster L107-146, resolveAim L161-178, resolvePos L221-246)

**Interfaces:**
- Consumes: `resolveCluster`, `resolveDensity` (T1), `beh` (T1).
- Produces: `resState[plr] = { pos, didDef, method, score(0-1), clusters, state }`; `resolveByMethod(plr, rawPos, localPos) -> pos, didDef`; `pickMethod(plr) -> "Cluster"|"Density"`.

- [ ] **Step 1: Agregar resState + pickMethod + resolveByMethod**

Tras `resolveDensity` (T1), agregar:
```lua
    local resState = {}   -- [player] = { pos, didDef, method, score, clusters, state, frameT }
    local function pickMethod(plr)
        local b = beh[plr]
        if b and b.voidFrac > 0.30 and b.voidFrac < 0.75 and b.flipRate > 0.35 then return "Density" end
        return "Cluster"
    end
    -- centraliza Cluster/Density/Auto + cachea por frame (varios callers por tick). Llena resState.
    local function resolveByMethod(plr, rawPos, localPos)
        local now = os.clock()
        local rs = resState[plr]
        if rs and rs.frameT == now then return rs.pos, rs.didDef end   -- cache por frame
        local method = O("ResolverMethod") or "Cluster"
        if method == "Auto" then method = pickMethod(plr) end
        local pos, didDef, score, clusters, state
        if method == "Density" then
            local p, dd, cnt = resolveDensity(plr, localPos)
            pos, didDef = p or rawPos, dd or false
            score = math.clamp(((cnt or 0) - Strafe.DEN.minMatches) / 8, 0, 1)
            clusters = cnt or 0
            state = didDef and "LOCKED" or (p and "RESOLVING" or "VOID")
        else
            local p, dd, sc, n = resolveCluster(plr, rawPos, now, localPos)
            pos, didDef = p, dd
            score = sc or 0; clusters = n or 0
            state = dd and "LOCKED" or ((clusters > 0) and "RESOLVING" or "NORMAL")
        end
        resState[plr] = { pos = pos, didDef = didDef, method = method, score = score, clusters = clusters, state = state, frameT = now }
        return pos, didDef
    end
```

- [ ] **Step 2: `resolveCluster` devuelve score + count**

`resolveCluster` (L107-146) hoy termina con `return (didDefensive and best.pos) or hitbox, didDefensive`. Cambiar el `return` a:
```lua
        local score = math.clamp(bestScore / (RP.accuracy * 2), 0, 1)
        return (didDefensive and best.pos) or hitbox, didDefensive, score, #t.list
```
(`bestScore` ya está calculado arriba en la función; `t.list` es la lista de clusters.)

- [ ] **Step 3: `resolveAim` usa resolveByMethod**

En `resolveAim` (L161-178), reemplazar la línea `local pos, didDefensive = resolveCluster(plr, rawHitboxPos, now, loc)` por:
```lua
        local pos, didDefensive = resolveByMethod(plr, rawHitboxPos, loc)
```
(El resto de resolveAim — velocidad resuelta + lead + floor — queda igual.)

- [ ] **Step 4: `resolvePos` usa resolveByMethod, quita legacy**

Reemplazar TODO el cuerpo de `resolvePos` (L221-246) por:
```lua
    function Strafe.resolvePos(plr, rawPos, method, samples, predictT)
        local r = myRoot(); local loc = r and r.Position or rawPos
        local p = resolveByMethod(plr, rawPos, loc)   -- Cluster/Density/Auto (descarta didDef, solo pos)
        if predictT and predictT > 0 then p = p + Strafe.targetVel(plr) * predictT end
        return p or rawPos
    end
```
(Elimina las ramas Median/Weighted/Average/Latest. `median` local queda sin uso → borrar la función `median` L74 para no dejar dead code.)

- [ ] **Step 5: Rebuild + verify estructural**

Rebuild. `luau-lsp analyze` → 0 SyntaxErrors.

- [ ] **Step 6: Verify MCP (funcional — Density resuelve real, ignora void)**

Reload. Probe (Method=Density, alimentar vía resolveAim con real+void interleaved sobre LocalPlayer):
```lua
local LIP=getgenv().LIP; local S=LIP.require("Combat.Strafe")
local LP=game:GetService("Players").LocalPlayer
LIP.Library.Options.ResolverMethod:SetValue("Density")
local real=Vector3.new(120,45,-80); local void=Vector3.new(9e8,9e8,9e8)
-- alimentar el log via sample (sampleAll usa players reales; inyectamos con resolveAim que NO llena hist)
-- => llenar hist directo no accesible; usar sampleAll no sirve. Validar con jugador real O con Method=Cluster.
return { note="Density feed necesita hist real; validar con target vivo o en Task 8 live" }
```
Nota: `hist` se llena solo con players reales (sampleAll). Con 1 solo cliente no hay target → validación funcional real de Density = Task 8 (con alt) o juego con enemigos. Este task: verificar que `resolveByMethod` corre sin error con Method=Cluster (probe existente de resolvedPeek sigue andando) + 0 SyntaxErrors.
```lua
local LIP=getgenv().LIP; local S=LIP.require("Combat.Strafe")
LIP.Library.Options.ResolverMethod:SetValue("Auto")
local LP=game:GetService("Players").LocalPlayer
for i=1,10 do S.resolveAim(LP, Vector3.new(120,45,-80)) end
return { peek = S.resolvedPeek(LP)~=nil, info = S.resolverInfo(LP).method }
```
Expected: `peek=true`, `info` = "Cluster" o "Density" (string, no nil).

- [ ] **Step 7: Commit**
```bash
git add Combat/Strafe.lua && git commit -m "feat(resolver): resolveByMethod (Cluster/Density/Auto) + resState unificado, quita legacy"
```

---

### Task 3: Telemetría por método (resolvedPeek + resolverInfo)

**Files:** Modify `Combat/Strafe.lua` (resolvedPeek L~197, resolverInfo L181-194)

**Interfaces:**
- Consumes: `resState` (T2).
- Produces: `resolverInfo(plr) -> { score, state, clusters, method }`; `resolvedPeek(plr) -> Vector3|nil` (método-agnóstico).

- [ ] **Step 1: `resolverInfo` lee resState**

Reemplazar el cuerpo de `resolverInfo(plr)` (L181-194) por:
```lua
    function Strafe.resolverInfo(plr)
        local rs = resState[plr]
        if not rs then return { score = 0, state = "NORMAL", clusters = 0, method = O("ResolverMethod") or "Cluster" } end
        return { score = rs.score or 0, state = rs.state or "NORMAL", clusters = rs.clusters or 0, method = rs.method or "Cluster" }
    end
```

- [ ] **Step 2: `resolvedPeek` método-agnóstico**

`resolvedPeek` hoy lee `clusters[plr]` (solo Cluster). Reemplazar su cuerpo por lectura de resState (funciona para ambos métodos) + el mismo lead:
```lua
    function Strafe.resolvedPeek(plr)
        local rs = resState[plr]
        if not rs or not rs.pos then return nil end
        local pos = rs.pos
        local v = velState[plr]
        if v and v.vel and v.vel.Magnitude <= 200 then
            local lead
            if (O("PredMode") or "Auto") == "Auto" then
                local ping = 0.1; pcall(function() ping = LP:GetNetworkPing() end); lead = ping * 2
            else lead = O("PredLead") or 0.12 end
            pos = pos + v.vel * lead
        end
        return pos
    end
```
(`velState` ya existe, definido antes de resolvedVel.)

- [ ] **Step 3: Rebuild + verify estructural** — `luau-lsp analyze` → 0 SyntaxErrors.

- [ ] **Step 4: Verify MCP**
```lua
local LIP=getgenv().LIP; local S=LIP.require("Combat.Strafe"); local LP=game:GetService("Players").LocalPlayer
LIP.Library.Options.ResolverMethod:SetValue("Cluster")
for i=1,10 do S.resolveAim(LP, Vector3.new(50,20,50)) end
local info=S.resolverInfo(LP)
return { method=info.method, state=info.state, score=math.floor(info.score*100)/100, peek=S.resolvedPeek(LP)~=nil }
```
Expected: `method="Cluster"`, `state` ∈ LOCKED/RESOLVING/NORMAL, `peek=true`.

- [ ] **Step 5: Commit**
```bash
git add Combat/Strafe.lua && git commit -m "feat(resolver): peek/info metodo-agnostico (leen resState)"
```

---

### Task 4: Ciclo dinámico (CHASE↔BAIT) + void bait

**Files:** Modify `Combat/Strafe.lua` (rng L270-272, Strafe.tick L345-432)

**Interfaces:**
- Produces: `LIP.strafePhase ∈ {"chase","bait"}`, `LIP.strafeMode` (string); `voidBaitCF() -> CFrame`; `cycleStep() -> ("chase"|"bait")`.

- [ ] **Step 1: Void bait CFrame (replica de Void.patternCF Random)**

Antes de `Strafe.tick` (L~344), agregar:
```lua
    -- FLING al void para baitear el resolver enemigo. ORIGIN alto + XYZ random + rot random, clamp Y≥30
    -- (NUNCA al vacío que mata). dist grande = ghost lejano. Reusa el rng brng.
    local VORIGIN = Vector3.new(0, 100, 0)
    local function voidBaitCF(dist)
        dist = dist or 5000
        local off = Vector3.new(rndS() * dist, rnd() * dist * 0.5, rndS() * dist)
        local pos = VORIGIN + off
        if pos.Y < 30 then pos = Vector3.new(pos.X, 30 + math.abs(pos.Y), pos.Z) end
        return CFrame.new(pos) * CFrame.Angles(rnd() * 6.2831, rnd() * 6.2831, rnd() * 6.2831)
    end
    -- FSM del ciclo: CHASE (orbita) aroundTime ↔ BAIT (void) voidTime. Presets setean los timers.
    local function cycleStep()
        local now = os.clock()
        local preset = O("BaitPreset") or "Timed"
        local aT, vT
        if preset == "Micro" then
            local ping = 0.1; pcall(function() ping = LP:GetNetworkPing() end)
            aT, vT = ping + 0.02, O("VoidTime") or 0.5
        elseif preset == "Spam" then aT, vT = 0.06, 0.11
        else aT, vT = O("AroundTime") or 3.0, O("VoidTime") or 1.0 end   -- Timed
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

- [ ] **Step 2: Integrar el ciclo en `Strafe.tick`**

En `Strafe.tick` (L345), después de calcular `center` (L352-358) y ANTES de `local goCF = orbitCF(...)` (L360), insertar:
```lua
        -- CICLO DINÁMICO: si DynStrafe ON, alterna CHASE (orbita) / BAIT (void). En BAIT el goCF va al void.
        local phase = "chase"
        if T("DynStrafe") then phase = cycleStep() else LIP.strafePhase = "chase" end
```
Luego cambiar la línea `local goCF = orbitCF(center, tRoot.CFrame.LookVector, opts)` (L360) por:
```lua
        local goCF
        if phase == "bait" then
            goCF = voidBaitCF(opts.radius and (opts.radius * 500) or 5000)
        else
            goCF = orbitCF(center, tRoot.CFrame.LookVector, opts)
        end
```
(El resto de tick — bait viejo, connExploit, posSpoof, directo — queda igual y aplica `goCF`.)

- [ ] **Step 3: Rebuild + verify estructural** — 0 SyntaxErrors.

- [ ] **Step 4: Verify MCP (fases alternan por timer)**
```lua
local LIP=getgenv().LIP
LIP.Library.Toggles.DynStrafe:SetValue(true)
LIP.Library.Options.BaitPreset:SetValue("Spam")   -- 0.06/0.11 rápido
local S=LIP.require("Combat.Strafe")
-- forzar cycleStep manual no accesible; observar LIP.strafePhase mientras un strafe corre (necesita target).
-- Sin target, validar que DynStrafe existe + no rompe:
return { dyn=LIP.Library.Toggles.DynStrafe.Value, phase=LIP.strafePhase }
```
Expected: `dyn=true`; `phase` = nil o "chase" (sin target el ciclo no corrió aún). Validación completa de alternancia = Task 8 con target.

- [ ] **Step 5: Commit**
```bash
git add Combat/Strafe.lua && git commit -m "feat(strafe): ciclo dinamico CHASE<->BAIT + void bait fling"
```

---

### Task 5: Auto-best-mode

**Files:** Modify `Combat/Strafe.lua` (orbitCF L276-299, cycleStep de T4, Strafe.tick)

**Interfaces:**
- Consumes: `resState` (T2), `LIP.strafeCycleNew` (T4).
- Produces: `pickBestMode(dist, tvel, spoof) -> string`; `LIP.strafeMode`.

- [ ] **Step 1: `pickBestMode`**

Antes de `cycleStep` (T4), agregar:
```lua
    -- AUTO-BEST-MODE (innovación): elige el modo de strafe según contexto, al entrar a CHASE. Histéresis: se
    -- guarda en LIP.strafeMode y solo cambia en el borde del ciclo (LIP.strafeCycleNew).
    local function pickBestMode(dist, tvel, spoof)
        if spoof > (O("AutoSpoofThresh") or 0.40) then return "Spiral" end
        if tvel  > (O("AutoFastThresh")  or 40)   then return "Behind" end
        if dist  > (O("AutoFarThresh")   or 60)   then return "Normal" end
        return "Random"
    end
```

- [ ] **Step 2: Elegir modo al entrar a CHASE (en Strafe.tick)**

En `Strafe.tick`, justo después del bloque del ciclo (T4 Step 2), agregar:
```lua
        -- AUTO-MODE: al iniciar un CHASE nuevo, re-elegir el mejor modo desde el contexto resuelto.
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
(`beh` y `resState` son upvalues accesibles dentro de Strafe.tick.)

- [ ] **Step 3: `orbitCF` respeta `LIP.strafeMode`**

En `orbitCF(center, tLook, opts)` (L276-299), cambiar la primera línea de resolución del modo:
`local mode = opts.mode or "Normal"` →
```lua
        local mode = (T("AutoMode") and LIP.strafeMode) or opts.mode or "Normal"
```
(Igual en `weldOrbitOffset` L326 y `offsetVec` L305 para que el connection weld también siga el auto-mode: cambiar sus `local mode = opts.mode or "Normal"` por `local mode = (T("AutoMode") and LIP.strafeMode) or opts.mode or "Normal"`.)

- [ ] **Step 4: Rebuild + verify estructural** — 0 SyntaxErrors.

- [ ] **Step 5: Verify MCP (pickBestMode por contexto)**

`pickBestMode` es local; validar vía el efecto: setear AutoMode + spoof alto sintético no es trivial sin target. Validar que AutoMode existe + no rompe, y testear la lógica con un probe que replica la fórmula:
```lua
local O=getgenv().LIP.Library.Options
local function pick(dist,tvel,spoof)
  if spoof>0.40 then return "Spiral" end
  if tvel>40 then return "Behind" end
  if dist>60 then return "Normal" end
  return "Random" end
return { far=pick(80,0,0), fast=pick(10,60,0), spoofing=pick(10,0,0.6), close=pick(10,0,0) }
```
Expected: `far="Normal"`, `fast="Behind"`, `spoofing="Spiral"`, `close="Random"`.

- [ ] **Step 6: Commit**
```bash
git add Combat/Strafe.lua && git commit -m "feat(strafe): auto-best-mode (Spiral/Behind/Normal/Random por dist/vel/spoof)"
```

---

### Task 6: Fire gate en bait

**Files:** Modify `Combat/Weapon.lua` (`tickAuto`)

**Interfaces:**
- Consumes: `LIP.strafePhase` (T4).

- [ ] **Step 1: Suprimir fire en fase bait**

En `Combat/Weapon.lua`, al inicio de `Weapon.tickAuto` (tras el early-return de AutoFire off), agregar:
```lua
        if LIP.strafePhase == "bait" then return end   -- en void tu origin no registra → no quemar balas
```
(Ubicarlo después del check de `T("AutoFire")` y antes del range gate / didDefensive.)

- [ ] **Step 2: Rebuild + verify estructural** — 0 SyntaxErrors.

- [ ] **Step 3: Verify MCP**
```lua
local LIP=getgenv().LIP
LIP.strafePhase="bait"
-- tickAuto es interno del driver; validar que el flag existe y el gate no rompe el reload:
return { phase=LIP.strafePhase }
```
Expected: `phase="bait"`. (Supresión real de fire = Task 8 con target.)

- [ ] **Step 4: Commit**
```bash
git add Combat/Weapon.lua && git commit -m "feat(autofire): suprimir disparo en fase bait (origin en void no registra)"
```

---

### Task 7: UI — Section "Resolver" en sidebar de Rage

**Files:** Modify `UI.lua` (panel rp L37-72 → migrar; agregar Section tras la section "Rage")

**Interfaces:**
- Consumes: `Strafe.RParams`, `Strafe.DEN` (para callbacks).
- Produces: flags `ResolverMethod`(Cluster/Density/Auto), `DenForgiveness/DenOutBonus/DenMinMatches/DenWindow/DenDistPenalty`, `DynStrafe/BaitPreset/AroundTime/VoidTime/AutoMode/AutoSpoofThresh/AutoFastThresh/AutoFarThresh`.

- [ ] **Step 1: Eliminar el panel `rp` viejo de la section "Rage"**

Borrar el bloque `local rp = RS:AddPanel("Resolver", ...)` completo (L37-72 + los RR* sliders que siguen hasta donde cierran, ~L71). Guardar el toggle `Resolver` (Spam Resolver) — se recrea en la nueva Section.

- [ ] **Step 2: Crear la Section "Resolver" (tras cerrar la section "Rage")**

Buscar dónde termina la section "Rage" (después del último panel de esa section) y agregar:
```lua
        --========================= RESOLVER (sidebar de Rage) =========================--
        local Res = Rage:AddSection("Resolver", "Cluster · Density · Dynamic Strafe", { Columns = 2 })
        local rm = Res:AddPanel("Método", { Column = 1 })
        rm:AddToggle("Resolver", { Text = "Spam Resolver", Default = false,
            Tooltip = "Resuelve el centro REAL del target (el strafe orbita ahí, no su jitter)" })
        rm:AddDropdown("ResolverMethod", { Text = "Method", Values = { "Cluster", "Density", "Auto" }, Default = "Cluster",
            Tooltip = "Cluster = histograma (juju). Density = vecindad batch (sakura, anti-alternador + far). Auto = elige según el target." })
        rm:AddSlider("ResolverReject", { Text = "Reject Vel", Min = 50, Max = 1000, Default = 300, Suffix = "st/s" })
        rm:AddSlider("ResolverPredict", { Text = "Predict", Min = 0, Max = 0.4, Default = 0.12, Decimals = 2, Suffix = "s" })
        rm:AddSlider("ResolverRate", { Text = "Resolver Rate", Min = 0, Max = 0.1, Default = 0.037, Decimals = 4, Suffix = "s" })
        rm:AddDropdown("PredMode", { Text = "Prediction", Values = { "Auto", "Manual" }, Default = "Auto" })
        rm:AddSlider("PredLead", { Text = "Pred Lead", Min = 0, Max = 0.4, Default = 0.12, Decimals = 2, Suffix = "s" })
        rm:AddToggle("FireResolved", { Text = "Fire on Resolved", Default = false,
            Tooltip = "Autofire dispara a la pos RESUELTA (didDefensive). RIESGO HBE. OFF = HBE-safe." })
        rm:AddToggle("ResolvedTracer", { Text = "Resolved Tracer", Default = false })
            :AddColorPicker("ResolvedTracerColor", { Default = Color3.fromRGB(255, 120, 120) })

        local RParams = Strafe.RParams; local DEN = Strafe.DEN
        rm:AddLabel("Cluster", { Header = true })
        rm:AddSlider("RRPosWeight", { Text = "Position Trust", Min = 0.1, Max = 5, Default = 1.5, Decimals = 2, Callback = function(v) if RParams then RParams.posWeight = v end end })
        rm:AddSlider("RRVoidWeight", { Text = "Void Trust", Min = 0.1, Max = 5, Default = 0.2, Decimals = 2, Callback = function(v) if RParams then RParams.voidWeight = v end end })
        rm:AddSlider("RRForget", { Text = "Forget Rate", Min = 0, Max = 1000, Default = 80, Suffix = "%", Callback = function(v) if RParams then RParams.forget = v end end })
        rm:AddSlider("RRDistPenalty", { Text = "Distance Penalty", Min = 0, Max = 5, Default = 2, Decimals = 1, Suffix = "x", Callback = function(v) if RParams then RParams.distPenalty = v end end })
        rm:AddSlider("RRAccuracy", { Text = "Accuracy", Min = 0.4, Max = 3, Default = 1.35, Decimals = 2, Callback = function(v) if RParams then RParams.accuracy = v end end })
        rm:AddSlider("RRLerp", { Text = "Lerp", Min = 0.1, Max = 1, Default = 0.1, Decimals = 2, Callback = function(v) if RParams then RParams.lerp = v end end })
        rm:AddLabel("Density", { Header = true })
        rm:AddSlider("DenForgiveness", { Text = "Forgiveness", Min = 2, Max = 60, Default = 14.4, Decimals = 1, Suffix = "st", Callback = function(v) if DEN then DEN.forgiveness = v end end })
        rm:AddSlider("DenOutBonus", { Text = "Out-of-Void Bonus", Min = 0, Max = 40, Default = 13, Decimals = 1, Suffix = "st", Callback = function(v) if DEN then DEN.outOfVoidBonus = v end end })
        rm:AddSlider("DenDistPenalty", { Text = "Distance Penalty", Min = 0, Max = 8, Default = 3.2, Decimals = 1, Suffix = "x", Callback = function(v) if DEN then DEN.distPenalty = v end end })
        rm:AddSlider("DenMinMatches", { Text = "Min Matches", Min = 2, Max = 10, Default = 3, Callback = function(v) if DEN then DEN.minMatches = math.floor(v) end end })
        rm:AddSlider("DenWindow", { Text = "Window", Min = 0.5, Max = 5, Default = 3, Decimals = 1, Suffix = "s", Callback = function(v) if DEN then DEN.window = v end end })

        local dyn = Res:AddPanel("Dynamic Strafe", { Column = 2 })
        dyn:AddToggle("DynStrafe", { Text = "Dynamic Cycle", Default = false,
            Tooltip = "Ciclo CHASE (orbita la resuelta) ↔ BAIT (fling al void). Baitea el resolver enemigo." })
        dyn:AddDropdown("BaitPreset", { Text = "Bait Preset", Values = { "Timed", "Micro", "Spam" }, Default = "Timed",
            Tooltip = "Timed = around 3s/void 1s. Micro = around ping+0.02/void corto. Spam = 0.06/0.11 rápido." })
        dyn:AddSlider("AroundTime", { Text = "Chase Time", Min = 0.05, Max = 10, Default = 3, Decimals = 2, Suffix = "s" })
        dyn:AddSlider("VoidTime", { Text = "Bait Time", Min = 0.05, Max = 12, Default = 1, Decimals = 2, Suffix = "s" })
        dyn:AddToggle("AutoMode", { Text = "Auto Best-Mode", Default = false,
            Tooltip = "Elige Spiral/Behind/Normal/Random según distancia/velocidad/spoof del target, al entrar a CHASE." })
        dyn:AddSlider("AutoSpoofThresh", { Text = "Spoof→Spiral", Min = 0, Max = 1, Default = 0.40, Decimals = 2 })
        dyn:AddSlider("AutoFastThresh", { Text = "Fast→Behind", Min = 5, Max = 150, Default = 40, Suffix = "st/s" })
        dyn:AddSlider("AutoFarThresh", { Text = "Far→Normal", Min = 10, Max = 200, Default = 60, Suffix = "st" })
```
(Quitar el flag `ResolverSamples` — ya no se usa tras sacar los métodos legacy. Verificar que nada más lo lea; `resolvePos` ya no lo usa tras T2.)

- [ ] **Step 3: Rebuild + verify estructural** — 0 SyntaxErrors.

- [ ] **Step 4: Verify MCP (toggles/options existen)**
```lua
local L=getgenv().LIP.Library
local function has(t,k) return t[k]~=nil end
return {
  method = has(L.Options,"ResolverMethod"), den = has(L.Options,"DenForgiveness"),
  dyn = has(L.Toggles,"DynStrafe"), preset = has(L.Options,"BaitPreset"),
  auto = has(L.Toggles,"AutoMode"), fireR = has(L.Toggles,"FireResolved"),
  vals = table.concat(L.Options.ResolverMethod.Values or {}, ",")
}
```
Expected: todos `true`; `vals="Cluster,Density,Auto"`.

- [ ] **Step 5: Commit**
```bash
git add UI.lua && git commit -m "feat(ui): Section Resolver en sidebar de Rage (metodo Density/Auto + Dynamic Strafe)"
```

---

### Task 8: Rebuild + gist + verificación live completa

**Files:** none (deploy + verify)

- [ ] **Step 1: Rebuild final + gist**
```
PowerShell: & "C:\Users\trabajo\.claude\jobs\be669aee\tmp\build_bundle.ps1"
gh gist edit 1552e7e4cb41aee0d826f644689838e2 -f LifeInPrisonPrimordial.lua "Scripts/LifeInPrisonPrimordial/LifeInPrisonPrimordial.lua"
gh api gists/<id> --jq '.files[...].raw_url'   # hashed
```

- [ ] **Step 2: Reload + smoke (0 errores de carga)**

Reload la raw hasheada en cliente. `get-console-output filter=LIP-RELOAD` → OK.

- [ ] **Step 3: Verify live (con target si hay, si no synthetic)**

Con un enemigo/alt presente: setear Resolver ON + Method Auto + DynStrafe ON + AutoMode ON + TargetStrafe. Probes:
- `resolverInfo(target).method` cambia Cluster↔Density según que el target camine o alterne void.
- `LIP.strafePhase` alterna "chase"↔"bait" por los timers.
- En "bait" no dispara (contador de op14 no sube).
- `resolvedPeek(target)` y el tracer apuntan a la pos resuelta (dist ~real).
Sin target: los probes estructurales de T2-T7 (todos verdes) + el usuario testea live con alt.

- [ ] **Step 4: Commit final si hubo ajustes** + actualizar memoria [[lifeinprisonprimordial]] con resolver v3.

---

## Self-Review
- **Spec coverage:** A(Density)→T1; A(Auto+ruteo)→T2; A(peek/info)→T3; B(ciclo chase/bait)→T4; B(auto-mode)→T5; B(fire gate)→T6; C(Section)→T7; deploy→T8. Cubierto.
- **Placeholders:** el código es real; las verificaciones funcionales que requieren target vivo están marcadas explícito (Density feed / phase alternation) y se cierran en T8 con alt — no son placeholders de diseño sino límites del entorno (1 cliente sin enemigos).
- **Type consistency:** `resolveByMethod(plr,rawPos,localPos)->pos,didDef`; `resState[plr]={pos,didDef,method,score,clusters,state,frameT}`; `resolveCluster` ahora devuelve `pos,didDef,score,count`; `resolverInfo->{score,state,clusters,method}`; `LIP.strafePhase`/`LIP.strafeMode`/`LIP.strafeCycleNew`; `pickBestMode(dist,tvel,spoof)`. Consistente entre tasks.
- **Riesgo residual:** validación funcional de Density/ciclo/fire-gate necesita target vivo (T8/usuario); estructural (luau-lsp) cubre sintaxis en cada task.
