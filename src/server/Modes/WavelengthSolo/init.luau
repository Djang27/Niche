-- ModuleScript: ServerScriptService > Modes > WavelengthSolo
--
-- Each round picks a pair: one player gives a clue, one player guesses on a dial.
-- Both score the same points, based on how close the guess landed. The pair rotates
-- every round so everyone takes both jobs. Other players watch that round.
--
-- The target position is the whole game, so it goes ONLY to the clue giver via
-- ctx.sendTo. Everyone else learns it at the reveal.

local Spectrums = require(script.Parent.Parent.Shared.Spectrums)
local TextFilter = require(script.Parent.Parent.Shared.TextFilter)

local WavelengthSolo = {
	name = "Wavelength Solo",
	blurb = "Two players, one dial, one clue",
	minPlayers = 2,
	maxPlayers = 4,
	rounds = 6,
}

-- tweak these
local CLUE_TIME = 25
local GUESS_TIME = 20
local REVEAL_TIME = 7
local MAX_CLUE_LEN = 40

-- how close the guess has to be, and what it pays
local BANDS = {
	{ within = 0.04, points = 4, label = "Dead on!" },
	{ within = 0.10, points = 3, label = "So close" },
	{ within = 0.18, points = 2, label = "Close enough" },
}

-- per-match state
local spectrums = {}
local currentSpectrum = nil
local target = nil
local hinter, guesser = nil, nil
local phase = nil -- nil | "clue" | "guess"
local clue = nil
local guess = nil

---------------------------------------------------------------- helpers

local function score(distance)
	for _, band in ipairs(BANDS) do
		if distance <= band.within then
			return band.points, band.label
		end
	end
	return 0, "Way off"
end

-- ctx.players() comes out of a hash table, so the order is not stable between calls.
-- Sorting keeps the pair rotation predictable instead of random each round.
local function orderedPlayers(ctx)
	local list = ctx.players()
	table.sort(list, function(a, b) return a.UserId < b.UserId end)
	return list
end

local function pickPair(ctx, round)
	local list = orderedPlayers(ctx)
	if #list < 2 then
		return nil, nil
	end
	local i = ((round - 1) % #list) + 1
	local j = (i % #list) + 1
	return list[i], list[j]
end

---------------------------------------------------------------- match hooks

function WavelengthSolo.beginMatch(ctx)
	currentSpectrum, target, hinter, guesser = nil, nil, nil, nil
	phase, clue, guess = nil, nil, nil

	spectrums = Spectrums.pick(ctx.rounds)
	ctx.rounds = #spectrums
end

function WavelengthSolo.runRound(ctx, round)
	currentSpectrum = spectrums[round]
	if not currentSpectrum then return end

	hinter, guesser = pickPair(ctx, round)
	if not hinter or not guesser then return end -- too few players left

	-- keep off the very ends, where a clue is barely a puzzle
	target = 0.08 + math.random() * 0.84
	clue, guess = nil, nil

	-- UserIds go with the names: display names are not unique, so the client must not
	-- work out whose turn it is by comparing them
	ctx.send("round", round, ctx.rounds,
		currentSpectrum.left, currentSpectrum.right,
		hinter.UserId, hinter.DisplayName,
		guesser.UserId, guesser.DisplayName, CLUE_TIME)
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
	ctx.send("clue", shown, clue and GUESS_TIME or 0)

	if clue then
		phase = "guess"
		ctx.waitUntil(GUESS_TIME, function()
			return guess ~= nil
		end)
		phase = nil
	end

	local points, label = 0, "No guess"
	if guess then
		points, label = score(math.abs(guess - target))
	end
	if points > 0 then
		ctx.award(hinter, points)
		ctx.award(guesser, points)
	end

	ctx.send("reveal", target, guess, points, label,
		hinter.DisplayName, guesser.DisplayName,
		ctx.scoreOf(hinter), ctx.scoreOf(guesser))

	task.wait(REVEAL_TIME)
end

function WavelengthSolo.endMatch()
	phase = nil
	currentSpectrum, target, hinter, guesser = nil, nil, nil, nil
	clue, guess = nil, nil
end

function WavelengthSolo.playerLeft(_, player)
	-- the round just times out if whoever left was mid-turn
	if hinter == player then hinter = nil end
	if guesser == player then guesser = nil end
end

---------------------------------------------------------------- client messages

function WavelengthSolo.onEvent(_, player, kind, value)
	if kind == "clue" then
		if phase ~= "clue" or player ~= hinter or clue then return end
		if typeof(value) ~= "string" then return end
		local text = value:gsub("^%s+", ""):gsub("%s+$", "")
		if text == "" or #text > MAX_CLUE_LEN then return end
		clue = text
	elseif kind == "guess" then
		if phase ~= "guess" or player ~= guesser or guess then return end
		if typeof(value) ~= "number" or value ~= value then return end -- NaN check
		guess = math.clamp(value, 0, 1)
	end
end

return WavelengthSolo
