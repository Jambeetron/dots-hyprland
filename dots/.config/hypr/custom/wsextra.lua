-- This file will not be overwritten across dots-hyprland updates.
-- The file name is for the sake of organization and does not matter
-- See the corresponding files in ~/.config/hypr/hyprland for examples
--
-- Extended workspaces (1-100):
--  * Super (hold) + type a number (1-100) -> switch workspace on Super RELEASE.
--  * Super+Alt (hold) + type a number (1-100) -> send the active window to that
--    workspace on Super or Alt release, WITHOUT changing the current workspace.
--  * Wheel over the bar's workspace area -> moves ±1.
--  * Super + wheel over that area -> moves ±10. Does nothing outside of it.
--
-- The original single-digit binds are unbound here and replaced, keeping the
-- same descriptions ("Workspace: Focus N" / "Window: Send to workspace N").
--
-- Technical notes (Hyprland 0.55):
--  * A single key event fires both the keysym bind AND the code: bind, so a
--    per-digit "consumed" flag makes each press accumulate only once.
--    The flag is cleared when the digit is released (or on Super/Alt release as a fallback).
--  * Release binds need transparent = true: otherwise Hyprland "shadows" them
--    (shadowKeybinds) while Super/Alt is held after pressing another key.
--  * The SUPER_L/SUPER_R release bind (below) doesn't always fire -- especially
--    when released right after a SINGLE digit. So the real commit doesn't rely
--    on that bind alone: each digit starts a poll (hl.is_key_down, NOT a
--    fixed-time timer) that checks every 50ms whether Super is still physically
--    held; only once it isn't does it commit. It never commits while Super is
--    still down, no matter how long you take to type the digits.

local digits = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" } -- index i = workspace i (10 -> "0")
local rowcodes = { 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 } -- number row (raw keycodes)
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
-- Digit accumulators (state persists across presses in Lua)
----------------------------------------------------------------------
local switch_buf = ""
local move_buf = ""
local switch_consumed = {} -- per digit: avoids double-counting keysym+code for the same press
local move_consumed = {}

-- References to the running poll timers. If they aren't stored somewhere,
-- Lua may garbage-collect them before they get to fire.
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
        -- follow = false -> moves the active window WITHOUT changing workspace
        hl.dispatch(hl.dsp.window.move({ workspace = n, follow = false }))
    else
        hl.notification.create({ text = "Workspace invalido: " .. n .. " (1-" .. MAX_WS .. ")", duration = 1500 })
    end
end

-- While Super is still physically held, it reschedules itself every POLL_MS.
-- Only once the poll sees it released does it commit.
local function poll_switch()
    if super_held() then
        switch_timer = hl.timer(poll_switch, { type = "oneshot", timeout = POLL_MS })
    else
        switch_polling = false
        commit_switch()
    end
end

-- The "send to workspace" gesture is Super+Alt+digit; it is confirmed when
-- either one is released (as ALT_L/ALT_R below already did).
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
-- Bind replacement: Super + number -> accumulate; dispatch on release
----------------------------------------------------------------------
for i = 1, 10 do
    local d = digits[i]
    -- Unbind the defaults (immediate single-digit switch/send)
    hl.unbind("SUPER + " .. d)
    hl.unbind("SUPER + code:" .. rowcodes[i])
    hl.unbind("SUPER + code:" .. numpadcodes[i])
    hl.unbind("SUPER + ALT + " .. d)
    hl.unbind("SUPER + ALT + code:" .. rowcodes[i])
    hl.unbind("SUPER + ALT + code:" .. numpadcodes[i])

    -- New binds: only accumulate; nothing happens until Super / Super+Alt is released.
    -- Same descriptions as the originals.
    hl.bind("SUPER + " .. d, function() press_switch_digit(d) end, { description = "Workspace: Focus " .. i })
    hl.bind("SUPER + code:" .. rowcodes[i], function() press_switch_digit(d) end)
    hl.bind("SUPER + code:" .. numpadcodes[i], function() press_switch_digit(d) end)

    hl.bind("SUPER + ALT + " .. d, function() press_move_digit(d) end, { description = "Window: Send to workspace " .. i })
    hl.bind("SUPER + ALT + code:" .. rowcodes[i], function() press_move_digit(d) end)
    hl.bind("SUPER + ALT + code:" .. numpadcodes[i], function() press_move_digit(d) end)

    -- Digit release: allows pressing the same digit again within the gesture
    hl.bind("SUPER + " .. d, function() release_switch_digit(d) end, { release = true })
    hl.bind("SUPER + code:" .. rowcodes[i], function() release_switch_digit(d) end, { release = true })
    hl.bind("SUPER + code:" .. numpadcodes[i], function() release_switch_digit(d) end, { release = true })
    hl.bind("SUPER + ALT + " .. d, function() release_move_digit(d) end, { release = true })
    hl.bind("SUPER + ALT + code:" .. rowcodes[i], function() release_move_digit(d) end, { release = true })
    hl.bind("SUPER + ALT + code:" .. numpadcodes[i], function() release_move_digit(d) end, { release = true })
end

-- On Super release: perform the workspace switch (and/or the pending send).
-- The Super tap that opens search is NOT evaluated here anymore -- it's handled
-- by the official "SUPER + SUPER_L/R" release bind in hyprland/keybinds.lua
-- (exec_cmd, normal Hyprland shadowing), which is independent of this bare
-- SUPER_L/R bind, so they don't step on each other.
-- ignore_mods = fire even if Alt (or another mod) is still held.
-- transparent = keeps Hyprland from shadowing the bind while Super is held.
local function on_super_release()
    commit_switch()
    commit_move()
end
hl.bind("SUPER_L", on_super_release,
    { release = true, ignore_mods = true, transparent = true, description = "Workspace: Commit extended switch/move" })
hl.bind("SUPER_R", on_super_release, { release = true, ignore_mods = true, transparent = true })

-- On Alt release (Super+Alt gesture): perform only the window send.
hl.bind("ALT_L", function()
    commit_move()
end, { release = true, ignore_mods = true, transparent = true })
hl.bind("ALT_R", function()
    commit_move()
end, { release = true, ignore_mods = true, transparent = true })

----------------------------------------------------------------------
-- Scrolling over the bar: by 1, or by 10 with Super
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
