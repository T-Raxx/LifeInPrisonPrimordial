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
        local Roadkill = require("Movement.Roadkill")
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
        c2:AddSlider("AutoFireRate", { Text = "Fire Rate Cap", Min = 0.5, Max = 30, Default = 30, Decimals = 2, Suffix = "/s",
            Tooltip = "TOPE de disparos/s (con DECIMALES: p/ SPAS ~1.42/s). El autofire capea a min(firerate observado, esto). Bajá para escopetas lentas (evita unequip). Cap máx 30/s." })
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
        c2:AddSlider("ShotgunPellets", { Text = "Shotgun Pellets", Min = 1, Max = 16, Default = 8,
            Tooltip = "Pellets por tiro para escopetas (SPAS/DB). El autofire manda N pellets = registra. Ajustá hasta que peguen (si el juego aprendió el count real, lo usa; si no, este slider)." })

        local vd = RS:AddPanel("Void Spam", { Column = 2 })
        vd:AddToggle("VoidSpam", { Text = "Void Spam", Default = false,
            Tooltip = "SOLO con Target Strafe ON. Oscila OUT (strafe-orbit al target, disparás) ↔ IN void (server te ve lejos, esconde, disparo pausado). Rompe el resolver de PREDICCIÓN enemigo. Con Void Reload: fuerza el void durante toda la recarga (recargás escondido)." })
        vd:AddSlider("VoidInTime", { Text = "In Void", Min = 0.1, Max = 2, Default = 0.4, Decimals = 2, Suffix = "s",
            Tooltip = "Tiempo escondido en el void (disparo pausado)" })
        vd:AddSlider("VoidOutTime", { Text = "Out Void", Min = 0.1, Max = 2, Default = 0.3, Decimals = 2, Suffix = "s",
            Tooltip = "Tiempo en tu pos real (disparás desde acá). Con Auto Time ON, es lo ÚNICO que seteás." })
        vd:AddToggle("VoidAutoTime", { Text = "Auto Time (per weapon)", Default = true,
            Tooltip = "In Void = auto según el firerate del arma equipada (1 disparo por ciclo). Solo Out Void configurable. OFF = usa el slider In Void manual." })
        vd:AddToggle("VoidShootOut", { Text = "Shoot Out Only", Default = true,
            Tooltip = "Solo dispara OUT del void; pausa el disparo mientras estás IN void." })
        vd:AddToggle("VoidReload", { Text = "Void Reload", Default = false,
            Tooltip = "Recarga el arma mientras estás IN void (escondido) cuando el cargador se agota." })
        vd:AddList("VoidPattern", { Values = { "Random", "Teleport", "Jitter", "StaticBreak", "Nebula" }, Default = "Jitter",
            Tooltip = "Non-pattern (Random/Teleport) = unpredecible pero PROMEDIABLE. Pattern (Jitter/StaticBreak) = anti-centroide. Nebula = far↔map a distancias RIDÍCULAS (300M ↔ spots random del mapa estáticos/jitter): irresolvible." })
        vd:AddSlider("VoidDist", { Text = "Radius", Min = 1, Max = 100, Default = 30, Suffix = "studs",
            Tooltip = "Radio del jitter alrededor del origen (close-range pro, para Random/Jitter/StaticBreak). El patrón protege, no la distancia." })
        vd:AddSlider("FarDist", { Text = "Far Dist", Min = 1000000, Max = 500000000, Default = 300000000, Suffix = "st",
            Tooltip = "Distancia de la fase FAR de Nebula (300M default). Ultra-lejos = un-hittable por latencia. Si tan lejos no replica (Roblox cullea CFrames extremos), bajalo." })
        vd:AddSlider("MapRadius", { Text = "Map Radius", Min = 100, Max = 10000, Default = 3000, Suffix = "st",
            Tooltip = "Spread de los spots random del mapa en la fase MAP de Nebula (sostenidos 0.3s, static o jitter)." })
        vd:AddDropdown("VoidPreset", { Text = "Preset", Values = { "Legit", "Jitter", "Peek", "Blink", "Chaos" }, Default = "Jitter",
            Tooltip = "Presets pro: setean pattern+radius+timing. Legit=sutil, Jitter/Peek=anti-centroide (centroide=aire), Blink=teleport, Chaos=random rápido.",
            Callback = function(v) Void.applyPreset(v) end })

        local cfd = RS:AddPanel("CFrame Desync", { Column = 2 })
        cfd:AddToggle("CFrameDesync", { Text = "CFrame Desync", Default = false,
            Tooltip = "Desync CONTINUO self-anchored: el server te ve desyncado RELATIVO a tu pos REAL (no al origen absoluto). Full customizable. Excluyente con Strafe/Idle/Godmode." })
        cfd:AddKeybind("CFrameDesyncKey", { Text = "Toggle Key", Mode = "Toggle",
            Callback = function(a) local t = Lib.Toggles.CFrameDesync; if t then t:SetValue(a) end end })
        cfd:AddList("CFDPattern", { Values = { "Random", "Teleport", "Jitter", "StaticBreak", "Nebula" }, Default = "Random",
            Tooltip = "Mismo set de patrones que void/idle pero anchor = tu pos real. Random 1-100 = sutil; Nebula = te vas 300M desde vos y volvés a spots random." })
        cfd:AddSlider("CFDDist", { Text = "Radius", Min = 1, Max = 100, Default = 30, Suffix = "studs",
            Tooltip = "Radio del jitter alrededor de tu pos real (Random/Jitter/StaticBreak). Nebula usa Far Dist/Map Radius del panel Void." })

        local tmr = RS:AddPanel("Timer", { Column = 2 })
        tmr:AddToggle("Timer", { Text = "Timer", Default = false,
            Tooltip = "Acelera tu simulación (StepPhysics) → time() más rápido → rapidfire + reload rápido LEGAL (única rapidfire viable; op14-spam = unequip). Causa FPS drops + lag de replicación (combatir con spam de tiros + Connection Weld)." })
        tmr:AddKeybind("TimerKey", { Text = "Timer Key", Mode = "Toggle",
            Callback = function(a) local t = Lib.Toggles.Timer; if t then t:SetValue(a) end end })
        tmr:AddSlider("TimerStatic", { Text = "Static Mult", Min = 1, Max = 3, Default = 1, Decimals = 2, Suffix = "x",
            Tooltip = "Mult constante cuando NO estás en Void Spam. 1 = off." })
        tmr:AddSlider("TimerOut", { Text = "Out Mult", Min = 1, Max = 3, Default = 2, Decimals = 2, Suffix = "x",
            Tooltip = "Mult DINÁMICO en la ventana OUT del Void Spam (rapidfire mientras disparás). In Void = 1x (escondido, sin acelerar → replicación normal del hide)." })
        tmr:AddSlider("TimerReload", { Text = "Reload Mult", Min = 1, Max = 3, Default = 2, Decimals = 2, Suffix = "x",
            Tooltip = "Mult mientras recargás (override, puede pasar in-void con Void Reload). Recarga rápida." })

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
        ts:AddKeybind("SpectateKey", { Text = "Spectate Key", Mode = "Toggle",
            Callback = function(a) local t = Lib.Toggles.Spectate; if t then t:SetValue(a) end end })

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
        idl:AddList("IdlePattern", { Values = { "Random", "Teleport", "Jitter", "StaticBreak", "Nebula" }, Default = "Jitter",
            Tooltip = "Non-pattern (Random/Teleport) vs Pattern anti-centroide (Jitter/StaticBreak) vs Nebula (far↔map ridículo)." })
        idl:AddSlider("IdleDist", { Text = "Radius", Min = 1, Max = 100, Default = 30, Suffix = "studs",
            Tooltip = "Radio del jitter alrededor del origen (close-range pro)." })

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
        --========================= RESOLVER (Section en el sidebar de Rage) =========================--
        local Res = Rage:AddSection("Resolver", "Cluster · Density · Dynamic Strafe", { Columns = 2 })
        local RParams = Strafe.RParams; local DEN = Strafe.DEN; local CONF = Strafe.CONF; local CEN = Strafe.CEN
        local rm = Res:AddPanel("Método", { Column = 1 })
        rm:AddToggle("Resolver", { Text = "Spam Resolver", Default = false,
            Tooltip = "Resuelve el centro REAL del target (el strafe orbita ahí, no su jitter)" })
        rm:AddDropdown("ResolverMethod", { Text = "Method", Values = { "Cluster", "Density", "Centroid", "Auto" }, Default = "Cluster",
            Tooltip = "Cluster = histograma (juju). Density = vecindad batch (sakura, anti-alternador + far). Centroid = media robusta void-excluida (clava el CENTRO de random ancho, sin muro de 27 studs; para móviles/idle random). Auto = elige según el target." })
        rm:AddSlider("ResolverPredict", { Text = "Predict", Min = 0, Max = 0.4, Default = 0.12, Decimals = 2, Suffix = "s",
            Tooltip = "Lead por velocidad (compensa el delay de replicación). 0 = off" })
        rm:AddSlider("ResolverRate", { Text = "Resolver Rate", Min = 0, Max = 0.1, Default = 0.037, Decimals = 4, Suffix = "s",
            Tooltip = "Intervalo de muestreo de velocidad (juju 0.037)." })
        rm:AddSlider("PredictBase", { Text = "Predict Base", Min = 0, Max = 0.4, Default = 0.10, Decimals = 2, Suffix = "s",
            Tooltip = "Lead constante (comp de ping), aplicado aún quieto" })
        rm:AddSlider("PredictAmp", { Text = "Predict Amp", Min = 0, Max = 0.4, Default = 0.15, Decimals = 2, Suffix = "s",
            Tooltip = "Lead extra (tiempo) modulado por la CONFIANZA del movimiento: smooth/lineal=full, random=~0" })
        rm:AddSlider("PredictKill", { Text = "Predict Kill", Min = 0, Max = 1, Default = 0.25, Decimals = 2,
            Tooltip = "Umbral: si la confianza lineal < esto (= movimiento random), MATA el lead completo (base incluido) → center-lock puro sin predict. 0 = nunca mata (siempre predice)." })
        rm:AddSlider("LeadCap", { Text = "Lead Cap", Min = 60, Max = 1000, Default = 400, Suffix = "st/s",
            Tooltip = "Tope de velocidad para el lead (CAP, no zero). Subir para fast movers (fly/vehículo ~300+). El void ya está guarded aparte." })
        rm:AddToggle("FireResolved", { Text = "Fire on Resolved", Default = false,
            Tooltip = "Autofire dispara a la pos RESUELTA (didDefensive). RIESGO HBE. OFF = HBE-safe." })
        rm:AddToggle("VoidAutofire", { Text = "Void Autofire", Default = true,
            Tooltip = "Dispara a targets ESTÁTICOS hondo en el void (50M+ studs): su pos del void ES su pos real. Remueve el void-zero de la confianza (la estabilidad de fireConfidence filtra a los spammers) + bypassea el gate de rango. OFF = comportamiento viejo (no dispara en void)." })
        rm:AddLabel("Centroid / Positioning", { Header = true })
        rm:AddSlider("CentroidWindow", { Text = "Cen Window", Min = 0.5, Max = 4, Default = 1.5, Decimals = 2, Suffix = "s",
            Tooltip = "Ventana temporal de samples para la media del método Centroid. Más larga = centro más estable pero más lento a reaccionar.",
            Callback = function(v) if CEN then CEN.window = v end end })
        rm:AddSlider("CentroidTrim", { Text = "Cen Trim", Min = 0, Max = 0.6, Default = 0.15, Decimals = 2, Suffix = "%",
            Tooltip = "Fracción de samples más lejanos a la media que se descartan (outliers/flickers) antes de recomputar el centro robusto. Medido: 0.15 óptimo (0.30 descarta data buena, 0.00 explota con outliers).",
            Callback = function(v) if CEN then CEN.trim = v end end })
        rm:AddToggle("WeaponClamp", { Text = "Weapon Clamp", Default = true,
            Tooltip = "Con Target Strafe: clampa MI pos a rango de arma del CENTRO resuelto → la escopeta siempre registra. Automatiza el 'ponerme al centro'. No aplica en bait ni con weld (ya glued al target)." })
        rm:AddSlider("WeaponRange", { Text = "Weapon Range", Min = 30, Max = 300, Default = 125, Suffix = "st",
            Tooltip = "Rango del arma para el Weapon Clamp (escopeta = 125). El radio efectivo se achica con el spread del random. Bajalo si querés pegarte más al centro." })
        rm:AddSlider("HistMax", { Text = "Sample Cap", Min = 60, Max = 500, Default = 200, Suffix = " smp",
            Tooltip = "Muestras del historial. Más = centroide de math.random más ajustado. Density O(n²): 400+ puede lagear.",
            Callback = function(v) if CONF then CONF.histMax = math.floor(v) end end })
        rm:AddSlider("BacktrackWindow", { Text = "Backtrack Win", Min = 0, Max = 0.5, Default = 0.15, Decimals = 2, Suffix = "s",
            Tooltip = "Ventana tras la última pos real donde el autofire dispara en void-frames (on-shot backtrack). 0 = off.",
            Callback = function(v) if CONF then CONF.backtrackWindow = v end end })
        rm:AddToggle("ResolvedTracer", { Text = "Resolved Tracer", Default = false,
            Tooltip = "Tracer del centro de pantalla a la pos RESUELTA por el método activo." })
            :AddColorPicker("ResolvedTracerColor", { Default = Color3.fromRGB(255, 120, 120) })
        rm:AddLabel("Cluster", { Header = true })
        rm:AddSlider("RRPosWeight", { Text = "Position Trust", Min = 0.1, Max = 5, Default = 1.5, Decimals = 2,
            Callback = function(v) if RParams then RParams.posWeight = v end end })
        rm:AddSlider("RRVoidWeight", { Text = "Void Trust", Min = 0.1, Max = 5, Default = 0.2, Decimals = 2,
            Callback = function(v) if RParams then RParams.voidWeight = v end end })
        rm:AddSlider("RRForget", { Text = "Forget Rate", Min = 0, Max = 1000, Default = 80, Suffix = "%",
            Callback = function(v) if RParams then RParams.forget = v end end })
        rm:AddSlider("RRDistPenalty", { Text = "Distance Penalty", Min = 0, Max = 5, Default = 2, Decimals = 1, Suffix = "x",
            Callback = function(v) if RParams then RParams.distPenalty = v end end })
        rm:AddSlider("RRAccuracy", { Text = "Accuracy", Min = 0, Max = 1, Default = 0.5, Decimals = 2,
            Tooltip = "Min resolver confidence to fire (0 = off, higher = holds fire on shaky resolves)",
            Callback = function() end })
        rm:AddSlider("VoidRange", { Text = "Void Range", Min = 7000, Max = 500000, Default = 50000, Suffix = "st",
            Tooltip = "Umbral |x|+|z| para tratar una pos como VOID (confianza 0). El void-spam real va a ~9e5; subilo si un target LEJOS legítimo (12k+) no se resuelve. Bajalo si querés detectar void más cerca.",
            Callback = function(v) if CONF then CONF.voidManhattan = v end end })
        rm:AddSlider("CwDom", { Text = "W: Dominance", Min = 0, Max = 1, Default = 0.45, Decimals = 2,
            Callback = function(v) if CONF then CONF.wDom = v end end })
        rm:AddSlider("CwStab", { Text = "W: Stability", Min = 0, Max = 1, Default = 0.35, Decimals = 2,
            Callback = function(v) if CONF then CONF.wStab = v end end })
        rm:AddSlider("CwResid", { Text = "W: Residual", Min = 0, Max = 1, Default = 0.20, Decimals = 2,
            Callback = function(v) if CONF then CONF.wResid = v end end })
        rm:AddSlider("CRevisit", { Text = "Revisit Bonus", Min = 0, Max = 1, Default = 0.30, Decimals = 2,
            Callback = function(v) if CONF then CONF.revisitBonus = v end end })
        rm:AddSlider("CPredMax", { Text = "Pred Max Speed", Min = 20, Max = 150, Default = 60, Suffix = "st/s",
            Callback = function(v) if CONF then CONF.predMaxSpeed = v end end })
        rm:AddSlider("NoiseAmpMax", { Text = "Strafe Amp Max", Min = 8, Max = 60, Default = 30, Suffix = "st",
            Callback = function(v) if CONF then CONF.ampMax = v end end })
        rm:AddSlider("NoiseFreqMax", { Text = "Strafe Freq Max", Min = 1, Max = 8, Default = 4, Decimals = 1,
            Callback = function(v) if CONF then CONF.freqMax = v end end })   -- leído en vivo por el gate del autofire: O('RRAccuracy')
        rm:AddSlider("RRLerp", { Text = "Lerp", Min = 0.1, Max = 1, Default = 0.1, Decimals = 2,
            Callback = function(v) if RParams then RParams.lerp = v end end })
        rm:AddLabel("Density", { Header = true })
        rm:AddSlider("DenForgiveness", { Text = "Forgiveness", Min = 2, Max = 60, Default = 14.4, Decimals = 1, Suffix = "st",
            Tooltip = "Radio de vecindad (studs). Chico = void nunca clusteriza.",
            Callback = function(v) if DEN then DEN.forgiveness = v end end })
        rm:AddSlider("DenOutBonus", { Text = "Out-of-Void Bonus", Min = 0, Max = 40, Default = 13, Decimals = 1, Suffix = "st",
            Callback = function(v) if DEN then DEN.outOfVoidBonus = v end end })
        rm:AddSlider("DenDistPenalty", { Text = "Distance Penalty", Min = 0, Max = 8, Default = 3.2, Decimals = 1, Suffix = "x",
            Tooltip = "Encoge el radio con la distancia (resolución far).",
            Callback = function(v) if DEN then DEN.distPenalty = v end end })
        rm:AddSlider("DenMinMatches", { Text = "Min Matches", Min = 2, Max = 10, Default = 3,
            Callback = function(v) if DEN then DEN.minMatches = math.floor(v) end end })
        rm:AddSlider("DenWindow", { Text = "Window", Min = 0.5, Max = 5, Default = 3, Decimals = 1, Suffix = "s",
            Callback = function(v) if DEN then DEN.window = v end end })

        local dyn = Res:AddPanel("Dynamic Strafe", { Column = 2 })
        dyn:AddToggle("DynStrafe", { Text = "Dynamic Cycle", Default = false,
            Tooltip = "Ciclo CHASE (orbit tight) → STRAFE (noise-path adaptativo) → BAIT (fling void). Strafe propio, sin modos. No dispara en bait." })
        dyn:AddDropdown("BaitPreset", { Text = "Bait Preset", Values = { "Timed", "Micro", "Spam" }, Default = "Timed",
            Tooltip = "Timed = chase 2s/strafe 2s/bait 1s. Micro = ping+0.02/0.5/0.5 (flash). Spam = 0.06/0.08/0.11 rápido (juju)." })
        dyn:AddSlider("AroundTime", { Text = "Chase Time", Min = 0.05, Max = 10, Default = 2, Decimals = 2, Suffix = "s" })
        dyn:AddSlider("StrafeTime", { Text = "Strafe Time", Min = 0.05, Max = 10, Default = 2, Decimals = 2, Suffix = "s",
            Tooltip = "Duración de la fase STRAFE (noise-path adaptativo alrededor del target, dispara)." })
        dyn:AddSlider("VoidTime", { Text = "Bait Time", Min = 0.05, Max = 12, Default = 1, Decimals = 2, Suffix = "s" })

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
        v2:AddToggle("AntiTaze", { Text = "Anti Taze / Ragdoll", Default = false,
            Tooltip = "Resiste el taze/fling enemigo: recover instantáneo (saca el Humanoid de Physics) + guard de velocidad (≥31 → el propio check del juego rechaza el RagdollImpulse). No cuando Godmode/Permanent Ragdoll (self-ragdoll intencional)." })
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

        -- EXPERIMENTAL: roadkill (server-side collision vehículo↔jugador). Varios métodos, disparo manual.
        local RK = Misc:AddSection("Experimental · Physics", "Roadkill / fling / velocity desync (network ownership)", { Columns = 2 })
        local rk1 = RK:AddPanel("Roadkill / Fling", { Column = 1 })
        rk1:AddDropdown("RKMethod", { Text = "Method", Values = { "PhysRep", "VehicleRam", "SelfPhysRep", "BringTarget", "WeldFling", "PropFling" }, Default = "PhysRep",
            Tooltip = "PhysRep/VehicleRam/SelfPhysRep = roadkill (vehículo). BringTarget = mover el target (dudoso). WeldFling = weld dentro del target + velocidad, spoof tu vel a 0 (lo flingueás sin volar). PropFling = flinguear la part suelta más cercana al target." })
        rk1:AddSlider("RKVelocity", { Text = "Velocity", Min = 100, Max = 5000, Default = 800, Suffix = "st/s",
            Tooltip = "Velocidad de la embestida. Roadkill server-side suele tener umbral de velocidad." })
        rk1:AddSlider("RKDuration", { Text = "Duration", Min = 0.1, Max = 2, Default = 0.5, Decimals = 2, Suffix = "s",
            Tooltip = "Cuánto dura el ram sostenido (la colisión necesita contacto en movimiento varios frames)." })
        rk1:AddKeybind("RKKey", { Text = "Roadkill Key", Mode = "Toggle", Callback = function() Roadkill.fire() end })
        rk1:AddButton("Fire Roadkill", function() Roadkill.fire() end)
        local rk2 = RK:AddPanel("Velocity Desync", { Column = 2 })
        rk2:AddToggle("VelDesync", { Text = "Velocity Desync", Default = false,
            Tooltip = "PINEA tu CFrame clientside (no volás) + setea velocidad enorme → el server extrapola tu pos LEJOS entre updates = desync jitter serverside (evasión, walkfling-like sin flingear). Fix del que te volaba. No corre si hay spoof/weld activo." })
        rk2:AddKeybind("VelDesyncKey", { Text = "Vel Desync Key", Mode = "Toggle",
            Callback = function(a) local t = Lib.Toggles.VelDesync; if t then t:SetValue(a) end end })
        rk2:AddSlider("VDMagnitude", { Text = "Magnitude", Min = 500, Max = 50000, Default = 5000, Suffix = "st/s",
            Tooltip = "Magnitud de la velocidad. Más = más lejos serverside = más desync." })
        local rk3 = RK:AddPanel("Prop Aura", { Column = 1 })
        rk3:AddToggle("PropAura", { Text = "Prop Aura (server-side)", Default = false,
            Tooltip = "Reclama las N parts SUELTAS más cercanas (owneadas por proximidad) y las hace ORBITAR tu HRP → el server las reps orbitando = OTROS lo ven (aura REAL, no un Drawing). A Speed alto la colisión puede pegar a enemigos." })
        rk3:AddSlider("PropAuraCount", { Text = "Count", Min = 1, Max = 20, Default = 6, Suffix = " props" })
        rk3:AddSlider("PropAuraRadius", { Text = "Radius", Min = 3, Max = 40, Default = 12, Suffix = "studs" })
        rk3:AddSlider("PropAuraSpeed", { Text = "Speed", Min = 1, Max = 30, Default = 4 })
        rk3:AddSlider("PropAuraHeight", { Text = "Height", Min = -10, Max = 20, Default = 2, Suffix = "studs" })

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
