# Port cluster resolver → symbol.lua + tracer resuelto — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement task-by-task. Steps use checkbox (`- [ ]`).

**Goal:** Reemplazar el RSV v2 de symbol.lua por el cluster histograma (juju/LiP), silent aim con Fire on Resolved, y un tracer a la pos resuelta en symbol.lua + LiP.

**Architecture:** Swap del motor RSV (L830-1309) manteniendo firmas `GetResolvedPosition/RSV_AimPos/CalculateConfidence` + campos de `RSV_State`. Silent aim lee la resuelta (L2515). Tracer Drawing.Line centro→resuelta.

**Tech Stack:** Luau, LinoriaLib (symbol) / PrimordialUI (LiP). symbol.lua = archivo único (sin build). LiP = bundle + gist.

## Global Constraints
- Params cluster (iguales a LiP): posWeight 1.5, voidWeight 0.2, forget 80 (decay/s = /20; outliers ×2.5), accuracy 1.35, lerp 0.1 (×3 cap 0.6 si no-void), distPenalty 2.0, resolverRate 0.037, prediction Auto = ping·2, weight clamp −1..18, score = weight·clamp(count·0.25,1,3), void = magnitud ≥9e5, merge = clamp(200−dist·0.4, 80, 200).
- symbol.lua: MANTENER firmas públicas + poblar TODOS los campos de RSV_State que los 9 call sites leen (.conf 0-100, .clusters, .best{.lastPos,.lastSeen}, .spamming, .desync, .teleporting, .model, .flash* stub, .rigOffY) → no romper nil.
- symbol.lua no tiene build ni git repo → editar directo; verificación = Lua Language Server sin errores de sintaxis + revisar los 9 call sites. Live = usuario en otros juegos.
- LiP: rebuild `build_bundle.ps1` + gist `1552e7e4cb41aee0d826f644689838e2`.
- Sin unit tests locales.

## File Structure
- Modify `Scripts/symbol.lua`: RSV block L830-1309 (motor), silent aim L2515, UI L2821+/2993+, tracer L2100/~3897/4410.
- Modify `LifeInPrisonPrimordial/Movement/Void.lua` (tracer render) + `UI.lua` (toggle+colorpicker) + rebuild.

---

### Task 1: symbol.lua — cluster histograma en RSV_Sample + estado

**Files:** Modify `Scripts/symbol.lua` (RSV_Sample L1023-1204; RSV_State L998-1021)

**Interfaces:**
- Produces: `RSV_State(name)` con `.hist = { list={...}, lastPos, lastT }` + campos telemetría. `RSV_Sample(player, partOverride)` alimenta el histograma.

- [ ] **Step 1: Agregar los params del cluster + config**

Cerca del bloque RSV config (L850-860), agregar:
```lua
RSV.CL = { posWeight = 1.5, voidWeight = 0.2, forget = 80, distPenalty = 2.0, accuracy = 1.35, lerp = 0.1 }
```

- [ ] **Step 2: Reemplazar el cuerpo de `RSV_Sample` por el ingest del histograma**

Leer el `RSV_Sample(player, partOverride)` actual (L1023-1204). Reemplazar su cuerpo por: obtener la pos del hitbox (part override o Head/HRP), y correr el ingest del cluster (idéntico a `resolveCluster` de LiP `Combat/Strafe.lua`, adaptado a `st.hist`):
```lua
local function RSV_Sample(player, partOverride)
    local st = RSV_State(player.Name)
    local char = player.Character; if not char then return end
    local part = partOverride or char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
    if not part then return end
    local hitbox = part.Position
    local now = clock()
    local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    local localPos = myRoot and myRoot.Position or hitbox
    local RP = RSV.CL
    local h = st.hist; if not h then h = { list = {} }; st.hist = h end
    local dist = (localPos - hitbox).Magnitude
    local distPenalty = math.clamp(1 - (dist/100) * (RP.distPenalty*0.01), 0.25, 1)
    local mergeR = math.clamp(200 - dist*0.4, 80, 200)
    local rate = RP.forget / 20
    local speed = 0
    if h.lastPos and h.lastT and (now - h.lastT) > 0 then speed = (hitbox - h.lastPos).Magnitude / (now - h.lastT) end
    h.lastPos = hitbox; h.lastT = now
    local isVoid = hitbox.Magnitude >= 9e5
    local lerpAmt = (isVoid or speed > 150) and RP.lerp or math.clamp(RP.lerp*3, RP.lerp, 0.6)
    local keep = {}
    for _, c in ipairs(h.list) do
        local dt = now - c.last
        if dt > 0 then
            local dm = (c.pos - hitbox).Magnitude > mergeR and 2.5 or 1
            c.weight = c.weight - dt*rate*dm; c.last = now
        end
        if c.weight >= 0.1 then keep[#keep+1] = c end
    end
    h.list = keep
    local addW = (isVoid and RP.voidWeight or RP.posWeight) * distPenalty
    local merged = false
    for _, c in ipairs(h.list) do
        if (c.pos - hitbox).Magnitude <= mergeR then
            c.pos = c.pos:Lerp(hitbox, lerpAmt); c.weight = math.clamp(c.weight + addW, -1, 18); c.count = c.count + 1; c.last = now; merged = true; break
        end
    end
    if not merged then h.list[#h.list+1] = { pos = hitbox, weight = addW, count = 1, last = now } end
    -- winner + telemetría
    local best, bestScore = nil, 0
    for _, c in ipairs(h.list) do
        local s = c.weight * math.clamp(c.count*0.25, 1, 3)
        if s > bestScore then bestScore = s; best = c end
    end
    st.clusters = #h.list
    st.bestScore = bestScore
    st.conf = math.clamp(bestScore / (RP.accuracy * 2), 0, 1) * 100        -- 0-100 (gate = 50)
    st.didDefensive = (best ~= nil and bestScore > RP.accuracy)
    st.best = best and { lastPos = best.pos, lastSeen = best.last } or st.best
    st.model = "cluster"
    st.spamming = #h.list >= 3
    st.teleporting = isVoid
    st.desync = isVoid and (hitbox - (best and best.pos or hitbox)) or Vector3.zero
    st.rigOffY = st.rigOffY or 0
    st.flashStarts = st.flashStarts or {}; st.flashPeriod = nil; st.flashLastT = st.flashLastT or 0   -- stub
end
```
(Nota: usar los nombres reales del script para clock/LocalPlayer/RSV_State — leerlos del archivo. `math.clamp` existe en Luau.)

- [ ] **Step 3: Asegurar los defaults de RSV_State**

En `RSV_State(name)` (L998-1021), agregar al init de la tabla: `hist = nil, conf = 0, clusters = 0, bestScore = 0, didDefensive = false` (los demás campos ya existen). No romper los existentes.

- [ ] **Step 4: Verify (estructural)**

Lua Language Server: sin errores de sintaxis en RSV_Sample/RSV_State. Confirmar que `st.conf/.clusters/.best/.spamming/.desync/.teleporting/.model/.flash*` se setean.

- [ ] **Step 5: Commit** (symbol.lua no versionado; commitear vía el repo LiP si se trackea, o snapshot manual)
```bash
cp "Scripts/symbol.lua" "Scripts/symbol.lua.bak-$(date +%s 2>/dev/null || echo prev)" 2>/dev/null || true
```

---

### Task 2: symbol.lua — RSV_AimPos + GetResolvedPosition + CalculateConfidence

**Files:** Modify `Scripts/symbol.lua` (RSV_AimPos L1210-1247; GetResolvedPosition L1249; CalculateConfidence L1255)

**Interfaces:**
- Consumes: `RSV_State(name).hist/.best/.conf`.
- Produces: `RSV_AimPos(player, pingMs) -> Vector3 pos, number conf(0-100)`; `GetResolvedPosition` y `CalculateConfidence` sin cambio de firma.

- [ ] **Step 1: Reescribir `RSV_AimPos`**

Leer el body actual (L1210-1247). Reemplazar por: pos = cluster ganador (o head crudo si no cruza gate) + prediction ping-lead + el floor del kill-plane existente:
```lua
local function RSV_AimPos(player, pingMs)
    local st = RSV_State(player.Name)
    local char = player.Character
    local part = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
    if not part then return nil, 0 end
    local raw = part.Position
    local pos = (st.didDefensive and st.best and st.best.lastPos) or raw
    -- prediction lead (ping-based auto o manual)
    local now = clock()
    local v = st._vel or Vector3.zero
    if st._velLastT and (now - st._velLastT) > (Opt('ResolverRate', 0.037)) then
        v = (pos - (st._velLastPos or pos)) / math.max(now - st._velLastT, 1e-3)
        if v.Magnitude > 200 then v = Vector3.zero end
        st._vel = v; st._velLastPos = pos; st._velLastT = now
    elseif not st._velLastT then st._velLastPos = pos; st._velLastT = now end
    local lead = (Opt('PredMode', 'Auto') == 'Auto') and ((pingMs or 0)/1000 * 2) or Opt('PredLead', 0.12)
    pos = pos + v * lead
    -- floor del kill-plane (conservar el clamp existente: KILL_Y + OutOfVoidBonus)
    if KILL_Y then local safeFloor = KILL_Y + math.max(Opt('OutOfVoidBonus', 2), 2); if pos.Y < safeFloor then pos = Vector3.new(pos.X, safeFloor, pos.Z) end end
    return pos, st.conf or 0
end
```
(Leer los nombres reales de `KILL_Y`/`Opt` del script. Si `KILL_Y` no existe con ese nombre, usar el que use el script para el floor.)

- [ ] **Step 2: `GetResolvedPosition` — sin cambios de lógica**

Confirmar que `GetResolvedPosition(target)` (L1249) sigue llamando `RSV_AimPos` y devolviendo la pos. Si tenía lógica extra, conservarla.

- [ ] **Step 3: `CalculateConfidence` — sin cambios de firma**

`CalculateConfidence(target)` (L1255) devuelve `RSV_State(target.Name).conf` (ya 0-100 del Task 1). Sin cambio si ya lee `.conf`.

- [ ] **Step 4: Verify** — sin errores; `RSV_AimPos` devuelve (pos, conf), el gate L3760 (`conf >= AutoFireMinConf`) sigue coherente (conf 0-100).

---

### Task 3: symbol.lua — remover el motor viejo + revisar call sites

**Files:** Modify `Scripts/symbol.lua` (RSV.FitQuad L865, FitCirc L893, EvalModel L927, BestModel L957, ClusterPlaus L977; RSV_PosAt L1274)

- [ ] **Step 1: Remover las funciones del motor multi-modelo**

Borrar `RSV.FitQuad/FitCirc/EvalModel/BestModel/ClusterPlaus` (ya no se usan tras Task 2). Conservar `RSV.TorsoHrpOffY`, `RSV.WeldAnchorPart`, `RSV_Clear`, `GetActivePing`.

- [ ] **Step 2: `RSV_PosAt` (backtrack) — stub o derivar**

`RSV_PosAt` (L1274) devolvía una pos histórica. Si algún call site lo usa, hacer que devuelva `st.best and st.best.lastPos or raw` (el cluster). Si no se usa afuera, borrar.

- [ ] **Step 3: Revisar los 9 call sites (no romper nil)**

Verificar que cada uno sigue funcionando con los campos nuevos:
- L2327 ESP label: lee `.conf/.spamming/.desync/.teleporting/.clusters/.model` → poblados ✓.
- L3680/3686 strafe center: `GetResolvedPosition` ✓.
- L3730 autofire gate: `CalculateConfidence` (conf 0-100) ✓.
- L3731 `rst` flash: `.flashStarts={}`/`.flashPeriod=nil` → el bloque flash (L3747-3768) no dispara → cae al gate de conf ✓.
- L3739 clientDist: `GetResolvedPosition` ✓.
- L2610+/2653 weld: `RSV.WeldAnchorPart/TorsoHrpOffY` ✓.
- L3898 ESP: `CalculateConfidence` ✓.

- [ ] **Step 4: Verify** — Lua Language Server sin `undefined field`/nil en los call sites.

---

### Task 4: symbol.lua — Fire on Resolved (silent aim)

**Files:** Modify `Scripts/symbol.lua` (L2515)

- [ ] **Step 1: Patch del cache del silent aim**

En L2508-2521 (`EnableSAMouseConn` RenderStepped), donde `_saCachedPos = p and p.Position`:
```lua
        local p = GetSATargetPart()
        local resolved = Tog('FireResolved') and GetResolvedPosition(CurrentTarget)
        _saCachedPos = resolved or (p and p.Position)
```
Mouse.Hit (L2505) y el `__namecall` hook (L4187-4217) heredan `_saCachedPos` sin más cambios.

- [ ] **Step 2: Verify** — con FireResolved OFF = comportamiento actual (raw part); ON = apunta a `GetResolvedPosition`.

---

### Task 5: symbol.lua — UI (sliders cluster + toggles)

**Files:** Modify `Scripts/symbol.lua` (ResolverGroup L2821-3013; SAGroup L2993)

- [ ] **Step 1: Sliders del cluster en ResolverGroup**

Después de los sliders existentes (~L2868), con el patrón LinoriaLib + `Callback` que actualiza `RSV.CL`:
```lua
ResolverGroup:AddSlider('RRPosWeight', { Text='Position Trust', Default=1.5, Min=0.1, Max=5, Rounding=2, Callback=function(v) RSV.CL.posWeight=v end })
ResolverGroup:AddSlider('RRVoidWeight', { Text='Void Trust', Default=0.2, Min=0.1, Max=5, Rounding=2, Callback=function(v) RSV.CL.voidWeight=v end })
ResolverGroup:AddSlider('RRForget', { Text='Forget Rate', Default=80, Min=0, Max=1000, Rounding=0, Suffix='%', Callback=function(v) RSV.CL.forget=v end })
ResolverGroup:AddSlider('RRAccuracy', { Text='Accuracy (gate)', Default=1.35, Min=0.4, Max=3, Rounding=2, Callback=function(v) RSV.CL.accuracy=v end })
ResolverGroup:AddSlider('RRLerp', { Text='Lerp', Default=0.1, Min=0.1, Max=1, Rounding=2, Callback=function(v) RSV.CL.lerp=v end })
ResolverGroup:AddSlider('RRDistPenalty', { Text='Distance Penalty', Default=2, Min=0, Max=5, Rounding=1, Callback=function(v) RSV.CL.distPenalty=v end })
ResolverGroup:AddSlider('ResolverRate', { Text='Resolver Rate', Default=0.037, Min=0, Max=0.1, Rounding=4, Suffix='s' })
ResolverGroup:AddDropdown('PredMode', { Text='Prediction', Values={'Auto','Manual'}, Default='Auto' })
ResolverGroup:AddSlider('PredLead', { Text='Pred Lead', Default=0.12, Min=0, Max=0.4, Rounding=2, Suffix='s' })
```

- [ ] **Step 2: Toggles FireResolved + ResolvedTracer en SAGroup**

Antes del `end` de L3013 (o en SAGroup ~L2993):
```lua
SAGroup:AddToggle('FireResolved', { Text='Fire on Resolved', Default=false, Tooltip='Silent aim apunta a la pos RESUELTA (no al part crudo).' })
SAGroup:AddToggle('ResolvedTracer', { Text='Resolved Tracer', Default=false }):AddColorPicker('ResolvedTracerColor', { Default=Color3.fromRGB(255,120,120) })
```

- [ ] **Step 3: Verify** — la UI carga sin error; los flags existen (`Tog('FireResolved')`, `Opt('RRPosWeight',...)`).

---

### Task 6: symbol.lua — tracer a la pos resuelta

**Files:** Modify `Scripts/symbol.lua` (~L2100 declaración; RenderStepped ESP ~L3897; cleanup L4410)

- [ ] **Step 1: Declarar el Drawing**

Cerca de `_dvTracer` (L2100):
```lua
local _resTracer = Drawing.new("Line"); _resTracer.Thickness = 1.5; _resTracer.Visible = false
```

- [ ] **Step 2: Update en el RenderStepped de ESP (~L3897)**

Dentro del loop de render:
```lua
if Tog('ResolvedTracer') and CurrentTarget and CurrentTarget.Character then
    local rp = GetResolvedPosition(CurrentTarget)
    local sp, on = rp and Camera:WorldToViewportPoint(rp)
    if on and sp.Z > 0 then
        local vp = Camera.ViewportSize
        _resTracer.From = Vector2.new(vp.X/2, vp.Y/2)
        _resTracer.To   = Vector2.new(sp.X, sp.Y)
        _resTracer.Color = Opt('ResolvedTracerColor', Color3.fromRGB(255,120,120))
        _resTracer.Visible = true
    else _resTracer.Visible = false end
else _resTracer.Visible = false end
```

- [ ] **Step 3: Cleanup** — agregar `_resTracer` al array de destrucción en L4410 (`:Remove()`).

- [ ] **Step 4: Verify** — sin errores; con ResolvedTracer ON + target, el tracer apunta al cluster ganador.

---

### Task 7: LiP — tracer a la pos resuelta

**Files:** Modify `LifeInPrisonPrimordial/Movement/Void.lua` (render) + `UI.lua` (toggle) + rebuild/gist

**Interfaces:** Consumes `Strafe.resolveAim(LIP.target, headPos)` o `LIP.cachedHitPos`.

- [ ] **Step 1: Toggle en UI (panel Resolver)**

En `UI.lua` panel `rp` (Resolver), agregar tras FireResolved:
```lua
        rp:AddToggle("ResolvedTracer", { Text = "Resolved Tracer", Default = false,
            Tooltip = "Tracer del centro de pantalla a la pos RESUELTA por el cluster." })
            :AddColorPicker("ResolvedTracerColor", { Default = Color3.fromRGB(255, 120, 120) })
```

- [ ] **Step 2: Render del tracer (reusar el patrón del viz del void)**

En `Movement/Void.lua`, en `Void.init` (o donde vive el render del viz), agregar un Drawing.Line + un RenderStepped que dibuje del centro a la pos resuelta:
```lua
    local resLine
    local function ensureResLine() if not resLine then resLine = Drawing.new("Line"); resLine.Thickness = 1.5 end end
    LIP.track(RunService.RenderStepped:Connect(function()
        pcall(function()
            local on = T("ResolvedTracer") and LIP.target and (T("Resolver"))
            if not on then if resLine then resLine.Visible = false end return end
            ensureResLine()
            local Strafe = LIP.require("Combat.Strafe")
            local ch = LIP.target.Character; local head = ch and ch:FindFirstChild("Head")
            local rp = head and Strafe.resolveAim(LIP.target, head.Position)
            local cam = Workspace.CurrentCamera
            local sp, vis = rp and cam:WorldToViewportPoint(rp)
            if vis and sp.Z > 0 then
                local vp = cam.ViewportSize
                resLine.From = Vector2.new(vp.X/2, vp.Y/2); resLine.To = Vector2.new(sp.X, sp.Y)
                resLine.Color = O("ResolvedTracerColor") or Color3.fromRGB(255,120,120); resLine.Visible = true
            else resLine.Visible = false end
        end)
    end))
    LIP.onCleanup(function() if resLine then pcall(function() resLine:Remove() end) end end)
```
(Usar `T`/`O`/`RunService`/`Workspace` que ya existen en Void.lua.)

- [ ] **Step 3: Rebuild + gist + verify MCP**

Rebuild. Push + gist. Reload pinned. Con Resolver + un target + ResolvedTracer ON: `get-data-by-code` confirma que existe un Drawing "Line" visible apuntando a `Strafe.resolveAim(target)`. Expected: tracer dibuja a la pos resuelta.

- [ ] **Step 4: Commit**
```bash
cd "C:/Users/trabajo/OneDrive/Escritorio/Scripts/LifeInPrisonPrimordial"
git add -A && git commit -m "feat(resolver): tracer a la pos resuelta (Drawing.Line centro->resuelta) + toggle"
```

---

## Self-Review
- **Spec coverage:** A(swap RSV: histograma+interface)→T1,T2,T3; B(Fire on Resolved)→T4; C(UI)→T5; D(tracer ambos)→T6(symbol),T7(LiP). Cubierto.
- **Placeholders:** el código nuevo es real; los `old_string` de los reemplazos se leen del archivo al ejecutar (symbol.lua bodies) — no son placeholders de diseño.
- **Type consistency:** `RSV_AimPos->pos,conf`; `.conf` 0-100 en todo; `st.best.lastPos/.lastSeen`; `RSV.CL` params; `Tog/Opt` LinoriaLib. Consistente.
- **Riesgo:** el swap de RSV_Sample/RSV_AimPos requiere leer los bodies exactos al ejecutar; revisar los 9 call sites (Task 3 Step 3) evita nil.
