# Resolver + Autofire Harmony (port juju.lol) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** El autofire de LiP dispara a la posición RESUELTA del target (histograma que resuelve void/desync), gateado por un único flag `didDefensive` (la harmonía juju), con prediction ping-lead y labels con más info.

**Architecture:** Extender el `resolveCluster` ya existente en `Combat/Strafe.lua` a un aim-resolver que devuelve `(pos, didDefensive)`, muestrea velocidad a `resolver_rate` y aplica prediction lead. `main.lua` `cacheHit` setea `cachedHitPos = resolvedPos` + `LIP.didDefensive` cuando `FireResolved` ON. `Weapon.tickAuto` dispara cuando `didDefensive` aunque el head esté en el void. HUD con state tags.

**Tech Stack:** Luau (Potassium executor), PrimordialUI (Lib.Toggles/Options). Testing vía roblox-executor-mcp. Build vía `build_bundle.ps1` + gist.

## Global Constraints

- Fire = op14 + GST REAL (no forjar). HBE-safe default: hitPos = centro del hitPart. `FireResolved` ON = disparo resuelto (riesgo HBE, aceptado, default OFF).
- `Math.random`/`os.time` random bloqueados → LCG. Ping = `LP:GetNetworkPing()` (SEGUNDOS).
- Params juju: posWeight 1.5, voidWeight 0.2, forget 80, accuracy 1.35, lerp 0.1, distPenalty 2.0, resolver_rate 0.037, prediction Auto = ping·2 (≡ ping_ms/500), weight clamp −1..18, score = weight·clamp(count·0.25,1,3), void = magnitud ≥9e5.
- El resolver ya vive en Strafe.lua (con `hist`/`sampleAll`); NO extraer a módulo aparte.
- Mantener el rate-limit al firerate (anti-unequip). La harmonía cambia DÓNDE + el gate, NO el timing anti-unequip.
- Verificación live = roblox-executor-mcp (set-active-client → execute/get-data-by-code). Live-fire real (daño/HBE) = usuario en burner.
- Rebuild tras cambios: `& "C:\Users\trabajo\.claude\jobs\be669aee\tmp\build_bundle.ps1"`; gist id `1552e7e4cb41aee0d826f644689838e2`.

---

### Task 1: UI — controles del resolver (ResolverRate, PredMode, PredLead, FireResolved)

**Files:**
- Modify: `UI.lua` (panel "Resolver", después de `ResolverPredict`)
- Verify: MCP (flags existen en Lib.Options/Toggles)

**Interfaces:**
- Produces: `Options.ResolverRate` (num), `Options.PredMode` (dropdown "Auto"/"Manual"), `Options.PredLead` (num), `Toggles.FireResolved` (bool).

- [ ] **Step 1: Agregar los controles al panel Resolver**

En `UI.lua`, en el panel `rp` (Resolver, Column 1), después de la línea `rp:AddSlider("ResolverPredict", ...)`:
```lua
        rp:AddSlider("ResolverRate", { Text = "Resolver Rate", Min = 0, Max = 0.1, Default = 0.037, Decimals = 4, Suffix = "s",
            Tooltip = "Intervalo de muestreo de velocidad (juju 0.037). Chico = fresco/ruidoso, grande = suave/laggy." })
        rp:AddDropdown("PredMode", { Text = "Prediction", Values = { "Auto", "Manual" }, Default = "Auto",
            Tooltip = "Auto = lead por ping (ping·2). Manual = usa Pred Lead." })
        rp:AddSlider("PredLead", { Text = "Pred Lead", Min = 0, Max = 0.4, Default = 0.12, Decimals = 2, Suffix = "s",
            Tooltip = "Lead manual (segundos de velocidad adelantada). Solo con Prediction = Manual." })
        rp:AddToggle("FireResolved", { Text = "Fire on Resolved", Default = false,
            Tooltip = "HARMONÍA: el autofire dispara a la pos RESUELTA (no al head crudo) cuando el resolver está confiado. RIESGO HBE (dispara fuera del hitbox del ghost). OFF = HBE-safe." })
```

- [ ] **Step 2: Rebuild + verify MCP**

Rebuild. En un cliente LiP con el bundle cargado: `get-data-by-code`: `local L=getgenv().LIP.Library; return L.Options.ResolverRate~=nil, L.Options.PredMode~=nil, L.Options.PredLead~=nil, L.Toggles.FireResolved~=nil`. Expected: los 4 true.

- [ ] **Step 3: Commit**

```bash
git add UI.lua LifeInPrisonPrimordial.lua
git commit -m "feat(resolver): UI controls (ResolverRate/PredMode/PredLead/FireResolved)"
```

---

### Task 2: Resolver aim — didDefensive + velocidad@resolver_rate + prediction lead

**Files:**
- Modify: `Combat/Strafe.lua` (`resolveCluster` return; nueva `Strafe.resolveAim`, `Strafe.resolvedVel`)
- Verify: MCP (resolveAim resuelve void → pos real, didDefensive)

**Interfaces:**
- Consumes: `resolveCluster` (interno), `O("ResolverRate")`, `O("PredMode")`, `O("PredLead")`.
- Produces: `Strafe.resolveAim(plr, rawHitboxPos) -> Vector3 pos, boolean didDefensive`; `Strafe.resolvedVel(plr, pos, now, rate) -> Vector3`.

- [ ] **Step 1: `resolveCluster` devuelve `(pos, didDefensive)`**

En `Combat/Strafe.lua`, cambiar el `return` final de `resolveCluster` (línea ~141):
```lua
        -- return: pos resuelta + didDefensive (el cluster ganador cruzó el gate de accuracy = fire-ready)
        local didDefensive = (best ~= nil and bestScore > RP.accuracy)
        return (didDefensive and best.pos) or hitbox, didDefensive
    end
```

- [ ] **Step 2: Ajustar `resolvePos` (que llama resolveCluster) para descartar el 2º valor en el strafe**

En `Strafe.resolvePos`, la rama Cluster (línea ~148):
```lua
        if method == "Cluster" then
            local r = myRoot(); local loc = r and r.Position or rawPos
            local p = resolveCluster(plr, rawPos, os.clock(), loc)   -- solo la pos para el orbit
            return p
        end
```

- [ ] **Step 3: Agregar `resolvedVel` (finite-diff rate-gated) + `resolveAim`**

Después de `resolveCluster` (antes de `Strafe.resolvePos`):
```lua
    -- velocidad muestreada a resolver_rate (por target) — finite-diff, no cada frame
    local velState = {}   -- [plr] = { lastPos, lastT, vel }
    function Strafe.resolvedVel(plr, pos, now, rate)
        local v = velState[plr]; if not v then v = { lastPos = pos, lastT = now, vel = Vector3.zero }; velState[plr] = v; return v.vel end
        if (now - v.lastT) > (rate or 0.037) then
            v.vel = (pos - v.lastPos) / math.max(now - v.lastT, 1e-3)
            v.lastPos = pos; v.lastT = now
        end
        return v.vel or Vector3.zero
    end
    -- AIM RESOLVER: pos resuelta + prediction lead + flag didDefensive (la harmonía). rawHitboxPos = head crudo.
    function Strafe.resolveAim(plr, rawHitboxPos)
        local now = os.clock()
        local r = myRoot(); local loc = r and r.Position or rawHitboxPos
        local pos, didDefensive = resolveCluster(plr, rawHitboxPos, now, loc)
        local rate = O("ResolverRate") or 0.037
        local vel = Strafe.resolvedVel(plr, rawHitboxPos, now, rate)
        local lead
        if (O("PredMode") or "Auto") == "Auto" then
            local ping = 0.1; pcall(function() ping = LP:GetNetworkPing() end)
            lead = ping * 2                       -- ≡ ping_ms/500 de juju (GetNetworkPing = segundos)
        else
            lead = O("PredLead") or 0.12
        end
        pos = pos + vel * lead
        return pos, didDefensive
    end
```
(Nota: `O` ya existe en Strafe.lua = `Lib.Options[f].Value`.)

- [ ] **Step 4: Rebuild + verify MCP (resolver resuelve void)**

Rebuild. Con un enemigo real de target (manual), simular void: `get-data-by-code` que llame `Strafe` (via require del bundle) — probar `Strafe.resolveAim(target, realHeadPos)` alimentando primero la pos REAL varios frames, luego una pos VOID (magnitud 9e5), y verificar que la pos devuelta sigue ≈ la real (el cluster real gana) y didDefensive=true tras acumular. Expected: resuelve a la pos real, ignora el void.

- [ ] **Step 5: Commit**

```bash
git add Combat/Strafe.lua LifeInPrisonPrimordial.lua
git commit -m "feat(resolver): resolveAim (didDefensive + vel@rate + prediction lead)"
```

---

### Task 3: cacheHit harmony — cachedHitPos = resolvedPos + LIP.didDefensive

**Files:**
- Modify: `main.lua` (`cacheHit`)
- Verify: MCP (cachedHitPos = resolved cuando FireResolved+didDefensive)

**Interfaces:**
- Consumes: `Strafe.resolveAim`, `T("Resolver")`, `T("FireResolved")`.
- Produces: `LIP.cachedHitPos` (resolved o crudo), `LIP.didDefensive` (bool).

- [ ] **Step 1: Inyectar la harmonía en `cacheHit`**

En `main.lua` `cacheHit`, donde setea `LIP.cachedHitPos = base` (línea ~71), reemplazar por:
```lua
            -- HARMONÍA: con Resolver + Fire on Resolved, disparar a la pos RESUELTA (no al head crudo) cuando
            -- el resolver está confiado (didDefensive). Riesgo HBE aceptado. Si no → head crudo (HBE-safe).
            local base = part.Position
            if (T.Resolver and T.Resolver.Value) and (T.FireResolved and T.FireResolved.Value) then
                local resolved, didDef = Strafe.resolveAim(t, base)
                if didDef then LIP.cachedHitPos = resolved; LIP.didDefensive = true
                else LIP.cachedHitPos = base; LIP.didDefensive = false end
            else
                LIP.cachedHitPos = base; LIP.didDefensive = false
            end
```
(El `local base = part.Position` de la línea siguiente original se elimina — ya está acá.)

- [ ] **Step 2: Limpiar didDefensive cuando no hay target**

Donde `cacheHit` no aplica (`LIP.cachedHitPart, LIP.cachedHitPos = nil, nil` en main ~152 y ~164), agregar `LIP.didDefensive = false` en cada uno.

- [ ] **Step 3: Rebuild + verify MCP**

Rebuild. Con Resolver+FireResolved ON, target void-spameando: `get-data-by-code`: leer `LIP.cachedHitPos` vs la pos VOID del target vs su pos REAL. Expected: `cachedHitPos` ≈ pos real (no la void), `LIP.didDefensive = true`. Con FireResolved OFF: `cachedHitPos` = head crudo, didDefensive=false.

- [ ] **Step 4: Commit**

```bash
git add main.lua LifeInPrisonPrimordial.lua
git commit -m "feat(resolver): cacheHit harmony (fire at resolved when didDefensive)"
```

---

### Task 4: Autofire gate — didDefensive desbloquea el disparo

**Files:**
- Modify: `Combat/Weapon.lua` (`tickAuto`: gate de rango + gate de hitPart)
- Verify: MCP (dispara con didDefensive aunque head lejos)

**Interfaces:**
- Consumes: `LIP.didDefensive`, `LIP.cachedHitPos`, `LIP.cachedHitPart`.

- [ ] **Step 1: El gate de rango se bypassa con didDefensive**

En `Weapon.tickAuto`, el gate de rango (la línea `if ref and (LIP.cachedHitPos - ref).Magnitude > (O("FireRange") or 200) then`), agregar el bypass:
```lua
        if autoOn and LIP.cachedHitPos and not LIP.didDefensive then   -- didDefensive = el resolver ya validó → no gatear por rango
            local h = char() and char():FindFirstChild("Head")
            local ref = ((LIP.spoofOn or LIP.connRep) and LIP.spoofFakePos)
                        or (LIP.wallbang and LIP.cachedOrigin) or (h and h.Position)
            if ref and (LIP.cachedHitPos - ref).Magnitude > (O("FireRange") or 200) then
                LIP.fireAccum = 0; lastTick = now; return
            end
        end
```
(Solo se agrega `and not LIP.didDefensive` a la condición del `if` externo.)

- [ ] **Step 2: Rebuild + verify MCP**

Rebuild. Con Resolver+AutoFire+FireResolved ON, target void (head lejos) pero resolver confiado: `get-data-by-code`: leer que el autofire NO se cortó por rango (`LIP.didDefensive=true` → dispara). Probar leyendo `LIP.shotsFired` incrementa. Non-destructive (sin daño real, o burner). Expected: dispara con didDefensive.

- [ ] **Step 3: Commit**

```bash
git add Combat/Weapon.lua LifeInPrisonPrimordial.lua
git commit -m "feat(resolver): autofire gate desbloqueado por didDefensive"
```

---

### Task 5: resolverInfo — telemetría para el HUD

**Files:**
- Modify: `Combat/Strafe.lua` (nueva `Strafe.resolverInfo`)
- Verify: MCP (tags correctos)

**Interfaces:**
- Produces: `Strafe.resolverInfo(plr) -> { score=number(0-1), state=string, clusters=number }`. state ∈ {LOCKED, RESOLVING, VOID, NORMAL}.

- [ ] **Step 1: Exponer `clusters[plr]` + agregar `resolverInfo`**

En `Combat/Strafe.lua`, después de `resolveCluster`:
```lua
    -- telemetría del resolver para el HUD (score normalizado + estado + nº de clusters)
    function Strafe.resolverInfo(plr)
        local t = clusters[plr]
        local n = t and #t.list or 0
        local best, bestScore = nil, 0
        if t then for _, c in ipairs(t.list) do
            local s = c.weight * math.clamp(c.count * 0.25, 1, 3)
            if s > bestScore then bestScore = s; best = c end
        end end
        local score = math.clamp(bestScore / (RP.accuracy * 2), 0, 1)   -- normalizado (accuracy = 0.5)
        local locked = best ~= nil and bestScore > RP.accuracy
        -- ¿el target está en el void ahora? (última muestra cruda lejos)
        local inVoid = t and t.lastPos and t.lastPos.Magnitude >= 9e5 or false
        local state = locked and "LOCKED" or (inVoid and "VOID") or (n > 0 and "RESOLVING") or "NORMAL"
        return { score = score, state = state, clusters = n }
    end
```

- [ ] **Step 2: Rebuild + verify MCP**

Rebuild. Con un target: `get-data-by-code` → `Strafe.resolverInfo(target)` → verificar `state`/`clusters`/`score` razonables (NORMAL con target quieto, VOID cuando spoofea, LOCKED cuando resuelto). Expected: tags correctos.

- [ ] **Step 3: Commit**

```bash
git add Combat/Strafe.lua LifeInPrisonPrimordial.lua
git commit -m "feat(resolver): resolverInfo (score/state/clusters) para el HUD"
```

---

### Task 6: HUD — labels con más info (state tags + clusters + HP) + rebuild final

**Files:**
- Modify: `Visuals/CrosshairHUD.lua` (activeLine base + Resolved)
- Verify: MCP (label renderiza los tags)

**Interfaces:**
- Consumes: `Strafe.resolverInfo`, `LIP.target`, `LIP.hudTargetName`.

- [ ] **Step 1: Enriquecer el label base**

En `Visuals/CrosshairHUD.lua`, en `activeLine()`, la rama base (`elseif LIP.hudTargetName then`), reemplazar por:
```lua
        elseif LIP.hudTargetName then
            local ri = (LIP.require and LIP.require("Combat.Strafe").resolverInfo(LIP.target)) or { score = LIP.hudResolved or 0, state = "NORMAL", clusters = 0 }
            local hp = 0
            local tc = LIP.target and LIP.target.Character
            local th = tc and tc:FindFirstChildOfClass("Humanoid")
            if th then hp = math.floor(th.Health) end
            return ("killing: %s | Resolved: %.3f | %s | clusters: %d | HP: %d"):format(
                LIP.hudTargetName, ri.score, ri.state, ri.clusters, hp)
        end
```
(Usa `LIP.require` — el bundle expone `LIP.require`; si el HUD no lo tiene, cachear `Strafe` en `CrossHUD.init` via `require("Combat.Strafe")`.)

- [ ] **Step 2: Cachear Strafe en init (evita require por frame)**

En `CrosshairHUD.lua` factory, arriba: `local Strafe`; en `CrossHUD.init()`: `pcall(function() Strafe = require("Combat.Strafe") end)`. Y en activeLine usar `Strafe and Strafe.resolverInfo(LIP.target)` en vez de `LIP.require(...)`.

- [ ] **Step 3: Rebuild + push + gist**

Rebuild. `git add -A && git commit`. Push + gist:
```bash
gh gist edit 1552e7e4cb41aee0d826f644689838e2 -f LifeInPrisonPrimordial.lua "$(pwd)/LifeInPrisonPrimordial.lua"
gh api gists/1552e7e4cb41aee0d826f644689838e2 --jq '.files["LifeInPrisonPrimordial.lua"].raw_url'
```

- [ ] **Step 4: Verify MCP (integración full)**

Reload pinned. Con Resolver+AutoFire+FireResolved ON + target: el HUD muestra `killing: user | Resolved: x.xyz | LOCKED/VOID/... | clusters: N | HP: NN`. `cachedHitPos` = resuelto. Expected: label rico + harmonía funcionando (verificación de daño = usuario en burner).

- [ ] **Step 5: Commit final**

```bash
git add -A
git commit -m "feat(resolver): HUD labels con state tags + clusters + HP; harmony integrada"
```

---

## Self-Review

- **Spec coverage:** A(arq: resolver en Strafe)→T2; B(resolveAim+didDefensive+vel@rate+prediction)→T2; C(cacheHit harmony+FireResolved)→T3; autofire gate→T4; D(void)→ya en resolveCluster; E(sin backtrack)→N/A; F(UI)→T1; 5(HUD labels+info)→T5,T6. Todo cubierto.
- **Placeholders:** ninguno; código real por step.
- **Type consistency:** `resolveAim(plr,pos)->pos,didDefensive` usado en T3; `resolverInfo(plr)->{score,state,clusters}` en T6; `LIP.didDefensive` seteado T3, leído T4; `resolvedVel` T2. Consistente.
- **Orden:** T1(UI flags) antes de T2/T3 que los leen. OK.
