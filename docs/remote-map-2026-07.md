# Life in Prison — Remote map (place 72659788689464, PlaceVersion 48)

Público, Group 750114916 (mismo grupo que el TEST 83945329336657). GameId 8051653879.
Framework **netevgen**: `ReplicatedStorage.Events` con 3 remotes multiplexados:
- `RemoteEvent` = dispatch, **arg1 = opcode numérico**
- `RemoteFunction` = request/response
- `KansloosRemoteEvent` (UnreliableRemoteEvent) = replicación high-rate

## Opcode = orden de registro (BClient @ ReplicatedFirst)
Constructor `shared.netevgen.RemoteEvent(u958)` / `.RemoteFunction(u958)` — **counter compartido**
(RE y RF incrementan el mismo). `opcode = (regLine-233501)/2 + 1` en el dump v48.
Anchors verificados x5 vs mapa TEST viejo (idénticos): FirearmBullets=14, OnMeleeRemote=16,
Ragdoll=23, OnPunchRemote=33, OnReload=40. **El mapa público v48 = idéntico al TEST.**

| op | evento | payload / notas |
|----|--------|-----------------|
| 12 | ReceiveTool | |
| 13 | SeatControl | |
| **14** | **FirearmBullets** (shoot) | `FireServer(14, Tool, bullets, GST())` — ver abajo |
| 15 | OnSoundReplicate | |
| **16** | **OnMeleeRemote** | `FireServer(16, Tool, GST(), hitPart, hitPart.CFrame:PointToObjectSpace(hitbox.Position))` |
| 17 | SetPosition | |
| **20** | **OnArrested** | |
| **21** | **OnTaze** | |
| 22 | OnDidArrest | |
| **23** | **Ragdoll** (self) | `FireServer(23)` **sin args** — TOGGLEA ragdoll server-side |
| 24 | RagdollImpulse | |
| 27 | OnNotice | |
| **33** | **OnPunchRemote** | `FireServer(33, enemyBasePart)` — parte con Humanoid parent, **sin GST** |
| **40** | **OnReload** | `FireServer(40, Tool, ammo, GST())` |
| 43 | OnThrow | `FireServer(43, Tool, 2, v,v,v)` o `(43, Tool, 1)` |
| 56 | Turret | |
| **57** | **Handcuffs** | arresto Police→target |

## SHOOT (op14) — bullet structure v48 (BClient u3414, confirmado)
`FirearmBullets:FireServer(14, Tool, bullets, GST())`
cada `bullets[i]` (hit real, no-Terrain):
```
{ [1]=origin V3, [2]=muzzle V3, [3]=hitPos V3, [4]=hitPart Instance, [5]=hitPart.Position V3, [6]=objspace V3 }
```
(Terrain hit: [5]=[6]=nil; sin hit: {origin, muzzle, endPos, nil,nil,nil})
**Silent aim** = por cada bullet: [3]=targetPos, [4]=targetPart, [5]=targetPos, [6]=Vector3.zero.

## GST() — token AC
`function v56.GST() end` = **stub vacío** en la def base (retorna nil). Override runtime
`u3707.GST=u3669` (posible token real). **No lo tocamos**: silent aim/melee = passive
(el cliente genera GST, nosotros solo redirigimos el HIT). Auto-punch op33 NO usa GST.

## Self-ragdoll (op23)
Bind original `R -> Ragdoll:FireServer()` está gateado tras `if IsStudio or IsDevGame`
(debug de dev, NO existe en el público). Pero el remote es real: firearlo manual desde el
cliente TOGGLEA el ragdoll. **Verificado en vivo:** state Running↔Physics, health intacta.

## Teams
Police / Prisoners / Criminals. Enemigo = team distinto. Chars = **R6**
(Head/Torso/Left Arm/Right Arm/Left Leg/Right Leg + HumanoidRootPart + RDCollision ragdoll parts).

## Anticheat
Nonce/GST stubbeado (AC desactualizado, confirma nota vieja). Regla heredada: **1 solo __namecall
hook** (doble hook + spam Tool:Activate = crash en recon, NO detección). No firear armas no equipadas.
Eventos AC (ACCFrameChanged/ACKickTrigger ~op58-61) vigilan CFrame/movimiento → movement = más riesgo.
