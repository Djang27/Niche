-- ModuleScript: StarterPlayerScripts > Modes > WavelengthCoop
-- Same dial as Solo, worded for one shared score instead of a winner.

local WavelengthDial = require(script.Parent.Parent.WavelengthDial)

local mode = WavelengthDial.new({ coop = true })

mode.name = "Wavelength Co-op"
mode.blurb = "One score for the room, beat your best"
mode.group = "Wavelength" -- shares the Wavelength button with Solo and Teams
mode.variant = "Co-op"

return mode
