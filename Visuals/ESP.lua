-- Visuals/ESP.lua — FACTORY. ESP Drawing API + Highlight (chams). Client-side puro = cero ban risk.
-- LiF usa R6 (Head/Torso/Left Arm/Right Arm/Left Leg/Right Leg + HumanoidRootPart).
-- Un solo RenderStepped; drawings pooled por jugador. Lee flags de Lib.Toggles/Options.
return function(require, LIP, Lib)
    local Players    = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Workspace  = game:GetService("Workspace")
    local LP = Players.LocalPlayer
    local ESP = {}

    local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
    local BONES = {                       -- R6
        { "Head", "Torso" },
        { "Torso", "Left Arm" }, { "Torso", "Right Arm" },
        { "Torso", "Left Leg" }, { "Torso", "Right Leg" },
    }

    local pool = {}

    local function mk(t, props)
        local d = Drawing.new(t)
        for k, v in pairs(props) do d[k] = v end
        return d
    end

    local function createSet(plr)
        if pool[plr] then return end
        local s = { all = {}, bones = {} }
        s.boxO   = mk("Square", { Thickness = 3, Filled = false, Color = BLACK, Visible = false, ZIndex = 1 })
        s.box    = mk("Square", { Thickness = 1, Filled = false, Color = WHITE, Visible = false, ZIndex = 2 })
        s.name   = mk("Text",   { Size = 13, Center = true, Outline = true, Color = WHITE, Visible = false })
        s.dist   = mk("Text",   { Size = 12, Center = true, Outline = true, Color = WHITE, Visible = false })
        s.hpBg   = mk("Line",   { Thickness = 3, Color = BLACK, Visible = false })
        s.hp     = mk("Line",   { Thickness = 1, Color = Color3.fromRGB(0, 255, 0), Visible = false })
        s.tracer = mk("Line",   { Thickness = 1, Color = WHITE, Visible = false })
        for i = 1, #BONES do s.bones[i] = mk("Line", { Thickness = 1, Color = WHITE, Visible = false }) end
        for _, d in pairs({ s.boxO, s.box, s.name, s.dist, s.hpBg, s.hp, s.tracer }) do s.all[#s.all + 1] = d end
        for _, b in ipairs(s.bones) do s.all[#s.all + 1] = b end
        pool[plr] = s
    end

    local function hideSet(s)
        for _, d in ipairs(s.all) do d.Visible = false end
        if s.highlight then s.highlight.Enabled = false end
    end
    local function destroySet(plr)
        local s = pool[plr]; if not s then return end
        for _, d in ipairs(s.all) do pcall(function() d:Remove() end) end
        if s.highlight then pcall(function() s.highlight:Destroy() end) end
        pool[plr] = nil
    end

    local function T(f) local t = Lib.Toggles[f]; return t and t.Value end
    local function O(f) local o = Lib.Options[f]; return o and o.Value end
    local function col(f, fallback) local o = Lib.Options[f]; return (o and o.Value) or fallback end

    local function isFriend(plr)
        local ok, r = pcall(function() return LP:IsFriendsWith(plr.UserId) end); return ok and r
    end
    local function visibleTo(cam, part, char)
        local rp = RaycastParams.new()
        rp.FilterType = Enum.RaycastFilterType.Exclude
        rp.FilterDescendantsInstances = { LP.Character, char }
        rp.IgnoreWater = true
        local o = cam.CFrame.Position
        return Workspace:Raycast(o, (part.Position - o), rp) == nil
    end

    local function ensureHighlight(s, char)
        if not s.highlight or s.highlight.Parent ~= char then
            if s.highlight then pcall(function() s.highlight:Destroy() end) end
            local h = Instance.new("Highlight")
            h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            h.FillTransparency = 0.5; h.OutlineTransparency = 0
            h.Adornee = char; h.Parent = char
            s.highlight = h
        end
    end

    local function update(plr, cam, myPos)
        local s = pool[plr]; if not s then return end
        local char = plr.Character
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        local head = char and char:FindFirstChild("Head")
        if not (char and hum and hrp and hum.Health > 0) then return hideSet(s) end
        if T("ESPTeamCheck") and LP.Team and plr.Team == LP.Team then return hideSet(s) end
        if T("ESPFriendCheck") and isFriend(plr) then return hideSet(s) end

        local dist = (hrp.Position - myPos).Magnitude
        if dist > (O("ESPMaxDist") or 1000) then return hideSet(s) end

        local topV, onTop = cam:WorldToViewportPoint((hrp.CFrame * CFrame.new(0, 3, 0)).Position)
        local botV = cam:WorldToViewportPoint((hrp.CFrame * CFrame.new(0, -3.2, 0)).Position)
        if not onTop then return hideSet(s) end

        local h = math.abs(topV.Y - botV.Y)
        local w = h * 0.5
        local x = topV.X - w / 2
        local y = topV.Y
        local color = (visibleTo(cam, head or hrp, char) and col("ESPVisibleColor", Color3.fromRGB(80, 255, 120)))
                       or col("ESPHiddenColor", Color3.fromRGB(255, 80, 80))

        if T("ESPBox") then
            s.boxO.Size = Vector2.new(w, h); s.boxO.Position = Vector2.new(x, y); s.boxO.Visible = true
            s.box.Size  = Vector2.new(w, h); s.box.Position  = Vector2.new(x, y); s.box.Color = color; s.box.Visible = true
        else s.boxO.Visible = false; s.box.Visible = false end

        if T("ESPName") then
            s.name.Text = plr.Name; s.name.Position = Vector2.new(x + w / 2, y - 15); s.name.Color = color; s.name.Visible = true
        else s.name.Visible = false end

        if T("ESPDistance") then
            s.dist.Text = math.floor(dist) .. "m"; s.dist.Position = Vector2.new(x + w / 2, y + h + 2); s.dist.Visible = true
        else s.dist.Visible = false end

        if T("ESPHealth") then
            local pct = math.clamp(hum.Health / (hum.MaxHealth > 0 and hum.MaxHealth or 100), 0, 1)
            local bx = x - 5
            s.hpBg.From = Vector2.new(bx, y); s.hpBg.To = Vector2.new(bx, y + h); s.hpBg.Visible = true
            s.hp.From = Vector2.new(bx, y + h * (1 - pct)); s.hp.To = Vector2.new(bx, y + h)
            s.hp.Color = Color3.fromRGB(math.floor(255 * (1 - pct)), math.floor(255 * pct), 60); s.hp.Visible = true
        else s.hpBg.Visible = false; s.hp.Visible = false end

        if T("ESPTracer") then
            local vp = cam.ViewportSize
            local originMode = O("TracerOrigin") or "Bottom"
            local from = (originMode == "Center" and Vector2.new(vp.X / 2, vp.Y / 2))
                       or (originMode == "Top" and Vector2.new(vp.X / 2, 0))
                       or Vector2.new(vp.X / 2, vp.Y)
            s.tracer.From = from; s.tracer.To = Vector2.new(topV.X, y + h); s.tracer.Color = color; s.tracer.Visible = true
        else s.tracer.Visible = false end

        if T("ESPSkeleton") then
            for i, pair in ipairs(BONES) do
                local a = char:FindFirstChild(pair[1]); local b = char:FindFirstChild(pair[2])
                local bl = s.bones[i]
                if a and b then
                    local av, aon = cam:WorldToViewportPoint(a.Position)
                    local bv, bon = cam:WorldToViewportPoint(b.Position)
                    if aon and bon then
                        bl.From = Vector2.new(av.X, av.Y); bl.To = Vector2.new(bv.X, bv.Y); bl.Color = color; bl.Visible = true
                    else bl.Visible = false end
                else bl.Visible = false end
            end
        else for _, b in ipairs(s.bones) do b.Visible = false end end

        if T("ESPChams") then
            ensureHighlight(s, char)
            s.highlight.FillColor = color; s.highlight.OutlineColor = WHITE; s.highlight.Enabled = true
        elseif s.highlight then s.highlight.Enabled = false end
    end

    function ESP.init()
        for _, plr in ipairs(Players:GetPlayers()) do if plr ~= LP then createSet(plr) end end
        LIP.track(Players.PlayerAdded:Connect(function(plr) createSet(plr) end))
        LIP.track(Players.PlayerRemoving:Connect(function(plr) destroySet(plr) end))
        LIP.track(RunService.RenderStepped:Connect(function()
            local cam = Workspace.CurrentCamera
            local myChar = LP.Character
            local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
            local on = T("ESP")
            for plr, s in pairs(pool) do
                if not on or not myHrp then hideSet(s)
                else
                    local ok = pcall(update, plr, cam, myHrp.Position)
                    if not ok then hideSet(s) end
                end
            end
        end))
    end

    return ESP
end
