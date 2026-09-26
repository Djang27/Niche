-- ModuleScript: ServerScriptService > Shared > Wavelength
-- The bits both Wavelength modes agree on: what a guess is worth, where targets land,
-- and how a clue is cleaned before it is trusted.
--
-- Deliberately small. The two modes' round flows are genuinely different (Solo runs one
-- pair, Teams runs both teams at once with private clues), so only the shared rules live
-- here, not a shared round loop.

local Wavelength = {}

-- how close the guess has to be, and what it pays
Wavelength.BANDS = {
	{ within = 0.04, points = 4, label = "Dead on!" },
	{ within = 0.10, points = 3, label = "So close" },
	{ within = 0.18, points = 2, label = "Close enough" },
}

function Wavelength.score(distance)
	for _, band in ipairs(Wavelength.BANDS) do
		if distance <= band.within then
			return band.points, band.label
		end
	end
	return 0, "Way off"
end

-- keep off the very ends, where a clue is barely a puzzle
function Wavelength.newTarget()
	return 0.08 + math.random() * 0.84
end

-- trims and length-checks a clue. Returns nil if it isn't usable, so callers can
-- treat "no clue" and "bad clue" the same way.
function Wavelength.cleanClue(text, maxLen)
	if typeof(text) ~= "string" then
		return nil
	end
	local clean = text:gsub("^%s+", ""):gsub("%s+$", "")
	if clean == "" or #clean > maxLen then
		return nil
	end
	return clean
end

-- ctx.players() comes out of a hash table, so the order is not stable between calls.
-- Sorting keeps rotations and team splits predictable instead of random each round.
function Wavelength.orderedPlayers(ctx)
	local list = ctx.players()
	table.sort(list, function(a, b) return a.UserId < b.UserId end)
	return list
end

return Wavelength
