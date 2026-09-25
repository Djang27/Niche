-- LocalScript: put in StarterPlayer > StarterPlayerScripts
-- Three screens: Lobby, Game, Podium. Which one shows depends on the server's state.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

local TIER_COLORS = {
	Common = "#b0b0b0",
	Rare = "#4da6ff",
	SuperRare = "#b366ff",
	Epic = "#ff9933",
	Legendary = "#ffd700",
	Invalid = "#ff4d4d",
}

local WHITE = Color3.new(1, 1, 1)
local YELLOW = Color3.fromRGB(255, 210, 80)
local RED = Color3.fromRGB(255, 90, 90)
local BLUE = Color3.fromRGB(70, 130, 255)
local GREEN = Color3.fromRGB(60, 180, 90)
local GRAY = Color3.fromRGB(70, 70, 90)

---------------------------------------------------------------- helpers

local function make(class, props)
	local inst = Instance.new(class)
	local parent = props.Parent
	props.Parent = nil
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function escape(s)
	return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function panel(parent)
	local f = make("Frame", {
		Size = UDim2.fromScale(0.5, 0.6), Position = UDim2.fromScale(0.25, 0.2),
		BackgroundColor3 = Color3.fromRGB(25, 25, 35), Visible = false, Parent = parent,
	})
	make("UICorner", { CornerRadius = UDim.new(0, 12), Parent = f })
	return f
end

local function label(parent, props)
	props.BackgroundTransparency = 1
	props.TextColor3 = props.TextColor3 or WHITE
	props.Font = props.Font or Enum.Font.Gotham
	props.Parent = parent
	return make("TextLabel", props)
end

local function button(parent, text, color, size, pos)
	local b = make("TextButton", {
		Size = size, Position = pos, Text = text, TextScaled = true,
		Font = Enum.Font.GothamBold, TextColor3 = WHITE, BackgroundColor3 = color, Parent = parent,
	})
	make("UICorner", { CornerRadius = UDim.new(0, 8), Parent = b })
	return b
end

---------------------------------------------------------------- base

local gui = make("ScreenGui", {
	Name = "NicheGui", ResetOnSpawn = false, IgnoreGuiInset = true,
	Parent = player:WaitForChild("PlayerGui"),
})

make("Frame", {
	Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(15, 15, 22),
	BorderSizePixel = 0, ZIndex = 0, Parent = gui,
})

---------------------------------------------------------------- lobby screen

local lobbyFrame = panel(gui)

label(lobbyFrame, {
	Size = UDim2.new(1, -20, 0.14, 0), Position = UDim2.new(0, 10, 0, 10),
	TextScaled = true, Font = Enum.Font.GothamBlack, Text = "NICHE",
})
label(lobbyFrame, {
	Size = UDim2.new(1, -20, 0.06, 0), Position = UDim2.new(0, 10, 0.15, 0),
	TextScaled = true, TextColor3 = Color3.fromRGB(170, 170, 190),
	Text = "The rarer your answer, the more points",
})

local playersLabel = label(lobbyFrame, {
	Size = UDim2.new(1, -40, 0.45, 0), Position = UDim2.new(0, 20, 0.25, 0),
	TextSize = 20, RichText = true, TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = "",
})

local statusLabel = label(lobbyFrame, {
	Size = UDim2.new(1, -20, 0.07, 0), Position = UDim2.new(0, 10, 0.71, 0),
	TextScaled = true, Font = Enum.Font.GothamMedium, TextColor3 = YELLOW, Text = "",
})

local readyButton = button(lobbyFrame, "Ready up", GREEN,
	UDim2.new(0.5, -15, 0.13, 0), UDim2.new(0, 10, 0.82, 0))
local startButton = button(lobbyFrame, "Start now", BLUE,
	UDim2.new(0.5, -15, 0.13, 0), UDim2.new(0.5, 5, 0.82, 0))

readyButton.Activated:Connect(function()
	remotes.LobbyAction:FireServer(player:GetAttribute("Ready") and "unready" or "ready")
end)
startButton.Activated:Connect(function()
	remotes.LobbyAction:FireServer("start")
end)

---------------------------------------------------------------- game screen

local gameFrame = panel(gui)

local promptLabel = label(gameFrame, {
	Size = UDim2.new(1, -20, 0.18, 0), Position = UDim2.new(0, 10, 0, 10),
	TextScaled = true, Font = Enum.Font.GothamBold, Text = "Get ready...",
})

local timerLabel = label(gameFrame, {
	Size = UDim2.new(1, -20, 0.08, 0), Position = UDim2.new(0, 10, 0.2, 0),
	TextScaled = true, TextColor3 = YELLOW, Text = "",
})

local input = make("TextBox", {
	Size = UDim2.new(0.7, -15, 0.12, 0), Position = UDim2.new(0, 10, 0.31, 0),
	PlaceholderText = "Your most niche answer...", Text = "", ClearTextOnFocus = false,
	TextScaled = true, Font = Enum.Font.Gotham, TextColor3 = WHITE,
	BackgroundColor3 = Color3.fromRGB(45, 45, 60), Parent = gameFrame,
})
make("UICorner", { CornerRadius = UDim.new(0, 8), Parent = input })

local submit = button(gameFrame, "Lock in", BLUE,
	UDim2.new(0.3, -15, 0.12, 0), UDim2.new(0.7, 5, 0.31, 0))

local hintLabel = label(gameFrame, {
	Size = UDim2.new(1, -20, 0.06, 0), Position = UDim2.new(0, 10, 0.44, 0),
	TextScaled = true, Font = Enum.Font.GothamMedium,
	TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = YELLOW, Text = "",
})

local resultsLabel = label(gameFrame, {
	Size = UDim2.new(1, -20, 0.46, -10), Position = UDim2.new(0, 10, 0.52, 0),
	TextWrapped = true, RichText = true, TextSize = 18,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = "",
})

---------------------------------------------------------------- podium screen

local podiumFrame = panel(gui)

label(podiumFrame, {
	Size = UDim2.new(1, -20, 0.14, 0), Position = UDim2.new(0, 10, 0, 10),
	TextScaled = true, Font = Enum.Font.GothamBlack, Text = "Match over!",
})

local standingsLabel = label(podiumFrame, {
	Size = UDim2.new(1, -40, 0.55, 0), Position = UDim2.new(0, 20, 0.18, 0),
	TextSize = 22, RichText = true, TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = "",
})

local playAgainButton = button(podiumFrame, "Play again", GREEN,
	UDim2.new(0.5, -15, 0.13, 0), UDim2.new(0, 10, 0.82, 0))
local toLobbyButton = button(podiumFrame, "Back to lobby", GRAY,
	UDim2.new(0.5, -15, 0.13, 0), UDim2.new(0.5, 5, 0.82, 0))

local podiumWaitLabel = label(podiumFrame, {
	Size = UDim2.new(1, -20, 0.08, 0), Position = UDim2.new(0, 10, 0.84, 0),
	TextScaled = true, Font = Enum.Font.GothamMedium, TextColor3 = YELLOW, Text = "", Visible = false,
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

---------------------------------------------------------------- answering

local locked = true
local checking = false
local roundId = 0
local pendingSuggestion = nil
local suggestionText = nil

local function setHint(text, color)
	hintLabel.Text = text
	hintLabel.TextColor3 = color or YELLOW
end

local function send(canonical, display)
	locked = true
	pendingSuggestion = nil
	input.TextEditable = false
	input.Text = display
	submit.Text = "Locked!"
	setHint("")
	remotes.SubmitAnswer:FireServer(canonical)
end

local function lockIn()
	if locked or checking or input.Text == "" then return end

	if pendingSuggestion then
		send(pendingSuggestion, suggestionText)
		return
	end

	checking = true
	local ok, status, canonical, display = pcall(function()
		return remotes.CheckAnswer:InvokeServer(input.Text)
	end)
	checking = false
	if not ok or locked then return end

	if status == "valid" then
		send(canonical, display)
	elseif status == "suggest" then
		input.Text = display
		pendingSuggestion = canonical
		suggestionText = display
		setHint(("Did you mean %s? Press Enter to confirm"):format(display), YELLOW)
		input:CaptureFocus()
	elseif status == "invalid" then
		setHint("Not an answer, try again", RED)
		input:CaptureFocus()
	end
end

input:GetPropertyChangedSignal("Text"):Connect(function()
	if pendingSuggestion and input.Text ~= suggestionText then
		pendingSuggestion = nil
		setHint("")
	elseif hintLabel.TextColor3 == RED then
		setHint("")
	end
end)

submit.Activated:Connect(lockIn)
input.FocusLost:Connect(function(enterPressed)
	if enterPressed then lockIn() end
end)

remotes.NewPrompt.OnClientEvent:Connect(function(text, seconds, round, total)
	roundId += 1
	local myRound = roundId

	locked = false
	pendingSuggestion = nil
	input.Text = ""
	input.TextEditable = true
	submit.Text = "Lock in"
	setHint("")
	promptLabel.Text = text
	resultsLabel.Text = ("Round %d / %d"):format(round, total)

	task.spawn(function()
		for t = seconds, 0, -1 do
			if roundId ~= myRound then return end
			timerLabel.Text = t .. "s"
			task.wait(1)
		end
	end)
end)

remotes.RoundResults.OnClientEvent:Connect(function(results)
	locked = true
	pendingSuggestion = nil
	input.TextEditable = false
	timerLabel.Text = ""
	setHint("")

	local lines = {}
	for _, r in ipairs(results) do
		table.insert(lines, ('%s: "%s"  <font color="%s">%s +%d</font>  (total %d)'):format(
			escape(r.name), escape(r.answer), TIER_COLORS[r.tier] or "#ffffff", r.tier, r.points, r.total
		))
	end
	resultsLabel.Text = #lines > 0 and table.concat(lines, "\n") or "Nobody answered 💀"
end)

remotes.MatchOver.OnClientEvent:Connect(function(standings)
	local medals = { "🥇", "🥈", "🥉" }
	local lines = {}
	for i, s in ipairs(standings) do
		table.insert(lines, ("%s %d. %s  <b>%d pts</b>"):format(medals[i] or "  ", i, escape(s.name), s.score))
	end
	standingsLabel.Text = table.concat(lines, "\n")
	playAgainButton.Visible = true
	toLobbyButton.Visible = true
	podiumWaitLabel.Visible = false

	-- reset the game screen for next time
	roundId += 1
	promptLabel.Text = "Get ready..."
	resultsLabel.Text = ""
	timerLabel.Text = ""
	input.Text = ""
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
		table.insert(lines, ("%s%s   %s"):format(escape(p.DisplayName), crown, status))
	end
	playersLabel.Text = table.concat(lines, "\n")

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
	readyButton.BackgroundColor3 = player:GetAttribute("Ready") and GRAY or GREEN
	startButton.Visible = isHost and state == "Lobby"
end

local function render()
	local state = ReplicatedStorage:GetAttribute("GameState") or "Lobby"
	local inMatch = player:GetAttribute("InMatch")

	local screen = "lobby"
	if inMatch and state == "InMatch" then
		screen = "game"
	elseif inMatch and state == "Podium" then
		screen = "podium"
	end

	lobbyFrame.Visible = screen == "lobby"
	gameFrame.Visible = screen == "game"
	podiumFrame.Visible = screen == "podium"

	if screen == "lobby" then
		renderLobby(state)
	end
end

while true do
	render()
	task.wait(0.2)
end
