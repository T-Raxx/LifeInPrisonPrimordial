-- Movement/PropAura.lua — FACTORY. AURA SERVER-SIDE: reclama las N parts SUELTAS (unanchored, owneadas por
-- proximidad = network ownership) más cercanas y las hace ORBITAR tu HRP escribiéndoles la CFrame cada frame.
-- Como owneás su física, el server las reps orbitando → los DEMÁS lo ven (aura real, no un Drawing). Confirmado
-- que los props se mueven (PropFling). Radius/Speed/Count por slider. Ofensivo opcional: a Speed alto la
-- colisión con enemigos puede pegarles (server-side). Suelta las props al apagar (les devuelve la velocidad 0).
return function(require, LIP, Lib)
    local RunService = game:GetService("RunService")
    local Workspace  = game:GetService("Workspace")
    local Players    = game:GetService("Players")
    local LP = Players.LocalPlayer
    local PA = {}

    local function O(f) local o = Lib.Options[f]; return o and o.Value end
    local function T(f) local t = Lib.Toggles[f]; return t and t.Value end

    local claimed = {}   -- {BasePart...} actualmente en órbita
    local ang = 0

    local function isFreeProp(d, chars)
        if not (d:IsA("BasePart") and not d.Anchored) then return false end
        if d.AssemblyRootPart ~= d then return false end       -- solo roots de assemblies libres
        local anc = d:FindFirstAncestorOfClass("Model")
        if anc and chars[anc] then return false end            -- no personajes
        return true
    end
    -- las N parts sueltas más cercanas a `pos`
    local function findProps(n, pos)
        local chars = {}
        for _, p in ipairs(Players:GetPlayers()) do if p.Character then chars[p.Character] = true end end
        local cand = {}
        for _, d in ipairs(Workspace:GetDescendants()) do
            if isFreeProp(d, chars) then
                cand[#cand + 1] = { d, (d.Position - pos).Magnitude }
            end
        end
        table.sort(cand, function(a, b) return a[2] < b[2] end)
        local out = {}
        for i = 1, math.min(n, #cand) do out[i] = cand[i][1] end
        return out
    end

    function PA.init()
        LIP.track(RunService.Heartbeat:Connect(function(dt)
            if not T("PropAura") then
                if #claimed > 0 then claimed = {} end
                return
            end
            local c = LP.Character
            local root = c and c:FindFirstChild("HumanoidRootPart")
            if not root then return end
            local n      = math.floor(O("PropAuraCount") or 6)
            local radius = O("PropAuraRadius") or 12
            local speed  = O("PropAuraSpeed") or 3
            local height = O("PropAuraHeight") or 2

            -- limpiar props muertos + (re)reclamar si faltan (se re-escanea barato cada ~0.5s vía count mismatch)
            local live = {}
            for _, p in ipairs(claimed) do if p and p.Parent and not p.Anchored then live[#live + 1] = p end end
            claimed = live
            if #claimed < n then claimed = findProps(n, root.Position) end

            ang = ang + speed * dt
            local m = #claimed
            for i = 1, m do
                local p = claimed[i]
                if p and p.Parent then
                    local a = ang + (i / m) * 6.2831853
                    local pos = root.Position + Vector3.new(math.cos(a) * radius, height, math.sin(a) * radius)
                    pcall(function()
                        p.CFrame = CFrame.lookAt(pos, root.Position)   -- owneado → el server lo reps orbitando
                        p.AssemblyLinearVelocity  = Vector3.zero
                        p.AssemblyAngularVelocity = Vector3.zero
                    end)
                end
            end
        end))
    end

    return PA
end
