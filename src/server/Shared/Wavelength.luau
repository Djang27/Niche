-- ModuleScript: ServerScriptService > Shared > Wavelength
-- Rules every Wavelength mode agrees on, plus a factory for the rotating ones.
--
-- Solo and Co-op run the identical round - one clue giver, everyone else guessing, the
-- clue giver rotating so each player takes the job once per rotation - and differ only
-- in who banks the points. They are built from `newRotatingMode` rather than copied.
-- Teams has a genuinely different flow and writes its own round.

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

---------------------------------------------------------------- rotating modes

local CLUE_TIME = 30 -- picking a category happens inside this, so it is a little longer
local GUESS_TIME = 20
local REVEAL_TIME = 8
local MAX_CLUE_LEN = 40
local CATEGORY_CHOICES = 3
local MAX_ROUNDS = 10 -- a big lobby shouldn't turn into a twenty minute match

-- config: { name, blurb, minPlayers, maxPlayers, rotations, shared }
--
-- Round length is derived, not fixed: every player gives the clue once per rotation, so
-- `rounds = players * rotations`. `shared` pools every point into one score for the room
-- (co-op) instead of paying individuals (competitive).
function Wavelength.newRotatingMode(config)
	local mode = {
		name = config.name,
		blurb = config.blurb,
		minPlayers = config.minPlayers,
		maxPlayers = config.maxPlayers,
		rounds = config.minPlayers, -- placeholder, recomputed from the real roster
	}

	-- state lives in this closure, so two modes built from this factory never share it
	local spectrums = {}
	local currentSpectrum, target = nil, nil
	local hinter = nil
	local phase = nil -- nil | "clue" | "guess"
	local categoryOptions, chosenCategory = {}, nil
	local clue = nil
	local guesses = {} -- [player] = 0..1
	local sharedTotal, roundsPlayed = 0, 0

	function mode.beginMatch(ctx)
		currentSpectrum, target, hinter = nil, nil, nil
		phase, clue, chosenCategory = nil, nil, nil
		categoryOptions, guesses = {}, {}
		sharedTotal, roundsPlayed = 0, 0

		local wanted = #Wavelength.orderedPlayers(ctx) * (config.rotations or 1)
		spectrums = Spectrums.pick(math.clamp(wanted, 1, MAX_ROUNDS))
		ctx.rounds = #spectrums
	end

	function mode.runRound(ctx, round)
		currentSpectrum = spectrums[round]
		if not currentSpectrum then return end

		local list = Wavelength.orderedPlayers(ctx)
		if #list < 2 then return end -- nobody left to guess

		-- one clue giver per round, rotating so everyone takes a turn
		hinter = list[((round - 1) % #list) + 1]
		target = Wavelength.newTarget()
		clue, chosenCategory = nil, nil
		guesses = {}
		roundsPlayed += 1
		categoryOptions = Categories.pickFor(currentSpectrum, CATEGORY_CHOICES)

		-- UserId, not DisplayName: display names are not unique, so the client must not
		-- work out whose turn it is by comparing them
		ctx.send("round", {
			round = round,
			rounds = ctx.rounds,
			left = currentSpectrum.left,
			right = currentSpectrum.right,
			hinterId = hinter.UserId,
			hinterName = hinter.DisplayName,
			seconds = CLUE_TIME,
			categories = categoryOptions,
		})
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
		-- 0 seconds means there is nothing to guess at, so the dial never arms
		ctx.send("clue", {
			category = chosenCategory or "",
			text = shown,
			seconds = clue and GUESS_TIME or 0,
		})

		if clue then
			phase = "guess"
			ctx.waitUntil(GUESS_TIME, function()
				for _, p in ipairs(ctx.players()) do
					if p ~= hinter and not guesses[p] then
						return false
					end
				end
				return true
			end)
			phase = nil
		end

		-- every guesser scores their own accuracy
		local scored, total, count = {}, 0, 0
		for _, p in ipairs(Wavelength.orderedPlayers(ctx)) do
			if p ~= hinter then
				count += 1
				local pts, label = 0, "No guess"
				if guesses[p] then
					pts, label = Wavelength.score(math.abs(guesses[p] - target))
				end
				total += pts
				table.insert(scored, { player = p, guess = guesses[p], points = pts, label = label })
			end
		end

		-- the clue giver is paid the floor of what their clue earned on average, so a
		-- clue that only one person reads correctly is worth less than one everybody gets
		local hinterPoints = count > 0 and math.floor(total / count) or 0

		if config.shared then
			-- co-op: one score for the room, so everyone banks the same points
			sharedTotal += total
			for _, p in ipairs(ctx.players()) do
				ctx.award(p, total)
			end
		else
			for _, row in ipairs(scored) do
				if row.points > 0 then
					ctx.award(row.player, row.points)
				end
			end
			if hinterPoints > 0 then
				ctx.award(hinter, hinterPoints)
			end
		end

		local rows = {}
		for _, row in ipairs(scored) do
			table.insert(rows, {
				name = row.player.DisplayName,
				guess = row.guess,
				points = row.points,
				total = ctx.scoreOf(row.player),
			})
		end

		ctx.send("reveal", {
			target = target,
			rows = rows,
			hinterName = hinter.DisplayName,
			hinterPoints = hinterPoints,
			hinterTotal = ctx.scoreOf(hinter),
			roomTotal = config.shared and sharedTotal or nil,
		})

		task.wait(REVEAL_TIME)
	end

	function mode.endMatch()
		phase = nil
		currentSpectrum, target, hinter = nil, nil, nil
		clue, chosenCategory = nil, nil
		categoryOptions, guesses = {}, {}
	end

	function mode.playerLeft(_, player)
		guesses[player] = nil
		if hinter == player then
			hinter = nil -- the clue phase just times out
		end
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
			if phase ~= "guess" or player == hinter or guesses[player] then return end
			if typeof(a) ~= "number" or a ~= a then return end -- NaN check
			guesses[player] = math.clamp(a, 0, 1)
		end
	end

	return mode
end

return Wavelength
