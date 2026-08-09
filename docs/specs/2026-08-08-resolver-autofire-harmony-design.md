# Resolver + Autofire Harmony (port juju.lol) — Diseño

Fecha: 2026-08-08 · Cheat: LifeInPrisonPrimordial (PrimordialUI) · Fuente: leak Da Hood juju.lol (`jujureal.lua`, source completo)

## Objetivo

Portar a FULL el resolver + la "harmonía" autofire↔resolver del leak juju al cheat LiP. El resolver histograma
ya está PARCIAL (`Strafe.resolveCluster`, port fiel de juju que resuelve el void), pero solo alimenta el centro
del orbit del strafe. Completarlo a un **aim-resolver** que produce `(posResuelta, didDefensive)` y hacer que el
**AUTOFIRE dispare a la pos resuelta**, gateado por `didDefensive` (la harmonía). + prediction (ping-lead). SIN
backtrack (no funciona en LiP). La update más importante de la rama.

## La harmonía (el core, de juju)

Un solo booleano **`did_defensive`** ES el contrato resolver↔autofire: cuando el cluster ganador del histograma
cruza el gate de accuracy → (a) el aim pasa a la **pos resuelta**, y (b) **autoriza el disparo** aunque el head
crudo esté en el void/lejos. **El gate de accuracy del resolver ES el gate de fire.** No hay hit-chance aparte.

## Contexto actual (el gap)

- `Strafe.resolveCluster` (Combat/Strafe.lua ~107): histograma ponderado fiel a juju (posWeight/voidWeight/forget/
  mergeRadius/accuracy/clamp -1..18/score = weight·clamp(count·0.25,1,3)). Resuelve el void. **Solo alimenta el
  strafe orbit center**, no el disparo.
- `Weapon.tickAuto` dispara a `LIP.cachedHitPos` = **centro CRUDO del hitPart** (Head), seteado por `cacheHit()`
  (main.lua), con diseño HBE-safe (no offsetea el hit). **No usa el resolver para disparar.**
- GAP = la harmonía: el autofire no dispara a la pos resuelta ni tiene el gate `didDefensive`.

## Componentes

### 1. Resolver aim (Combat/Strafe.lua)
- `resolveCluster` extendido → devuelve `(pos, didDefensive)` donde `didDefensive = (bestScore > RP.accuracy)`.
- `Strafe.resolveAim(plr, rawHitboxPos) -> pos, didDefensive`: corre el histograma + aplica **prediction lead**.
- **Velocidad a `resolver_rate`** (finite-diff rate-gated, por target): `if clock()-lastRefresh > resolver_rate
  then vel = (pos - lastPos)/dt; lastPos = pos; lastRefresh = clock() end`. (Hoy `targetVel` es cada frame.)
- **Prediction lead**: `pos = pos + vel * lead`, `lead = predMode=="Auto" and (ping/500) or predSeconds`.
  `ping = LP:GetNetworkPing()`.

### 2. cacheHit (main.lua) — harmonía
- Con Resolver ON: `resolvedPos, didDefensive = Strafe.resolveAim(target, head.Position)`.
- Si `FireResolved` ON y `didDefensive`: `cachedHitPos = resolvedPos` (**riesgo HBE aceptado**),
  `cachedHitPart = head`, `LIP.didDefensive = true`.
- Si no: fallback = comportamiento actual (head crudo center, HBE-safe), `LIP.didDefensive = false`.
- Toggle **`FireResolved`**: OFF → siempre head crudo (HBE-safe) para el disparo (el resolver sigue steereando
  el strafe); ON → la harmonía (dispara resuelto).

### 3. Autofire gate (Combat/Weapon.tickAuto)
- Hoy: `if autoOn and not cachedHitPart then return` (no dispara sin hitPart).
- Con harmonía: disparar cuando `LIP.didDefensive` **aunque el head esté lejos/void** (el resolver ya dio la pos
  real). Gate: `cachedHitPart and (inRange OR LIP.didDefensive OR alwaysFire)`.
- **Mantener el rate-limit al firerate** (GST timing anti-unequip). La harmonía cambia DÓNDE + el gate, NO el
  timing anti-unequip (juju usa fire_cooldown 5ms; LiP no puede — el firerate lo capea el server).

### 4. Void detection
- Ya está: `hitbox.Magnitude >= 9e5` → suma `voidWeight 0.2` + se olvida; la pos real clusteriza y gana el score.

### 5. HUD (Visuals/CrosshairHUD) — labels con MÁS INFO (estilo symbol)
- "Resolved: x.xyz" = atar al **score/didDefensive del cluster** (confianza real del resolver: bestScore/accuracy
  normalizado, clamp 0–1), reemplazar `Strafe.confidence` (residual lineal viejo) por esta métrica.
- **Expandir el label base** con telemetría del resolver (Strafe expone `Strafe.resolverInfo(plr)`):
  `killing: <user> | Resolved: x.xyz | <STATE> | clusters: N | HP: NN`
  - `<STATE>` tags por prioridad: **LOCKED** (didDefensive, fire-ready) / **RESOLVING** (hay clusters pero score <
    accuracy) / **VOID** (target en magnitud ≥9e5, spoofeando) / **NORMAL** (target quieto/predecible) /
    **PREDICT +Xms** (lead activo).
  - `clusters: N` = cantidad de clusters vivos en el histograma (más = target más errático/spameando).
  - `HP: NN` = vida del target.
- Overrides existentes intactos (Reloading In Void / Killed waiting). Color wave existente. Todo configurable.

### 6. UI (UI.lua)
- Ya: sliders cluster (posWeight/voidWeight/forget/accuracy/lerp/distPenalty).
- Agregar: `ResolverRate` slider (0–0.1s, def 0.037), `PredMode` dropdown (Auto/Manual), `PredLead` slider
  (0–0.4s, def 0.12), toggle `FireResolved` (harmonía on/off, default OFF = HBE-safe).

## Fuera de scope
- **Backtrack**: no funciona en LiP (op14 valida `hitPart.Position` ACTUAL, sin lag-comp rewind como Da Hood →
  disparar a pos vieja = rechazado/flag, como el Overkill). El resolver (pos real ACTUAL) es la herramienta
  correcta para LiP.
- **symbollol resolver**: juju es primario; symbol solo si el juju no alcanza (referencia).

## Params (defaults juju)
posWeight 1.5, voidWeight 0.2, forget 80 (decay/s = /20; outliers ×2.5), accuracy 1.35, lerp 0.1 (×3 cap 0.6 si
target lento), distPenalty 2.0 (·0.01, clamp 0.25–1), mergeRadius clamp(200−dist·0.4, 80, 200), resolver_rate
0.037, prediction Auto = ping/500, weight clamp −1..18, score = weight·clamp(count·0.25, 1, 3).

## Testing (roblox-executor-mcp; live-fire real = usuario en burner)
- **Resolver**: target void-spameando (magnitud ≥9e5) → `resolveAim` devuelve la pos REAL (cluster), didDefensive
  =true tras acumular. Leer el histograma resuelve vs la pos real del target.
- **Harmonía**: Resolver+AutoFire+FireResolved ON → `cachedHitPos` = resolvedPos (no el void), autofire dispara
  (gate didDefensive). Non-destructive: leer cachedHitPos vs target real, GST válido + arma intacta.
- **Prediction**: vel lead aplicado (ping-based) → cachedHitPos adelantado por la velocidad del target.
- **HUD**: "Resolved x.xyz" refleja el score del cluster.
- **Live**: daño + registro + ¿flag HBE? = usuario en burner. `FireResolved` OFF revierte al HBE-safe.

## Riesgos
- **HBE**: disparar a la pos resuelta (≠ hitPart center) puede flaguear el HBE de LiP → test burner; el toggle
  `FireResolved` permite volver al HBE-safe.
- resolver_rate muy chico = vel ruidosa; muy grande = lead laggy. Default 0.037 (juju).
