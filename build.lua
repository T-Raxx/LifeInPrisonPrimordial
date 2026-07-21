-- build.lua — concatena módulos (factories) → dist/LifeInPrisonPrimordial.lua (un loadstring).
-- Correr en el executor (Potassium): loadstring(readfile("LifeInPrisonPrimordial/build.lua"))()
-- Rutas relativas al workspace del executor. Ver docs/ops.md.
-- Builds INCREMENTALES: los módulos que aún no existen se saltan (skip), no rompen.
local ORDER = {
    "Core/State.lua",
    "Net.lua",
    "Combat/Target.lua",
    "Combat/Ragdoll.lua",
    "Combat/Melee.lua",
    "Combat/Spoof.lua",
    "Combat/Strafe.lua",
    "Combat/Weapon.lua",
    "Combat/Godmode.lua",
    "Combat/Niche.lua",
    "Combat/Utility.lua",
    "Combat/AutoWeapons.lua",
    "Movement/Movement.lua",
    "Movement/Vehicle.lua",
    "Movement/Void.lua",
    "Visuals/ESP.lua",
    "UI.lua",
    "main.lua",
}
local base = "LifeInPrisonPrimordial/"
local out  = { "-- LifeInPrisonPrimordial — bundle generado por build.lua. No editar a mano.\n" }
out[#out+1] = "local _MODS = {}\n"
for _, path in ipairs(ORDER) do
    if isfile(base .. path) then
        local src = readfile(base .. path)
        local name = path:gsub("%.lua$", ""):gsub("/", ".")
        -- cada módulo es una FACTORY: `return function(require, LIP, Lib) ... end`.
        out[#out+1] = ("_MODS[%q] = (function()\n"):format(name)
        out[#out+1] = src
        out[#out+1] = "\nend)()\n"
    else
        print("[build] skip (no existe aún): " .. path)
    end
end
out[#out+1] = [[
local _cache = {}
local Lib = loadstring(readfile("PrimordialUI/dist/PrimordialUI.lua"))()
local LIP
local function require(name)
    if _cache[name] then return _cache[name] end
    local m = _MODS[name](require, LIP, Lib)
    _cache[name] = m
    return m
end
LIP = _MODS["Core.State"](require, nil, Lib)
_cache["Core.State"] = LIP
LIP.Library = Lib
LIP.require = require
_MODS["main"](require, LIP, Lib)
return LIP
]]
writefile("LifeInPrisonPrimordial/dist/LifeInPrisonPrimordial.lua", table.concat(out))
print("[build] dist/LifeInPrisonPrimordial.lua escrito (" .. #table.concat(out) .. " bytes)")
