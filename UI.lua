-- UI.lua — FACTORY. Categorías/paneles PrimordialUI. Flags en Lib.Toggles / Lib.Options.
return function(require, LIP, Lib)
    local UI = {}

    function UI.build(Window)
        local Ragdoll = require("Combat.Ragdoll")
        local Weapon  = require("Combat.Weapon")
        local Vehicle = require("Movement.Vehicle")
        local Util    = require("Combat.Utility")

        --== Categoría COMBAT ==--
        local Combat = Window:AddCategory("Combat", "swords")
        local S = Combat:AddSection("Combat", "Ragdoll · Melee · Silent Aim", { Columns = 3 })

        --· Col 1: Self & Melee ·--
        local c1 = S:AddPanel("Self & Melee", { Column = 1 })
        c1:AddLabel("Self", { Header = true })
        c1:AddButton("Self Ragdoll", function() Ragdoll.toggle() end)
        c1:AddKeybind("RagdollKey", { Text = "Ragdoll Key", Mode = "Toggle",
            Callback = function() Ragdoll.toggle() end })
        c1:AddToggle("RagdollLock", { Text = "Permanent Ragdoll", Default = false,
            Tooltip = "Re-ragdolla al recuperarse (op23, event-driven, sin spam)" })
        c1:AddDivider()
        c1:AddLabel("Melee / Fists", { Header = true })
        c1:AddToggle("AutoPunch", { Text = "Auto Punch", Default = false,
            Tooltip = "op33 activo (puños, sin GST): golpea al enemigo más cercano en rango" })
        c1:AddSlider("PunchRange", { Text = "Punch Range", Min = 4, Max = 30, Default = 8, Suffix = "studs" })
        c1:AddToggle("MeleeAura", { Text = "Melee Aura", Default = false,
            Tooltip = "op16 passive: al golpear con arma melee, redirige el hit al enemigo más cercano" })
        c1:AddSlider("MeleeRange", { Text = "Melee Range", Min = 4, Max = 30, Default = 12, Suffix = "studs" })
        c1:AddDivider()
        c1:AddLabel("Firearm", { Header = true })
        c1:AddButton("Instant Reload", function() Weapon.instantReload() end)
        c1:AddKeybind("ReloadKey", { Text = "Reload Key", Mode = "Toggle",
            Callback = function() Weapon.instantReload() end })
        c1:AddSlider("ReloadAmmo", { Text = "Reload Ammo", Min = 1, Max = 120, Default = 30,
            Tooltip = "Valor de mag a mandar (op40). Ajusta por arma; el server debería clampear a magammo" })
        c1:AddToggle("RapidFire", { Text = "Rapid Fire", Default = false,
            Tooltip = "Ráfaga extra de op14 al target al disparar (salta el firerate, gate es client-only)" })
        c1:AddSlider("RapidCount", { Text = "Burst Count", Min = 1, Max = 12, Default = 3 })

        --· Col 2: Silent Aim ·--
        local c2 = S:AddPanel("Silent Aim", { Column = 2 })
        c2:AddToggle("SilentAim", { Text = "Silent Aim", Default = false,
            Tooltip = "op14 passive arg-swap: redirige los bullets al target. Cámara NO se toca, GST intacto." })
        c2:AddDropdown("SelMode", { Text = "Selection", Values = { "Crosshair", "Distance", "Health" }, Default = "Crosshair" })
        c2:AddSlider("FOV", { Text = "FOV (Crosshair)", Min = 0, Max = 500, Default = 150 })
        c2:AddToggle("Wallcheck", { Text = "Wallcheck", Default = false,
            Tooltip = "ON = solo redirige con línea de vista. OFF = WALLBANG (server confía en hitPart, no hace LOS check)" })
        c2:AddToggle("AntiInvis", { Text = "Anti Invisible", Default = false, Tooltip = "hitPos con offset -1.4 studs" })
        c2:AddToggle("Resolver", { Text = "Spam Resolver", Default = false,
            Tooltip = "Apunta al centro real del target (mediana de N frames) — resiste strafe/fling de cheaters enemigos" })
        c2:AddDivider()
        c2:AddLabel("Target Strafe", { Header = true })
        c2:AddToggle("TargetStrafe", { Text = "Target Strafe", Default = false,
            Tooltip = "Desync HvH: orbita al target escribiendo HRP.CFrame (AC no lo detecta). Difícil de pegarte." })
        c2:AddKeybind("StrafeKey", { Text = "Strafe Key", Mode = "Toggle",
            Callback = function(a) local t = Lib.Toggles.TargetStrafe; if t then t:SetValue(a) end end })
        c2:AddDropdown("StrafeMode", { Text = "Mode", Values = { "Normal", "Random", "Behind" }, Default = "Normal" })
        c2:AddSlider("StrafeRadius", { Text = "Radius", Min = 4, Max = 25, Default = 10, Suffix = "studs" })
        c2:AddSlider("StrafeSpeed",  { Text = "Speed", Min = 2, Max = 40, Default = 14 })
        c2:AddSlider("StrafeHeight", { Text = "Height", Min = -10, Max = 10, Default = 0 })

        --· Col 3: Target ·--
        local c3 = S:AddPanel("Target", { Column = 3 })
        c3:AddLabel("Filters", { Header = true })
        c3:AddToggle("TeamCheck", { Text = "Team Check", Default = true,
            Tooltip = "Ignora tu team (Police/Prisoners/Criminals)" })
        c3:AddToggle("FriendCheck", { Text = "Friend Check", Default = true })

        --== Categoría VISUALS (ESP) ==--
        local Vis  = Window:AddCategory("Visuals", "eye")
        local VSec = Vis:AddSection("ESP", "Player ESP (R6, client-side)")
        local vp = VSec:AddPanel("ESP", { Column = 1 })
        vp:AddToggle("ESP", { Text = "Enabled", Default = false, Tooltip = "Client-side, cero ban risk" })
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

        --== Categoría MOVEMENT ==--
        local Mov  = Window:AddCategory("Movement", "move")
        local MSec = Mov:AddSection("Movement", "Fly · Noclip · Speed")
        local m1 = MSec:AddPanel("Fly / Noclip", { Column = 1 })
        m1:AddToggle("Fly", { Text = "Fly", Default = false, Tooltip = "WASD + Space/Shift (arriba/abajo), mira con la cámara" })
        m1:AddKeybind("FlyKey", { Text = "Fly Key", Mode = "Toggle",
            Callback = function(a) local t = Lib.Toggles.Fly; if t then t:SetValue(a) end end })
        m1:AddSlider("FlySpeed", { Text = "Fly Speed", Min = 10, Max = 300, Default = 60, Suffix = "studs/s" })
        m1:AddToggle("Noclip", { Text = "Noclip", Default = false, Tooltip = "Atraviesa paredes (CanCollide=false)" })
        m1:AddKeybind("NoclipKey", { Text = "Noclip Key", Mode = "Toggle",
            Callback = function(a) local t = Lib.Toggles.Noclip; if t then t:SetValue(a) end end })
        local m2 = MSec:AddPanel("Speed / Jump", { Column = 2 })
        m2:AddToggle("WalkSpeedOn", { Text = "WalkSpeed", Default = false,
            Tooltip = "Via buff op47 (AC-safe). Escribir WalkSpeed crudo = auto-kill del AC." })
        m2:AddSlider("WalkSpeed", { Text = "Speed", Min = 16, Max = 200, Default = 40 })
        m2:AddToggle("JumpOn", { Text = "JumpHeight", Default = false, Tooltip = "Via buff op47 (base 7.2)" })
        m2:AddSlider("JumpHeight", { Text = "Jump", Min = 7, Max = 100, Default = 25 })
        m2:AddToggle("InfJump", { Text = "Infinite Jump", Default = false })

        local m3 = MSec:AddPanel("Vehicle", { Column = 3 })
        m3:AddLabel("Client-owned physics", { Header = true })
        m3:AddToggle("VehSpeedOn", { Text = "Vehicle Speed", Default = false,
            Tooltip = "Multiplica FastSpeed/FastTorque del vehículo (ocupante = network owner)" })
        m3:AddSlider("VehSpeed", { Text = "Multiplier", Min = 1, Max = 20, Default = 5, Suffix = "x" })
        m3:AddButton("Vehicle Fling", function() Vehicle.fling() end)
        m3:AddSlider("VehFlingPower", { Text = "Fling Power", Min = 100, Max = 5000, Default = 800 })
        m3:AddButton("Sit Nearest Seat", function() Vehicle.sitNearest() end)
        m3:AddSlider("SitRange", { Text = "Sit Range", Min = 10, Max = 150, Default = 40, Suffix = "studs" })

        --== Categoría UTILITY ==--
        local Ut   = Window:AddCategory("Utility", "wrench")
        local USec = Ut:AddSection("Utility", "Team · Remotes")
        local u1 = USec:AddPanel("Team", { Column = 1 })
        u1:AddLabel("Join Team (op1)", { Header = true })
        u1:AddButton("Police",    function() Util.joinTeam("Police") end)
        u1:AddButton("Criminals", function() Util.joinTeam("Criminals") end)
        u1:AddButton("Prisoners", function() Util.joinTeam("Prisoners") end)
        u1:AddButton("Neutral",   function() Util.joinTeam("Neutral") end)
        local u2 = USec:AddPanel("Remotes", { Column = 2 })
        u2:AddButton("Heal Tick (op28)", function() Util.healSpam() end)
        u2:AddKeybind("HealKey", { Text = "Heal Key", Mode = "Toggle",
            Callback = function() Util.healSpam() end })
        u2:AddButton("Grab Nearest Tool (op12)", function() Util.grabNearest() end)
    end

    return UI
end
