-- This file will not be overwritten across dots-hyprland updates.
-- The file name is for the sake of organization and does not matter
-- See the corresponding files in ~/.config/hypr/hyprland for examples

require("custom.wsextra")

hl.bind("SUPER + U", hl.dsp.exec_cmd("wayscriber --daemon-toggle"), { description = "App: Wayscriber" })
hl.bind("SUPER + B", hl.dsp.exec_cmd("nwg-drawer -d"), { description = "App: nwg-drawer" })
-- Mousekeys handles Super+H internally through its input daemon.
hl.bind("SUPER + ALT + D", hl.dsp.exec_cmd("$HOME/.local/bin/toggle-hyprland-dock-autohide"),
    { description = "Dock: Toggle auto-hide" })
hl.bind("SUPER + ALT + SHIFT + D", hl.dsp.exec_cmd("$HOME/.local/bin/toggle-hyprland-dock"),
    { description = "Dock: Toggle visibility" })

-- Open the Waffle search on a standalone Super tap, but not after a chord.
hl.unbind("SUPER + SUPER_L")
hl.unbind("SUPER + SUPER_R")
local superTapCandidate = false
local superTapFirstEvent = false
for _, key in ipairs({ "SUPER_L", "SUPER_R" }) do
    hl.bind(key, function()
        superTapCandidate = true
        superTapFirstEvent = true
    end,
        { ignore_mods = true, transparent = true })
    hl.bind(key, function()
        if superTapCandidate then
            hl.dispatch(hl.dsp.exec_cmd("qs -c $qsConfig ipc call waffleSearch toggle"))
        end
        superTapCandidate = false
    end, { release = true, ignore_mods = true, transparent = true })
end
hl.bind("SUPER + catchall", function()
    if superTapCandidate then
        if superTapFirstEvent then
            superTapFirstEvent = false
        else
            superTapCandidate = false
        end
    end
end, { non_consuming = true, transparent = true })

-- Keep the terminal launcher on Super+T only.
hl.unbind("SUPER + T")
hl.bind("SUPER + T", hl.dsp.exec_cmd(terminal), { description = "App: Terminal" })

hl.bind("CTRL + SUPER + ALT + Space", hl.dsp.window.center(), { description = "Window: Center" })

-- Correct the overview labels for the existing PageUp/PageDown window moves.
hl.unbind("SUPER + SHIFT + Page_Up")
hl.unbind("SUPER + SHIFT + Page_Down")
hl.bind("SUPER + SHIFT + Page_Up", hl.dsp.window.move({ workspace = "r-1" }),
    { description = "Window: Send to workspace right" })
hl.bind("SUPER + SHIFT + Page_Down", hl.dsp.window.move({ workspace = "r+1" }),
    { description = "Window: Send to workspace left" })

-- Remove unused unmodified navigation shortcuts.
for _, key in ipairs({ "Page_Up", "Page_Down", "Home", "End" }) do
    hl.unbind("SUPER + " .. key)
end

-- Resize the active window with Super+Alt+Arrow.
local resizeKeys = { "Left", "Right", "Up", "Down" }
local resizeDeltas = { -50, 50, 50, -50 }
for i = 1, #resizeKeys do
    hl.bind("SUPER + ALT + " .. resizeKeys[i],
        hl.dsp.window.resize({
            x = i <= 2 and resizeDeltas[i] or 0,
            y = i > 2 and resizeDeltas[i] or 0,
            relative = true,
        }),
        { repeating = true, description = "Window: Resize " .. resizeKeys[i] })
end

-- Send the active window to a relative workspace.
hl.unbind("SUPER + ALT + Page_Up")
hl.unbind("SUPER + ALT + Page_Down")
hl.bind("SUPER + ALT + Page_Up", hl.dsp.window.move({ workspace = "r+1" }),
    { description = "Window: Send to workspace +1" })
hl.bind("SUPER + ALT + Page_Down", hl.dsp.window.move({ workspace = "r-1" }),
    { description = "Window: Send to workspace -1" })

hl.unbind("SUPER + ALT + Home")
hl.unbind("SUPER + ALT + End")
hl.bind("SUPER + ALT + Home", hl.dsp.window.move({ workspace = "r+10" }),
    { description = "Window: Send to workspace +10" })
hl.bind("SUPER + ALT + End", hl.dsp.window.move({ workspace = "r-10" }),
    { description = "Window: Send to workspace -10" })

hl.unbind("CTRL + SUPER + Page_Up")
hl.unbind("CTRL + SUPER + Page_Down")
hl.bind("CTRL + SUPER + Page_Up", hl.dsp.focus({ workspace = "r+1" }),
    { description = "Workspace: Focus next" })
hl.bind("CTRL + SUPER + Page_Down", hl.dsp.focus({ workspace = "r-1" }),
    { description = "Workspace: Focus previous" })

for _, key in ipairs({ "Home", "End" }) do
    hl.unbind("CTRL + SUPER + " .. key)
end
hl.bind("CTRL + SUPER + Home", hl.dsp.focus({ workspace = "r+10" }),
    { description = "Workspace: Focus +10" })
hl.bind("CTRL + SUPER + End", hl.dsp.focus({ workspace = "r-10" }),
    { description = "Workspace: Focus -10" })

for _, key in ipairs({ "Up", "Down" }) do
    hl.unbind("CTRL + SUPER + SHIFT + " .. key)
end
hl.bind("CTRL + SUPER + SHIFT + Up", hl.dsp.window.move({ workspace = "r+10" }),
    { description = "Window: Send to workspace +10" })
hl.bind("CTRL + SUPER + SHIFT + Down", hl.dsp.window.move({ workspace = "r-10" }),
    { description = "Window: Send to workspace -10" })

-- With two side-by-side tiled Dwindle windows, stack the active window above
-- or below the other. Keep these keys inactive for every other arrangement.
local function stackSideBySideWindow(direction)
    local active = hl.get_active_window()
    local workspace = active and active.workspace
    if not active then
        return
    end

    if active.floating then
        hl.dispatch(hl.dsp.window.move({ direction = direction == "Up" and "u" or "d" }))
        return
    end

    if not workspace or workspace.tiled_layout ~= "dwindle" then
        return
    end

    local tiledWindows = {}
    for _, window in ipairs(hl.get_workspace_windows(workspace)) do
        if not window.floating then
            table.insert(tiledWindows, window)
        end
    end
    if #tiledWindows ~= 2 then
        return
    end

    local other = tiledWindows[1].address == active.address and tiledWindows[2] or tiledWindows[1]
    local overlapX = math.max(0, math.min(active.at.x + active.size.x, other.at.x + other.size.x)
        - math.max(active.at.x, other.at.x))
    local overlapY = math.max(0, math.min(active.at.y + active.size.y, other.at.y + other.size.y)
        - math.max(active.at.y, other.at.y))
    local overlapXRatio = overlapX / math.min(active.size.x, other.size.x)
    local overlapYRatio = overlapY / math.min(active.size.y, other.size.y)

    -- Side-by-side windows overlap vertically, but not horizontally.
    if overlapXRatio >= overlapYRatio then
        return
    end

    local activeOnLeft = active.at.x < other.at.x
    local shouldSwap = (direction == "Up" and not activeOnLeft)
        or (direction == "Down" and activeOnLeft)
    if shouldSwap then
        hl.dispatch(hl.dsp.layout("swapsplit"))
    end
    hl.dispatch(hl.dsp.layout("togglesplit"))
end

for _, direction in ipairs({ "Up", "Down" }) do
    hl.unbind("SUPER + SHIFT + " .. direction)
    hl.bind("SUPER + SHIFT + " .. direction, function()
        stackSideBySideWindow(direction)
    end, {
        description = direction == "Up" and "Window: Stack above / Float up" or "Window: Stack below / Float down",
    })
end

-- CTRL+SUPER+Up/Down: saltar un grupo completo de workspaces (10)
hl.unbind("CTRL + SUPER + Up")
hl.unbind("CTRL + SUPER + Down")

hl.bind("CTRL + SUPER + Up", function()
    local cur = hl.get_active_workspace().id
    if cur + 10 <= 100 then
        hl.dispatch(hl.dsp.focus({ workspace = cur + 10 }))
    end
end, { description = "Workspace: Saltar +10 (siguiente grupo)" })

hl.bind("CTRL + SUPER + Down", function()
    local cur = hl.get_active_workspace().id
    if cur - 10 >= 1 then
        hl.dispatch(hl.dsp.focus({ workspace = cur - 10 }))
    end
end, { description = "Workspace: Saltar -10 (grupo anterior)" })
