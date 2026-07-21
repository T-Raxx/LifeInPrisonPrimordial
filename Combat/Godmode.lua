-- Combat/Godmode.lua — NEUTRALIZADO.
-- El godmode por desplazamiento de partes (mover Head/Torso/HRP) = detectado como HBE
-- (Hitbox Expander) por el anticheat SERVER-SIDE → BAN (confirmado en vivo 2026-07-20).
-- NO hay anti-hit seguro por este método: el reverse mostró que el ragdoll SOLO no da inmunidad,
-- y la única forma de anti-hit era mover el hitbox — que es exactamente lo que HBE detecta.
-- → Godmode queda como NO-OP (no mueve nada) + aviso. No re-implementar mover partes.
return function(require, LIP, Lib)
    local God = {}
    local warned = false

    function God.tick()
        if not warned then
            warned = true
            pcall(function()
                if LIP.Library and LIP.Library.Notify then
                    LIP.Library:Notify({ Title = "Godmode desactivado",
                        Description = "Mover el hitbox = ban por HBE. Sin anti-hit seguro por este método.", Time = 7 })
                end
            end)
        end
    end

    function God.stop() warned = false; LIP.godBase = nil end

    return God
end
