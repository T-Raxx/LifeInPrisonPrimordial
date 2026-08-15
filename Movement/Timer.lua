-- Movement/Timer.lua — FACTORY. Game-speed timer (idéntico al de Minecraft/vape): acelera la SIMULACIÓN local
-- vía StepPhysics selectivo sobre tu rootpart → tu time() avanza más rápido → el fire loop del arma
-- (`if firerate <= time()-lastfire`) y el reload (ambos time()-based) clarean más rápido en tiempo REAL →
-- rapidfire + reload rápido LEGAL (GST=f22(time()) consistente, deltas legales → server acepta, sin unequip).
-- op14-spam directo NO sirve (server valida el delta del GST → unequip). Timer = la única rapidfire viable.
--
-- DINÁMICO (pedido usuario): el mult depende de la fase para minimizar el lag de replicación que causa la
-- aceleración → solo acelera en la ventana de disparo, el void te esconde durante el lag:
--   · reloading         → TimerReload  (recarga rápida, override; puede pasar in-void con Void Reload)
--   · void spam OUT      → TimerOut     (rapidfire en la ventana de disparo)
--   · void spam IN       → 1            (escondido, sin acelerar → replicación normal del hide)
--   · sin void spam      → TimerStatic  (mult manual constante)
-- Caveats (aceptados): FPS drops por los pasos extra de física + lag de replicación (se combate con spam de
-- tiros + Connection Weld). El AC de teleports está muerto → StepPhysics del movimiento no flaggea.
return function(require, LIP, Lib)
    local RunService = game:GetService("RunService")
    local Workspace  = game:GetService("Workspace")
    local LP = game:GetService("Players").LocalPlayer
    local Timer = {}

    local function O(f) local o = Lib.Options[f]; return o and o.Value end
    local function T(f) local t = Lib.Toggles[f]; return t and t.Value end

    -- fflags necesarios para StepPhysics manual (una vez, al activar)
    local fflagsSet = false
    local function ensureFflags()
        if fflagsSet then return end
        pcall(function()
            setfflag("SimEnableStepPhysics", "True")
            setfflag("SimEnableStepPhysicsSelective", "True")
        end)
        fflagsSet = true
    end

    -- mult DINÁMICO según la fase actual (reload > void-out > void-in > static)
    function Timer.currentMult()
        if not T("Ragebot") then return 1 end   -- gateado por el master ragebot (el Timer vive en el árbol)
        if not T("Timer") then return 1 end
        if LIP.reloading then return O("TimerReload") or 1 end
        if LIP.voidSpamOn then
            if LIP.voidPhase == "out" then return O("TimerOut") or 1
            else return 1 end                                  -- IN void (o transición): normal, sin acelerar
        end
        return O("TimerStatic") or 1
    end

    function Timer.init()
        LIP.track(RunService.RenderStepped:Connect(function(dt)
            if not T("Timer") then return end
            ensureFflags()
            local mult = Timer.currentMult()
            if not mult or mult <= 1 then return end
            local c = LP.Character
            local root = c and c:FindFirstChild("HumanoidRootPart")
            if not root then return end
            pcall(function()
                RunService:Pause()
                Workspace:StepPhysics(dt * (mult - 1), { root })   -- pasos extra SOLO en tu rootpart
                RunService:Run()
            end)
        end))
    end

    return Timer
end
