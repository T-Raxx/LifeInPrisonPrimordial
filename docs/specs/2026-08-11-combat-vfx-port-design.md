# Combat VFX Port (juju → GUIWorkspace) — Batch 1 Design

**Date:** 2026-08-11
**Status:** Approved (brainstorm)
**Scope:** Batch 1 of a multi-batch visual overhaul. Ports the standout combat VFX from `Scripts/ResolverStudy/jujudotlol.lua` into the GUIWorkspace visuals suite, wired to LifeInPrisonPrimordial's signals.

## Context & decisions

- Target runs **only in the main + test game** (LiP, place 72659788689464) — game-agnostic AC-safety is moot, and LiP's anticheat is dead. **Full Instances allowed** (ParticleEmitter/Beam/Highlight/Part/Model), not just Drawing. This unlocks the Instance-only VFX (Aura, beam tracers, hit particles, hit chams).
- Port lives in **GUIWorkspace** (the visual module the user wants updated); LiP supplies triggers via a **game profile**.
- GUIWorkspace GUIWorkspace fixes (watermark/keybind/aspect/ESP-centering) are a SEPARATE later batch — not in scope here.

## Batch 1 features (from the juju inventory)

| # | Feature | juju lines | Back-end |
|---|---------|-----------|----------|
| Aura VFX (E11) | 15 auras (6 procedural + 9 rbxassetid), colorizable, multi-select, on local char | 19679–20320 | Instances (ParticleEmitter/Beam/PointLight) |
| Hit Tracers (A1/A2) | muzzle→impact tracer, `line` (Drawing) + `beam` (Instance) modes, gradient | 13364–13547 | Drawing Line + Instance Beam |
| Hitmarker 3D (A7) | world-anchored X cross at hit part, lethal color, fade | 14965–15085 | Drawing Line ×8 |
| Hitmarker 2D (A8) | same X fixed at screen center | 15089–15200 | Drawing Line ×8 |
| Damage Numbers (A6) | floating rising number at hit part, lethal color, ragebot data | 14875–14961 | Drawing Text |
| Target Ring (E3) | spinning 32-seg world ring around target, gradient comet-tail | 22690+ | Drawing Line ×32 |
| Hit Particles (A10) | particle burst at hit (sparks/blood/lightning/…10 presets) | 14313–14820 | Instance ParticleEmitter (pooled) |
| Hit Chams (A13) | recolored fading clone of hit enemy | 15204–15473 | Instance Model clone + SelectionBox |

## Architecture

Two new GUIWorkspace modules + one LiP profile + a shared tween foundation.

### New GUIWorkspace files

```
core/combat.lua      module "combat": tracers, hitmarker 2D/3D, damage numbers, target ring, hit particles, hit chams
core/aura.lua        module "aura": the 15-aura self-cosmetic system
schema/combat.lua    rows (Combat_*)  — toggles/sliders/colorpickers per feature
schema/aura.lua      rows (Aura_*)    — multiselect + color + options
games/lifeinprison.lua   LiP profile: provider hooks feeding the modules
core/tween.lua       GV.Tween — ported juju easing/tween engine (Drawings can't use TweenService)
```

`build.lua` ORDER gains: `core/tween.lua` (after util), `core/combat.lua` + `core/aura.lua` (after selffx), `schema/combat.lua` + `schema/aura.lua` (after local), `games/lifeinprison.lua` (before entry/attach).

### Module conventions (match existing GUIWorkspace)

Each module is `return function(GV) … end` mutating `GV`. A module object has `:UseProfile(p)` (sets `self._provider`), `:_draw(class, props)` (Drawing factory), an `:Init()` that connects provider signals, and a per-frame `:_update(now, dt)` driven from the suite's heartbeat. Combat/aura create Instances directly via a `GV.newInstance` helper (mirror ESP's `create_instance` usage). Flags read via `self:_flag(name, default)`.

### Provider contract (LiP profile → modules)

`games/lifeinprison.lua` returns a provider table consumed by combat + aura:

```
provider.localCharacter()          -> Model | nil          (LP.Character)
provider.target()                  -> Player | nil         (LIP.target)
provider.onShot                    -> Signal(origin: Vector3, hitPos: Vector3, isLocal: bool)
provider.onHit                     -> Signal(player: Player, part: BasePart, damage: number, lethal: bool)
provider.bulletBeams()             -> table                 (optional; muzzle/impact override)
```

- `onShot` — fired by LiP's `Weapon.fireOne` on each op14 with `(cachedOrigin or muzzle, cachedHitPos, true)`.
- `onHit` — fired by LiP's `Visuals/HitEffects` when its correlation confirms a hit (enemy HealthChanged within the shot window), carrying the enemy, the hit part, the damage delta, and `lethal` (Died within the kill window).
- `target`/`localCharacter` — polled per frame.

The provider is a thin adapter; all detection logic already exists in LiP (HitEffects correlation, Net op14, `LIP.target`).

### Tween foundation (`core/tween.lua`)

Port juju's `tween(object, props, easing, _, duration)` (juju L463–529): per-property closures registered into a frame loop, `color3_lerp` for colors, easing {exponential, quad, circular(default), sine}, snap-on-complete, per-object/property dedup. Exposed as `GV.Tween(obj, props, easing, dur)` + `GV.tweenStep(now, dt)` called from the suite heartbeat. Every fade in combat/aura uses it.

### LiP integration

- `main.lua`: add `"combat", "aura"` to the Attach `modules` list; pass `profile = "lifeinprison"` (or the profile table) to `LIP.Visuals.Attach`. Bundle already inlines GUIWorkspace via `bundle.lua`.
- `Combat/Weapon.lua` `fireOne`: after firing, `if LIP.onShot then LIP.onShot:Fire(origin, hitPos, true) end`.
- `Visuals/HitEffects.lua`: where it already detects a hit/kill by correlation, `if LIP.onHit then LIP.onHit:Fire(plr, part, dmg, lethal) end`.
- `Core/State`: create `LIP.onShot`, `LIP.onHit` as simple signal objects (BindableEvent or a tiny Lua signal) at init.

## Non-goals

- No GUIWorkspace watermark/keybind/aspect/ESP-centering fixes (separate batch).
- No ESP 2D polish (tool icon/bars) — later batch.
- No world/lighting suite.
- Batch 1 does not touch the resolver/strafe code.

## Feature notes (port guidance per feature)

Each feature is ported by reading its juju line-range and adapting to GUIWorkspace conventions (GV draw/instance factories, `self:_flag`, `GV.Tween`, provider signals). Key adaptations:

- **Aura (19679–20320):** port `build_angel_wing_aura`/`build_blue_heat_aura`/`build_heal_aura`/`build_ambient_aura`/`build_nimb_aura`/`build_tornado_aura` (procedural) verbatim (they only need `Instance.new` + NumberSequences); port the 9 `rbxassetid` loaders via `game:GetObjects`. On `provider.localCharacter()` change, clone/re-parent emitters onto body parts (rename `"\0\0"`). Multiselect + `ColorSequence` recolor.
- **Tracers (13364–13547):** `line` mode = 2 Drawing Lines (main+outline) projected from `origin`→`hitPos`, fade via `GV.Tween`. `beam` mode = clone a prebuilt textured Beam+2 Attachments (port the `beams` bank L13364) onto Terrain, fade a transparency NumberSequence. Driven by `provider.onShot`.
- **Hitmarker 3D/2D (14965–15200):** 8 Drawing Lines (4 marker + 4 outline). 3D projects `part.Position` per frame; 2D fixed at `ViewportSize/2`. Lethal color from `onHit`'s `lethal`. Fade via tween.
- **Damage Numbers (14875–14961):** Drawing Text at hit part, rise `(0,1.5,0)`, ease-in then fade, lethal color, optional ragebot reason. Pooled/heartbeat.
- **Target Ring (E3, 22690+):** 32 Drawing Lines forming a world ring around `provider.target()` UpperTorso, radius bounding-box-fit, spin `(clock*speed)%2π`, `color3_lerp` comet-tail + per-segment transparency.
- **Hit Particles (14313–14820):** one pooled anchored Part holding 10 prebuilt ParticleEmitters; move to hit CFrame + `:Emit(count)`. `behind_walls` → ZOffset. Port the 10 emitter configs.
- **Hit Chams (15204–15473):** clone hit enemy Model, recolor MeshParts (Neon/ForceField, anchored, TextureID=""), grow+fade via heartbeat tween; `only_last_hit` keeps one. Outline variant = per-part SelectionBox.

## Testing

Via `roblox-executor-mcp` + build/bundle; live-fire deferred to user:
1. Each new module builds clean; GUIWorkspace `dist/Visuals.Primordial.lua` rebuilds; LiP `bundle.lua` inlines it; `compila=true`.
2. Suite loads with `modules={world,esp,selffx,combat,aura}` + LiP profile; no error; the new "Combat"/"Aura" schema rows render in Visuals.
3. Probe: `provider.onShot`/`onHit` exist; firing them manually spawns a tracer/hitmarker/damage-number without error; aura applies emitters to the local character.
4. Live-fire (user): shoot an enemy → tracer + hitmarker + damage number + particles + chams; enable an aura → particles on own character; target ring around the ragebot target.
