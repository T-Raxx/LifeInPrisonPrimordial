# Resolver v3 (Density + Auto-método) + Target Strafe dinámico + Section propia — Diseño

Fecha: 2026-08-10 · Repo: `LifeInPrisonPrimordial` · Fuentes de estudio: `ResolverStudy/{sakura,jujudotlol}.lua` + `RESOLVERS-REFERENCE.md`

## Objetivo

Subir el resolver de LiP un nivel más: agregar el método **Density** (sakura / Unnamed Enhancements) junto al **Cluster** (juju, ya portado) + **Auto-método** que elige entre ambos según el comportamiento del target. Construir un **Target Strafe dinámico** de ciclo unificado (chase→bait→re-pick de modo on-the-fly) que compone el oscilador around↔void probado de los leaks con una FSM de auto-selección de modo (innovación nuestra). Mover todo el resolver a su propia **Section** en el sidebar de Rage.

## Reality-check del estudio (qué hacen los leaks de verdad)

- sakura y juju usan **el mismo cluster histograma que LiP ya tiene** (params idénticos: `dist_penalty`, `adaptive_lerp`, `merge_radius`). El único método que NO tenemos es el **Density batch** (sakura `artifical`): O(n²) sobre ventana, cuenta vecinos dentro de un radio chico, centroide del vecindario más denso; el radio **encoge con la distancia** = resolución a distancia.
- El "persiguen X seg → bait → cambian de modo" **no existe literal**: es un **oscilador around↔void por tiempo** (sakura Experimental 3s/10s, v2 ping+0.02/4s; juju random-spam 0.06/0.11s) con **modo fijo**. El auto-select de modo es innovación nuestra. El "chase" = fase around orbitando la pos resuelta (predicha). Backtrack (juju) queda **fuera** (no sirve en LiP).

## Arquitectura general

Tres piezas, todas dentro de `Combat/Strafe.lua` + UI:

```
Resolver v3 (Strafe.lua)          Dynamic Strafe (Strafe.lua)        UI (UI.lua)
 ├ resolveCluster (existe)         ├ Strafe.cycleStep (FSM nuevo)     └ Section "Resolver"
 ├ resolveDensity (NUEVO)          │   CHASE ↔ BAIT por timers            (sidebar de Rage)
 ├ pickMethod Auto  (NUEVO)        ├ pickBestMode (auto FSM, NUEVO)
 ├ resolveAim → ruta por método    ├ voidBaitCF (reusa Void ORIGIN)
 ├ resolvedPeek / resolverInfo     └ expone LIP.strafePhase
 └ contrato didDefensive/conf único
```

---

## A) Resolver v3

### A.1 Density (`resolveDensity`) — port de sakura `artifical`

Consume el log de muestras crudas por target (`hist[plr]` que ya llena `Strafe.sampleAll`; si no corre continuo con Resolver ON, se agrega un sampler liviano). Devuelve `(pos, didDefensive)` con el mismo contrato que Cluster.

```lua
-- Strafe.DEN = { forgiveness=14.4, outOfVoidBonus=13, distPenalty=3.2, minMatches=3, window=3.0, voidManhattan=7000 }
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
            local forg  = D.forgiveness + (inMap and D.outOfVoidBonus or 0)
            if localPos then forg = forg - ((localPos - p1).Magnitude / 100) * D.distPenalty end
            forg = math.clamp(forg, 1, 1000)
            local count, sum = 0, p1
            for j = 1, n do
                if i ~= j and (now - h.t[j] <= D.window) and (p1 - h.s[j]).Magnitude <= forg then
                    count = count + 1; sum = sum + h.s[j]
                end
            end
            if count >= D.minMatches and count > bestCount then
                bestCount = count; bestPos = sum / (count + 1)   -- centroide
            end
        end
    end
    local didDef = bestPos ~= nil and bestCount >= (D.minMatches + 1)
    return bestPos, didDef
end
```

- **Cap del log**: la ventana 3s a ~20Hz ≈ 60 muestras → O(60²)=3600 comparaciones/target, barato. Cap duro del log a 300 (como sakura) por si acaso.
- **conf para Density**: `conf = clamp((bestCount - minMatches) / 8, 0, 1) * 100` (más vecinos = más confianza). EMA igual que Cluster.

### A.2 Auto-método (`pickMethod`)

Cada `autoMethodRate` (~0.5s) por target, mide el comportamiento y elige:

```lua
-- por muestra en el sampler: contar void vs real + flips consecutivos (real↔void)
-- st.voidFrac = EMA de (isVoid ? 1 : 0);  st.flipRate = EMA de (isVoid != prevVoid ? 1 : 0)
-- decisión: alternador rápido → Density ; void irregular / caminando → Cluster
local function pickMethod(st)
    if st.voidFrac > 0.30 and st.voidFrac < 0.75 and st.flipRate > 0.35 then return "Density" end
    return "Cluster"
end
```

- Solo aplica cuando `ResolverMethod == "Auto"`. Con "Cluster"/"Density" explícito, se respeta el fijo.
- Histéresis: no cambiar de método más de 1 vez por ventana (evita flapping).

### A.3 Contrato unificado

`Strafe.resolveAim(plr, rawHitboxPos) -> pos, didDefensive` rutea por `ResolverMethod`:
- `"Cluster"` → `resolveCluster` (existe).
- `"Density"` → `resolveDensity`.
- `"Auto"` → `pickMethod(st)` y llama al elegido.
- Predicción (lead ping·2 / manual) + floor kill-plane se aplican DESPUÉS, igual que hoy, sobre el `pos` de cualquier método.
- `resolvedPeek(plr)` (lector puro para el tracer) y `resolverInfo(plr)` (telemetría HUD) reportan el método activo + su score/state.
- `Strafe.resolvePos(plr, rawPos, ...)` (pivote del orbit del strafe) rutea por el MISMO método (Cluster/Density/Auto) — se elimina el switch legacy Median/Weighted/Average/Latest (branches muertos tras sacarlos del dropdown). Un solo helper interno `resolveByMethod(plr, rawPos, localPos)` centraliza el ruteo y lo usan `resolveAim` y `resolvePos`.
- Fallback: si el método activo devuelve nil (sin resolver), cae a la última muestra cruda (comportamiento actual).

### A.4 Far-tuning

- Density: el shrink de `forgiveness` por distancia ya es el mecanismo far (portado).
- Cluster: `distPenalty` ya existe.
- No se agrega lead extra por distancia (ninguno de los leaks lo hace; el lead es por ping).

---

## B) Target Strafe dinámico — ciclo unificado

### B.1 FSM de ciclo (`Strafe.cycleStep`)

Estado en `LIP` (global, sobrevive reload): `LIP.strafePhase ∈ {"chase","bait"}`, `LIP.strafePhaseUntil`, `LIP.strafeMode` (modo elegido activo).

```
CHASE (aroundTime s): orbita la pos resuelta con LIP.strafeMode (pickBestMode al ENTRAR)
   └─ timer expira → BAIT
BAIT (voidTime s): staged CFrame = voidBaitCF() (fling al void)  → NO fire
   └─ timer expira → CHASE (re-pick mode)
```

- Se ejecuta dentro de `Strafe.tick`, ANTES de calcular `goCF`. Si `DynStrafe` OFF → comportamiento actual (sin ciclo, modo fijo del dropdown).
- **Presets de bait** (`BaitPreset` dropdown): `Timed` (around 3s / void 10s), `Micro` (around = ping+0.02, void 0.5s), `Spam` (around 0.06 / void 0.11s). Cada preset setea aroundTime/voidTime (los sliders los override si el usuario toca).
- `voidBaitCF()` reusa el generador de Void.lua (ORIGIN 0,100,0 + XYZ random alto, **clamp Y≥30** anti-killplane, rotación random). No cruza el kill plane (que mata).

### B.2 Auto-best-mode (`pickBestMode`) — innovación

Llamado al ENTRAR a CHASE (no per-frame → sin jitter). Inputs: `dist` (local→resuelta), `tvel` (magnitud vel resuelta), `spoof` (voidFrac / !didDefensive estable). Reglas en orden con histéresis (no cambiar si el nuevo == anterior por <1 ciclo):

```lua
local function pickBestMode(st, dist, tvel, spoof)
    if spoof > 0.40           then return "Spiral"  end   -- target spoofea fuerte → 3D impredecible
    if tvel  > 40             then return "Behind"  end   -- se mueve rápido → pegado a su espalda
    if dist  > 60             then return "Normal"  end   -- lejos → órbita ancha
    return "Random"                                        -- cerca+estático+resoluble → máx jitter
end
```

- Solo con `AutoMode` ON. OFF = usa el modo del dropdown `StrafeMode` fijo (comportamiento actual).
- Umbrales configurables (sliders): `AutoSpoofThresh` 0.40, `AutoFastThresh` 40, `AutoFarThresh` 60.
- (Opcional futuro) escalar radius con distancia; NO en esta versión (YAGNI).

### B.3 Integración con aplicación + fire

- Los 3 modos de aplicación (Pos Spoof / Connection Weld / directo) **no cambian**. El ciclo solo decide el `goCF` (órbita en CHASE, void en BAIT) que alimenta la aplicación existente.
- **Fire gate**: `main.lua` autofire chequea `LIP.strafePhase ~= "bait"` (en void tu origin no registra). En CHASE dispara por el gate normal (conf/didDefensive/harmony).
- Respeta `LIP.awGrabbing` (autograb pausa el ciclo, como hoy pausa el strafe).

---

## C) UI — Section "Resolver" en sidebar de Rage

`Rage` pasa de 1 a 2 Sections (sidebar izq): **"Rage"** (existente) + **"Resolver"** (nueva). En `UI.build`, tras la section actual:

```lua
local Res = Rage:AddSection("Resolver", "Cluster · Density · Dynamic Strafe", { Columns = 2 })
```

**Col 1 — Método + telemetría:**
- `ResolverMethod` dropdown: `Cluster / Density / Auto` (reemplaza el actual; se quitan Median/Weighted/Average/Latest legacy).
- Params Cluster (RR* existentes) + params Density (`DenForgiveness`, `DenOutBonus`, `DenMinMatches`, `DenWindow`, `DenDistPenalty`) + Auto (`AutoMethodRate`).
- `FireResolved` + `ResolvedTracer` + colorpicker (movidos desde el panel `rp` actual).
- Label telemetría: `método · state · score · clusters` (extiende `resolverInfo`).

**Col 2 — Dynamic Strafe:**
- `DynStrafe` toggle (ciclo chase↔bait).
- `BaitPreset` dropdown (Timed / Micro / Spam) + sliders `AroundTime` / `VoidTime`.
- `AutoMode` toggle + sliders `AutoSpoofThresh` / `AutoFastThresh` / `AutoFarThresh`.

El panel `rp` viejo en la section "Rage" se elimina; sus controles migran acá. El strafe base (StrafeMode/PosSpoof/ConnExploit/distancia/altura/velocidad) **queda en "Rage"** (el ciclo dinámico los usa como base).

---

## Archivos tocados

- `Combat/Strafe.lua`: `resolveDensity`, `pickMethod`, ruta en `resolveAim`, `resolvedPeek`/`resolverInfo` por método, `Strafe.DEN`, sampler de behavior (voidFrac/flipRate), `Strafe.cycleStep`, `pickBestMode`, `voidBaitCF`, expone `LIP.strafePhase`/`LIP.strafeMode`; `orbitCF`/`offsetVec`/`weldOrbitOffset` leen `LIP.strafeMode` cuando AutoMode ON.
- `UI.lua`: nueva Section "Resolver", migración de controles, dropdown de método actualizado, sliders Density/Auto/Dynamic.
- `main.lua`: fire gate `strafePhase ~= "bait"`.
- `Movement/Void.lua`: exportar el generador de void pos (`Void.baitCF()`) para reuso del ciclo (o replicar la fórmula en Strafe).
- Rebuild bundle + gist.

## Testing

- **Estructural**: `luau-lsp analyze` → 0 SyntaxErrors en el bundle.
- **MCP live** (cliente LiP): 
  - Density: alimentar hist con real+void alternado → `resolveDensity` devuelve pos real (dist ~0), void ignorado.
  - Auto-método: `pickMethod` elige Density con alternador, Cluster con walker.
  - Ciclo: `LIP.strafePhase` alterna chase↔bait por timers; en bait el goCF está en void; fire suprimido en bait.
  - `pickBestMode`: devuelve Spiral/Behind/Normal/Random según dist/vel/spoof sintéticos.
  - Tracer + Fire on Resolved siguen andando con cada método.
- Live-fire real = usuario (farmeo alt / otros juegos).

## Riesgos

- **Density O(n²)**: mitigar con window 3s + cap 300. Con muchos jugadores, solo se corre para el target activo (no todos).
- **Auto-método flapping**: histéresis + EMA de voidFrac/flipRate.
- **Ciclo bait en juegos sensibles**: el void alto puede remover network ownership; el clamp Y≥30 + presets cortos (Micro) lo mitigan. `DynStrafe` default OFF.
- **Fire en bait**: gate `strafePhase ~= "bait"` evita quemar balas al void.
- **hist[plr] no alimentado**: si `sampleAll` no corre continuo con Resolver ON, agregar sampler liviano (dependencia a verificar en el plan).
```
