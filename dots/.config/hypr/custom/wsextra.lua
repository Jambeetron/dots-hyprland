-- This file will not be overwritten across dots-hyprland updates.
-- The file name is for the sake of organization and does not matter
-- See the corresponding files in ~/.config/hypr/hyprland for examples
--
-- Workspaces extendidos (1-100):
--  * Super (mantener) + digitar numero (1-100) -> cambia de workspace al SOLTAR Super.
--  * Super+Alt (mantener) + digitar numero (1-100) -> envia la ventana activa a ese
--    workspace al soltar Super o Alt, SIN cambiar el workspace actual.
--  * Rueda sobre el area de workspaces de la barra -> cambia ±1.
--  * Super + rueda sobre esa area -> cambia ±10. Fuera del area no actua.
--
-- Los binds originales de un solo digito se desvinculan aqui y se reemplazan,
-- conservando las mismas descripciones ("Workspace: Focus N" / "Window: Send to workspace N").
--
-- Notas tecnicas (Hyprland 0.55):
--  * Un mismo evento de tecla dispara el bind por keysym Y el bind por code:, asi que
--    se usa un flag "consumed" por digito para acumular una sola vez por pulsacion.
--    El flag se limpia al soltar el digito (o al soltar Super/Alt como respaldo).
--  * Los binds de liberacion necesitan transparent = true: si no, Hyprland los
--    "sombrea" (shadowKeybinds) al mantener Super/Alt tras pulsar otra tecla.
--  * El release-bind de SUPER_L/SUPER_R (abajo) no siempre dispara -- sobre todo
--    soltando justo despues de UN solo digito. Por eso el commit real no depende
--    solo de ese bind: cada digito arranca un sondeo (hl.is_key_down, NO un timer
--    de tiempo fijo) que revisa cada 50ms si Super sigue fisicamente presionado;
--    recien cuando deja de estarlo hace el commit. Nunca comete mientras Super
--    sigue abajo, sin importar cuanto tardes en tipear los digitos.

local digits = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" } -- indice i = workspace i (10 -> "0")
local rowcodes = { 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 } -- fila numerica (raw keycodes)
local numpadcodes = { 87, 88, 89, 83, 84, 85, 79, 80, 81, 90 } -- numpad 1..0 (raw keycodes)

local MAX_WS = 100
local MAX_DIGITS = 3
local POLL_MS = 50

local function super_held()
    return hl.is_key_down("Super_L") or hl.is_key_down("Super_R")
end

local function alt_held()
    return hl.is_key_down("Alt_L") or hl.is_key_down("Alt_R")
end

----------------------------------------------------------------------
-- Acumuladores de digitos (estado persiste entre pulsaciones en Lua)
----------------------------------------------------------------------
local switch_buf = ""
local move_buf = ""
local switch_consumed = {} -- por digito: evita doble conteo keysym+code de una misma pulsacion
local move_consumed = {}

-- Referencias a los timers de sondeo en curso. Si no se guardan en algun
-- lado, Lua puede recolectarlas (GC) antes de que lleguen a disparar.
local switch_timer = nil
local move_timer = nil
local switch_polling = false
local move_polling = false

local function commit_switch()
    local n = tonumber(switch_buf)
    switch_buf = ""
    switch_consumed = {}
    if not n then
        return
    end
    if n >= 1 and n <= MAX_WS then
        hl.dispatch(hl.dsp.focus({ workspace = n }))
    else
        hl.notification.create({ text = "Workspace invalido: " .. n .. " (1-" .. MAX_WS .. ")", duration = 1500 })
    end
end

local function commit_move()
    local n = tonumber(move_buf)
    move_buf = ""
    move_consumed = {}
    if not n then
        return
    end
    if n >= 1 and n <= MAX_WS then
        -- follow = false -> mueve la ventana activa SIN cambiar de workspace
        hl.dispatch(hl.dsp.window.move({ workspace = n, follow = false }))
    else
        hl.notification.create({ text = "Workspace invalido: " .. n .. " (1-" .. MAX_WS .. ")", duration = 1500 })
    end
end

-- Mientras Super siga fisicamente presionado, se reprograma cada POLL_MS.
-- Recien cuando el sondeo detecta que ya no esta presionado hace el commit.
local function poll_switch()
    if super_held() then
        switch_timer = hl.timer(poll_switch, { type = "oneshot", timeout = POLL_MS })
    else
        switch_polling = false
        commit_switch()
    end
end

-- El gesto de "enviar a workspace" es Super+Alt+digito; se confirma al
-- soltar cualquiera de los dos (igual que ya hacian ALT_L/ALT_R mas abajo).
local function poll_move()
    if super_held() and alt_held() then
        move_timer = hl.timer(poll_move, { type = "oneshot", timeout = POLL_MS })
    else
        move_polling = false
        commit_move()
    end
end

local function press_switch_digit(d)
    if switch_consumed[d] then
        return
    end
    switch_consumed[d] = true
    if #switch_buf >= MAX_DIGITS then
        return
    end
    switch_buf = switch_buf .. d
    hl.notification.create({ text = "Ir a workspace: " .. switch_buf, duration = 800 })
    if not switch_polling then
        switch_polling = true
        poll_switch()
    end
end

local function press_move_digit(d)
    if move_consumed[d] then
        return
    end
    move_consumed[d] = true
    if #move_buf >= MAX_DIGITS then
        return
    end
    move_buf = move_buf .. d
    hl.notification.create({ text = "Enviar ventana a workspace: " .. move_buf, duration = 800 })
    if not move_polling then
        move_polling = true
        poll_move()
    end
end

local function release_switch_digit(d)
    switch_consumed[d] = nil
end

local function release_move_digit(d)
    move_consumed[d] = nil
end

----------------------------------------------------------------------
-- Reemplazo de binds: Super + numero -> acumular; dispatch al soltar
----------------------------------------------------------------------
for i = 1, 10 do
    local d = digits[i]
    -- Desvincula los defaults (cambio/envio inmediato de un digito)
    hl.unbind("SUPER + " .. d)
    hl.unbind("SUPER + code:" .. rowcodes[i])
    hl.unbind("SUPER + code:" .. numpadcodes[i])
    hl.unbind("SUPER + ALT + " .. d)
    hl.unbind("SUPER + ALT + code:" .. rowcodes[i])
    hl.unbind("SUPER + ALT + code:" .. numpadcodes[i])

    -- Nuevos binds: solo acumulan; no actuan hasta soltar Super / Super+Alt.
    -- Mismas descripciones que los originales.
    hl.bind("SUPER + " .. d, function() press_switch_digit(d) end, { description = "Workspace: Focus " .. i })
    hl.bind("SUPER + code:" .. rowcodes[i], function() press_switch_digit(d) end)
    hl.bind("SUPER + code:" .. numpadcodes[i], function() press_switch_digit(d) end)

    hl.bind("SUPER + ALT + " .. d, function() press_move_digit(d) end, { description = "Window: Send to workspace " .. i })
    hl.bind("SUPER + ALT + code:" .. rowcodes[i], function() press_move_digit(d) end)
    hl.bind("SUPER + ALT + code:" .. numpadcodes[i], function() press_move_digit(d) end)

    -- Liberacion del digito: permite volver a pulsar el mismo digito dentro del gesto
    hl.bind("SUPER + " .. d, function() release_switch_digit(d) end, { release = true })
    hl.bind("SUPER + code:" .. rowcodes[i], function() release_switch_digit(d) end, { release = true })
    hl.bind("SUPER + code:" .. numpadcodes[i], function() release_switch_digit(d) end, { release = true })
    hl.bind("SUPER + ALT + " .. d, function() release_move_digit(d) end, { release = true })
    hl.bind("SUPER + ALT + code:" .. rowcodes[i], function() release_move_digit(d) end, { release = true })
    hl.bind("SUPER + ALT + code:" .. numpadcodes[i], function() release_move_digit(d) end, { release = true })
end

-- Al soltar Super: ejecuta el cambio de workspace (y/o el envio pendiente).
-- El tap de Super para abrir search ya NO se evalua aqui -- lo maneja el bind
-- oficial "SUPER + SUPER_L/R" release en hyprland/keybinds.lua (exec_cmd,
-- sombreado normal de Hyprland), que es independiente de este bind sobre
-- SUPER_L/R suelto y no se pisan entre si.
-- ignore_mods = que dispare aunque Alt (u otro mod) siga presionado.
-- transparent = evita que Hyprland sombree el bind mientras Super sigue pulsado.
local function on_super_release()
    commit_switch()
    commit_move()
end
hl.bind("SUPER_L", on_super_release,
    { release = true, ignore_mods = true, transparent = true, description = "Workspace: Commit extended switch/move" })
hl.bind("SUPER_R", on_super_release, { release = true, ignore_mods = true, transparent = true })

-- Al soltar Alt (gesto Super+Alt): ejecuta solo el envio de ventana.
hl.bind("ALT_L", function()
    commit_move()
end, { release = true, ignore_mods = true, transparent = true })
hl.bind("ALT_R", function()
    commit_move()
end, { release = true, ignore_mods = true, transparent = true })

----------------------------------------------------------------------
-- Scroll sobre la barra: de 1 en 1, o de 10 en 10 con Super
----------------------------------------------------------------------
hl.unbind("mouse_up")
hl.unbind("mouse_down")
hl.unbind("SUPER + mouse_up")
hl.unbind("SUPER + mouse_down")

-- Unmodified wheel scrolling remains handled only by Workspaces.qml on the bar.
hl.bind("mouse_down", function() end, {
    non_consuming = true,
    description = "Workspace: Focus next (over bar)",
})
hl.bind("mouse_up", function() end, {
    non_consuming = true,
    description = "Workspace: Focus previous (over bar)",
})
-- Super + wheel: forward to Quickshell instead of dispatching focus here.
-- A previous version dispatched +-1 from Lua AND let the bar (non_consuming)
-- separately dispatch its own group-of-10 correction -- two independent
-- dispatches for one scroll notch, which raced and caused a visible flicker
-- to the wrong workspace before the correction landed. Now Quickshell
-- (GlobalStates.superScroll) is the only thing that ever dispatches focus
-- for this gesture; it decides +-1 vs +-10 based on whether the bar's
-- workspace widget is hovered, with no second dispatch to race against.
hl.bind("SUPER + mouse_down", hl.dsp.global("quickshell:superScrollDown"), {
    description = "Workspace: Focus -1 outside / -10 on bar",
})
hl.bind("SUPER + mouse_up", hl.dsp.global("quickshell:superScrollUp"), {
    description = "Workspace: Focus +1 outside / +10 on bar",
})
