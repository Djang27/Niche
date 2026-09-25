-- LocalScript: StarterPlayer > StarterPlayerScripts
-- The shell around every mode's screen: lobby, podium, and which one is showing.
--
-- The middle screen belongs to whichever mode the server has active. Each module in
-- Modes/ exposes { name, blurb, build(parent, api) -> frame, onEvent(kind, ...), reset() }
-- and the shell just shows or hides the frame build() handed back.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local UiKit = require(script.Parent:WaitForChild("UiKit"))

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

---------------------------------------------------------------- base

local gui = UiKit.make("ScreenGui", {
	Name = "NicheGui", ResetOnSpawn = false, IgnoreGuiInset = true,
	Parent = player:WaitForChild("PlayerGui"),
})

UiKit.make("Frame", {
	Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(15, 15, 22),
	BorderSizePixel = 0, ZIndex = 0, Parent = gui,
})

---------------------------------------------------------------- modes

-- what a mode screen is allowed to say to its half of the server
local api = {
	send = function(kind, ...)
		remotes.ModeEvent:FireServer(kind, ...)
	end,
	request = function(kind, ...)
		return remotes.ModeRequest:InvokeServer(kind, ...)
	end,
}

local modes = {}

for _, child in ipairs(script.Parent:WaitForChild("Modes"):GetChildren()) do
	if child:IsA("ModuleScript") then
		local ok, mode = pcall(require, child)
		if ok and type(mode) == "table" and type(mode.build) == "function" then
			local built, frame = pcall(mode.build, gui, api)
			if built then
				mode.frame = frame
				modes[child.Name] = mode
			else
				warn(("[GameUI] mode %s failed to build: %s"):format(child.Name, tostring(frame)))
			end
		else
			warn(("[GameUI] couldn't load mode %s: %s"):format(child.Name, tostring(mode)))
		end
	end
end

local function activeMode()
	return modes[ReplicatedStorage:GetAttribute("ActiveMode") or ""]
end

remotes.ModeEvent.OnClientEvent:Connect(function(kind, ...)
	local mode = activeMode()
	if mode and mode.onEvent then
		mode.onEvent(kind, ...)
	end
end)

---------------------------------------------------------------- lobby screen

local lobbyFrame = UiKit.panel(gui)

local titleLabel = UiKit.label(lobbyFrame, {
	Size = UDim2.new(1, -20, 0.14, 0), Position = UDim2.new(0, 10, 0, 10),
	TextScaled = true, Font = Enum.Font.GothamBlack, Text = "NICHE",
})
local blurbLabel = UiKit.label(lobbyFrame, {
	Size = UDim2.new(1, -20, 0.06, 0), Position = UDim2.new(0, 10, 0.15, 0),
	TextScaled = true, TextColor3 = UiKit.DIM, Text = "",
})

local playersLabel = UiKit.label(lobbyFrame, {
	Size = UDim2.new(1, -40, 0.45, 0), Position = UDim2.new(0, 20, 0.25, 0),
	TextSize = 20, RichText = true, TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = "",
})

local statusLabel = UiKit.label(lobbyFrame, {
	Size = UDim2.new(1, -20, 0.07, 0), Position = UDim2.new(0, 10, 0.71, 0),
	TextScaled = true, Font = Enum.Font.GothamMedium, TextColor3 = UiKit.YELLOW, Text = "",
})

local readyButton = UiKit.button(lobbyFrame, "Ready up", UiKit.GREEN,
	UDim2.new(0.5, -15, 0.13, 0), UDim2.new(0, 10, 0.82, 0))
local startButton = UiKit.button(lobbyFrame, "Start now", UiKit.BLUE,
	UDim2.new(0.5, -15, 0.13, 0), UDim2.new(0.5, 5, 0.82, 0))

readyButton.Activated:Connect(function()
	remotes.LobbyAction:FireServer(player:GetAttribute("Ready") and "unready" or "ready")
end)
startButton.Activated:Connect(function()
	remotes.LobbyAction:FireServer("start")
end)

---------------------------------------------------------------- podium screen

local podiumFrame = UiKit.panel(gui)

UiKit.label(podiumFrame, {
	Size = UDim2.new(1, -20, 0.14, 0), Position = UDim2.new(0, 10, 0, 10),
	TextScaled = true, Font = Enum.Font.GothamBlack, Text = "Match over!",
})

local standingsLabel = UiKit.label(podiumFrame, {
	Size = UDim2.new(1, -40, 0.55, 0), Position = UDim2.new(0, 20, 0.18, 0),
	TextSize = 22, RichText = true, TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = "",
})

local playAgainButton = UiKit.button(podiumFrame, "Play again", UiKit.GREEN,
	UDim2.new(0.5, -15, 0.13, 0), UDim2.new(0, 10, 0.82, 0))
local toLobbyButton = UiKit.button(podiumFrame, "Back to lobby", UiKit.GRAY,
	UDim2.new(0.5, -15, 0.13, 0), UDim2.new(0.5, 5, 0.82, 0))

local podiumWaitLabel = UiKit.label(podiumFrame, {
	Size = UDim2.new(1, -20, 0.08, 0), Position = UDim2.new(0, 10, 0.84, 0),
	TextScaled = true, Font = Enum.Font.GothamMedium, TextColor3 = UiKit.YELLOW, Text = "", Visible = false,
})

local function podiumChoice(action, message)
	remotes.LobbyAction:FireServer(action)
	playAgainButton.Visible = false
	toLobbyButton.Visible = false
	podiumWaitLabel.Text = message
	podiumWaitLabel.Visible = true
end

playAgainButton.Activated:Connect(function()
	podiumChoice("playAgain", "You're in! Waiting for the others...")
end)
toLobbyButton.Activated:Connect(function()
	podiumChoice("toLobby", "Heading back to the lobby...")
end)

remotes.MatchOver.OnClientEvent:Connect(function(standings)
	local medals = { "🥇", "🥈", "🥉" }
	local lines = {}
	for i, s in ipairs(standings) do
		table.insert(lines, ("%s %d. %s  <b>%d pts</b>"):format(
			medals[i] or "  ", i, UiKit.escape(s.name), s.score))
	end
	standingsLabel.Text = table.concat(lines, "\n")
	playAgainButton.Visible = true
	toLobbyButton.Visible = true
	podiumWaitLabel.Visible = false

	local mode = activeMode()
	if mode and mode.reset then
		mode.reset()
	end
end)

---------------------------------------------------------------- screen switching

local function renderLobby(state)
	local hostId = ReplicatedStorage:GetAttribute("HostUserId")
	local matchRunning = state == "InMatch" or state == "Podium"
	local ready, total = 0, 0
	local lines = {}

	for _, p in ipairs(Players:GetPlayers()) do
		total += 1
		local isReady = p:GetAttribute("Ready")
		if isReady then ready += 1 end

		local status
		if matchRunning then
			status = p:GetAttribute("InMatch") and '<font color="#4da6ff">playing</font>'
				or '<font color="#b0b0b0">waiting</font>'
		else
			status = isReady and '<font color="#5cd65c">ready</font>'
				or '<font color="#b0b0b0">not ready</font>'
		end
		local crown = p.UserId == hostId and " 👑" or ""
		table.insert(lines, ("%s%s   %s"):format(UiKit.escape(p.DisplayName), crown, status))
	end
	playersLabel.Text = table.concat(lines, "\n")

	local mode = activeMode()
	titleLabel.Text = mode and mode.name:upper() or "NICHE"
	blurbLabel.Text = mode and mode.blurb or ""

	local isHost = player.UserId == hostId
	if state == "Lobby" then
		statusLabel.Text = ("%d/%d ready. Starts when everyone's ready%s"):format(
			ready, total, isHost and ", or hit Start" or "")
	elseif state == "Countdown" then
		statusLabel.Text = ("Starting in %d..."):format(ReplicatedStorage:GetAttribute("Countdown") or 0)
	else
		statusLabel.Text = "Match in progress, you'll be in the next one"
	end

	readyButton.Visible = not matchRunning
	readyButton.Text = player:GetAttribute("Ready") and "Unready" or "Ready up"
	readyButton.BackgroundColor3 = player:GetAttribute("Ready") and UiKit.GRAY or UiKit.GREEN
	startButton.Visible = isHost and state == "Lobby"
end

local function render()
	local state = ReplicatedStorage:GetAttribute("GameState") or "Lobby"
	local inMatch = player:GetAttribute("InMatch")
	local mode = activeMode()

	local screen = "lobby"
	if inMatch and state == "InMatch" then
		screen = "game"
	elseif inMatch and state == "Podium" then
		screen = "podium"
	end

	lobbyFrame.Visible = screen == "lobby"
	podiumFrame.Visible = screen == "podium"

	-- only the active mode's screen is ever visible
	for _, m in pairs(modes) do
		if m.frame then
			m.frame.Visible = (screen == "game" and m == mode)
		end
	end

	if screen == "lobby" then
		renderLobby(state)
	end
end

while true do
	render()
	task.wait(0.2)
end
