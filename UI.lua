-- UI.lua — FACTORY. Categorías Rage / Legit / Misc / Visuals. Paneles separados por función.
-- Flags en Lib.Toggles / Lib.Options.
return function(require, LIP, Lib)
    local UI = {}

    function UI.build(Window)
        local Ragdoll = require("Combat.Ragdoll")
        local Weapon  = require("Combat.Weapon")
        local Strafe  = require("Combat.Strafe")
        local Vehicle = require("Movement.Vehicle")
        local Void    = require("Movement.Void")
        local Util    = require("Combat.Utility")

        --========================= RAGE =========================--
        local Rage = Window:AddCategory("Rage", "crosshair")
        local RS = Rage:AddSection("Ragebot", "Silent aim · Rapid fire · Target strafe", { Columns = 3 })

        -- Col 1: Silent Aim
        local c1 = RS:AddPanel("Silent Aim", { Column = 1 })
        c1:AddToggle("SilentAim", { Text = "Silent Aim", Default = false,
            Tooltip = "op14 passive arg-swap al target. Cámara no se toca, GST intacto." })
        c1:AddDropdown("SelMode", { Text = "Selection", Values = { "Crosshair", "Distance", "Health" }, Default = "Crosshair" })
        c1:AddSlider("FOV", { Text = "FOV", Min = 0, Max = 500, Default = 150 })
        c1:AddToggle("Wallcheck", { Text = "Wallcheck", Default = false,
            Tooltip = "ON = solo con línea de vista" })
        c1:AddToggle("Wallbang", { Text = "Wallbang", Default = false,
            Tooltip = "Raycast target→vos, pone el origin del lado del target de la pared = LOS garantizada (atraviesa paredes)" })
        c1:AddToggle("AntiInvis", { Text = "Anti Invisible", Default = false })
        c1:AddDivider()
        c1:AddToggle("TeamCheck", { Text = "Team Check", Default = true })
        c1:AddToggle("FriendCheck", { Text = "Friend Check", Default = true })

        -- Col 2: Rapid Fire / Instant Reload / Auto Fire
        local c2 = RS:AddPanel("Firepower", { Column = 2 })
        c2:AddToggle("RapidFire", { Text = "Rapid Fire", Default = false,
            Tooltip = "Ráfaga extra de op14 al disparar (gate firerate es client-only)" })
        c2:AddSlider("RapidCount", { Text = "Burst Count", Min = 1, Max = 12, Default = 3 })
        c2:AddToggle("AutoFire", { Text = "Auto Fire", Default = false,
            Tooltip = "Dispara op14 al target automáticamente (interno, sin mouse1click)" })
        c2:AddSlider("AutoFireRate", { Text = "Auto Rate", Min = 0.05, Max = 1, Default = 0.15, Decimals = 2, Suffix = "s" })
        c2:AddSlider("FireRange", { Text = "Fire Range", Min = 20, Max = 500, Default = 200, Suffix = "studs",
            Tooltip = "No dispara si el target está más lejos (fuera de rango = server rechaza)" })
        c2:AddDivider()
        c2:AddButton("Force Reload", function() Weapon.instantReload() end)
        c2:AddKeybind("ReloadKey", { Text = "Reload Key", Mode = "Toggle", Callback = function() Weapon.instantReload() end })
        c2:AddSlider("ReloadAmmo", { Text = "Mag Size", Min = 1, Max = 120, Default = 15,
            Tooltip = "Balas por cargador de tu arma (fallback; se auto-detecta del reload real del juego)" })
        c2:AddSlider("ReloadTime", { Text = "Reload Time", Min = 0.3, Max = 3, Default = 1.2, Decimals = 1, Suffix = "s",
            Tooltip = "Espera antes del op40 (debe ~= duración de la anim de recarga, o el server rechaza)" })
        c2:AddToggle("ShotgunReload", { Text = "Shotgun Reload", Default = false,
            Tooltip = "Para escopetas (SPAS): op40 por bala en vez de uno solo (protocolo per-shell). Pistola/rifle = OFF." })

        -- Col 3: Target Strafe
        local c3 = RS:AddPanel("Target Strafe", { Column = 3 })
        c3:AddToggle("TargetStrafe", { Text = "Target Strafe", Default = false,
            Tooltip = "Desync: server te ve orbitando, cuerpo/cámara reales quietos (CFrame spoof)" })
        c3:AddKeybind("StrafeKey", { Text = "Strafe Key", Mode = "Toggle",
            Callback = function(a) local t = Lib.Toggles.TargetStrafe; if t then t:SetValue(a) end end })
        c3:AddDropdown("StrafePreset", { Text = "Preset", Values = { "Normal", "Random", "Behind" }, Default = "Normal",
            Callback = function(v) Strafe.applyPreset(v) end })
        c3:AddDropdown("StrafeMode", { Text = "Mode", Values = { "Normal", "Random", "Behind" }, Default = "Normal" })
        c3:AddSlider("StrafeRadius", { Text = "Radius", Min = 4, Max = 25, Default = 10, Decimals = 1, Suffix = "studs" })
        c3:AddSlider("StrafeSpeed",  { Text = "Speed", Min = 1, Max = 40, Default = 4 })
        c3:AddSlider("StrafeHeight", { Text = "Height", Min = -10, Max = 10, Default = 0 })
        c3:AddToggle("PosSpoof", { Text = "Pos Spoof (master)", Default = true,
            Tooltip = "MASTER de Strafe + Void. ON = desync (cuerpo/cámara reales quietos). OFF = mueve el cuerpo real." })
        c3:AddToggle("StrafeChase", { Text = "Dynamic Chase", Default = true,
            Tooltip = "Predice la pos del target por su velocidad (orbita su posición futura)" })
        c3:AddToggle("StrafeBait", { Text = "Bait", Default = false,
            Tooltip = "Invierte el sentido del strafe al azar (baitea el aim enemigo)" })
        c3:AddDivider()
        c3:AddKeybind("SetTargetKey", { Text = "Set Target (crosshair)", Mode = "Toggle",
            Callback = function() Strafe.pickCrosshair() end })
        c3:AddButton("Clear Target", function() Strafe.clearManual() end)
        c3:AddToggle("Spectate", { Text = "Spectate Target", Default = false,
            Tooltip = "Cámara al target manual; persiste en muerte/rejoin hasta cambiarlo" })

        -- Section propia: Resolver
        local RSR = Rage:AddSection("Resolver", "Spam resolver (anti cheaters)")
        local r1 = RSR:AddPanel("Resolver", { Column = 1 })
        r1:AddToggle("Resolver", { Text = "Spam Resolver", Default = false,
            Tooltip = "Resuelve el centro real del target vs strafe/fling enemigo" })
        r1:AddDropdown("ResolverMethod", { Text = "Method", Values = { "Median", "Weighted", "Average", "Latest" }, Default = "Median" })
        r1:AddSlider("ResolverSamples", { Text = "Samples", Min = 3, Max = 16, Default = 8 })
        r1:AddSlider("ResolverReject", { Text = "Reject Vel", Min = 50, Max = 1000, Default = 300, Suffix = "st/s",
            Tooltip = "Descarta muestras que saltan más rápido (fling/tp spoof)" })
        r1:AddSlider("ResolverPredict", { Text = "Predict", Min = 0, Max = 0.4, Default = 0.12, Decimals = 2, Suffix = "s",
            Tooltip = "Lead por velocidad del target (compensa ping/movimiento). 0 = off" })
        local r2 = RSR:AddPanel("Notes", { Column = 2 })
        r2:AddLabel("Median = robusto a extremos. Weighted = recientes pesan más. Predict = lead por velocidad.", {})

        -- Sección Void Spam (en Rage) — origen absoluto (0,100,0), random far cada frame
        local RSV = Rage:AddSection("Void Spam", "Anti-aim · origen absoluto (0,100,0)")
        local vd = RSV:AddPanel("Void Spam", { Column = 1 })
        vd:AddToggle("VoidSpam", { Text = "Void Spam", Default = false,
            Tooltip = "Origen absoluto (0,100,0), rotación XYZ random. Nunca toca el vacío (clamp Y). Usa el master Pos Spoof." })
        vd:AddDropdown("VoidPattern", { Text = "Pattern", Values = { "Random", "High", "Orbit", "Tween", "Teleport" }, Default = "Random" })
        vd:AddSlider("VoidDist", { Text = "Distance", Min = 100, Max = 5000, Default = 1000, Suffix = "studs" })
        vd:AddToggle("VoidViz", { Text = "Visualizer", Default = true, Tooltip = "Part + icono + tracer a la pos spoofeada" })

        --========================= LEGIT =========================--
        local Legit = Window:AddCategory("Legit", "target")
        local LS = Legit:AddSection("Legit", "Melee · Fists", { Columns = 2 })
        local l1 = LS:AddPanel("Melee", { Column = 1 })
        l1:AddToggle("MeleeAura", { Text = "Melee Aura", Default = false,
            Tooltip = "op16 passive: al golpear con arma melee, redirige el hit al enemigo cercano" })
        l1:AddSlider("MeleeRange", { Text = "Melee Range", Min = 4, Max = 30, Default = 12, Suffix = "studs" })
        local l2 = LS:AddPanel("Fists", { Column = 2 })
        l2:AddToggle("AutoPunch", { Text = "Auto Punch", Default = false,
            Tooltip = "op33 activo (puños, sin GST): golpea al enemigo cercano en rango" })
        l2:AddSlider("PunchRange", { Text = "Punch Range", Min = 4, Max = 30, Default = 8, Suffix = "studs" })

        --========================= MISC =========================--
        local Misc = Window:AddCategory("Misc", "wrench")
        local MS = Misc:AddSection("Movement", "Fly · Noclip · Speed · Vehicle", { Columns = 3 })
        local m1 = MS:AddPanel("Fly / Noclip", { Column = 1 })
        m1:AddToggle("Fly", { Text = "Fly", Default = false, Tooltip = "WASD + Space/Shift" })
        m1:AddKeybind("FlyKey", { Text = "Fly Key", Mode = "Toggle",
            Callback = function(a) local t = Lib.Toggles.Fly; if t then t:SetValue(a) end end })
        m1:AddSlider("FlySpeed", { Text = "Fly Speed", Min = 10, Max = 300, Default = 60 })
        m1:AddToggle("Noclip", { Text = "Noclip", Default = false })
        m1:AddKeybind("NoclipKey", { Text = "Noclip Key", Mode = "Toggle",
            Callback = function(a) local t = Lib.Toggles.Noclip; if t then t:SetValue(a) end end })
        local m2 = MS:AddPanel("Speed / Jump", { Column = 2 })
        m2:AddToggle("WalkSpeedOn", { Text = "WalkSpeed", Default = false, Tooltip = "Via buff op47 (AC-safe)" })
        m2:AddSlider("WalkSpeed", { Text = "Speed", Min = 16, Max = 200, Default = 40 })
        m2:AddToggle("JumpOn", { Text = "JumpHeight", Default = false, Tooltip = "Via buff op47 (base 7.2)" })
        m2:AddSlider("JumpHeight", { Text = "Jump", Min = 7, Max = 100, Default = 25 })
        m2:AddToggle("InfJump", { Text = "Infinite Jump", Default = false })
        local m3 = MS:AddPanel("Vehicle", { Column = 3 })
        m3:AddToggle("VehSpeedOn", { Text = "Vehicle Speed", Default = false })
        m3:AddSlider("VehSpeed", { Text = "Multiplier", Min = 1, Max = 20, Default = 5, Suffix = "x" })
        m3:AddButton("Vehicle Fling", function() Vehicle.fling() end)
        m3:AddSlider("VehFlingPower", { Text = "Fling Power", Min = 100, Max = 5000, Default = 800 })
        m3:AddButton("Sit Nearest", function() Vehicle.sitNearest() end)
        m3:AddSlider("SitRange", { Text = "Sit Range", Min = 10, Max = 150, Default = 40 })

        local VS = Misc:AddSection("Body & Utility", "Ragdoll · Godmode · Utility", { Columns = 2 })
        local v2 = VS:AddPanel("Self", { Column = 1 })
        v2:AddButton("Self Ragdoll", function() Ragdoll.toggle() end)
        v2:AddKeybind("RagdollKey", { Text = "Ragdoll Key", Mode = "Toggle", Callback = function() Ragdoll.toggle() end })
        v2:AddToggle("RagdollLock", { Text = "Permanent Ragdoll", Default = false })
        v2:AddToggle("Godmode", { Text = "Godmode (ragdoll)", Default = false,
            Tooltip = "Self-ragdoll + mueve el assembly lejos (hitbox real fuera). Dispara con AutoFire (op14 directo). WIP" })
        v2:AddDropdown("GodMode", { Text = "God Mode", Values = { "High", "Jitter" }, Default = "High" })
        v2:AddSlider("GodHeight", { Text = "God Height", Min = 50, Max = 500, Default = 150, Suffix = "studs" })
        local v3 = VS:AddPanel("Utility", { Column = 2 })
        v3:AddLabel("Join Team (op1)", { Header = true })
        v3:AddButton("Police", function() Util.joinTeam("Police") end)
        v3:AddButton("Criminals", function() Util.joinTeam("Criminals") end)
        v3:AddButton("Prisoners", function() Util.joinTeam("Prisoners") end)
        v3:AddButton("Neutral", function() Util.joinTeam("Neutral") end)
        v3:AddButton("Grab Tool (op12)", function() Util.grabNearest() end)
        v3:AddButton("Heal (op28)", function() Util.healSpam() end)

        --========================= VISUALS =========================--
        local Vis  = Window:AddCategory("Visuals", "eye")
        local VSec = Vis:AddSection("ESP", "Player ESP (R6, client-side)")
        local vp = VSec:AddPanel("ESP", { Column = 1 })
        vp:AddToggle("ESP", { Text = "Enabled", Default = false })
            :AddColorPicker("ESPVisibleColor", { Default = Color3.fromRGB(80, 255, 120) })
            :AddColorPicker("ESPHiddenColor",  { Default = Color3.fromRGB(255, 80, 80) })
        vp:AddToggle("ESPBox",      { Text = "Box" })
        vp:AddToggle("ESPName",     { Text = "Name" })
        vp:AddToggle("ESPHealth",   { Text = "Health bar" })
        vp:AddToggle("ESPDistance", { Text = "Distance" })
        vp:AddToggle("ESPTracer",   { Text = "Tracer" })
        vp:AddToggle("ESPSkeleton", { Text = "Skeleton" })
        vp:AddToggle("ESPChams",    { Text = "Chams (through walls)" })
        local vp2 = VSec:AddPanel("Filters", { Column = 2 })
        vp2:AddDropdown("TracerOrigin", { Text = "Tracer origin", Values = { "Bottom", "Center", "Top" }, Default = "Bottom" })
        vp2:AddSlider("ESPMaxDist",     { Text = "Max distance", Min = 50, Max = 2000, Default = 1000, Suffix = "m" })
        vp2:AddToggle("ESPTeamCheck",   { Text = "Team Check", Default = true })
        vp2:AddToggle("ESPFriendCheck", { Text = "Friend Check", Default = false })
    end

    return UI
end
