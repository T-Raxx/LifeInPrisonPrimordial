-- Visuals/CrosshairHUD.lua — FACTORY. Labels de estado del ragebot abajo del crosshair central.
-- Una línea, prioridad de overrides:
--   killedWait  → "Killed: <user>, waiting for HRP..."   (limpia al respawn del user + ForceField off)
--   reloadVoid  → "Reloading In Void..."                 (limpia al terminar la recarga)
--   base        → "killing: <user> | Resolved: x.xyz"    (x.xyz = confianza del resolver 0.000–1.000)
-- Font = el del watermark (GothamBold). Fade CONFIGURABLE + crossfade suave entre cambios de override
-- (fade-out del texto viejo → swap → fade-in del nuevo). Todo lo consume de flags LIP (los setea main).
return function(require, LIP, Lib)
    local Players    = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local CrossHUD = {}
    local Strafe   -- cacheado en init (para resolverInfo del HUD)

    local function T(f) local t = Lib.Toggles[f]; return t and t.Value end
    local function O(f) local o = Lib.Options[f]; return o and o.Value end

    -- parent seguro (gethui si existe, si no CoreGui) — sobrevive respawn
    local function guiParent()
        local ok, h = pcall(function() return gethui and gethui() end)
        if ok and h then return h end
        return game:GetService("CoreGui")
    end
    -- font idéntico al watermark si está creado, si no GothamBold (= T.FontBold del theme)
    local function wmFont()
        local wm = Lib._wm
        local ok, f = pcall(function() return wm and wm.T and wm.T.Font end)
        return (ok and f) or Enum.Font.GothamBold
    end

    local sg, lbl, grad
    local function ensure()
        if sg and sg.Parent and lbl and lbl.Parent then return end
        sg = Instance.new("ScreenGui")
        sg.Name = "LIP_XHUD"; sg.ResetOnSpawn = false; sg.IgnoreGuiInset = true
        sg.DisplayOrder = 999; sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        pcall(function() sg.Parent = guiParent() end)
        lbl = Instance.new("TextLabel")
        lbl.Name = "L"; lbl.BackgroundTransparency = 1
        lbl.AnchorPoint = Vector2.new(0.5, 0)          -- centrado horizontal, crece simétrico desde el centro
        lbl.AutomaticSize = Enum.AutomaticSize.XY
        lbl.Size = UDim2.fromOffset(0, 0)
        lbl.TextXAlignment = Enum.TextXAlignment.Center
        lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)  -- outline para legibilidad sobre cualquier fondo
        lbl.Text = ""; lbl.Visible = false
        lbl.Parent = sg
        -- UIGradient para la OLA DE COLOR (recorre las letras). Enabled solo con el toggle de wave.
        grad = Instance.new("UIGradient")
        grad.Enabled = false
        grad.Parent = lbl
    end

    -- línea activa según prioridad (killed > reloadVoid > base). "" = nada que mostrar.
    local function activeLine()
        if LIP.killedWait then
            return ("Killed: %s, waiting for HRP..."):format(LIP.killedWait)
        elseif LIP.hudReloadVoid then
            return "Reloading In Void..."
        elseif LIP.hudTargetName then
            local ri = (Strafe and Strafe.resolverInfo(LIP.target)) or { score = LIP.hudResolved or 0, state = "NORMAL", clusters = 0, confidence = 0 }
            local hp = 0
            local tc = LIP.target and LIP.target.Character
            local th = tc and tc:FindFirstChildOfClass("Humanoid")
            if th then hp = math.floor(th.Health) end
            return ("killing: %s | Conf: %.2f | Fire: %.2f | %s | HP: %d"):format(
                LIP.hudTargetName, ri.confidence or 0, LIP.fireMult or 1, ri.state, hp)
        end
        return ""
    end

    -- Smooth Fade = OLA DE COLOR (no fade alpha): una banda de color/brillo recorre las letras via UIGradient
    -- animado. El texto se muestra sólido al instante; en cambios de override sólo se swappea (la ola sigue).
    local function update(dt)
        if not T("CrossHUD") then if lbl then lbl.Visible = false end return end
        ensure()
        local shown = activeLine()
        if shown == "" then lbl.Visible = false; return end
        local col = O("CrossHUDColor") or Color3.fromRGB(202, 151, 161)
        lbl.Text = shown
        lbl.Font = wmFont()
        lbl.TextSize = O("CrossHUDSize") or 16
        lbl.TextColor3 = col
        lbl.TextTransparency = 0
        lbl.TextStrokeTransparency = 0.5
        lbl.Position = UDim2.new(0.5, 0, 0.5, O("CrossHUDOffset") or 34)   -- centro de pantalla + offset abajo
        lbl.Visible = true
        -- OLA DE COLOR: banda brillante que barre las letras de izq→der (UIGradient con offset animado).
        if T("CrossHUDFade") then
            local hi = col:Lerp(Color3.new(1, 1, 1), 0.75)   -- pico de la ola = color base aclarado
            grad.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0.0, col),
                ColorSequenceKeypoint.new(0.4, col),
                ColorSequenceKeypoint.new(0.5, hi),
                ColorSequenceKeypoint.new(0.6, col),
                ColorSequenceKeypoint.new(1.0, col),
            })
            local spd = O("CrossHUDFadeSpeed") or 6
            grad.Offset = Vector2.new(((os.clock() * spd * 0.15) % 1.4) - 0.7, 0)   -- barrido continuo
            grad.Enabled = true
        else
            grad.Enabled = false
        end
    end

    function CrossHUD.init()
        pcall(function() Strafe = require("Combat.Strafe") end)   -- para resolverInfo (score/state/clusters)
        LIP.track(RunService.RenderStepped:Connect(function(dt) pcall(update, dt) end))
        LIP.onCleanup(function() if sg then pcall(function() sg:Destroy() end) end end)
    end

    return CrossHUD
end
