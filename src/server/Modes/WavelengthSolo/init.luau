-- ModuleScript: ServerScriptService > Modes > WavelengthSolo
--
-- One clue giver per round, everyone else guessing on the dial. The clue giver rotates
-- so every player takes the job exactly once, which is why the match length comes from
-- the roster rather than a fixed number.
--
-- Guessers score their own accuracy. The clue giver is paid the floor of their guessers'
-- average, so a clue only one person reads correctly is worth less than one everybody gets.
--
-- minPlayers is 3 on purpose. At 2 players there is a single guesser, so the clue giver's
-- "average" is just that one score and both players finish level every round - the match
-- could only ever tie. Two players who want to play together want Co-op.

local Wavelength = require(script.Parent.Parent.Shared.Wavelength)

return Wavelength.newRotatingMode({
	name = "Wavelength Solo",
	blurb = "Everyone guesses, the clue giver rotates",
	minPlayers = 3,
	maxPlayers = 4,
	rotations = 1, -- everybody gives the clue once, so 3-4 rounds
	shared = false,
})
