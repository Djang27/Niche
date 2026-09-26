-- ModuleScript: ServerScriptService > Modes > WavelengthCoop
--
-- The same rotating-pair round as Solo, but there is no opponent: every point goes into
-- one score for the whole room, and the podium reports the total instead of a winner.
--
-- This is the honest home for two players. In Solo a pair of two would be the same two
-- people every round scoring identically, which can only tie; here that is the point.

local Wavelength = require(script.Parent.Parent.Shared.Wavelength)

return Wavelength.newPairMode({
	name = "Wavelength Co-op",
	blurb = "One score for the room, beat your best",
	minPlayers = 2,
	maxPlayers = 4,
	rounds = 6,
	shared = true,
})
