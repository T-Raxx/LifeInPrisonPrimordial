-- Visuals/HitEffects.lua — FACTORY. Hitsounds + killsounds + hitmarker visual (X que se desvanece).
-- Hit = op46 Hitmarker (server→cliente, confirma TU hit; payload = pos 3D del impacto). Kill = enemigo
-- muere con un hit tuyo reciente. Sonidos por SoundService:PlayLocalSound (local, no lo oyen los demás).
-- Todo client-side puro = cero ban risk. IDs/volumen/pitch/color configurables.
return function(require, LIP, Lib)
    local Players      = game:GetService("Players")
    local RunService   = game:GetService("RunService")
    local Workspace    = game:GetService("Workspace")
    local SoundService = game:GetService("SoundService")
    local Debris       = game:GetService("Debris")
    local LP = Players.LocalPlayer
    local HE = {}

    local WHITE = Color3.new(1, 1, 1)
    local function O(f) local o = Lib.Options[f]; return o and o.Value end
    local function T(f) local t = Lib.Toggles[f]; return t and t.Value end

    local function playSound(id, vol, pitch)
        id = tostring(id or "")
        if id == "" or id == "0" then return end
        local s = Instance.new("Sound")
        s.SoundId    = id:find("rbxassetid") and id or ("rbxassetid://" .. id)
        s.Volume     = vol or 2
        s.PlaybackSpeed = pitch or 1
        s.Parent     = SoundService
        local ok = pcall(function() SoundService:PlayLocalSound(s) end)
        if not ok then pcall(function() s.Parent = LP:FindFirstChildOfClass("PlayerGui") or Workspace; s:Play() end) end
        Debris:AddItem(s, 5)
    end

    -- ── HITMARKER (pool de X de 4 líneas Drawing, fade) ──
    local FADE = 0.45
    local pool, poolI = {}, 0
    local function mkSet()
        local set = { lines = {}, untilT = 0, pos = nil }
        for i = 1, 4 do local l = Drawing.new("Line"); l.Thickness = 2; l.Visible = false; set.lines[i] = l end
        return set
    end
    local function showHitmarker(worldPos)
        poolI = (poolI % 6) + 1
        pool[poolI] = pool[poolI] or mkSet()
        pool[poolI].pos = worldPos
        pool[poolI].untilT = os.clock() + FADE
    end
    local function renderMarks()
        local cam = Workspace.CurrentCamera
        local gap = O("HitMarkGap") or 4
        local len = O("HitMarkSize") or 7
        local col = O("HitMarkColor") or WHITE
        local now = os.clock()
        for _, set in pairs(pool) do
            local live = set.untilT > now and set.pos
            if live then
                local sp, on = cam:WorldToViewportPoint(set.pos)
                if on and sp.Z > 0 then
                    local x, y = sp.X, sp.Y
                    local a = 1 - (set.untilT - now) / FADE   -- transparencia 0→1 (fade out)
                    local seg = {
                        {  gap,  gap,  gap + len,  gap + len },
                        { -gap, -gap, -gap - len, -gap - len },
                        {  gap, -gap,  gap + len, -gap - len },
                        { -gap,  gap, -gap - len,  gap + len },
                    }
                    for i = 1, 4 do
                        local l = set.lines[i]
                        l.From = Vector2.new(x + seg[i][1], y + seg[i][2])
                        l.To   = Vector2.new(x + seg[i][3], y + seg[i][4])
                        l.Color = col; l.Transparency = math.clamp(a, 0, 1); l.Visible = true
                    end
                else for i = 1, 4 do set.lines[i].Visible = false end end
            else for i = 1, 4 do if set.lines[i] then set.lines[i].Visible = false end end end
        end
    end

    function HE.hit(worldPos)
        if T("HitSound") then playSound(O("HitSoundId") or "4499400560", O("HitVol") or 2, O("HitPitch") or 1) end
        if T("HitMarker") and worldPos then showHitmarker(worldPos) end
        LIP.lastHitT = os.clock()
    end
    function HE.kill()
        if T("KillSound") then playSound(O("KillSoundId") or "8394333801", O("KillVol") or 3, O("KillPitch") or 1) end
    end

    function HE.init()
        LIP.RE = LIP.RE or (LIP.Events and LIP.Events:FindFirstChild("RemoteEvent"))
        -- HITS: op46 Hitmarker del server (confirma tu hit; arg2 = pos 3D del impacto)
        if LIP.RE then
            LIP.track(LIP.RE.OnClientEvent:Connect(function(op, a)
                if op == 46 then HE.hit(typeof(a) == "Vector3" and a or nil) end
            end))
        end
        -- KILLS: enemigo muere con un hit tuyo reciente (<2.5s)
        local function hookChar(plr, char)
            local h = char and char:FindFirstChildOfClass("Humanoid")
            if not h then return end
            LIP.track(h.Died:Connect(function()
                if LP.Team and plr.Team == LP.Team then return end
                if LIP.lastHitT and (os.clock() - LIP.lastHitT) < 2.5 then HE.kill() end
            end))
        end
        local function watch(plr)
            if plr == LP then return end
            if plr.Character then hookChar(plr, plr.Character) end
            LIP.track(plr.CharacterAdded:Connect(function(c) hookChar(plr, c) end))
        end
        for _, p in ipairs(Players:GetPlayers()) do watch(p) end
        LIP.track(Players.PlayerAdded:Connect(watch))
        LIP.track(RunService.RenderStepped:Connect(function() pcall(renderMarks) end))
        LIP.onCleanup(function()
            for _, set in pairs(pool) do for _, l in ipairs(set.lines) do pcall(function() l:Remove() end) end end
        end)
    end

    return HE
end
