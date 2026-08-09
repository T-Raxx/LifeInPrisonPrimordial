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
        local AutoWeapons = require("Combat.AutoWeapons")
        local HitFX   = require("Visuals.HitEffects")

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
        c1:AddToggle("FFCheck", { Text = "ForceField Check", Default = true,
            Tooltip = "Si el target tiene ForceField (spawn protection) o murió → te escondés (idle) y no disparás hasta que respawnee / se le quite el FF. Ignore temporal." })

        local rp = RS:AddPanel("Resolver", { Column = 1 })
        rp:AddToggle("Resolver", { Text = "Spam Resolver", Default = false,
            Tooltip = "Resuelve el centro REAL del target (el strafe orbita ahí, no su jitter)" })
        rp:AddDropdown("ResolverMethod", { Text = "Method", Values = { "Cluster", "Median", "Weighted", "Average", "Latest" }, Default = "Cluster" })
        rp:AddSlider("ResolverSamples", { Text = "Samples", Min = 3, Max = 20, Default = 12 })
        rp:AddSlider("ResolverReject", { Text = "Reject Vel", Min = 50, Max = 1000, Default = 300, Suffix = "st/s",
            Tooltip = "Descarta muestras que saltan más rápido (fling/tp spoof)" })
        rp:AddSlider("ResolverPredict", { Text = "Predict", Min = 0, Max = 0.4, Default = 0.12, Decimals = 2, Suffix = "s",
            Tooltip = "Lead por velocidad (compensa el delay de replicación). 0 = off" })
        rp:AddSlider("ResolverRate", { Text = "Resolver Rate", Min = 0, Max = 0.1, Default = 0.037, Decimals = 4, Suffix = "s",
            Tooltip = "Intervalo de muestreo de velocidad (juju 0.037). Chico = fresco/ruidoso, grande = suave/laggy." })
        rp:AddDropdown("PredMode", { Text = "Prediction", Values = { "Auto", "Manual" }, Default = "Auto",
            Tooltip = "Auto = lead por ping (ping·2). Manual = usa Pred Lead." })
        rp:AddSlider("PredLead", { Text = "Pred Lead", Min = 0, Max = 0.4, Default = 0.12, Decimals = 2, Suffix = "s",
            Tooltip = "Lead manual (segundos de velocidad adelantada). Solo con Prediction = Manual." })
        rp:AddToggle("FireResolved", { Text = "Fire on Resolved", Default = false,
            Tooltip = "HARMONÍA: el autofire dispara a la pos RESUELTA (no al head crudo) cuando el resolver está confiado (didDefensive). RIESGO HBE (fuera del hitbox del ghost). OFF = HBE-safe." })
        -- Config del Cluster resolver (juju-style). Solo aplica con Method = Cluster.
        local RP = Strafe.RParams
        rp:AddLabel("Cluster Resolver", { Header = true })
        rp:AddSlider("RRPosWeight", { Text = "Position Trust", Min = 0.1, Max = 5, Default = 1.5, Decimals = 2,
            Callback = function(v) if RP then RP.posWeight = v end end })
        rp:AddSlider("RRVoidWeight", { Text = "Void Trust", Min = 0.1, Max = 5, Default = 0.2, Decimals = 2,
            Tooltip = "Confianza en posiciones void (magnitud enorme). Baja = ignora void spam",
            Callback = function(v) if RP then RP.voidWeight = v end end })
        rp:AddSlider("RRForget", { Text = "Forget Rate", Min = 0, Max = 1000, Default = 80, Suffix = "%",
            Callback = function(v) if RP then RP.forget = v end end })
        rp:AddSlider("RRDistPenalty", { Text = "Distance Penalty", Min = 0, Max = 5, Default = 2, Decimals = 1, Suffix = "x",
            Callback = function(v) if RP then RP.distPenalty = v end end })
        rp:AddSlider("RRAccuracy", { Text = "Accuracy (gate)", Min = 0.4, Max = 3, Default = 1.35, Decimals = 2,
            Tooltip = "Confianza mínima para lockear un cluster. Alto = más certeza, menos tiros",
            Callback = function(v) if RP then RP.accuracy = v end end })
        rp:AddSlider("RRLerp", { Text = "Lerp", Min = 0.1, Max = 1, Default = 0.1, Decimals = 2,
            Callback = function(v) if RP then RP.lerp = v end end })

        --== Col 2: Firepower + Void Spam ==--
        local c2 = RS:AddPanel("Firepower", { Column = 2 })
        c2:AddToggle("MultiFire", { Text = "Bullet Multiplier", Default = false,
            Tooltip = "Padea el array de balas del op14 (del juego Y nuestro) a N pellets → N× daño POR disparo legal. Este es el rapidfire real (el server rate-limita disparar rápido, pero NO cuántas balas por disparo)." })
        c2:AddSlider("BulletMult", { Text = "Bullets/Shot", Min = 1, Max = 20, Default = 6,
            Tooltip = "Cuántas balas mete cada disparo. Sube el daño por disparo. También arregla escopetas (autofire necesita varios pellets)." })
        c2:AddToggle("RapidFire", { Text = "Rapid Fire", Default = false,
            Tooltip = "Stream de op14 mientras mantenés mouse1, CAPEADO al firerate del arma (exceder = unequip). El daño extra viene del Bullet Multiplier, no de disparar más rápido." })
        c2:AddToggle("AutoFire", { Text = "Auto Fire", Default = false,
            Tooltip = "Dispara al target auto (sin click). SOLO con Target Strafe ON. Capeado al firerate." })
        c2:AddSlider("AutoFireRate", { Text = "Fire Rate Cap", Min = 1, Max = 120, Default = 120, Suffix = "/s",
            Tooltip = "TOPE manual opcional. El autofire ya obedece el firerate REAL del arma (mantené mouse1 1 vez para calibrarlo). Bajá esto solo si querés disparar más lento. El DPS lo da el Bullet Multiplier." })
        c2:AddToggle("AutoReload", { Text = "Auto Reload", Default = true,
            Tooltip = "Recarga sola al agotar el cargador (op42→espera ReloadTime→op40, timing real). Solo en Auto Fire." })
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
            Tooltip = "SOLO con Target Strafe ON. Oscila OUT (strafe-orbit al target, disparás) ↔ IN void (server te ve lejos, esconde, disparo pausado). Rompe el resolver de PREDICCIÓN enemigo. Con Void Reload: fuerza el void durante toda la recarga (recargás escondido)." })
        vd:AddSlider("VoidInTime", { Text = "In Void", Min = 0.1, Max = 2, Default = 0.4, Decimals = 2, Suffix = "s",
            Tooltip = "Tiempo escondido en el void (disparo pausado)" })
        vd:AddSlider("VoidOutTime", { Text = "Out Void", Min = 0.1, Max = 2, Default = 0.3, Decimals = 2, Suffix = "s",
            Tooltip = "Tiempo en tu pos real (disparás desde acá)" })
        vd:AddToggle("VoidShootOut", { Text = "Shoot Out Only", Default = true,
            Tooltip = "Solo dispara OUT del void; pausa el disparo mientras estás IN void." })
        vd:AddToggle("VoidReload", { Text = "Void Reload", Default = false,
            Tooltip = "Recarga el arma mientras estás IN void (escondido) cuando el cargador se agota." })
        vd:AddList("VoidPattern", { Values = { "Random", "High", "Orbit", "Tween", "Teleport" }, Default = "Random" })
        vd:AddSlider("VoidDist", { Text = "Distance", Min = 100, Max = 5000, Default = 1000, Suffix = "studs" })

        --== Col 3: Target Strafe + Server Position ==--
        local ts = RS:AddPanel("Target Strafe", { Column = 3 })
        ts:AddToggle("TargetStrafe", { Text = "Target Strafe", Default = false,
            Tooltip = "Desync: el server te ve orbitando; cuerpo/cámara reales quietos" })
        ts:AddKeybind("StrafeKey", { Text = "Strafe Key", Mode = "Toggle",
            Callback = function(a) local t = Lib.Toggles.TargetStrafe; if t then t:SetValue(a) end end })
        ts:AddDropdown("StrafePreset", { Text = "Preset", Values = { "Normal", "Random", "Behind", "Spiral" }, Default = "Normal",
            Callback = function(v) Strafe.applyPreset(v) end })
        ts:AddDropdown("StrafeMode", { Text = "Mode", Values = { "Normal", "Random", "Behind", "Spiral" }, Default = "Normal" })
        ts:AddSlider("StrafeRadius", { Text = "Radius", Min = 4, Max = 150, Default = 10, Decimals = 1, Suffix = "studs" })
        ts:AddSlider("StrafeSpeed",  { Text = "Speed", Min = 1, Max = 40, Default = 4 })
        ts:AddSlider("StrafeHeight", { Text = "Height", Min = -50, Max = 50, Default = 0 })
        ts:AddToggle("StrafeBait", { Text = "Bait", Default = false,
            Tooltip = "Cada 1-3s (random) salta a un spot random por 0.3s" })
        ts:AddDivider()
        ts:AddKeybind("SetTargetKey", { Text = "Set Target (crosshair)", Mode = "Toggle",
            Callback = function() Strafe.pickCrosshair() end })
        ts:AddButton("Clear Target", function() Strafe.clearManual() end)
        ts:AddToggle("Spectate", { Text = "Spectate Target", Default = false })

        local sp = RS:AddPanel("Server Position", { Column = 3 })
        sp:AddToggle("PosSpoof", { Text = "Pos Spoof", Default = true,
            Tooltip = "ON = desync (cuerpo real quieto). Con Connection Weld ON = ancla la cámara a tu pos real (vista estable, harmonía). OFF (solo desync) = mueve el cuerpo real." })
        sp:AddToggle("ConnExploit", { Text = "Connection Weld", Default = false,
            Tooltip = "WELD real al target: tu cuerpo se pega a él (target.CFrame*offset, sigue rotación) + PhysicsRepRootPart = su HRP → replica SIN delay ni flicker. Es el método de posición (ignora Pos Spoof). Radius = distancia atrás/órbita (sin fling)." })
        sp:AddToggle("VoidViz", { Text = "Indicator", Default = true, Tooltip = "Part + icono + tracer a la pos que ve el server" })
            :AddColorPicker("VizColor", { Default = Color3.fromRGB(202, 151, 161) })

        local idl = RS:AddPanel("Idle State", { Column = 3 })
        idl:AddToggle("IdleState", { Text = "Idle State", Default = false,
            Tooltip = "Anti-aim CONTINUO (no dispara): el server te ve teleportando lejos con el pattern todo el tiempo. Para esconderte cuando NO estás tirando. (Antes se llamaba Void Spam.)" })
        idl:AddList("IdlePattern", { Values = { "Random", "High", "Orbit", "Tween", "Teleport" }, Default = "Random" })
        idl:AddSlider("IdleDist", { Text = "Distance", Min = 100, Max = 5000, Default = 1000, Suffix = "studs" })

        local hud = RS:AddPanel("Crosshair HUD", { Column = 3 })
        hud:AddToggle("CrossHUD", { Text = "Crosshair HUD", Default = true,
            Tooltip = "Labels de estado del ragebot abajo del crosshair (killing: user | Resolved: x.xyz; overrides: Reloading In Void / Killed waiting). Font del watermark. 1.000=full resuelto (tiro seguro), 0.000=tiro difícil." })
            :AddColorPicker("CrossHUDColor", { Default = Color3.fromRGB(202, 151, 161) })
        hud:AddToggle("CrossHUDFade", { Text = "Color Wave", Default = true,
            Tooltip = "Ola de color: una banda de brillo recorre las letras (en vez de fade de transparencia alpha)." })
        hud:AddSlider("CrossHUDFadeSpeed", { Text = "Wave Speed", Min = 1, Max = 20, Default = 6, Decimals = 1,
            Tooltip = "Velocidad de la ola de color." })
        hud:AddSlider("CrossHUDSize", { Text = "Text Size", Min = 10, Max = 28, Default = 16 })
        hud:AddSlider("CrossHUDOffset", { Text = "Y Offset", Min = 10, Max = 120, Default = 34, Suffix = "px",
            Tooltip = "Distancia abajo del centro del crosshair." })

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

        -- Auto Weapons: teleport a un pickup suelto + grab (op12) + volver. Multi-select con búsqueda.
        local AW = Misc:AddSection("Auto Weapons", "Recoge armas sueltas del mapa (teleport + grab)", { Columns = 2 })
        local aw1 = AW:AddPanel("Auto Weapons", { Column = 1 })
        aw1:AddToggle("AutoWeapons", { Text = "Auto Weapons", Default = false,
            Tooltip = "Va al pickup de un arma seleccionada, la agarra (op12 ReceiveTool) y restaura tu posición. Persiste en muerte. Elegí las armas en la lista →" })
        aw1:AddToggle("AWPosSpoof", { Text = "Pos Spoof", Default = true,
            Tooltip = "ON = desync (server te ve en el pickup, tu cuerpo REAL se queda = menos riesgo de arresto). OFF = teletransporta el cuerpo real (más visible)." })
        aw1:AddButton("Grab Now", function()
            local wl = Lib.Options.WeaponList
            if wl then AutoWeapons.nextRun = 0; AutoWeapons.tick(wl:GetValue()) end
        end)
        aw1:AddDivider()
        aw1:AddLabel("Buscá y tildá las armas que querés. Agarra la 1a disponible de tu selección.", {})
        local aw2 = AW:AddPanel("Weapon List", { Column = 2 })
        local weaponList
        aw2:AddTextBox("WeaponSearch", { Text = "Search", Placeholder = "filtrar arma...",
            Callback = function(txt)
                if not weaponList then return end
                txt = (txt or ""):lower()
                if txt == "" then weaponList:SetValues(AutoWeapons.WEAPONS); return end
                local f = {}
                for _, n in ipairs(AutoWeapons.WEAPONS) do if n:lower():find(txt, 1, true) then f[#f+1] = n end end
                weaponList:SetValues(f)
            end })
        weaponList = aw2:AddList("WeaponList", { Values = AutoWeapons.WEAPONS, Multi = true, Height = 150 })

        --========================= VISUALS =========================--
        -- Categoría "Visuals": Hit Effects (LiP) + suite World Visuals (GUIVisuals: World/ESP/SelfFX/Preview),
        -- montada en main via Visuals.Attach que REUSA esta categoría por Window.__visualsCat. El ESP viejo
        -- de LiP lo reemplaza el ESP de GUIVisuals (box/health/skeleton/headdot/tracer/offscreen/chams/object).
        local Vis  = Window:AddCategory("Visuals", "eye")
        Window.__visualsCat = Vis

        -- Hit Effects: hitsounds + killsounds + hitmarker (detección por correlación con tu disparo)
        local HFX = Vis:AddSection("Hit Effects", "Hit/Kill sounds + hitmarker", { Columns = 2 })
        local hf1 = HFX:AddPanel("Sounds", { Column = 1 })
        hf1:AddToggle("HitSound", { Text = "Hit Sound", Default = false, Tooltip = "Suena al confirmar un hit (op46 del server)." })
        hf1:AddDropdown("HitSoundName", { Text = "Sound", Values = HitFX.HITNAMES, Default = "Neverlose",
            Tooltip = "Hitsounds de tu Overkill. (Neverlose Old / Sparkles / Ouch no cargan en LiP.)" })
        hf1:AddTextBox("HitSoundId", { Text = "Custom ID (opcional)", Default = "", Numeric = true,
            Tooltip = "rbxassetid propio; si lo ponés, overridea el dropdown." })
        hf1:AddSlider("HitVol", { Text = "Hit Volume", Min = 0.1, Max = 10, Default = 2, Decimals = 1 })
        hf1:AddSlider("HitPitch", { Text = "Hit Pitch", Min = 0.5, Max = 3, Default = 1, Decimals = 2 })
        hf1:AddDivider()
        hf1:AddToggle("KillSound", { Text = "Kill Sound", Default = false, Tooltip = "Suena al matar (enemigo muere con un hit tuyo reciente)." })
        hf1:AddDropdown("KillSoundName", { Text = "Sound", Values = HitFX.KILLNAMES, Default = "Killsound1" })
        hf1:AddTextBox("KillSoundId", { Text = "Custom ID (opcional)", Default = "", Numeric = true })
        hf1:AddSlider("KillVol", { Text = "Kill Volume", Min = 0.1, Max = 10, Default = 3, Decimals = 1 })
        hf1:AddSlider("KillPitch", { Text = "Kill Pitch", Min = 0.5, Max = 3, Default = 1, Decimals = 2 })
        hf1:AddDivider()
        hf1:AddButton("Test Hit", function() HitFX.testHit() end)
        hf1:AddButton("Test Kill", function() HitFX.testKill() end)
        local hf2 = HFX:AddPanel("Hitmarker", { Column = 2 })
        hf2:AddToggle("HitMarker", { Text = "Hitmarker (X)", Default = false, Tooltip = "X en el punto del hit, se desvanece." })
            :AddColorPicker("HitMarkColor", { Default = Color3.fromRGB(255, 255, 255) })
        hf2:AddSlider("HitMarkSize", { Text = "Size", Min = 2, Max = 20, Default = 7 })
        hf2:AddSlider("HitMarkGap", { Text = "Gap", Min = 0, Max = 15, Default = 4 })
    end

    return UI
end
