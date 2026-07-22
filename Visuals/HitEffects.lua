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

    -- hitsounds/killsounds del script de Overkill del usuario. (En LiP fallan 3: Neverlose Old / Sparkles /
    -- Ouch → asset-type; el resto carga. Los dejamos igual para que matchee la lista de Overkill.)
    HE.HITSOUNDS = {
        Neverlose = "139452805868562", ["Neverlose Old"] = "8679627751", Killsound1 = "75221171330522",
        ["Rust HS"] = "99796705017337", ["Fortnite HS"] = "132390332380260", Bell = "186809061",
        Sparkles = "110241936966089", Ouch = "119713732135343", Break = "125409047699942", Skeet = "83717596220569",
    }
    HE.HITNAMES  = { "Neverlose", "Rust HS", "Fortnite HS", "Killsound1", "Bell", "Break", "Skeet", "Neverlose Old", "Sparkles", "Ouch" }
    HE.KILLSOUNDS = { Killsound1 = "75221171330522", ["Rust HS"] = "99796705017337",
                      ["Fortnite HS"] = "132390332380260", Neverlose = "139452805868562" }
    HE.KILLNAMES  = { "Killsound1", "Rust HS", "Fortnite HS", "Neverlose" }

    -- resuelve el ID: custom (textbox) si está seteado, si no el nombre elegido en el dropdown.
    local function resolveId(customFlag, nameFlag, tbl, fallback)
        local c = O(customFlag)
        if c and tostring(c) ~= "" and tostring(c) ~= "0" then return c end
        return tbl[O(nameFlag) or ""] or fallback
    end

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
        if T("HitSound") then
            playSound(resolveId("HitSoundId", "HitSoundName", HE.HITSOUNDS, "139452805868562"), O("HitVol") or 2, O("HitPitch") or 1)
        end
        if T("HitMarker") and worldPos then showHitmarker(worldPos) end
        LIP.lastHitT = os.clock()
    end
    function HE.kill()
        if T("KillSound") then
            playSound(resolveId("KillSoundId", "KillSoundName", HE.KILLSOUNDS, "75221171330522"), O("KillVol") or 3, O("KillPitch") or 1)
        end
    end

    function HE.init()
        -- HIT/KILL por CORRELACIÓN (como Overkill): TU disparo (LIP.lastShotT, seteado en Net por cada op14)
        -- + el enemigo pierde vida / muere en la ventana → hit/kill. El hitmarker del server (op36 entrante)
        -- es un broadcast global de TODOS los jugadores, no aislable; esto es robusto y solo tuyo.
        -- ¿le estoy pegando YO? = es mi target de silent aim/autofire, o le estoy apuntando (mira <12°).
        -- Filtra los falsos positivos del daño que le hacen OTROS jugadores al mismo enemigo.
        local function aimingAt(char)
            if LIP.target and LIP.target.Character == char then return true end
            local part = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
            if not part then return false end
            local cam = Workspace.CurrentCamera
            local dir = part.Position - cam.CFrame.Position
            if dir.Magnitude < 2 then return true end
            local ang = math.deg(math.acos(math.clamp(cam.CFrame.LookVector:Dot(dir.Unit), -1, 1)))
            return ang < 12
        end
        local function hookChar(plr, char)
            local h = char and char:FindFirstChildOfClass("Humanoid")
            if not h then return end
            local last = h.Health
            local function mine() return not (LP.Team and plr.Team == LP.Team)
                and LIP.lastShotT and (os.clock() - LIP.lastShotT) < 0.3 and aimingAt(char) end
            LIP.track(h.HealthChanged:Connect(function(hp)
                local dropped = hp < (last - 0.5)
                last = hp
                if dropped and mine() then
                    local part = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
                    HE.hit(part and part.Position or nil)
                end
            end))
            LIP.track(h.Died:Connect(function()
                -- kill: enemigo muere apuntándole vos con un disparo reciente (ventana un toque más amplia)
                if not (LP.Team and plr.Team == LP.Team) and LIP.lastShotT
                   and (os.clock() - LIP.lastShotT) < 1.0 and aimingAt(char) then HE.kill() end
            end))
        end
        local function watch(plr)
            if plr == LP then return end
            if plr.Character then hookChar(plr, plr.Character) end
            LIP.track(plr.CharacterAdded:Connect(function(c) task.wait(0.3); hookChar(plr, c) end))
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
