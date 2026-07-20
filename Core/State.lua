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
        cleanups  = {},              -- funciones de limpieza (destruir instancias en Unload)
        -- refs cacheadas del framework netevgen (1 RemoteEvent multiplexado, opcode=arg1)
        Events    = RS:FindFirstChild("Events"),
    }
    LIP.RE = LIP.Events and LIP.Events:FindFirstChild("RemoteEvent")
    getgenv().LIP = LIP

    -- dispara el RemoteEvent multiplexado con opcode + payload (client→server). Único punto de salida.
    function LIP.fire(op, ...)
        if LIP.RE then LIP.RE:FireServer(op, ...) end
    end

    -- dispara el OnClientEvent LOCAL (el dispatcher del juego rutea por opcode=arg1). Se usa para
    -- entrar por caminos "sancionados" del cliente (ej. buffs op47 → ruta graceada, sin flag AC).
    local firesig = firesignal or replicatesignal
    function LIP.fireLocal(op, ...)
        if LIP.RE and firesig then pcall(firesig, LIP.RE.OnClientEvent, op, ...) end
    end
    LIP.hasFireLocal = firesig ~= nil

    function LIP.track(c) LIP.conns[#LIP.conns + 1] = c ; return c end
    function LIP.onCleanup(fn) LIP.cleanups[#LIP.cleanups + 1] = fn ; return fn end

    function LIP.Unload()
        LIP.enabled, LIP.swapOn = false, false
        for _, fn in ipairs(LIP.cleanups) do pcall(fn) end   -- destruir instancias (fly BV, etc.)
        LIP.cleanups = {}
        for _, c in ipairs(LIP.conns) do pcall(function() c:Disconnect() end) end
        LIP.conns = {}
        -- los hooks (__namecall) NO se desinstalan (hookmetamethod); pasan transparentes
        -- porque leen getgenv().LIP dinámico y queda swapOn=false.
        if LIP.Library then pcall(function() LIP.Library:Unload() end) end
    end

    return LIP
end
