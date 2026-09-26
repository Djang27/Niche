-- ModuleScript: StarterPlayerScripts > Modes > WavelengthSolo
-- Competitive pairs. The screen itself is the shared dial.

local WavelengthDial = require(script.Parent.Parent.WavelengthDial)

local mode = WavelengthDial.new({ coop = false })

mode.name = "Wavelength Solo"
mode.blurb = "Rotating pairs, highest score wins"
mode.group = "Wavelength" -- shares the Wavelength button with Teams and Co-op
mode.variant = "Solo"

return mode
