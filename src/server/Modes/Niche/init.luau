-- ModuleScript: ServerScriptService > Modes > Niche
-- The original game: one prompt per round, rarer answers score more.
--
-- The shell (RoundManager) owns the lobby, scores and podium. This module owns
-- everything specific to Niche: which prompt, how long, and what an answer is worth.

local PromptData = require(script.PromptData)
local AnswerJudge = require(script.AnswerJudge)
local AnswerLog = require(script.AnswerLog)

local Niche = {
	name = "Niche",
	blurb = "The rarer your answer, the more points",
	minPlayers = 1,
	rounds = 3,
}

-- tweak these
local ANSWER_TIME = 20
local RESULTS_TIME = 6
local SHARED_ANSWER_MULT = 0.5 -- same answer as someone else = half points
local CHECK_COOLDOWN = 0.3     -- stops people spamming checks to dig up the answer list
local MAX_ANSWER_LEN = 50

-- per-match state, reset in beginMatch
local prompts = {}
local currentPrompt = nil
local accepting = false
local submissions = {}
local lastCheck = {}

---------------------------------------------------------------- scoring

local function everyoneAnswered(ctx)
	for _, p in ipairs(ctx.players()) do
		if not submissions[p] then
			return false
		end
	end
	return true
end

local function scoreRound(ctx, prompt)
	local judged = {}
	local counts = {}

	for player, raw in pairs(submissions) do
		if player.Parent then
			local answer, tier, points = AnswerJudge.judge(prompt, raw)
			judged[player] = { answer = answer, tier = tier, points = points }
			if tier then
				counts[answer] = (counts[answer] or 0) + 1
			end
		end
	end

	local submitted = {}
	for _, j in pairs(judged) do
		if j.answer then
			table.insert(submitted, j.answer)
		end
	end
	AnswerLog.logRound(prompt, #ctx.players(), submitted)

	local results = {}
	for player, j in pairs(judged) do
		local points = j.points
		if j.tier and counts[j.answer] > 1 then
			points = math.floor(points * SHARED_ANSWER_MULT)
		end
		ctx.award(player, points)

		table.insert(results, {
			name = player.DisplayName,
			answer = j.answer and AnswerJudge.prettify(j.answer) or "?",
			tier = j.tier or "Invalid",
			points = points,
			total = ctx.scoreOf(player),
		})
	end

	table.sort(results, function(a, b) return a.points > b.points end)
	return results
end

---------------------------------------------------------------- match hooks

function Niche.beginMatch(ctx)
	currentPrompt = nil
	accepting = false
	submissions = {}
	lastCheck = {}

	prompts = PromptData.pickPrompts(ctx.rounds)
	-- pickPrompts can come back short if the server has run out of fresh prompts,
	-- so the shell is told how many rounds there actually are
	ctx.rounds = #prompts
end

function Niche.runRound(ctx, round)
	local prompt = prompts[round]
	if not prompt then return end

	submissions = {}
	currentPrompt = prompt
	accepting = true
	ctx.send("prompt", prompt.text, ANSWER_TIME, round, ctx.rounds)

	ctx.waitUntil(ANSWER_TIME, function()
		return everyoneAnswered(ctx)
	end)

	accepting = false
	ctx.send("results", scoreRound(ctx, prompt))
	currentPrompt = nil
	task.wait(RESULTS_TIME)
end

function Niche.endMatch()
	accepting = false
	currentPrompt = nil
	submissions = {}
	lastCheck = {}
end

function Niche.playerLeft(_, player)
	submissions[player] = nil
	lastCheck[player] = nil
end

---------------------------------------------------------------- client messages

-- "check": does this answer count? Answered before the player commits to it.
-- Returns status, canonicalAnswer, displayText (status: valid | suggest | invalid | slow | closed)
function Niche.onRequest(_, player, kind, answer)
	if kind ~= "check" then return nil end
	if not accepting or not currentPrompt then return "closed" end
	if typeof(answer) ~= "string" or #answer > MAX_ANSWER_LEN then return "invalid" end

	local now = os.clock()
	if lastCheck[player] and now - lastCheck[player] < CHECK_COOLDOWN then
		return "slow"
	end
	lastCheck[player] = now

	local status, canonical, display = AnswerJudge.check(currentPrompt, answer)
	-- a rejection usually means the list is missing an answer, a correction means
	-- it's missing an alias. Both are worth knowing about.
	if status == "invalid" then
		AnswerLog.logMiss(currentPrompt, answer)
	elseif status == "suggest" then
		AnswerLog.logNearMiss(currentPrompt, answer, canonical)
	end
	return status, canonical, display
end

-- "submit": lock an answer in. Re-checked here, never trust the client.
function Niche.onEvent(_, player, kind, answer)
	if kind ~= "submit" then return end
	if not accepting or not currentPrompt then return end
	if typeof(answer) ~= "string" or #answer > MAX_ANSWER_LEN then return end
	if submissions[player] then return end
	if AnswerJudge.check(currentPrompt, answer) ~= "valid" then return end
	submissions[player] = answer
end

return Niche
