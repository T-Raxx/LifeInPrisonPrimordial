-- STUB visual del diseño "Flat" de la tab Rage consolidada. Solo UI (sin lógica) para aprobar el layout.
-- Master "Ragebot" + todos los sub-features como toggles planos que dependen de él. Resolver sin cambios.
-- Cargar: loadstring(readfile("LifeInPrisonPrimordial/stubs/ragebot_flat.lua"))()
local Lib = loadstring(readfile("PrimordialUI/dist/PrimordialUI.lua"))()
local Window = Lib:CreateWindow({ Title = "ragebot (stub · flat)", Size = Vector2.new(834, 586) })
local Rage = Window:AddCategory("Rage", "crosshair")
local sec = Rage:AddSection("Ragebot", nil, { Columns = 2 })

-- ── Col 1: RAGEBOT master + sub-toggles (todos DependsOn "Ragebot") ──
local p1 = sec:AddPanel("Ragebot", { Column = 1 })
p1:AddToggle("Ragebot", { Text = "Ragebot", Default = false,
    Tooltip = "MASTER. Enciende el ragebot; los sub-toggles de abajo dependen de esto." })
p1:AddKeybind("RagebotKey", { Text = "Ragebot Key", Mode = "Toggle" })
local function dep(w) if w and w.DependsOn then pcall(function() w:DependsOn("Ragebot", true) end) end return w end

p1:AddLabel("Aim", { Header = true })
dep(p1:AddToggle("SilentAim", { Text = "Silent Aim", Default = true, Tooltip = "Apunta al hitPart del target" }))
dep(p1:AddSlider("AimFOV", { Text = "FOV", Min = 0, Max = 500, Default = 120, Suffix = "px" }))
dep(p1:AddDropdown("Hitbox", { Text = "Hitbox", Values = { "Head", "Torso", "Nearest" }, Default = "Head" }))
dep(p1:AddToggle("AutoFire", { Text = "Auto Fire", Default = true }))
dep(p1:AddToggle("RapidFire", { Text = "Rapid Fire", Default = false }))
dep(p1:AddToggle("Wallbang", { Text = "Wallbang", Default = false }))

p1:AddLabel("Desync / Anti-Aim", { Header = true })
dep(p1:AddToggle("TargetStrafe", { Text = "Target Strafe", Default = true }))
dep(p1:AddDropdown("StrafeMode", { Text = "Mode", Values = { "Normal", "Random", "Behind", "Spiral", "Inside" }, Default = "Inside" }))
dep(p1:AddSlider("StrafeRadius", { Text = "Radius", Min = 0, Max = 150, Default = 10, Suffix = "st" }))
dep(p1:AddToggle("VoidSpam", { Text = "Void Spam", Default = false }))
dep(p1:AddDropdown("VoidPreset", { Text = "Void Preset", Values = { "Legit", "Jitter", "Peek", "Blink", "Chaos" }, Default = "Jitter" }))
dep(p1:AddToggle("AntiDelta", { Text = "Anti Delta", Default = false }))
dep(p1:AddToggle("CFrameDesync", { Text = "CFrame Desync", Default = false }))

p1:AddLabel("Fire Boost / Defense", { Header = true })
dep(p1:AddToggle("Timer", { Text = "Timer (rapidfire)", Default = false }))
dep(p1:AddSlider("TimerOut", { Text = "Out Mult", Min = 1, Max = 3, Default = 2, Decimals = 2, Suffix = "x" }))
dep(p1:AddToggle("AntiTaze", { Text = "Anti Taze / Ragdoll", Default = false }))

-- ── Col 2: RESOLVER (sin cambios) ──
local p2 = sec:AddPanel("Resolver", { Column = 2 })
p2:AddToggle("Resolver", { Text = "Resolver", Default = true })
p2:AddDropdown("ResolverMethod", { Text = "Method", Values = { "Cluster", "Density", "Centroid", "Auto" }, Default = "Centroid" })
p2:AddToggle("VoidAutofire", { Text = "Void Autofire", Default = true })
p2:AddSlider("RRAccuracy", { Text = "Accuracy", Min = 0, Max = 1, Default = 0.5, Decimals = 2 })
p2:AddSlider("PredictKill", { Text = "Predict Kill", Min = 0, Max = 1, Default = 0.25, Decimals = 2 })
p2:AddSlider("WeaponRange", { Text = "Weapon Range", Min = 30, Max = 300, Default = 125, Suffix = "st" })
p2:AddToggle("WeaponClamp", { Text = "Weapon Clamp", Default = true })
p2:AddLabel("Centroid", { Header = true })
p2:AddSlider("CentroidWindow", { Text = "Cen Window", Min = 0.5, Max = 4, Default = 1.5, Decimals = 2, Suffix = "s" })
p2:AddSlider("CentroidTrim", { Text = "Cen Trim", Min = 0, Max = 0.6, Default = 0.15, Decimals = 2, Suffix = "%" })

print("[STUB] Ragebot Flat cargado. Master + sub-toggles (DependsOn) | Resolver aparte.")
