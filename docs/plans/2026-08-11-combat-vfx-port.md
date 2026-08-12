# Combat VFX Port (juju → GUIWorkspace) — Batch 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development (sequential — feature tasks share `core/combat.lua`/`schema/combat.lua`, so do NOT run them in parallel). Steps use checkbox (`- [ ]`).

**Goal:** Port the standout combat VFX from `Scripts/ResolverStudy/jujudotlol.lua` into GUIWorkspace as two new modules (`combat`, `aura`), wired to LifeInPrisonPrimordial via a game profile.

**Architecture:** New GUIWorkspace `core/combat.lua` + `core/aura.lua` + `core/tween.lua` + `schema/combat.lua` + `schema/aura.lua` + `games/lifeinprison.lua`; LiP fires `LIP.onShot`/`LIP.onHit` signals and adds the modules to `LIP.Visuals.Attach`. Full Instances allowed (LiP AC dead).

**Tech Stack:** Luau, GUIWorkspace visuals suite (`return function(GV)` modules, bundled to `dist/Visuals.Primordial.lua`), PrimordialUI, tested via `roblox-executor-mcp`.

## Global Constraints

- Two repos: **GUIWorkspace** (`Escritorio/Scripts/GUIWorkspace`, own git) holds the visual modules; **LifeInPrisonPrimordial** (`Escritorio/Scripts/LifeInPrisonPrimordial`, own git, on master) holds the profile-firing hooks + Attach call. Commit each repo separately.
- GUIWorkspace module convention: `return function(GV) … end`, no `require`; module object has `:UseProfile(p)`, `:_draw(class,props)`, `:Init()`, `:_update(now,dt)`; flags via `self:_flag(name,default)`. Match `core/selffx.lua` patterns exactly.
- Bundle pipeline: edit GUIWorkspace source → `loadstring(readfile("GUIWorkspace/build.lua"))()(GV,"primordial")` rebuilds `dist/Visuals.Primordial.lua` → sync GUIWorkspace/dist to Potassium → LiP `bundle.lua` re-inlines it into the root bundle. **Both** GUIWorkspace/dist and LiP must be synced to the Potassium workspace before building.
- Source of truth for every feature = the juju line-range named in the task. The subagent MUST read that range from `Scripts/ResolverStudy/jujudotlol.lua` and adapt it — not invent.
- Instances are created directly (mirror ESP's `create_instance`); Drawings via `self:_draw`. Fades via `GV.Tween`.
- No local Lua; verify via executor build/load + probes. Live-fire deferred to user.
- Do NOT touch resolver/strafe/GUIWorkspace-fix code.

## File Structure

| File | Repo | Responsibility |
|------|------|----------------|
| `core/tween.lua` | GUIWorkspace | `GV.Tween` easing/tween engine (ported juju L463–529) |
| `core/combat.lua` | GUIWorkspace | module "combat": tracers, hitmarkers, dmg numbers, ring, particles, chams |
| `core/aura.lua` | GUIWorkspace | module "aura": 15-aura self-cosmetic |
| `schema/combat.lua` | GUIWorkspace | `Combat_*` rows |
| `schema/aura.lua` | GUIWorkspace | `Aura_*` rows |
| `games/lifeinprison.lua` | GUIWorkspace | LiP provider (onShot/onHit/target/localCharacter) |
| `build.lua` | GUIWorkspace | ORDER += the new files |
| `Core/State.lua` | LiP | create `LIP.onShot`/`LIP.onHit` signals |
| `Combat/Weapon.lua` | LiP | fire `LIP.onShot` in `fireOne` |
| `Visuals/HitEffects.lua` | LiP | fire `LIP.onHit` on confirmed hit/kill |
| `main.lua` | LiP | add `combat`/`aura` to modules + pass profile |

Task order: **1 (foundation) must complete first.** Then 2→8 (features) sequentially (shared files). Then 9 (bundle+smoke).

---

### Task 1: Foundation — tween, signals, profile, module scaffolds, wiring

**Files:** create `core/tween.lua`, `core/combat.lua`, `core/aura.lua`, `schema/combat.lua`, `schema/aura.lua`, `games/lifeinprison.lua`; edit `build.lua` (GUIWorkspace); edit `Core/State.lua`, `Combat/Weapon.lua`, `Visuals/HitEffects.lua`, `main.lua` (LiP).

**Interfaces produced:**
- `GV.Tween(obj, props, easing, dur)` + `GV.tweenStep(now, dt)`.
- Module "combat" and "aura": empty-but-loadable, `:UseProfile`, `:Init` connects `provider.onShot`/`onHit`, `:_update` no-op stubs, per-feature render fns added by later tasks.
- `games/lifeinprison.lua` → provider `{ localCharacter, target, onShot, onHit }`.
- `LIP.onShot:Fire(origin,hitPos,isLocal)`, `LIP.onHit:Fire(player,part,damage,lethal)`.
- schema rows `Combat_Enabled`, `Aura_Enabled` (masters) so the categories render.

- [ ] **Step 1: Port the tween engine.** Read `jujudotlol.lua` L463–529 (`tween`, `color3_lerp`, easing table). Create `core/tween.lua` = `return function(GV) … end` exposing `GV.Tween(obj, props, easing, dur)` (registers per-property lerp closures into an internal list) and `GV.tweenStep(now, dt)` (advances them, snaps on complete, dedups per obj+prop). Support Drawing props (Color/OutlineColor/Transparency/Size/Position) + Color3 via `color3_lerp`. Easing: exponential/quad/circular(default)/sine.

- [ ] **Step 2: Signal helper + LiP signals.** In `Core/State.lua`, add a tiny signal (BindableEvent wrapper or Lua-table signal with `:Connect`/`:Fire`) and create `LIP.onShot`, `LIP.onHit` at init (idempotent under the double-load guard).

- [ ] **Step 3: Fire `onShot`.** In `Combat/Weapon.lua` `fireOne(hitPart, hitPos, gst)`, after the shot is sent, add: `if LIP.onShot then local o = (LIP.spoofOn or LIP.connRep) and LIP.spoofFakePos or (function() local h=char() and char():FindFirstChild("Head"); return h and h.Position end)(); pcall(function() LIP.onShot:Fire(LIP.cachedOrigin or o, hitPos, true) end) end`.

- [ ] **Step 4: Fire `onHit`.** In `Visuals/HitEffects.lua`, at the point it confirms a hit (enemy HealthChanged within the shot window) and a kill (Died within the kill window), add `if LIP.onHit then pcall(function() LIP.onHit:Fire(plr, hitPart, dmg, isKill) end) end` (reuse its existing hit/kill locals; `hitPart` = the enemy Head or the part it already targets, `dmg` = the health delta it computes, `isKill` = its Died branch).

- [ ] **Step 5: LiP profile.** Create `games/lifeinprison.lua` = `return function(GV) GV.Profiles = GV.Profiles or {}; GV.Profiles.lifeinprison = function(services) … return provider end end` following `games/_template.lua` + `games/rivals.lua` conventions. Provider: `localCharacter = function() return services.Players.LocalPlayer.Character end`, `target = function() return getgenv().LIP and getgenv().LIP.target end`, `onShot = getgenv().LIP and getgenv().LIP.onShot`, `onHit = getgenv().LIP and getgenv().LIP.onHit`. (Read `games/_template.lua` fully first for the exact contract.)

- [ ] **Step 6: Module scaffolds.** Create `core/combat.lua` and `core/aura.lua` as `return function(GV) … end` mirroring `core/selffx.lua`'s skeleton: a module table with `:UseProfile(p)`, `:_draw(class,props)`, `:_flag(name,default)`, `:Init()` (connect `self._provider.onShot`/`onHit` if present; store connections), `:_update(now,dt)` (call `GV.tweenStep` + per-feature updaters — stubs for now), and registration into `GV` the same way SelfFX registers. No feature rendering yet (later tasks fill in).

- [ ] **Step 7: Schema masters.** Create `schema/combat.lua` and `schema/aura.lua` following `schema/local.lua` structure: at minimum a master toggle row (`Combat_Enabled`, `Aura_Enabled`) so the renderer builds a category. Read `schema/_helpers.lua` for `CF`/`pushCF`/`suiteRows` usage.

- [ ] **Step 8: build ORDER + Attach.** Edit GUIWorkspace `build.lua` ORDER: add `"core/tween.lua"` after `core/util.lua`; `"core/combat.lua","core/aura.lua"` after `core/selffx.lua`; `"schema/combat.lua","schema/aura.lua"` after `schema/local.lua`; `"games/lifeinprison.lua"` before `entry/attach.lua`. In LiP `main.lua`, change the Attach call to `modules = { "world", "esp", "selffx", "combat", "aura" }` and pass `profile = "lifeinprison"`.

- [ ] **Step 9: Build + load smoke.** Rebuild GUIWorkspace dist (`loadstring(readfile("GUIWorkspace/build.lua"))()(GV,"primordial")` — check how `init.lua`/existing build is invoked; use the documented call), sync GUIWorkspace/dist + LiP to Potassium, run LiP `bundle.lua`, load the root bundle. Expected: `compila=true`, no errors, `LIP.onShot`/`LIP.onHit` exist, suite loads with combat+aura categories present.

- [ ] **Step 10: Commit both repos.**
```bash
# GUIWorkspace
cd .../GUIWorkspace && git add -A && git commit -m "feat(visuals): combat+aura module scaffolds, GV.Tween, LiP profile, build ORDER"
# LiP
cd .../LifeInPrisonPrimordial && git add Core/State.lua Combat/Weapon.lua Visuals/HitEffects.lua main.lua && git commit -m "feat(visuals): LIP.onShot/onHit signals + attach combat/aura modules with lifeinprison profile"
```

---

### Tasks 2–8: one VFX feature each

Each task is executed by a fresh subagent given: the juju line-range to read, the GUIWorkspace module + schema to extend, and the trigger. Pattern per task:
- Read the juju range; understand the exact primitives/params/animation.
- Add a render function + per-frame updater to `core/combat.lua` (or `core/aura.lua`), created lazily/pooled like ESP.
- Add the feature's schema rows to `schema/combat.lua`/`schema/aura.lua` (toggle + color + tunables mirroring juju's menu rows named in the inventory).
- Wire the trigger: `onShot`→tracers; `onHit`→hitmarkers/dmg/particles/chams; `target()`→ring; `localCharacter()`→aura.
- Build GUIWorkspace dist + LiP bundle, load, and probe by manually firing the relevant signal (e.g. `LIP.onShot:Fire(v3a, v3b, true)`) and confirming a drawing/instance appears with no error.
- Commit GUIWorkspace (+ LiP only if a hook changed).

- [ ] **Task 2 — Aura VFX.** juju L19679–20320 (+ builders L19688–20108, asset loader L20111). Into `core/aura.lua` + `schema/aura.lua`. Port the 6 procedural aura builders verbatim + the 9 `rbxassetid` loaders; on `provider.localCharacter()` (re)apply: clone/re-parent emitters/beams/lights onto body parts, rename `"\0\0"`, recolor via `ColorSequence`. Schema: multiselect (15 + custom .rbxm), color+transparency. Verify: enable → emitters parented to LP.Character parts.

- [ ] **Task 3 — Hit Tracers (line + beam).** juju L13364–13547 (beams bank L13364, `do_line_bullet_tracer` L13460, `do_beam_bullet_tracer` L13438). Into `core/combat.lua` + `schema/combat.lua`. `line` = 2 Drawing Lines projected origin→hitPos + fade; `beam` = clone the textured Beam+2 Attachments onto Terrain + fade NumberSequence. Trigger `provider.onShot`. Schema: type{line,beam}, style{laser,light,flow}, colors, gradient, lifetime. Verify: `LIP.onShot:Fire(a,b,true)` → tracer.

- [ ] **Task 4 — Hitmarkers 2D + 3D.** juju L14965–15085 (3D) + L15089–15200 (2D). Into `core/combat.lua`. 8 Drawing Lines each; 3D projects `part.Position`, 2D at `ViewportSize/2`; lethal color from `onHit`'s lethal flag; fade. Schema: per-marker lifetime/thickness/colors/lethal/outline. Trigger `provider.onHit`. Verify: `LIP.onHit:Fire(plr,part,50,false)` → cross.

- [ ] **Task 5 — Damage Numbers.** juju L14875–14961. Into `core/combat.lua`. Drawing Text at hit part, rise `(0,1.5,0)`, ease-in→fade, lethal color, optional ragebot reason (skip if not available). Schema: font/lifetime/colors/outline/show-data. Trigger `provider.onHit` (uses damage). Verify: fire onHit → rising number.

- [ ] **Task 6 — Target Ring.** juju L22690+ (3D target circle). Into `core/combat.lua`. 32 Drawing Lines forming a world ring around `provider.target()` UpperTorso; radius bounding-box-fit; spin `(clock*speed)%2π`; `color3_lerp` comet-tail + per-seg transparency. Schema: color/gradient/thickness/speed/toggle. Driven per-frame while a target exists. Verify: set `LIP.target` → ring around it.

- [ ] **Task 7 — Hit Particles.** juju L14313–14820 (part+emitters L14316–14765, `do_hit_particle` L14770). Into `core/combat.lua`. One pooled anchored Part holding the 10 prebuilt ParticleEmitters; on `onHit` move to hit CFrame + `:Emit(count)`; `behind_walls`→ZOffset. Schema: particle preset (10 + custom .rbxm), behind-walls, color/lethal. Verify: fire onHit → emit burst at part.

- [ ] **Task 8 — Hit Chams.** juju L15204–15473 (`do_hit_chams` L15319, outline variant). Into `core/combat.lua`. Clone hit enemy Model, recolor MeshParts (Neon/ForceField, anchored, TextureID=""), grow+fade via `GV.Tween`/heartbeat; `only_last_hit` keeps one; outline variant = per-part SelectionBox. Schema: only-last-hit, animation{new fade,fade,none}, type{forcefield,outline,neon}, lifetime, color. Trigger `provider.onHit`. Verify: fire onHit against a live enemy → fading clone.

---

### Task 9: Rebuild bundle + full smoke + commit

- [ ] **Step 1:** Rebuild GUIWorkspace dist (both `primordial` + `claudeui` if the build does both) + sync + LiP `bundle.lua`. Expected `compila=true`, bytes grew, `LIP.Visuals` set, combat+aura categories present, no load errors.
- [ ] **Step 2:** Probe each signal once (`onShot`, `onHit`) + set a target; confirm no runtime errors across a few seconds (`get-console-output`).
- [ ] **Step 3:** Copy LiP root bundle back to Escritorio; commit LiP bundle. (Do NOT push/gist unless the user asks — they'll validate live-fire first.)
- [ ] **Step 4:** Hand off live-fire: user shoots an enemy → tracer+hitmarker+damage+particles+chams; enables an aura → self particles; ragebot target → ring.

---

## Self-Review

**Spec coverage:** Aura→T2, Tracers→T3, Hitmarkers→T4, DamageNumbers→T5, TargetRing→T6, HitParticles→T7, HitChams→T8; foundation (tween/profile/signals/scaffold/wiring)→T1; bundle→T9. All 8 Batch-1 features + enablers covered.

**Type consistency:** `GV.Tween(obj,props,easing,dur)`/`GV.tweenStep(now,dt)` (T1) used by all features. Provider `{localCharacter()->Model?, target()->Player?, onShot:Signal, onHit:Signal}` defined T1 Step 5, consumed T2–T8. `LIP.onShot:Fire(origin,hitPos,isLocal)` / `LIP.onHit:Fire(player,part,damage,lethal)` fired T1 Steps 3–4, consumed via provider T3–T8. Modules "combat"/"aura" registered T1 Step 6, added to Attach T1 Step 8.

**Placeholder scan:** feature tasks intentionally delegate exact code to the implementing subagent via named juju line-ranges (the 27k-line source can't be inlined here); each task names the precise range, the target file, the schema rows, the trigger, and a concrete signal-fire verification. No vague "add error handling"; the pattern block above defines the per-task procedure.

**Risk note:** Tasks 2–8 all edit `core/combat.lua` + `schema/combat.lua` (except T2 = aura files) → MUST run sequentially, not parallel, to avoid clobbering. Foundation (T1) is a hard prerequisite for all.
