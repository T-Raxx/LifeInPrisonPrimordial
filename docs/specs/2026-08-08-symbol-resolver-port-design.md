# Port del cluster resolver a symbol.lua + tracer resuelto (ambos scripts) — Diseño

Fecha: 2026-08-08 · Scripts: `Scripts\symbol.lua` (universal PvP) + `LifeInPrisonPrimordial` (tracer)

## Objetivo

Reemplazar el "Real Resolver v2" (RSV, multi-cluster + multi-modelo quad/circular) de `symbol.lua` — obsoleto vs
resolvers modernos (juju/sakura) — por el **cluster histograma** ya validado en LiP (port de juju). Hacer que el
silent aim de symbol apunte a la pos RESUELTA (modo **Fire on Resolved**, como LiP). Agregar un **tracer a la pos
resuelta** en AMBOS scripts (symbol.lua + LiP).

## symbol.lua — arquitectura (reemplazar internals, MANTENER interface)

El RSV vive en L830–1309. La estrategia: swap del MOTOR, conservar las firmas públicas + los campos de
`RSV_State` que el resto lee → los call sites (strafe L3680/3686, autofire gate L3730, clientDist L3739, ESP
L2327/3898, weld L2610+) NO cambian.

### Componentes symbol.lua

1. **Cluster histograma (reemplaza el motor RSV):** ingest en `RSV_Sample(player, partOverride)` (L1023) — por
   muestra: decay/forget (outliers ×2.5), merge por `mergeRadius = clamp(200 - dist·0.4, 80, 200)`, add weight
   (`isVoid = pos.Magnitude ≥ 9e5 ? voidWeight : posWeight` × distPenalty), lerp del centroide, score = weight·
   clamp(count·0.25,1,3), clamp weight −1..18. Estado del histograma guardado en `RSV_State(name)`.
2. **`RSV_AimPos(player, pingMs) -> pos, conf`** (L1210): pos = cluster ganador (si cruza `accuracy`) + prediction
   lead (`vel_resuelta · (pingMs/1000 · 2)` auto, o lead manual). Mantiene el floor del kill-plane existente.
3. **`GetResolvedPosition(target) -> Vector3|nil`** (L1249): sin cambios de firma (llama RSV_AimPos).
4. **`CalculateConfidence(target) -> conf(0-100)`** (L1255): `conf = clamp(bestScore / accuracy, 0, 1) · 100`.
   `didDefensive` (cruzó el gate) → conf alta → el gate `conf ≥ AutoFireMinConf` (L3760) sigue andando.
5. **Poblar `RSV_State` (campos leídos afuera):** `.conf` (0-100), `.clusters` (#), `.best` = `{ lastPos, lastSeen }`
   del cluster ganador, `.spamming`/`.desync`/`.teleporting` derivados del void detection (magnitud/varianza),
   `.model = "cluster"`. **Stub del flash-timing:** `.flashStarts = {}`, `.flashPeriod = nil`, `.flashLastT = 0`
   → el autofire cae al gate de conf (L3760), sin la ruta flash/pre-fire.
6. **Remover:** `RSV.FitQuad/FitCirc/EvalModel/BestModel/ClusterPlaus` (motor viejo) y el estado multi-modelo.
   Conservar `RSV.TorsoHrpOffY` (L1264), `RSV.WeldAnchorPart` (L2461), `RSV_PosAt` (L1274, backtrack — stub o
   deriva del cluster), `RSV_Clear`, `GetActivePing`.

### Fire on Resolved (silent aim)
- Patch en **L2515** (cache updater del silent aim): `_saCachedPos = (Tog('FireResolved') and
  GetResolvedPosition(CurrentTarget)) or (p and p.Position)`. Mouse.Hit (L2505) y el `__namecall` hook
  (L4187-4217) heredan el aim resuelto sin más cambios.

### UI (LinoriaLib)
- **ResolverGroup** (L2821, cierra L3013): sliders del cluster — `RRPosWeight/RRVoidWeight/RRForget/RRAccuracy/
  RRLerp/RRDistPenalty/ResolverRate/PredLead` (+ `PredMode` dropdown Auto/Manual). Reusar `AutoPing`/`PingAdjustment`
  existentes para el ping-lead auto.
- **SAGroup** (L2993): toggles `FireResolved` (default OFF) + `ResolvedTracer` (default OFF) + colorpicker/slider
  del tracer.

## Tracer a la pos resuelta (AMBOS scripts)

`Drawing.new("Line")` (creado 1 vez, cleanup en el array de destrucción). Cada frame: `From = centro de pantalla`
(`Camera.ViewportSize/2`), `sp,on = Camera:WorldToViewportPoint(GetResolvedPosition(target))`; si `on` → `To =
Vector2(sp.X,sp.Y)`, `Visible = true`; gated por `Tog('ResolvedTracer')` + hay target + hay pos resuelta.
- **symbol.lua:** declarar el Drawing cerca de L2100 (con `_dvTracer`), update en el RenderStepped de ESP
  (~L3897), cleanup en L4410. Color/thickness configurable.
- **LiP:** reusar el patrón del visualizador del void (Movement/Void.lua, Drawing.Line desde el centro). Fuente de
  la pos = `Strafe.resolveAim(LIP.target, head.Pos)` o `LIP.cachedHitPos` cuando didDefensive. Toggle
  `ResolvedTracer` en el panel Resolver + colorpicker. (FireResolved en LiP ya existe.)

## Params (defaults juju, iguales a LiP)
posWeight 1.5, voidWeight 0.2, forget 80, accuracy 1.35, lerp 0.1, distPenalty 2.0, resolverRate 0.037, prediction
Auto = ping·2, weight clamp −1..18, score = weight·clamp(count·0.25,1,3), void = magnitud ≥9e5, merge = clamp(200
− dist·0.4, 80, 200).

## Testing
- symbol.lua: probar en OTROS juegos (el usuario) — universal. Verificar: el resolver resuelve void/desync a la
  pos real (conf sube, cluster locked), el silent aim con FireResolved ON apunta a la resuelta, el tracer dibuja
  al cluster ganador, el autofire gatea por conf. Los call sites (strafe/ESP) siguen andando (sin errores de nil).
- LiP: el tracer resuelto dibuja a la pos que ya resuelve el cluster (verificado en LiP). Via roblox-executor-mcp
  donde aplique; live-fire = usuario.

## Riesgos
- Romper un call site que lea un campo de `RSV_State` no poblado → nil error. Mitigación: poblar TODOS los campos
  listados + stubs. Revisar los 9 call sites tras el swap.
- La predicción lineal del cluster < la multi-modelo vieja para targets con curvas — aceptado (el usuario prefiere
  el cluster de juju, validado). El resolver es universal → tunear por juego con los sliders.
- HBE / detección al apuntar a la resuelta = depende del juego (symbol es universal). FireResolved default OFF.
