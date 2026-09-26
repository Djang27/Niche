-- ModuleScript: ServerScriptService > Modes > WavelengthCoop
--
-- The same rotating round as Solo - one clue giver, everyone else guessing - but there is
-- no opponent: every point goes into one score for the whole room, and the podium reports
-- the total instead of a winner.
--
-- Two rotations rather than Solo's one, so a pair doesn't get a two-round match.

local Wavelength = require(script.Parent.Parent.Shared.Wavelength)

return Wavelength.newRotatingMode({
	name = "Wavelength Co-op",
	blurb = "One score for the room, beat your best",
	minPlayers = 2,
	maxPlayers = 4,
	rotations = 2, -- 4 to 8 rounds depending on the roster
	shared = true,
})
