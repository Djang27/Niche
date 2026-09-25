-- Script: ServerScriptService > RoundManager
-- The shell every game mode runs inside.
-- Flow: Lobby -> Countdown -> InMatch -> Podium -> back to Lobby
--
-- This file owns the lobby, ready-up, host, countdown, scores, standings and podium.
-- It knows nothing about prompts or answers: a mode in Modes/ owns the round itself.
-- A mode module looks like:
--   { name, blurb, minPlayers, rounds,
--     beginMatch(ctx), runRound(ctx, round), endMatch(ctx), playerLeft(ctx, player),
--     onEvent(ctx, player, kind, ...), onRequest(ctx, player, kind, ...) }
-- Only `runRound` is required.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

Players.CharacterAutoLoads = false -- menu-style game, no characters

-- tweak these
local COUNTDOWN_TIME = 5
local PODIUM_TIME = 20 -- max time on the podium screen before everyone goes back to lobby
local MIN_PLAYERS = 1  -- set to 2+ once you're testing with friends
local DEFAULT_MODE = "Niche"

---------------------------------------------------------------- remotes
-- Built before anything that can fail, so a broken mode never leaves clients
-- hanging forever on WaitForChild("Remotes").

local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage

local function makeRemote(name)
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end

local MatchOver = makeRemote("MatchOver")
local LobbyAction = makeRemote("LobbyAction") -- "ready", "unready", "start", "playAgain", "toLobby"
local ModeEvent = makeRemote("ModeEvent")     -- both directions, first arg is a mode-defined kind

local ModeRequest = Instance.new("RemoteFunction") -- client asks the mode something
ModeRequest.Name = "ModeRequest"
ModeRequest.Parent = remotes

---------------------------------------------------------------- state
-- Clients read these through attributes:
--   ReplicatedStorage: GameState, Countdown, HostUserId, ActiveMode
--   each Player: Ready, InMatch

local state = "Lobby"
local forceStart = false
local participants = {}  -- [player] = true for everyone in the current match
local podiumChoices = {} -- [player] = true once they picked Play again / Back to lobby
local joinOrder = {}     -- first person in the list is host
local scores = {}

local function setState(s)
	state = s
	ReplicatedStorage:SetAttribute("GameState", s)
end
setState("Lobby")

---------------------------------------------------------------- modes

local modes = {}
local activeMode = nil

for _, child in ipairs(script.Parent:WaitForChild("Modes"):GetChildren()) do
	if child:IsA("ModuleScript") then
		local ok, mode = pcall(require, child)
		if ok and type(mode) == "table" and type(mode.runRound) == "function" then
			mode.id = child.Name
			modes[child.Name] = mode
		else
			warn(("[RoundManager] couldn't load mode %s: %s"):format(child.Name, tostring(mode)))
		end
	end
end

activeMode = modes[DEFAULT_MODE]
if not activeMode then
	for _, mode in pairs(modes) do
		activeMode = mode
		break
	end
end

if activeMode then
	ReplicatedStorage:SetAttribute("ActiveMode", activeMode.id)
	print(("[RoundManager] active mode: %s"):format(activeMode.id))
else
	warn("[RoundManager] no playable mode loaded, the lobby will never start a match")
end

---------------------------------------------------------------- players

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

---------------------------------------------------------------- the mode's handle on the match

local ctx = {
	rounds = 0,
}

function ctx.players()
	return participantList()
end

function ctx.isPlaying(player)
	return participants[player] == true
end

function ctx.send(kind, ...)
	fireParticipants(ModeEvent, kind, ...)
end

function ctx.sendTo(player, kind, ...)
	if participants[player] and player.Parent then
		ModeEvent:FireClient(player, kind, ...)
	end
end

function ctx.award(player, points)
	scores[player] = (scores[player] or 0) + points
end

function ctx.scoreOf(player)
	return scores[player] or 0
end

-- waits up to `seconds`, stopping early once `predicate` is true.
-- returns true if it stopped early.
function ctx.waitUntil(seconds, predicate)
	local deadline = os.clock() + seconds
	while os.clock() < deadline do
		if predicate and predicate() then
			return true
		end
		task.wait(0.25)
	end
	return false
end

Players.PlayerRemoving:Connect(function(player)
	local i = table.find(joinOrder, player)
	if i then
		table.remove(joinOrder, i)
	end
	updateHost()
	participants[player] = nil
	scores[player] = nil
	if activeMode and activeMode.playerLeft then
		pcall(activeMode.playerLeft, ctx, player)
	end
end)

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

---------------------------------------------------------------- mode traffic

ModeEvent.OnServerEvent:Connect(function(player, kind, ...)
	if not activeMode or not activeMode.onEvent then return end
	if not participants[player] or typeof(kind) ~= "string" then return end
	activeMode.onEvent(ctx, player, kind, ...)
end)

ModeRequest.OnServerInvoke = function(player, kind, ...)
	if not activeMode or not activeMode.onRequest then return nil end
	if not participants[player] or typeof(kind) ~= "string" then return nil end
	return activeMode.onRequest(ctx, player, kind, ...)
end

---------------------------------------------------------------- phases

local function countdownHolds()
	if not activeMode then
		return false
	end
	if #Players:GetPlayers() < math.max(MIN_PLAYERS, activeMode.minPlayers or 1) then
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
	scores = {}
	for _, p in ipairs(Players:GetPlayers()) do
		participants[p] = true
		scores[p] = 0
		p:SetAttribute("InMatch", true)
		p:SetAttribute("Ready", false)
	end
	setState("InMatch")
end

-- returns true if the match finished, false if everyone left
local function runMatch()
	local mode = activeMode

	ctx.rounds = mode.rounds or 3
	if mode.beginMatch then
		mode.beginMatch(ctx) -- may shorten ctx.rounds
	end

	for round = 1, ctx.rounds do
		if #participantList() == 0 then
			return false
		end
		mode.runRound(ctx, round)
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
	if activeMode and activeMode.endMatch then
		pcall(activeMode.endMatch, ctx)
	end
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
	end

	endMatch()
end
