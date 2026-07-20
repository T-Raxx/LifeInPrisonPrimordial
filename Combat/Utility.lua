-- Combat/Utility.lua — FACTORY. Exploits sueltos de remote (fire directo, args del reverse).
--  · Team swap  op1  JoinTeam(TeamInstance)         — sin gate client-side
--  · Heal spam  op28 Consume(Tool, nil)             — cura server-side, spam si no hay cooldown
--  · Grab tool  op12 ReceiveTool(Tool)              — recoge arma caída a distancia (~60 studs)
return function(require, LIP, Lib)
    local Teams     = game:GetService("Teams")
    local Players   = game:GetService("Players")
    local Workspace = game:GetService("Workspace")
    local LP = Players.LocalPlayer
    local Util = {}

    function Util.joinTeam(name)
        local t = Teams:FindFirstChild(name)
        if t then LIP.fire(1, t) end
    end

    -- heal spam: usa el consumible equipado (medkit/comida). op28 con nil = tick de cura.
    function Util.healSpam()
        local c = LP.Character; local tool = c and c:FindFirstChildOfClass("Tool")
        if tool then LIP.fire(28, tool, nil) end
    end

    -- grab: recoge el Tool caído más cercano (op12). El server resuelve por instancia.
    function Util.grabNearest()
        local c = LP.Character; local hrp = c and c:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        local best, bestD = nil, 60
        for _, t in ipairs(Workspace:GetChildren()) do
            if t:IsA("Tool") then
                local h = t:FindFirstChild("Handle")
                local d = h and (h.Position - hrp.Position).Magnitude
                if d and d <= bestD then best, bestD = t, d end
            end
        end
        if best then LIP.fire(12, best) end
    end

    return Util
end
