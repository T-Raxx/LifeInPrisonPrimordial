# LifeInPrisonPrimordial

Cheat de **Life in Prison** (Roblox, place 72659788689464) construido desde 0 sobre la UI lib
propia **PrimordialUI** (réplica del cheat CS2 primordial.dev). Reemplaza la suite Linoria vieja.

## Features (v1)
- **Combat**
  - Self-ragdoll (op23): botón + keybind + Permanent Ragdoll (lock event-driven). Verificado en vivo.
  - Auto-punch (op33): puños activos, sin GST, al enemigo más cercano en rango.
  - Melee aura (op16): passive redirect del hit al target al golpear con arma melee.
  - Silent aim (op14): passive arg-swap de los bullets al target (Crosshair/Distance/Health, FOV,
    wallcheck, anti-invis). Cámara NO se toca, GST intacto.
- **Visuals** — ESP R6 (box/name/health/distance/tracer/skeleton/chams), filtros team/friend/maxdist.

## Arquitectura
Módulos factory `return function(require, LIP, Lib)`. `build.lua` bundlea a
`dist/LifeInPrisonPrimordial.lua` (un loadstring). Estado global `getgenv().LIP`. UI = PrimordialUI
`Toggles/Options`. 1 solo `__namecall` hook (Net.lua) passive+precache.

Ver `docs/remote-map-2026-07.md` (reverse) y `docs/ops.md` (entorno/sync/testing).

## Uso
```
loadstring(readfile("LifeInPrisonPrimordial/build.lua"))()          -- build
loadstring(readfile("LifeInPrisonPrimordial/dist/LifeInPrisonPrimordial.lua"))()  -- load
```
Requiere `PrimordialUI/dist/PrimordialUI.lua` en el workspace del executor.
