-- Movement/PropAura.lua — FACTORY. AURA SERVER-SIDE: reclama parts SUELTAS (unanchored, owneadas por
-- proximidad = network ownership) y las hace ORBITAR tu HRP escribiéndoles la CFrame cada frame. Como owneás
-- su física, el server las reps orbitando → los DEMÁS lo ven (aura REAL, choca gente, mueve autos — confirmado).
-- FILTRO: solo props "buenos" (masa/tamaño acotados, no estructurales por nombre, no puertas/hinges) para no
-- arrancar puertas del mapa ni traer basura (jarrones/aspas). CLAIM STICKY: mantiene los mismos props, solo
-- rellena hasta N (no re-escanea todo cada frame → estable, sin traer basura de a poco).
return function(require, LIP, Lib)
    local RunService = game:GetService("RunService")
    local Workspace  = game:GetService("Workspace")
    local Players    = game:GetService("Players")
    local LP = Players.LocalPlayer
    local PA = {}

    local function O(f) local o = Lib.Options[f]; return o and o.Value end
    local function T(f) local t = Lib.Toggles[f]; return t and t.Value end

    local claimed = {}   -- {BasePart...} en órbita (sticky)
    local ang = 0

    -- nombres estructurales a EXCLUIR (puertas/ventanas/ventiladores/vidrios/etc = anclados o hinged al mapa)
    local BADNAME = { "door", "window", "gate", "fan", "blade", "hinge", "glass", "wall", "floor", "roof", "fence", "sign", "light", "lamp" }
    local CRATE   = { "crate", "box", "barrel", "pallet", "container", "cargo" }
    local function nameHits(name, list)
        local n = name:lower()
        for _, w in ipairs(list) do if n:find(w, 1, true) then return true end end
        return false
    end

    -- prop válido: assembly libre real (root unanchored), sin joints (no hinged al mapa), masa/tamaño acotados,
    -- nombre no estructural. Con CratesOnly = solo nombres de caja.
    local function isFreeProp(d, chars)
        if not (d:IsA("BasePart") and not d.Anchored) then return false end
        if d.AssemblyRootPart ~= d then return false end              -- solo el root del assembly
        local anc = d:FindFirstAncestorOfClass("Model")
        if anc and chars[anc] then return false end                   -- no personajes
        if #d:GetJoints() > 0 then return false end                   -- sin joints/constraints = NO hinged al mapa (puertas/aspas)
        local mass = d:GetMass()
        if mass < 0.5 or mass > (O("PropAuraMaxMass") or 400) then return false end   -- ni aspas diminutas ni estructural
        local sz = d.Size.Magnitude
        if sz < 1.5 or sz > 60 then return false end
        if nameHits(d.Name, BADNAME) then return false end            -- excluir estructurales por nombre
        if T("PropAuraCrates") and not nameHits(d.Name, CRATE) then return false end  -- solo cajas si el toggle
        return true
    end

    -- las N parts válidas más cercanas a `pos`, excluyendo las ya en `have`
    local function findProps(n, pos, have)
        local chars = {}
        for _, p in ipairs(Players:GetPlayers()) do if p.Character then chars[p.Character] = true end end
        local cand = {}
        for _, d in ipairs(Workspace:GetDescendants()) do
            if not have[d] and isFreeProp(d, chars) then
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

            -- STICKY: limpiar muertos, mantener el resto, rellenar hasta N con props nuevos (no re-escaneo total)
            local live, have = {}, {}
            for _, p in ipairs(claimed) do
                if p and p.Parent and not p.Anchored then live[#live + 1] = p; have[p] = true end
            end
            claimed = live
            if #claimed < n then
                for _, p in ipairs(findProps(n - #claimed, root.Position, have)) do claimed[#claimed + 1] = p end
            end
            while #claimed > n do table.remove(claimed) end            -- si N bajó, soltar el excedente

            ang = ang + speed * dt
            local m = #claimed
            local base = root.Position
            for i = 1, m do
                local p = claimed[i]
                if p and p.Parent then
                    local a = ang + (i / m) * 6.2831853
                    local pos = base + Vector3.new(math.cos(a) * radius, height, math.sin(a) * radius)
                    pcall(function()
                        p.CFrame = CFrame.new(pos)                     -- sin lookAt (menos jitter de rotación)
                        p.AssemblyLinearVelocity  = Vector3.zero
                        p.AssemblyAngularVelocity = Vector3.zero
                    end)
                end
            end
        end))
    end

    return PA
end
