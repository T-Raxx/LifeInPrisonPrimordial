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

## Loadstring (ejecutable)
Bundle self-contained (PrimordialUI inline) hosteado en gist secreto:
```lua
loadstring(game:HttpGet("https://gist.githubusercontent.com/T-Raxx/1552e7e4cb41aee0d826f644689838e2/raw/LifeInPrisonPrimordial.lua"))()
```

Repo privado: `github.com/T-Raxx/LifeInPrisonPrimordial`. Alternativa con PAT (sin gist):
```lua
local r = request({
  Url = "https://api.github.com/repos/T-Raxx/LifeInPrisonPrimordial/contents/LifeInPrisonPrimordial.lua",
  Headers = { Authorization = "token <TU_PAT_READONLY>", Accept = "application/vnd.github.raw" },
})
loadstring(r.Body)()
```

## Dev / actualizar el bundle
```lua
loadstring(readfile("LifeInPrisonPrimordial/build.lua"))()   -- build dist (modular)
loadstring(readfile("LifeInPrisonPrimordial/bundle.lua"))()  -- genera LifeInPrisonPrimordial.lua self-contained
```
Luego: `git add -A && git commit && git push` + `gh gist edit 1552e7e4cb41aee0d826f644689838e2 LifeInPrisonPrimordial.lua`.
Dev local (sin bundle) requiere `PrimordialUI/dist/PrimordialUI.lua` en el workspace. Ver `docs/ops.md`.
