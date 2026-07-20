# LifeInPrisonPrimordial — Ops / entorno

## Estructura
Cheat de Life in Prison (place 72659788689464) desde 0 sobre la UI lib propia PrimordialUI,
reemplazando la suite Linoria vieja `Scripts/LifeInPrison/`. Módulos = **factories**
`return function(require, LIP, Lib) ... end`. Estado global único `getgenv().LIP`.
`build.lua` concatena → `dist/LifeInPrisonPrimordial.lua` (un loadstring). PrimordialUI
`Flags/Toggles/Options` = única fuente de verdad de la config.

Módulos: `Core/State` (getgenv, guard doble-carga, `LIP.fire(op,...)`), `Net` (1 hook __namecall
unificado: silent aim op14 + melee aura op16, passive+precache), `Combat/{Target,Ragdoll,Melee}`,
`Visuals/ESP` (R6, Drawing+Highlight), `UI`, `main` (driver Heartbeat).

## Executor / sync
- Executor **Potassium**. Workspace root: `C:\Users\trabajo\AppData\Local\Potassium\workspace`.
- `readfile`/`writefile` relativos a ese root. Junction OneDrive rompe readfile → **copia real** (robocopy).
- Sync antes de cada build/test (PowerShell):
```powershell
$src = "C:\Users\trabajo\OneDrive\Escritorio\Scripts\LifeInPrisonPrimordial"
$dst = "C:\Users\trabajo\AppData\Local\Potassium\workspace\LifeInPrisonPrimordial"
robocopy "$src" "$dst" /E /XD ".git" ".superpowers" "dist" "docs" /NFL /NDL /NJH /NJS /R:1 /W:1 | Out-Null
```
(robocopy exit 0-7 = OK.)

## Build + load (vía MCP roblox-executor)
1. Sync (arriba).
2. Build: `execute` → `loadstring(readfile("LifeInPrisonPrimordial/build.lua"))()`.
3. Load: `execute` → `loadstring(readfile("LifeInPrisonPrimordial/dist/LifeInPrisonPrimordial.lua"))()`.
   (`execute-file` con path del dist NO resuelve — usar loadstring+readfile.)
4. Verificar: `screenshot-window` + `get-console-output` (limit bajo) + `get-data-by-code` read-only.

## Testing — REGLAS DE RIESGO
- Cliente vivo = **graveLxtan @ Life in Prison** (burner). Server **público con gente real**.
- **Self-ragdoll / ESP = riesgo 0** (self / client-side). Testear libremente.
- **Auto-punch / Melee aura / Silent aim = disparan a jugadores reales.** NO spamear. El
  controller valida SOLO el plumbing sin daño (dry-run: target resuelto + precache poblado, sin
  disparar). El live-fire (daño real) lo maneja el usuario en burner (su workflow).
- Estado seguro tras testear: combat toggles OFF (`swapOn/meleeOn=false`).
- **1 solo __namecall hook** (regla del juego: doble hook + spam = crash). Reload-safe vía flag
  `getgenv().__LIP_HOOK`; el guard de `Core/State` neutraliza el build viejo (pasa transparente).

## Fuente decompilada
`decompile(ReplicatedFirst.BClient)` → `workspace\lip_bclient_v48.lua` (~251k líneas, padding
`print()` obfuscation, NO cifrado). Grep sobre el dump en disco. script-grep MCP = 0 (bytecode live).

## Pendiente / TODO
- Live-fire validación de silent aim (swap del bullet aplica daño) + auto-punch (server acepta op33
  sin estado de puño?) + melee aura, en burner con enemigo cerca.
- Si op33 requiere estado de animación de puño: fallback a passive (redirect en el .Touched).
- Movement (fly/noclip/speed) = fase futura, riesgo AC (vigila CFrame).
