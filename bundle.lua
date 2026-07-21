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
writefile("LifeInPrisonPrimordial/LifeInPrisonPrimordial.lua", bundle)
local f, err = loadstring(bundle)
print("[BUNDLE] escrito bytes=" .. #bundle .. " compila=" .. tostring(f ~= nil) .. (err and (" err=" .. tostring(err)) or ""))
