-- Script: put in ServerScriptService (same folder as PromptData + AnswerJudge)
-- Flow: Lobby -> Countdown -> InMatch -> Podium -> back to Lobby

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PromptData = require(script.Parent.PromptData)
local AnswerJudge = require(script.Parent.AnswerJudge)
local AnswerLog = require(script.Parent.AnswerLog)

Players.CharacterAutoLoads = false -- menu-style game, no characters

-- tweak these
local ROUNDS_PER_MATCH = 3
local ANSWER_TIME = 20
local RESULTS_TIME = 6
local COUNTDOWN_TIME = 5
local PODIUM_TIME = 20         -- max time on the podium screen before everyone goes back to lobby
local MIN_PLAYERS = 1          -- set to 2+ once you're testing with friends
local SHARED_ANSWER_MULT = 0.5 -- same answer as someone else = half points
local CHECK_COOLDOWN = 0.3     -- stops people spamming checks to dig up the answer list

---------------------------------------------------------------- remotes

local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage

local function makeRemote(name)
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end

local NewPrompt = makeRemote("NewPrompt")
local SubmitAnswer = makeRemote("SubmitAnswer")
local RoundResults = makeRemote("RoundResults")
local MatchOver = makeRemote("MatchOver")
local LobbyAction = makeRemote("LobbyAction") -- client -> server: "ready", "unready", "start", "playAgain", "toLobby"

local CheckAnswer = Instance.new("RemoteFunction")
CheckAnswer.Name = "CheckAnswer"
CheckAnswer.Parent = remotes

---------------------------------------------------------------- state
-- Clients read these through attributes:
--   ReplicatedStorage: GameState, Countdown, HostUserId
--   each Player: Ready, InMatch

local state = "Lobby"
local forceStart = false
local participants = {}  -- [player] = true for everyone in the current match
local podiumChoices = {} -- [player] = true once they picked Play again / Back to lobby
local joinOrder = {}     -- first person in the list is host

local scores = {}
local submissions = {}
local acceptingAnswers = false
local currentPrompt = nil
local lastCheck = {}

local function setState(s)
	state = s
	ReplicatedStorage:SetAttribute("GameState", s)
end
setState("Lobby")

local function updateHost()
	local host = joinOrder[1]
	ReplicatedStorage:SetAttribute("HostUserId", host and host.UserId or 0)
end

local function onPlayerAdded(player)
	player:SetAttribute("Ready", false)
	player:SetAttribute("InMatch", false)
	table.insert(joinOrder, player)
	updateHost()
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do
	onPlayerAdded(p)
end

Players.PlayerRemoving:Connect(function(player)
	local i = table.find(joinOrder, player)
	if i then
		table.remove(joinOrder, i)
	end
	updateHost()
	participants[player] = nil
	lastCheck[player] = nil
end)

local function participantList()
	local list = {}
	for p in pairs(participants) do
		if p.Parent then
			table.insert(list, p)
		end
	end
	return list
end

local function fireParticipants(remote, ...)
	for _, p in ipairs(participantList()) do
		remote:FireClient(p, ...)
	end
end

local function allReady()
	local list = Players:GetPlayers()
	if #list < MIN_PLAYERS then
		return false
	end
	for _, p in ipairs(list) do
		if not p:GetAttribute("Ready") then
			return false
		end
	end
	return true
end

---------------------------------------------------------------- lobby actions

LobbyAction.OnServerEvent:Connect(function(player, action)
	if action == "ready" or action == "unready" then
		if state == "Lobby" or state == "Countdown" then
			player:SetAttribute("Ready", action == "ready")
		end
	elseif action == "start" then
		if state == "Lobby" and player.UserId == ReplicatedStorage:GetAttribute("HostUserId") then
			forceStart = true
		end
	elseif action == "playAgain" or action == "toLobby" then
		if state == "Podium" and participants[player] then
			player:SetAttribute("Ready", action == "playAgain")
			podiumChoices[player] = true
		end
	end
end)

---------------------------------------------------------------- answers

CheckAnswer.OnServerInvoke = function(player, answer)
	if not acceptingAnswers or not currentPrompt or not participants[player] then return "closed" end
	if typeof(answer) ~= "string" or #answer > 50 then return "invalid" end

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

SubmitAnswer.OnServerEvent:Connect(function(player, answer)
	if not acceptingAnswers or not currentPrompt or not participants[player] then return end
	if typeof(answer) ~= "string" or #answer > 50 then return end
	if submissions[player] then return end
	if AnswerJudge.check(currentPrompt, answer) ~= "valid" then return end
	submissions[player] = answer
end)

local function scoreRound(prompt)
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
	AnswerLog.logRound(prompt, #participantList(), submitted)

	local results = {}
	for player, j in pairs(judged) do
		local points = j.points
		if j.tier and counts[j.answer] > 1 then
			points = math.floor(points * SHARED_ANSWER_MULT)
		end
		scores[player] = (scores[player] or 0) + points

		table.insert(results, {
			name = player.DisplayName,
			answer = j.answer and AnswerJudge.prettify(j.answer) or "?",
			tier = j.tier or "Invalid",
			points = points,
			total = scores[player],
		})
	end

	table.sort(results, function(a, b) return a.points > b.points end)
	return results
end

local function everyoneAnswered()
	for _, p in ipairs(participantList()) do
		if not submissions[p] then
			return false
		end
	end
	return true
end

---------------------------------------------------------------- phases

local function countdownHolds()
	if #Players:GetPlayers() < MIN_PLAYERS then
		return false
	end
	return forceStart or allReady()
end

-- blocks until a countdown finishes without getting cancelled
local function waitForStart()
	while true do
		forceStart = false
		setState("Lobby")
		repeat
			task.wait(0.2)
		until countdownHolds()

		setState("Countdown")
		local ok = true
		for t = COUNTDOWN_TIME, 1, -1 do
			ReplicatedStorage:SetAttribute("Countdown", t)
			for _ = 1, 10 do
				task.wait(0.1)
				if not countdownHolds() then
					ok = false -- someone unreadied or left
					break
				end
			end
			if not ok then break end
		end
		if ok then return end
	end
end

local function startMatch()
	participants = {}
	for _, p in ipairs(Players:GetPlayers()) do
		participants[p] = true
		p:SetAttribute("InMatch", true)
		p:SetAttribute("Ready", false)
	end
	setState("InMatch")
end

-- returns true if the match finished, false if everyone left
local function runMatch()
	scores = {}
	for p in pairs(participants) do
		scores[p] = 0
	end

	local prompts = PromptData.pickPrompts(ROUNDS_PER_MATCH)
	for round, prompt in ipairs(prompts) do
		if #participantList() == 0 then
			return false
		end

		submissions = {}
		currentPrompt = prompt
		acceptingAnswers = true
		fireParticipants(NewPrompt, prompt.text, ANSWER_TIME, round, #prompts)

		local deadline = os.clock() + ANSWER_TIME
		while os.clock() < deadline and not everyoneAnswered() do
			task.wait(0.25)
		end

		acceptingAnswers = false
		fireParticipants(RoundResults, scoreRound(prompt))
		currentPrompt = nil
		task.wait(RESULTS_TIME)
	end

	local standings = {}
	for p, s in pairs(scores) do
		if p.Parent then
			table.insert(standings, { name = p.DisplayName, score = s })
		end
	end
	table.sort(standings, function(a, b) return a.score > b.score end)
	fireParticipants(MatchOver, standings)
	return true
end

-- podium stays up until every player picks a button, or PODIUM_TIME runs out
local function runPodium()
	podiumChoices = {}
	setState("Podium")
	local deadline = os.clock() + PODIUM_TIME
	while os.clock() < deadline do
		local allChose = true
		for _, p in ipairs(participantList()) do
			if not podiumChoices[p] then
				allChose = false
				break
			end
		end
		if allChose then break end
		task.wait(0.2)
	end
end

local function endMatch()
	for _, p in ipairs(Players:GetPlayers()) do
		p:SetAttribute("InMatch", false)
	end
	participants = {}
end

---------------------------------------------------------------- main loop

while true do
	waitForStart()
	startMatch()

	-- Without this, any error inside a match kills this thread for good: the server
	-- would sit in InMatch forever and every client would hang with no way out.
	-- Dropping back to the lobby loses a match, which is a far better failure.
	local ok, err = pcall(function()
		if runMatch() then
			runPodium()
		end
	end)
	if not ok then
		warn(("[RoundManager] match failed, returning everyone to the lobby: %s"):format(tostring(err)))
		acceptingAnswers = false
		currentPrompt = nil
	end

	endMatch()
end
