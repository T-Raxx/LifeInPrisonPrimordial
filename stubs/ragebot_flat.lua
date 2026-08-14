-- STUB v2 del Ragebot (spec detallada del usuario). Solo UI. Árbol anidado: ragebot(master) →
-- TargetStrafe/AutoFire/Voidspam/Timer (dep ragebot) → sub-opciones (dep del padre). Silent Aim SEPARADO.
-- Col2 = Spam Resolver entero. Cargar: loadstring(readfile("LifeInPrisonPrimordial/stubs/ragebot_flat.lua"))()
local Lib = loadstring(readfile("PrimordialUI/dist/PrimordialUI.lua"))()
local Window = Lib:CreateWindow({ Title = "ragebot (stub v2)", Size = Vector2.new(834, 586) })
local Rage = Window:AddCategory("Rage", "crosshair")
local sec = Rage:AddSection("Ragebot", nil, { Columns = 2 })
local function dep(w, parent) if w and w.DependsOn then pcall(function() w:DependsOn(parent, true) end) end return w end

-- ═══ Col 1: RAGEBOT ═══
local p = sec:AddPanel("Ragebot", { Column = 1 })
p:AddToggle("Ragebot", { Text = "Ragebot", Default = false, Tooltip = "MASTER del ragebot" })
p:AddKeybind("RagebotKey", { Text = "Ragebot Key", Mode = "Toggle" })
-- Silent Aim SEPARADO del ragebot (autofire ya usa silent por default; esto es para mouse1 manual)
p:AddToggle("SilentAim", { Text = "Silent Aim (manual)", Default = true, Tooltip = "Silent aim al target en disparo manual. Separado del ragebot (el autofire ya lo usa)." })

-- ── Target Strafe (dep ragebot) ──
dep(p:AddToggle("TargetStrafe", { Text = "Target Strafe", Default = true }), "Ragebot")
p:AddKeybind("StrafeKey", { Text = "Strafe Key", Mode = "Toggle" })
dep(p:AddKeybind("SetTargetKey", { Text = "Set Target (crosshair)", Mode = "Toggle" }), "TargetStrafe")
dep(p:AddToggle("Spectate", { Text = "View Target", Default = false }), "TargetStrafe")
dep(p:AddButton("Clear Target", function() end), "TargetStrafe")
p:AddLabel("Server Position", { Header = true })
dep(p:AddToggle("PosSpoof", { Text = "Pos Spoof", Default = true }), "TargetStrafe")
dep(p:AddToggle("ConnExploit", { Text = "Connection Weld", Default = false }), "TargetStrafe")
dep(p:AddToggle("VoidViz", { Text = "Indicator", Default = true }), "TargetStrafe")
    :AddColorPicker("VizColor", { Default = Color3.fromRGB(202, 151, 161) })
dep(p:AddToggle("StrafeBait", { Text = "Bait", Default = false }), "TargetStrafe")
dep(p:AddDropdown("StrafeMode", { Text = "Mode", Values = { "Normal", "Random", "Behind", "Spiral", "Inside" }, Default = "Inside" }), "TargetStrafe")
dep(p:AddSlider("StrafeRadius", { Text = "Radius", Min = 0, Max = 150, Default = 10, Decimals = 1, Suffix = "st" }), "TargetStrafe")
dep(p:AddSlider("StrafeSpeed",  { Text = "Speed", Min = 1, Max = 40, Default = 4 }), "TargetStrafe")
dep(p:AddSlider("StrafeHeight", { Text = "Height", Min = -50, Max = 50, Default = 0 }), "TargetStrafe")

-- ── AutoFire (dep ragebot) ──
dep(p:AddToggle("AutoFire", { Text = "Auto Fire", Default = true, Tooltip = "Usa silent aim por default. Auto-reload pasivo (detecta escopeta SPAS/DB + ajusta al cargador del arma)." }), "Ragebot")
dep(p:AddSlider("AutoFireRate", { Text = "Max Rate", Min = 0, Max = 30, Default = 30, Decimals = 2, Suffix = "/s" }), "AutoFire")

-- ── Void Spam (dep ragebot) ──
dep(p:AddToggle("VoidSpam", { Text = "Void Spam", Default = false }), "Ragebot")
dep(p:AddSlider("VoidInTime", { Text = "In Void", Min = 0.01, Max = 2, Default = 0.4, Decimals = 2, Suffix = "s" }), "VoidSpam")
dep(p:AddSlider("VoidOutTime", { Text = "Out Of Void", Min = 0.01, Max = 2, Default = 0.13, Decimals = 2, Suffix = "s" }), "VoidSpam")
dep(p:AddDropdown("VoidPreset", { Text = "Void Preset", Values = { "Legit", "Jitter", "Peek", "Blink", "Chaos" }, Default = "Jitter" }), "VoidSpam")
dep(p:AddToggle("AntiDelta", { Text = "Anti Delta", Default = false }), "VoidSpam")
dep(p:AddToggle("VoidAutoTime", { Text = "Adjust Void To Shot Delay", Default = true }), "VoidSpam")
dep(p:AddToggle("VoidReload", { Text = "Idle Reload", Default = false }), "VoidSpam")

-- ── Timer (dep ragebot) ──
dep(p:AddToggle("Timer", { Text = "Timer", Default = false }), "Ragebot")
dep(p:AddSlider("TimerStatic", { Text = "Static Mult", Min = 1, Max = 3, Default = 1, Decimals = 2, Suffix = "x" }), "Timer")
dep(p:AddSlider("TimerOut", { Text = "Out Mult", Min = 1, Max = 3, Default = 2, Decimals = 2, Suffix = "x" }), "Timer")
dep(p:AddSlider("TimerReload", { Text = "Reload Mult", Min = 1, Max = 3, Default = 2, Decimals = 2, Suffix = "x" }), "Timer")

-- ── CFrame Desync + Idle State (mi colocación: dep ragebot, abajo) ──
dep(p:AddToggle("CFrameDesync", { Text = "CFrame Desync", Default = false }), "Ragebot")
dep(p:AddToggle("IdleState", { Text = "Idle State", Default = false }), "Ragebot")

-- ═══ Col 2: SPAM RESOLVER (entero, sin cambios) ═══
local r = sec:AddPanel("Spam Resolver", { Column = 2 })
r:AddToggle("Resolver", { Text = "Resolver", Default = true })
r:AddDropdown("ResolverMethod", { Text = "Method", Values = { "Cluster", "Density", "Centroid", "Auto" }, Default = "Centroid" })
r:AddToggle("VoidAutofire", { Text = "Void Autofire", Default = true })
r:AddToggle("FireResolved", { Text = "Fire on Resolved", Default = false })
r:AddSlider("PredictBase", { Text = "Predict Base", Min = 0, Max = 0.4, Default = 0.10, Decimals = 2, Suffix = "s" })
r:AddSlider("PredictAmp", { Text = "Predict Amp", Min = 0, Max = 0.4, Default = 0.15, Decimals = 2, Suffix = "s" })
r:AddSlider("PredictKill", { Text = "Predict Kill", Min = 0, Max = 1, Default = 0.25, Decimals = 2 })
r:AddSlider("LeadCap", { Text = "Lead Cap", Min = 60, Max = 1000, Default = 400, Suffix = "st/s" })
r:AddSlider("WeaponRange", { Text = "Weapon Range", Min = 30, Max = 300, Default = 125, Suffix = "st" })
r:AddToggle("WeaponClamp", { Text = "Weapon Clamp", Default = true })
r:AddLabel("Centroid", { Header = true })
r:AddSlider("CentroidWindow", { Text = "Cen Window", Min = 0.5, Max = 4, Default = 1.5, Decimals = 2, Suffix = "s" })
r:AddSlider("CentroidTrim", { Text = "Cen Trim", Min = 0, Max = 0.6, Default = 0.15, Decimals = 2, Suffix = "%" })
r:AddSlider("RRAccuracy", { Text = "Accuracy", Min = 0, Max = 1, Default = 0.5, Decimals = 2 })
r:AddSlider("VoidRange", { Text = "Void Range", Min = 7000, Max = 500000, Default = 50000, Suffix = "st" })

print("[STUB v2] Ragebot árbol anidado + Spam Resolver. Silent Aim separado, sin StrafePreset.")
