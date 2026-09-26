-- ModuleScript: ServerScriptService > Shared > Wavelength
-- Rules both Wavelength modes agree on, plus a factory for the pair-based ones.
--
-- Solo and Co-op run the identical round (one clue giver, one guesser, rotating) and
-- differ only in who the points go to, so they are built from `newPairMode` rather than
-- copied. Teams has a genuinely different flow and builds its own round.

local Spectrums = require(script.Parent.Spectrums)
local Categories = require(script.Parent.Categories)
local TextFilter = require(script.Parent.TextFilter)

local Wavelength = {}

-- how close the guess has to be, and what it pays
Wavelength.BANDS = {
	{ within = 0.04, points = 4, label = "Dead on!" },
	{ within = 0.10, points = 3, label = "So close" },
	{ within = 0.18, points = 2, label = "Close enough" },
}

Wavelength.MAX_POINTS = 4

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

---------------------------------------------------------------- pair-based modes

local CLUE_TIME = 30 -- picking a category happens inside this, so it is a little longer
local GUESS_TIME = 20
local REVEAL_TIME = 7
local MAX_CLUE_LEN = 40
local CATEGORY_CHOICES = 3

-- config: { name, blurb, minPlayers, maxPlayers, rounds, shared }
-- `shared` makes every player score the round's points together (co-op) instead of
-- only the pair scoring it (competitive).
function Wavelength.newPairMode(config)
	local mode = {
		name = config.name,
		blurb = config.blurb,
		minPlayers = config.minPlayers,
		maxPlayers = config.maxPlayers,
		rounds = config.rounds or 6,
	}

	-- state lives in this closure, so two modes built from this factory never share it
	local spectrums = {}
	local currentSpectrum, target = nil, nil
	local hinter, guesser = nil, nil
	local phase = nil -- nil | "clue" | "guess"
	local categoryOptions, chosenCategory = {}, nil
	local clue, guess = nil, nil
	local sharedTotal, roundsPlayed = 0, 0

	local function pickPair(ctx, round)
		local list = Wavelength.orderedPlayers(ctx)
		if #list < 2 then
			return nil, nil
		end
		local i = ((round - 1) % #list) + 1
		local j = (i % #list) + 1
		return list[i], list[j]
	end

	function mode.beginMatch(ctx)
		currentSpectrum, target, hinter, guesser = nil, nil, nil, nil
		phase, clue, guess, chosenCategory = nil, nil, nil, nil
		categoryOptions = {}
		sharedTotal, roundsPlayed = 0, 0

		spectrums = Spectrums.pick(ctx.rounds)
		ctx.rounds = #spectrums
	end

	function mode.runRound(ctx, round)
		currentSpectrum = spectrums[round]
		if not currentSpectrum then return end

		hinter, guesser = pickPair(ctx, round)
		if not hinter or not guesser then return end -- too few players left

		target = Wavelength.newTarget()
		clue, guess, chosenCategory = nil, nil, nil
		categoryOptions = Categories.pick(CATEGORY_CHOICES)
		roundsPlayed += 1

		-- UserIds go with the names: display names are not unique, so the client must
		-- not work out whose turn it is by comparing them
		ctx.send("round", round, ctx.rounds,
			currentSpectrum.left, currentSpectrum.right,
			hinter.UserId, hinter.DisplayName,
			guesser.UserId, guesser.DisplayName,
			CLUE_TIME, categoryOptions)
		ctx.sendTo(hinter, "target", target)

		phase = "clue"
		ctx.waitUntil(CLUE_TIME, function()
			return clue ~= nil
		end)
		phase = nil

		local shown
		if clue then
			-- free-form player text going to everyone, so it is filtered first
			shown = TextFilter.forBroadcast(clue, hinter.UserId)
		else
			shown = "(no clue given)"
		end
		-- 0 seconds tells the client there is nothing to guess at, so it doesn't briefly
		-- arm the dial before the reveal lands
		ctx.send("clue", chosenCategory or "", shown, clue and GUESS_TIME or 0)

		if clue then
			phase = "guess"
			ctx.waitUntil(GUESS_TIME, function()
				return guess ~= nil
			end)
			phase = nil
		end

		local points, label = 0, "No guess"
		if guess then
			points, label = Wavelength.score(math.abs(guess - target))
		end

		if points > 0 then
			if config.shared then
				-- co-op: one score for the room, so everyone banks the same points
				sharedTotal += points
				for _, p in ipairs(ctx.players()) do
					ctx.award(p, points)
				end
			else
				ctx.award(hinter, points)
				ctx.award(guesser, points)
			end
		end

		ctx.send("reveal", target, guess, points, label,
			hinter.DisplayName, guesser.DisplayName,
			ctx.scoreOf(hinter), ctx.scoreOf(guesser))

		task.wait(REVEAL_TIME)
	end

	function mode.endMatch()
		phase = nil
		currentSpectrum, target, hinter, guesser = nil, nil, nil, nil
		clue, guess, chosenCategory = nil, nil, nil
		categoryOptions = {}
	end

	function mode.playerLeft(_, player)
		-- the round just times out if whoever left was mid-turn
		if hinter == player then hinter = nil end
		if guesser == player then guesser = nil end
	end

	-- co-op has no winner to crown, so the podium gets a combined line instead
	if config.shared then
		function mode.matchSummary()
			return ("You scored %d together, out of a possible %d"):format(
				sharedTotal, roundsPlayed * Wavelength.MAX_POINTS)
		end
	end

	-- "clue" carries which offered category was picked plus the clue text.
	-- "guess" carries a dial position from 0 to 1.
	function mode.onEvent(_, player, kind, a, b)
		if kind == "clue" then
			if phase ~= "clue" or player ~= hinter or clue then return end
			if typeof(a) ~= "number" or not categoryOptions[a] then return end
			local text = Wavelength.cleanClue(b, MAX_CLUE_LEN)
			if not text then return end
			chosenCategory = categoryOptions[a]
			clue = text
		elseif kind == "guess" then
			if phase ~= "guess" or player ~= guesser or guess then return end
			if typeof(a) ~= "number" or a ~= a then return end -- NaN check
			guess = math.clamp(a, 0, 1)
		end
	end

	return mode
end

return Wavelength
