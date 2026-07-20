-- Core/State.lua — FACTORY. Estado global único getgenv().LIP, tracking de conns/hooks,
-- Unload, guard doble-carga, helper fire(op,...) del RemoteEvent multiplexado (netevgen).
-- (el param LIP se ignora aquí: State ES quien crea LIP y lo pone en getgenv)
return function(require, _unused, Lib)
    -- neutralizar build viejo ANTES de nada (hooks stale deben pasar transparentes)
    if getgenv().LIP then
        local old = getgenv().LIP
        old.enabled = false
        old.swapOn  = false          -- __namecall silent-aim viejo pasa transparente
        if old.Unload then pcall(old.Unload) end
    end

    local RS = game:GetService("ReplicatedStorage")

    local LIP = {
        enabled   = false,           -- master del engine
        swapOn    = false,           -- silent aim arg-swap activo
        target    = nil,             -- Player resuelto
        conns     = {},              -- RBXScriptConnections trackeadas
        -- refs cacheadas del framework netevgen (1 RemoteEvent multiplexado, opcode=arg1)
        Events    = RS:FindFirstChild("Events"),
    }
    LIP.RE = LIP.Events and LIP.Events:FindFirstChild("RemoteEvent")
    getgenv().LIP = LIP

    -- dispara el RemoteEvent multiplexado con opcode + payload. Único punto de salida.
    function LIP.fire(op, ...)
        if LIP.RE then LIP.RE:FireServer(op, ...) end
    end

    function LIP.track(c) LIP.conns[#LIP.conns + 1] = c ; return c end

    function LIP.Unload()
        LIP.enabled, LIP.swapOn = false, false
        for _, c in ipairs(LIP.conns) do pcall(function() c:Disconnect() end) end
        LIP.conns = {}
        -- los hooks (__namecall) NO se desinstalan (hookmetamethod); pasan transparentes
        -- porque leen getgenv().LIP dinámico y queda swapOn=false.
        if LIP.Library then pcall(function() LIP.Library:Unload() end) end
    end

    return LIP
end
