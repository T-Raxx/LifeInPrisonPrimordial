-- Combat/Target.lua — FACTORY. Selección de target (silent aim + melee/punch).
-- Teams LiP: Police / Prisoners / Criminals. Enemigo = team distinto (teamCheck).
-- Target.pick(opts)      -> silent aim (Crosshair/Distance/Health, FOV, wallcheck) -> LIP.target
-- Target.nearestEnemy(opts) -> melee/punch (más cercano en rango mundo)
return function(require, LIP, Lib)
    local Players   = game:GetService("Players")
    local Workspace = game:GetService("Workspace")
    local LP = Players.LocalPlayer
    local Target = {}

    local function alive(char)
        local h = char and char:FindFirstChildOfClass("Humanoid")
        return (h and h.Health > 0) or false, h
    end
    local function visible(part, char)
        local cam = Workspace.CurrentCamera
        local rp = RaycastParams.new()
        rp.FilterType = Enum.RaycastFilterType.Exclude
        rp.FilterDescendantsInstances = { LP.Character, char }
        rp.IgnoreWater = true
        local o = cam.CFrame.Position
        return Workspace:Raycast(o, (part.Position - o), rp) == nil
    end
    local function isFriend(plr)
        local s, r = pcall(function() return LP:IsFriendsWith(plr.UserId) end)
        return s and r
    end
    local function hasFF(char)   -- spawn protection (ForceField) → intocable
        return char and char:FindFirstChildOfClass("ForceField") ~= nil
    end
    -- checks UNIVERSALES de target (team / friend / forcefield). El wallcheck (LOS) va aparte en cada
    -- selector (usa la cámara). Los tres los comparten pick (silent aim) y nearestEnemy (melee/punch).
    local function isEnemy(plr, opts)
        if plr == LP then return false end
        if opts.teamCheck and LP.Team and plr.Team == LP.Team then return false end
        if opts.friendCheck and isFriend(plr) then return false end
        if opts.ffCheck and hasFF(plr.Character) then return false end   -- no enfocar target con FF
        return true
    end
    Target.hasFF = hasFF

    -- silent aim: elige el mejor target según modo. Setea LIP.target.
    function Target.pick(opts)
        local cam = Workspace.CurrentCamera
        local myHRP = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        local mode = opts.mode or "Crosshair"
        local best, bestScore = nil, math.huge
        for _, plr in ipairs(Players:GetPlayers()) do
            local char = plr.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp and select(1, alive(char)) and isEnemy(plr, opts) then
                if not (opts.wallcheck and not visible(hrp, char)) then
                    local score
                    if mode == "Crosshair" then
                        local sp, on = cam:WorldToViewportPoint(hrp.Position)
                        if on and sp.Z > 0 then
                            local d = (Vector2.new(sp.X, sp.Y) - Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)).Magnitude
                            if d <= (opts.fov or 1e9) then score = d end
                        end
                    elseif mode == "Health" then
                        local _, hum = alive(char); score = hum and hum.Health or nil
                    else -- "Distance"
                        score = myHRP and (hrp.Position - myHRP.Position).Magnitude or nil
                    end
                    if score and score < bestScore then best, bestScore = plr, score end
                end
            end
        end
        LIP.target = best
        return best
    end

    -- melee/punch: enemigo vivo más cercano dentro de rango (mundo).
    function Target.nearestEnemy(opts)
        local myHRP = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if not myHRP then return nil end
        local best, bestD = nil, (opts.range or 12)
        for _, plr in ipairs(Players:GetPlayers()) do
            local char = plr.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp and select(1, alive(char)) and isEnemy(plr, opts) then
                local d = (hrp.Position - myHRP.Position).Magnitude
                if d <= bestD and (not opts.wallcheck or visible(hrp, char)) then
                    best, bestD = plr, d
                end
            end
        end
        return best
    end

    return Target
end
