-- This file will not be overwritten across dots-hyprland updates.
-- The file name is for the sake of organization and does not matter
-- See the corresponding files in ~/.config/hypr/hyprland for examples

require("custom.wsextra")

hl.bind("SUPER + U", hl.dsp.exec_cmd("wayscriber --daemon-toggle"), { description = "App: Wayscriber" })
