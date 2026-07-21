-- UI.lua — FACTORY. Categorías Rage / Legit / Misc / Visuals. Paneles separados por función.
-- Flags en Lib.Toggles / Lib.Options.
return function(require, LIP, Lib)
    local UI = {}

    function UI.build(Window)
        local Ragdoll = require("Combat.Ragdoll")
        local Weapon  = require("Combat.Weapon")
        local Strafe  = require("Combat.Strafe")
        local Godmode = require("Combat.Godmode")
        local Niche   = require("Combat.Niche")
        local Vehicle = require("Movement.Vehicle")
        local Void    = require("Movement.Void")
        local Util    = require("Combat.Utility")

        --========================= RAGE =========================--
        -- UNA sección con 3 columnas; cajas apiladas (estilo symbol: todas visibles a la vez).
        local Rage = Window:AddCategory("Rage", "crosshair")
        local RS = Rage:AddSection("Rage", "Aimbot · Strafe · Resolver · Void", { Columns = 3 })

        --== Col 1: Silent Aim + Resolver ==--
        local c1 = RS:AddPanel("Silent Aim", { Column = 1 })
        c1:AddToggle("SilentAim", { Text = "Silent Aim", Default = false,
            Tooltip = "op14 passive arg-swap al target. Cámara no se toca, GST intacto." })
        c1:AddDropdown("SelMode", { Text = "Selection", Values = { "Crosshair", "Distance", "Health" }, Default = "Crosshair" })
        c1:AddSlider("FOV", { Text = "FOV", Min = 0, Max = 500, Default = 150 })
        c1:AddToggle("Wallcheck", { Text = "Wallcheck", Default = false, Tooltip = "ON = solo con línea de vista" })
        c1:AddToggle("Wallbang", { Text = "Wallbang", Default = false,
            Tooltip = "Origin del lado del target de la pared = LOS garantizada (atraviesa paredes)" })
        c1:AddToggle("TeamCheck", { Text = "Team Check", Default = true })
        c1:AddToggle("FriendCheck", { Text = "Friend Check", Default = true })

        local rp = RS:AddPanel("Resolver", { Column = 1 })
        rp:AddToggle("Resolver", { Text = "Spam Resolver", Default = false,
            Tooltip = "Resuelve el centro REAL del target (el strafe orbita ahí, no su jitter)" })
        rp:AddDropdown("ResolverMethod", { Text = "Method", Values = { "Median", "Weighted", "Average", "Latest" }, Default = "Median" })
        rp:AddSlider("ResolverSamples", { Text = "Samples", Min = 3, Max = 20, Default = 12 })
        rp:AddSlider("ResolverReject", { Text = "Reject Vel", Min = 50, Max = 1000, Default = 300, Suffix = "st/s",
            Tooltip = "Descarta muestras que saltan más rápido (fling/tp spoof)" })
        rp:AddSlider("ResolverPredict", { Text = "Predict", Min = 0, Max = 0.4, Default = 0.12, Decimals = 2, Suffix = "s",
            Tooltip = "Lead por velocidad (compensa el delay de replicación). 0 = off" })

        --== Col 2: Firepower + Void Spam ==--
        local c2 = RS:AddPanel("Firepower", { Column = 2 })
        c2:AddToggle("RapidFire", { Text = "Rapid Fire", Default = false,
            Tooltip = "Stream de op14 mientras mantenés mouse1, al Fire Rate. GST forjado = sin unequip." })
        c2:AddToggle("AutoFire", { Text = "Auto Fire", Default = false,
            Tooltip = "Dispara al target auto (sin click). SOLO con Target Strafe ON." })
        c2:AddSlider("AutoFireRate", { Text = "Fire Rate", Min = 1, Max = 120, Default = 40, Suffix = "/s",
            Tooltip = "Disparos por segundo REALES. El GST forjado hace que el server los vea con espaciado legal → sin unequip aunque dispares 120/s." })
        c2:AddSlider("FakeFirerate", { Text = "Faked Rate", Min = 0.05, Max = 0.5, Default = 0.11, Decimals = 2, Suffix = "s",
            Tooltip = "Espaciado LEGAL que finge el GST (≥ firerate real del arma). Se auto-usa el firerate observado si recalibrás con un disparo manual." })
        c2:AddSlider("FireRange", { Text = "Fire Range", Min = 20, Max = 500, Default = 200, Suffix = "studs" })
        c2:AddDivider()
        c2:AddButton("Force Reload", function() Weapon.instantReload() end)
        c2:AddKeybind("ReloadKey", { Text = "Reload Key", Mode = "Toggle", Callback = function() Weapon.instantReload() end })
        c2:AddSlider("ReloadAmmo", { Text = "Mag Size", Min = 1, Max = 120, Default = 15,
            Tooltip = "Cargador de tu arma (se auto-detecta si recargás con R 1 vez)" })
        c2:AddSlider("ReloadTime", { Text = "Reload Time", Min = 0.3, Max = 3, Default = 1.2, Decimals = 1, Suffix = "s" })
        c2:AddToggle("ShotgunReload", { Text = "Shotgun Reload", Default = false, Tooltip = "Escopeta: op40 por bala. Pistola/rifle = OFF." })

        local vd = RS:AddPanel("Void Spam", { Column = 2 })
        vd:AddToggle("VoidSpam", { Text = "Void Spam", Default = false,
            Tooltip = "Origen absoluto (0,100,0), rotación XYZ random. Nunca toca el vacío. Usa Pos Spoof/Conn Weld." })
        vd:AddList("VoidPattern", { Values = { "Random", "High", "Orbit", "Tween", "Teleport" }, Default = "Random" })
        vd:AddSlider("VoidDist", { Text = "Distance", Min = 100, Max = 5000, Default = 1000, Suffix = "studs" })

        --== Col 3: Target Strafe + Server Position ==--
        local ts = RS:AddPanel("Target Strafe", { Column = 3 })
        ts:AddToggle("TargetStrafe", { Text = "Target Strafe", Default = false,
            Tooltip = "Desync: el server te ve orbitando; cuerpo/cámara reales quietos" })
        ts:AddKeybind("StrafeKey", { Text = "Strafe Key", Mode = "Toggle",
            Callback = function(a) local t = Lib.Toggles.TargetStrafe; if t then t:SetValue(a) end end })
        ts:AddDropdown("StrafePreset", { Text = "Preset", Values = { "Normal", "Random", "Behind" }, Default = "Normal",
            Callback = function(v) Strafe.applyPreset(v) end })
        ts:AddDropdown("StrafeMode", { Text = "Mode", Values = { "Normal", "Random", "Behind" }, Default = "Normal" })
        ts:AddSlider("StrafeRadius", { Text = "Radius", Min = 4, Max = 25, Default = 10, Decimals = 1, Suffix = "studs" })
        ts:AddSlider("StrafeSpeed",  { Text = "Speed", Min = 1, Max = 40, Default = 4 })
        ts:AddSlider("StrafeHeight", { Text = "Height", Min = -10, Max = 10, Default = 0 })
        ts:AddToggle("StrafeBait", { Text = "Bait", Default = false,
            Tooltip = "Cada 1-3s (random) salta a un spot random por 0.3s" })
        ts:AddDivider()
        ts:AddKeybind("SetTargetKey", { Text = "Set Target (crosshair)", Mode = "Toggle",
            Callback = function() Strafe.pickCrosshair() end })
        ts:AddButton("Clear Target", function() Strafe.clearManual() end)
        ts:AddToggle("Spectate", { Text = "Spectate Target", Default = false })

        local sp = RS:AddPanel("Server Position", { Column = 3 })
        sp:AddToggle("PosSpoof", { Text = "Pos Spoof", Default = true,
            Tooltip = "Método master. ON = desync (cuerpo real quieto). OFF = mueve el cuerpo real." })
        sp:AddToggle("ConnExploit", { Text = "Connection Weld", Default = false,
            Tooltip = "PhysicsRepRootPart weld (solo pos, sin rotación). Cuerpo REAL libre. Override de Pos Spoof." })
        sp:AddToggle("VoidViz", { Text = "Indicator", Default = true, Tooltip = "Part + icono + tracer a la pos que ve el server" })
            :AddColorPicker("VizColor", { Default = Color3.fromRGB(202, 151, 161) })

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
            Tooltip = "Self-ragdoll + mueve el assembly lejos (hitbox real fuera). Dispará con AutoFire (op14 directo bypasea el gate de ragdoll). Equipá el arma ANTES." })
        v2:AddDropdown("GodPreset", { Text = "Preset", Values = { "High", "ExtremeHigh", "Jitter", "FarJitter" }, Default = "High",
            Callback = function(v) Godmode.applyPreset(v) end })
        v2:AddDropdown("GodMode", { Text = "Mode", Values = { "High", "Jitter" }, Default = "High" })
        v2:AddSlider("GodHeight", { Text = "God Height", Min = 50, Max = 1500, Default = 150, Suffix = "studs" })
        local v3 = VS:AddPanel("Utility", { Column = 2 })
        v3:AddLabel("Join Team (op1)", { Header = true })
        v3:AddButton("Police", function() Util.joinTeam("Police") end)
        v3:AddButton("Criminals", function() Util.joinTeam("Criminals") end)
        v3:AddButton("Prisoners", function() Util.joinTeam("Prisoners") end)
        v3:AddButton("Neutral", function() Util.joinTeam("Neutral") end)
        v3:AddButton("Grab Tool (op12)", function() Util.grabNearest() end)
        v3:AddButton("Heal (op28)", function() Util.healSpam() end)
        v3:AddDivider()
        v3:AddLabel("Niche", { Header = true })
        v3:AddToggle("AutoThrow", { Text = "Auto Throw (op43)", Default = false,
            Tooltip = "Lanza el throwable equipado (granada/cuchillo) al enemigo cercano" })
        v3:AddToggle("AutoArrest", { Text = "Auto Arrest (op57)", Default = false,
            Tooltip = "Esposa al enemigo cercano (necesita Handcuffs; Police). Validación 8-studs es client-side" })
        v3:AddButton("Detonate C4 (op44)", function() Niche.detonateC4() end)

        --========================= VISUALS =========================--
        local Vis  = Window:AddCategory("Visuals", "eye")
        local VSec = Vis:AddSection("ESP", "Player ESP (R6, client-side) · todo coloreable", { Columns = 2 })
        local vp = VSec:AddPanel("Elements", { Column = 1 })
        vp:AddToggle("ESP", { Text = "Enabled", Default = false })
        vp:AddToggle("ESPBox", { Text = "Box (LOS color)" })
            :AddColorPicker("ESPVisibleColor", { Default = Color3.fromRGB(80, 255, 120) })
            :AddColorPicker("ESPHiddenColor",  { Default = Color3.fromRGB(255, 80, 80) })
        vp:AddToggle("ESPName", { Text = "Name" }):AddColorPicker("ESPNameColor", { Default = Color3.fromRGB(255, 255, 255) })
        vp:AddToggle("ESPDistance", { Text = "Distance" }):AddColorPicker("ESPDistColor", { Default = Color3.fromRGB(220, 220, 220) })
        vp:AddToggle("ESPHealth", { Text = "Health bar" })
        vp:AddToggle("ESPTracer", { Text = "Tracer" }):AddColorPicker("ESPTracerColor", { Default = Color3.fromRGB(255, 255, 255) })
        vp:AddToggle("ESPSkeleton", { Text = "Skeleton" }):AddColorPicker("ESPSkeletonColor", { Default = Color3.fromRGB(255, 255, 255) })
        vp:AddToggle("ESPChams", { Text = "Chams (through walls)" }):AddColorPicker("ESPChamsOutline", { Default = Color3.fromRGB(255, 255, 255) })
        local vp2 = VSec:AddPanel("Filters", { Column = 2 })
        vp2:AddDropdown("TracerOrigin", { Text = "Tracer origin", Values = { "Bottom", "Center", "Top" }, Default = "Bottom" })
        vp2:AddSlider("ESPMaxDist", { Text = "Max distance", Min = 0, Max = 5000, Default = 0, Suffix = "m",
            Tooltip = "0 = SIN LÍMITE" })
        vp2:AddToggle("ESPTeamCheck",   { Text = "Team Check", Default = true })
        vp2:AddToggle("ESPFriendCheck", { Text = "Friend Check", Default = false })
    end

    return UI
end
