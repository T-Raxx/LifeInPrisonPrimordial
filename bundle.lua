-- bundle.lua — genera `LifeInPrisonPrimordial.lua` (self-contained, PrimordialUI inline) para loadstring.
-- Correr en el executor (Potassium): loadstring(readfile("LifeInPrisonPrimordial/bundle.lua"))()
-- Requiere PrimordialUI/dist/PrimordialUI.lua en el workspace. Ver docs/ops.md.
loadstring(readfile("LifeInPrisonPrimordial/build.lua"))()   -- rebuild dist actual
task.wait(0.3)
local lip  = readfile("LifeInPrisonPrimordial/dist/LifeInPrisonPrimordial.lua")
local prim = readfile("PrimordialUI/dist/PrimordialUI.lua")
local target = 'loadstring(readfile("PrimordialUI/dist/PrimordialUI.lua"))()'
local a, b = string.find(lip, target, 1, true)
if not a then return warn("[BUNDLE] marker de PrimordialUI NO encontrado en el dist") end
-- reemplaza el readfile de PrimordialUI por su fuente inline → bundle self-contained
local bundle = "-- LifeInPrisonPrimordial bundle self-contained (PrimordialUI inline). No editar a mano.\n"
    .. string.sub(lip, 1, a - 1)
    .. "(function()\n" .. prim .. "\nend)()"
    .. string.sub(lip, b + 1)
-- INYECTA el suite World Visuals (GUIVisuals) inline + LIP.Visuals = Visuals. Antes lo hacía build_bundle.ps1
-- (perdido con el scratchpad) → sin esto el bundle sale SIN la sub-tab Visuals (main.lua gatea en LIP.Visuals).
local gvPath = "GUIWorkspace/dist/Visuals.Primordial.lua"
local gvOk, gv = pcall(readfile, gvPath)
if gvOk and gv and #gv > 0 then
    local m1 = "\nlocal LIP\nlocal function require(name)"
    local i1 = string.find(bundle, m1, 1, true)
    if i1 then
        bundle = string.sub(bundle, 1, i1)
            .. "local Visuals = (function()\n" .. gv .. "\nend)()\n"
            .. string.sub(bundle, i1 + 1)
        local m2 = '_MODS["main"](require, LIP, Lib)'
        local i2 = string.find(bundle, m2, 1, true)
        if i2 then
            bundle = string.sub(bundle, 1, i2 - 1) .. "LIP.Visuals = Visuals\n" .. string.sub(bundle, i2)
        else
            warn("[BUNDLE] marker _MODS[main] NO encontrado — LIP.Visuals no seteado")
        end
    else
        warn("[BUNDLE] marker 'local LIP' NO encontrado — GUIVisuals no inlineado")
    end
else
    warn("[BUNDLE] " .. gvPath .. " no encontrado — bundle SIN World Visuals (sub-tab Visuals faltará)")
end
writefile("LifeInPrisonPrimordial/LifeInPrisonPrimordial.lua", bundle)
local f, err = loadstring(bundle)
print("[BUNDLE] escrito bytes=" .. #bundle .. " compila=" .. tostring(f ~= nil) .. (err and (" err=" .. tostring(err)) or ""))
