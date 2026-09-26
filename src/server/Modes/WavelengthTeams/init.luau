-- ModuleScript: ServerScriptService > Modes > WavelengthTeams
--
-- Two teams play the same dial at the same time, each with its own hidden target and
-- its own clue giver. A team's clue goes only to that team, so nothing here may use
-- ctx.send during the clue or guess phases: every message is ctx.sendTo, per player.
-- Broadcasting a clue would hand the other team the answer.
--
-- Every guesser's points go into their team's total, and each round every member of a
-- team is awarded the team's points. That way the shell's own per-player standings
-- already read as team standings on the podium, with no shell changes.

local Wavelength = require(script.Parent.Parent.Shared.Wavelength)
local Spectrums = require(script.Parent.Parent.Shared.Spectrums)
local Categories = require(script.Parent.Parent.Shared.Categories)
local TextFilter = require(script.Parent.Parent.Shared.TextFilter)

local WavelengthTeams = {
	name = "Wavelength Teams",
	blurb = "Two teams, two clues, one dial",
	minPlayers = 4,
	rounds = 6,
}

-- tweak these
local CLUE_TIME = 30
local GUESS_TIME = 20
local REVEAL_TIME = 8
local MAX_CLUE_LEN = 40
local CATEGORY_CHOICES = 3
local TEAM_NAMES = { "Red", "Blue" }

-- per-match state
local spectrums = {}
local teamOf = {}    -- [player] = 1 or 2
local teamScore = { 0, 0 }
local phase = nil    -- nil | "clue" | "guess"
local targets = {}   -- [team] = 0..1
local givers = {}    -- [team] = player
local options = {}   -- [team] = { category names }
local chosen = {}    -- [team] = category name
local clues = {}     -- [team] = raw text
local guesses = {}   -- [player] = 0..1

---------------------------------------------------------------- helpers

-- live members of a team, in stable order
local function members(ctx, team)
	local list = {}
	for _, p in ipairs(Wavelength.orderedPlayers(ctx)) do
		if teamOf[p] == team then
			table.insert(list, p)
		end
	end
	return list
end

local function giverTeam(player)
	for team, giver in pairs(givers) do
		if giver == player then
			return team
		end
	end
	return nil
end

---------------------------------------------------------------- match hooks

function WavelengthTeams.beginMatch(ctx)
	teamOf = {}
	teamScore = { 0, 0 }
	targets, givers, options, chosen, clues, guesses = {}, {}, {}, {}, {}, {}
	phase = nil

	-- alternate down a stable ordering, so teams are balanced and repeatable
	for i, p in ipairs(Wavelength.orderedPlayers(ctx)) do
		teamOf[p] = (i % 2) + 1
	end

	spectrums = Spectrums.pick(ctx.rounds)
	ctx.rounds = #spectrums
end

function WavelengthTeams.runRound(ctx, round)
	local spectrum = spectrums[round]
	if not spectrum then return end

	targets, givers, options, chosen, clues, guesses = {}, {}, {}, {}, {}, {}

	for team = 1, 2 do
		local roster = members(ctx, team)
		if #roster > 0 then
			targets[team] = Wavelength.newTarget()
			givers[team] = roster[((round - 1) % #roster) + 1]
			options[team] = Categories.pick(CATEGORY_CHOICES)
		end
	end

	-- per player, never broadcast: only your own team's clue giver and categories
	for team = 1, 2 do
		local giver = givers[team]
		for _, p in ipairs(members(ctx, team)) do
			local isGiver = giver == p
			ctx.sendTo(p, "round", {
				round = round,
				rounds = ctx.rounds,
				left = spectrum.left,
				right = spectrum.right,
				teamName = TEAM_NAMES[team],
				giverName = giver and giver.DisplayName or "?",
				isGiver = isGiver,
				seconds = CLUE_TIME,
				categories = isGiver and options[team] or nil,
			})
			if isGiver then
				ctx.sendTo(p, "target", targets[team])
			end
		end
	end

	phase = "clue"
	ctx.waitUntil(CLUE_TIME, function()
		for team = 1, 2 do
			if givers[team] and not clues[team] then
				return false
			end
		end
		return true
	end)
	phase = nil

	local shown = {}
	for team = 1, 2 do
		if clues[team] then
			shown[team] = TextFilter.forBroadcast(clues[team], givers[team].UserId)
		else
			shown[team] = "(no clue given)"
		end
	end

	-- again per player: the other team must not see this
	local anyClue = false
	for team = 1, 2 do
		if clues[team] then anyClue = true end
		for _, p in ipairs(members(ctx, team)) do
			ctx.sendTo(p, "clue", {
				category = chosen[team] or "",
				text = shown[team],
				seconds = clues[team] and GUESS_TIME or 0,
			})
		end
	end

	if anyClue then
		phase = "guess"
		ctx.waitUntil(GUESS_TIME, function()
			for team = 1, 2 do
				if clues[team] then
					for _, p in ipairs(members(ctx, team)) do
						if p ~= givers[team] and not guesses[p] then
							return false
						end
					end
				end
			end
			return true
		end)
		phase = nil
	end

	local roundPoints = { 0, 0 }
	local placed = { {}, {} }
	for team = 1, 2 do
		if targets[team] then
			for _, p in ipairs(members(ctx, team)) do
				if p ~= givers[team] and guesses[p] then
					local pts = Wavelength.score(math.abs(guesses[p] - targets[team]))
					roundPoints[team] += pts
					table.insert(placed[team], guesses[p])
				end
			end
		end
	end

	for team = 1, 2 do
		teamScore[team] += roundPoints[team]
		if roundPoints[team] > 0 then
			for _, p in ipairs(members(ctx, team)) do
				ctx.award(p, roundPoints[team])
			end
		end
	end

	-- the reveal is the one moment everything is public
	ctx.send("reveal", {
		teamNames = TEAM_NAMES,
		targets = { targets[1] or -1, targets[2] or -1 },
		guesses = placed,
		clues = shown,
		categories = { chosen[1] or "", chosen[2] or "" },
		points = roundPoints,
		totals = teamScore,
	})

	task.wait(REVEAL_TIME)
end

function WavelengthTeams.endMatch()
	phase = nil
	targets, givers, options, chosen, clues, guesses = {}, {}, {}, {}, {}, {}
end

function WavelengthTeams.playerLeft(_, player)
	guesses[player] = nil
	local team = giverTeam(player)
	if team then
		givers[team] = nil -- that team's clue phase just times out
	end
	teamOf[player] = nil
end

---------------------------------------------------------------- client messages

function WavelengthTeams.onEvent(_, player, kind, a, b)
	if kind == "clue" then
		if phase ~= "clue" then return end
		local team = giverTeam(player)
		if not team or clues[team] then return end
		if typeof(a) ~= "number" or not (options[team] and options[team][a]) then return end
		local text = Wavelength.cleanClue(b, MAX_CLUE_LEN)
		if not text then return end
		chosen[team] = options[team][a]
		clues[team] = text
	elseif kind == "guess" then
		if phase ~= "guess" then return end
		local team = teamOf[player]
		-- clue givers don't guess, and nobody guesses before their team has a clue
		if not team or givers[team] == player or not clues[team] then return end
		if guesses[player] then return end
		if typeof(a) ~= "number" or a ~= a then return end -- NaN check
		guesses[player] = math.clamp(a, 0, 1)
	end
end

return WavelengthTeams
