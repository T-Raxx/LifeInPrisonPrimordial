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

    local sg, lbl
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
    end

    -- línea activa según prioridad (killed > reloadVoid > base). "" = nada que mostrar.
    local function activeLine()
        if LIP.killedWait then
            return ("Killed: %s, waiting for HRP..."):format(LIP.killedWait)
        elseif LIP.hudReloadVoid then
            return "Reloading In Void..."
        elseif LIP.hudTargetName then
            return ("killing: %s | Resolved: %.3f"):format(LIP.hudTargetName, LIP.hudResolved or 0)
        end
        return ""
    end

    -- máquina de fade: alpha 0→1, phase "in"/"out". Un cambio de línea fuerza "out" (fade-out completo)
    -- antes de swappear el texto y hacer "in" → crossfade suave entre overrides.
    local shown, alpha, phase = "", 0, "in"
    local function update(dt)
        if not T("CrossHUD") then if lbl then lbl.Visible = false end return end
        ensure()
        local want = activeLine()
        if T("CrossHUDFade") then
            local spd = O("CrossHUDFadeSpeed") or 6
            if phase == "in" and want ~= shown then phase = "out" end
            if phase == "out" then
                alpha = math.max(0, alpha - dt * spd)
                if alpha <= 0.001 then shown = want; phase = "in" end
            else
                local goal = (shown ~= "") and 1 or 0
                if alpha < goal then alpha = math.min(goal, alpha + dt * spd)
                elseif alpha > goal then alpha = math.max(goal, alpha - dt * spd) end
            end
        else
            shown = want; alpha = (shown ~= "") and 1 or 0
        end
        local col = O("CrossHUDColor") or Color3.fromRGB(202, 151, 161)
        lbl.Text = shown
        lbl.Font = wmFont()
        lbl.TextSize = O("CrossHUDSize") or 16
        lbl.TextColor3 = col
        lbl.TextTransparency = 1 - alpha
        lbl.TextStrokeTransparency = 1 - alpha * 0.5
        lbl.Position = UDim2.new(0.5, 0, 0.5, O("CrossHUDOffset") or 34)   -- centro de pantalla + offset abajo
        lbl.Visible = shown ~= "" and alpha > 0.01
    end

    function CrossHUD.init()
        LIP.track(RunService.RenderStepped:Connect(function(dt) pcall(update, dt) end))
        LIP.onCleanup(function() if sg then pcall(function() sg:Destroy() end) end end)
    end

    return CrossHUD
end
