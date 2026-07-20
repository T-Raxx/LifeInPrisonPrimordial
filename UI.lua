-- UI.lua — FACTORY. Categorías/paneles PrimordialUI. Flags en Lib.Toggles / Lib.Options.
return function(require, LIP, Lib)
    local UI = {}

    function UI.build(Window)
        local Ragdoll = require("Combat.Ragdoll")

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

        --· Col 2: Silent Aim ·--
        local c2 = S:AddPanel("Silent Aim", { Column = 2 })
        c2:AddToggle("SilentAim", { Text = "Silent Aim", Default = false,
            Tooltip = "op14 passive arg-swap: redirige los bullets al target. Cámara NO se toca, GST intacto." })
        c2:AddDropdown("SelMode", { Text = "Selection", Values = { "Crosshair", "Distance", "Health" }, Default = "Crosshair" })
        c2:AddSlider("FOV", { Text = "FOV (Crosshair)", Min = 0, Max = 500, Default = 150 })
        c2:AddToggle("Wallcheck", { Text = "Wallcheck", Default = false,
            Tooltip = "Solo redirige si hay línea de vista al target (evita tiros inválidos)" })
        c2:AddToggle("AntiInvis", { Text = "Anti Invisible", Default = false, Tooltip = "hitPos con offset -1.4 studs" })

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
        m2:AddToggle("WalkSpeedOn", { Text = "WalkSpeed", Default = false })
        m2:AddSlider("WalkSpeed", { Text = "Speed", Min = 16, Max = 200, Default = 32 })
        m2:AddToggle("JumpOn", { Text = "JumpPower", Default = false })
        m2:AddSlider("JumpPower", { Text = "Jump", Min = 50, Max = 300, Default = 80 })
        m2:AddToggle("InfJump", { Text = "Infinite Jump", Default = false })
    end

    return UI
end
