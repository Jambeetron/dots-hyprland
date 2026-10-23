-- This file will not be overwritten across dots-hyprland updates.
-- The file name is for the sake of organization and does not matter
-- See the corresponding files in ~/.config/hypr/hyprland for examples

require("custom.wsextra")

hl.bind("SUPER + U", hl.dsp.exec_cmd("wayscriber --daemon-toggle"), { description = "App: Wayscriber" })
hl.bind("SUPER + B", hl.dsp.exec_cmd("nwg-drawer -d"), { description = "App: nwg-drawer" })

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
