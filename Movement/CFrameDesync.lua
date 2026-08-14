-- Movement/CFrameDesync.lua — FACTORY. Desync CONTINUO (estilo idle/void) pero ANCHOR = tu HRP REAL (self-based),
-- no el origen absoluto (0,100,0). Full customizable (pattern/dist/timing propios, sub-tab dedicada). Reusa
-- Void.patternCF con anchor = tu pos real → apareces desyncado RELATIVO a donde estás (Random 1-100 = sutil;
-- Nebula/far = te vas 300M desde vos). Respeta el master Pos Spoof (LIP.posSpoof): ON = desync (cuerpo/cámara
-- reales quietos), OFF = teleport crudo del cuerpo real. Compone con el mismo Spoof que Void/Strafe.
return function(require, LIP, Lib)
    local Players   = game:GetService("Players")
    local Workspace = game:GetService("Workspace")
    local LP = Players.LocalPlayer
    local Spoof = require("Combat.Spoof")
    local Void  = require("Movement.Void")   -- reusa patternCF (misma lógica de patrones)
    local CFD = {}

    local function myRoot() local c = LP.Character; return c and c:FindFirstChild("HumanoidRootPart") end

    -- desync self-anchored: goCF = patternCF(tu_pos_real, dist, pattern). Igual que Void.tick pero anchor = self.
    function CFD.tick(opts)
        local root = myRoot(); local cam = Workspace.CurrentCamera
        if not root then Spoof.stop(cam); return end
        local anchor = root.Position                       -- ANCHOR = tu pos REAL (restaurada por RenderStepped)
        local goCF = Void.patternCF(anchor, opts.dist or 30, opts.pattern or "Random")
        LIP.spoofFakePos = goCF.Position
        LIP.tightFollow = false
        if opts.posSpoof ~= false then
            -- DESYNC: server te ve en goCF (desyncado de tu pos real), cuerpo/cámara reales quietos.
            if LIP.connRep then Spoof.unweld() end
            local realCF = Spoof.captureReal(root)
            LIP.cachedRoot   = root
            LIP.spoofRealCF  = realCF
            LIP.spoofOn      = true
            LIP.spoofVel     = root.AssemblyLinearVelocity
            LIP.spoofRestore = realCF
            Spoof.camToLocal(cam, realCF)
            pcall(function() root.CFrame = goCF end)
        else
            -- teleport crudo del cuerpo real (riesgoso; respeta Pos Spoof OFF)
            if LIP.spoofOn or LIP.connRep then Spoof.stop(cam) end
            pcall(function() root.CFrame = goCF; root.AssemblyLinearVelocity = Vector3.zero end)
        end
    end

    function CFD.stop() Spoof.stop(Workspace.CurrentCamera) end
    function CFD.init() Spoof.init() end   -- Spoof.init idempotente (compartido con Void/Strafe)

    return CFD
end
