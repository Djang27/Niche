-- ModuleScript: ServerScriptService > Modes > WavelengthSolo
--
-- Competitive pairs: each round one player gives a clue and one guesses, both score the
-- same points, and the pair rotates so everyone takes both jobs. Everyone else watches.
--
-- minPlayers is 3 on purpose. With exactly two players the pair is always the same two
-- people and both always score identically, so the match could only ever end in a tie.
-- Two players who want to play together want Co-op, which is honest about that.

local Wavelength = require(script.Parent.Parent.Shared.Wavelength)

return Wavelength.newPairMode({
	name = "Wavelength Solo",
	blurb = "Rotating pairs, highest score wins",
	minPlayers = 3,
	maxPlayers = 4,
	rounds = 6,
	shared = false,
})
