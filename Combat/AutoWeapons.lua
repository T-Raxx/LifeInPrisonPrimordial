-- Combat/AutoWeapons.lua — FACTORY. Recoge armas sueltas del mapa automáticamente (HvH).
-- Mecánica (reverse v48 + verificado en vivo): las armas sueltas son MODELS (SPAS/MP5/FAL/...) hijos del
-- contenedor "pickups" (tag PickupSource). El grab = op12 `ReceiveTool:FireServer(Model)` PERO el server
-- valida proximidad (≤8 studs; fire directo lejos = falla). → teleport rápido al pickup, firar, volver.
-- Cámara anclada a la pos real (no salta la vista). Ventana server-side ~0.3s (rápido = menos riesgo de
-- que un poli te arreste). Persiste en muerte (el driver re-chequea). Notifica encontrado/equipado/no-hay.
return function(require, LIP, Lib)
    local Players    = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Workspace  = game:GetService("Workspace")
    local CS         = game:GetService("CollectionService")
    local LP = Players.LocalPlayer
    local Spoof = require("Combat.Spoof")
    local AutoWeapons = {}

    local function myRoot() local c = LP.Character; return c and c:FindFirstChild("HumanoidRootPart") end

    -- ¿el modelo `m` es un pickup de arma suelto? Model + PrimaryPart, hijo de un PickupSource "pickups",
    -- NO dentro de un Character ni de una vending machine.
    local function isLoosePickup(m)
        if not (m:IsA("Model") and m.PrimaryPart) then return false end
        local p = m.Parent
        if not (p and CS:HasTag(p, "PickupSource")) then return false end
        if p.Name ~= "pickups" then return false end                 -- vending usa Folder, no "pickups"
        return true
    end

    -- ¿ya tengo alguna de las armas seleccionadas (equipada o en el backpack)?
    function AutoWeapons.have(names)
        local set = {}; for _, n in ipairs(names) do set[n] = true end
        local c = LP.Character
        if c then for _, t in ipairs(c:GetChildren()) do if t:IsA("Tool") and set[t.Name] then return t.Name end end end
        local bp = LP:FindFirstChild("Backpack")
        if bp then for _, t in ipairs(bp:GetChildren()) do if t:IsA("Tool") and set[t.Name] then return t.Name end end end
        return nil
    end

    -- busca el pickup disponible más cercano cuyo nombre esté en `names`.
    function AutoWeapons.findPickup(names)
        local set = {}; for _, n in ipairs(names) do set[n] = true end
        local root = myRoot(); local myPos = root and root.Position
        local best, bestD
        for _, m in ipairs(Workspace:GetDescendants()) do
            if set[m.Name] and isLoosePickup(m) then
                local d = myPos and (m.PrimaryPart.Position - myPos).Magnitude or 0
                if not bestD or d < bestD then best, bestD = m, d end
            end
        end
        return best, bestD
    end

    -- GRAB: el server te tiene que ver ≤8 studs del pickup. Dos modos:
    --  · posSpoof (desync): server te ve en el pickup, tu cuerpo REAL se queda (restaurado cada frame por
    --    el loop de Spoof). NO teletransporta el cuerpo → menos riesgo de arresto. Cámara anclada (subida).
    --  · teleport (posSpoof=false): mueve el cuerpo real al pickup unos frames (más visible).
    -- Devuelve true si el pickup desapareció (o el arma entró al inventario).
    function AutoWeapons.grab(model, posSpoof)
        local root = myRoot(); if not (root and model and model.PrimaryPart) then return false end
        local cam = Workspace.CurrentCamera
        LIP.awGrabbing = true    -- pausa el position chain + fire del main (no pisar el desync del grab)
        Spoof.ensureParts()
        local realCF = Spoof.captureReal(root)
        local goCF   = CFrame.new(model.PrimaryPart.Position + Vector3.new(0, 3, 0))
        local name   = model.Name
        Spoof.camToLocal(cam, realCF)            -- cámara a la pos real (subida un poco)
        -- DESYNC (pos spoof, VERIFICADO): escribí el pickup cada Heartbeat + marcá el restore → el loop de
        -- Spoof devuelve tu cuerpo real cada frame. El server te ve en el pickup (pasa el check ≤8), tu
        -- cuerpo NO teleporta de verdad = menos riesgo de arresto. (El connection weld NO sirve para el
        -- check del pickup; el desync sí.) Sin pos spoof = teleport crudo del cuerpo.
        local hold = RunService.Heartbeat:Connect(function()
            if posSpoof then
                pcall(function()
                    LIP.cachedRoot = root; LIP.spoofRealCF = realCF; LIP.spoofOn = true
                    LIP.spoofRestore = realCF; LIP.spoofVel = Vector3.zero
                    root.CFrame = goCF
                end)
            else
                pcall(function() root.CFrame = goCF; root.AssemblyLinearVelocity = Vector3.zero end)
            end
        end)
        task.wait(0.22)                          -- el server registra la pos del pickup
        pcall(function() LIP.fire(12, model) end) -- ReceiveTool(Model) = grab
        task.wait(0.18)
        hold:Disconnect()
        if posSpoof then
            Spoof.stop(cam)                      -- limpia el desync + restaura cuerpo + cámara
        else
            pcall(function() root.CFrame = realCF; root.AssemblyLinearVelocity = Vector3.zero end)
            Spoof.camToChar(cam)
        end
        LIP.awGrabbing = false
        task.wait(0.15)
        -- AUTO-EQUIPAR el arma recién agarrada (el op12 la manda al Backpack → equiparla al personaje)
        do
            local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
            local bp = LP:FindFirstChild("Backpack")
            local t = (bp and bp:FindFirstChild(name)) or (LP.Character and LP.Character:FindFirstChild(name))
            if hum and t and t:IsA("Tool") then pcall(function() hum:EquipTool(t) end) end
        end
        return (model.Parent == nil) or (AutoWeapons.have({ name }) ~= nil)
    end

    -- notificación con throttle por clave (evita spam)
    local lastNotify = {}
    local function notify(key, title, desc, gap)
        local now = os.clock()
        if lastNotify[key] and (now - lastNotify[key]) < (gap or 3) then return end
        lastNotify[key] = now
        if LIP.Library and LIP.Library.Notify then LIP.Library:Notify({ Title = title, Description = desc, Time = 4 }) end
    end

    -- DRIVER (llamado por main con throttle). Si no tengo ninguna seleccionada, busco pickup y lo agarro.
    AutoWeapons.busy = false
    AutoWeapons.nextRun = 0
    function AutoWeapons.tick(names, posSpoof)
        if AutoWeapons.busy or not names or #names == 0 then return end
        local now = os.clock()
        if now < AutoWeapons.nextRun then return end
        AutoWeapons.nextRun = now + 1.0                       -- re-chequeo cada 1s
        if AutoWeapons.have(names) then return end            -- ya tengo una → idle
        local model = AutoWeapons.findPickup(names)
        if not model then
            notify("nf", "Auto Weapons", table.concat(names, " / ") .. " — sin pickup en el mapa", 6)
            return
        end
        AutoWeapons.busy = true
        task.spawn(function()
            local nm = model.Name
            local ok = AutoWeapons.grab(model, posSpoof)
            notify("grab", "Auto Weapons", ok and ("Equipada: " .. nm) or ("Falló grab: " .. nm), 0.5)
            AutoWeapons.nextRun = os.clock() + 0.8
            AutoWeapons.busy = false
        end)
    end

    -- lista de nombres de armas conocidas (para poblar el multi-select del UI). Se puede ampliar leyendo
    -- los pickups vivos, pero un set estático es predecible.
    AutoWeapons.WEAPONS = {
        "AWM", "Minigun", "M79", "SPAS", "DB Shotgun", "SCAR-H", "FAL", "AK-74", "AR 15", "M40",
        "MP5", "UZI", "PDW", "Micro AK", "TEC-9", "Glock", "Luger", "M9", "M9A1", "Screwdriver",
    }

    return AutoWeapons
end
