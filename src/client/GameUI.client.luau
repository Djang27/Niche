-- LocalScript: StarterPlayer > StarterPlayerScripts
-- The shell around every mode's screen.
--
-- Screens: menu -> modes -> lobby -> (the active mode's own screen) -> podium.
-- Menu/modes/lobby are where *this* player has navigated to, which is purely local.
-- A running match overrides that: once the server says InMatch, the game screen wins.
--
-- Each module in Modes/ exposes
--   { name, blurb, build(parent, api) -> frame, onEvent(kind, ...), reset() }
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

-- Games we intend to build, shown greyed out on the modes screen. As soon as a real
-- module with the same name exists it is picked up as playable and drops off this list.
local PLANNED = { "Wavelength", "???", "???" }

---------------------------------------------------------------- base

local gui = UiKit.make("ScreenGui", {
	Name = "NicheGui", ResetOnSpawn = false, IgnoreGuiInset = true,
	Parent = player:WaitForChild("PlayerGui"),
})

UiKit.make("Frame", {
	Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(15, 15, 22),
	BorderSizePixel = 0, ZIndex = 0, Parent = gui,
})

---------------------------------------------------------------- navigation

-- Where this player has browsed to. Local only: two players can be on different
-- screens, and the server is told just one thing, whether we are in the lobby.
local nav = "menu"

local function goTo(name)
	if nav == name then return end
	nav = name
	remotes.LobbyAction:FireServer("inLobby", name == "lobby")
end

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

local availableModes = ReplicatedStorage:WaitForChild("AvailableModes")

-- a game is only playable if both halves exist: the server can run it and we built a screen
local function playableModes()
	local list = {}
	for _, entry in ipairs(availableModes:GetChildren()) do
		if modes[entry.Name] then
			table.insert(list, entry.Name)
		end
	end
	table.sort(list)
	return list
end

local function minPlayersFor(id)
	local entry = availableModes:FindFirstChild(id or "")
	return entry and entry:GetAttribute("MinPlayers") or 1
end

remotes.ModeEvent.OnClientEvent:Connect(function(kind, ...)
	local mode = activeMode()
	if mode and mode.onEvent then
		mode.onEvent(kind, ...)
	end
end)

---------------------------------------------------------------- main menu

local menuFrame = UiKit.panel(gui)

UiKit.label(menuFrame, {
	Size = UDim2.new(1, -20, 0.2, 0), Position = UDim2.new(0, 10, 0.06, 0),
	TextScaled = true, Font = Enum.Font.GothamBlack, Text = "NICHE",
})
UiKit.label(menuFrame, {
	Size = UDim2.new(1, -20, 0.07, 0), Position = UDim2.new(0, 10, 0.28, 0),
	TextScaled = true, TextColor3 = UiKit.DIM, Text = "Party games, one lobby",
})

local playButton = UiKit.button(menuFrame, "Play", UiKit.GREEN,
	UDim2.new(1, -40, 0.16, 0), UDim2.new(0, 20, 0.44, 0))
local storeButton = UiKit.button(menuFrame, "Store", UiKit.GRAY,
	UDim2.new(1, -40, 0.13, 0), UDim2.new(0, 20, 0.64, 0))

local menuHint = UiKit.label(menuFrame, {
	Size = UDim2.new(1, -20, 0.07, 0), Position = UDim2.new(0, 10, 0.8, 0),
	TextScaled = true, Font = Enum.Font.GothamMedium, TextColor3 = UiKit.YELLOW, Text = "",
})

playButton.Activated:Connect(function()
	menuHint.Text = ""
	goTo("modes")
end)
storeButton.Activated:Connect(function()
	menuHint.Text = "The store isn't built yet"
end)

---------------------------------------------------------------- game modes

local modesFrame = UiKit.panel(gui)

UiKit.label(modesFrame, {
	Size = UDim2.new(1, -20, 0.12, 0), Position = UDim2.new(0, 10, 0.04, 0),
	TextScaled = true, Font = Enum.Font.GothamBold, Text = "Choose a game",
})

local modesHint = UiKit.label(modesFrame, {
	Size = UDim2.new(1, -20, 0.07, 0), Position = UDim2.new(0, 10, 0.7, 0),
	TextScaled = true, Font = Enum.Font.GothamMedium, TextColor3 = UiKit.YELLOW, Text = "",
})

-- a 2x2 grid, filled with the real games first and then the planned ones
local GRID = {
	UDim2.new(0, 10, 0.22, 0),
	UDim2.new(0.5, 5, 0.22, 0),
	UDim2.new(0, 10, 0.46, 0),
	UDim2.new(0.5, 5, 0.46, 0),
}

local function modeEntries()
	local entries = {}
	for _, id in ipairs(playableModes()) do
		table.insert(entries, { id = id, label = modes[id].name or id })
	end
	for _, name in ipairs(PLANNED) do
		if not modes[name] then
			table.insert(entries, { id = nil, label = name })
		end
	end
	return entries
end

local modeButtons = {}

local function rebuildModeGrid()
	for _, old in ipairs(modeButtons) do
		old:Destroy()
	end
	table.clear(modeButtons)

	for i, entry in ipairs(modeEntries()) do
		if not GRID[i] then break end

		local playable = entry.id ~= nil
		local b = UiKit.button(modesFrame, entry.label,
			playable and UiKit.BLUE or Color3.fromRGB(38, 38, 50),
			UDim2.new(0.5, -15, 0.2, 0), GRID[i])
		b.AutoButtonColor = playable
		if not playable then
			b.TextColor3 = Color3.fromRGB(120, 120, 140)
		end

		b.Activated:Connect(function()
			if not playable then
				modesHint.Text = ("%s isn't built yet"):format(entry.label)
				return
			end
			modesHint.Text = ""
			-- the server ignores this unless we're the host, which is the intended gate
			remotes.LobbyAction:FireServer("setMode", entry.id)
			goTo("lobby")
		end)

		table.insert(modeButtons, b)
	end
end

rebuildModeGrid()

-- WaitForChild returns as soon as the folder itself replicates, which in Play Solo can
-- beat its contents: the grid would come up with Niche missing. Rebuild as entries land
-- instead of trusting the list to be complete at startup.
availableModes.ChildAdded:Connect(function()
	task.defer(rebuildModeGrid)
end)

local modesBackButton = UiKit.button(modesFrame, "Back", UiKit.GRAY,
	UDim2.new(1, -20, 0.13, 0), UDim2.new(0, 10, 0.82, 0))
modesBackButton.Activated:Connect(function()
	modesHint.Text = ""
	goTo("menu")
end)

---------------------------------------------------------------- lobby

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

local lobbyBackButton = UiKit.button(lobbyFrame, "Back", UiKit.GRAY,
	UDim2.new(0.25, -10, 0.13, 0), UDim2.new(0, 10, 0.82, 0))
local readyButton = UiKit.button(lobbyFrame, "Ready up", UiKit.GREEN,
	UDim2.new(0.4, -10, 0.13, 0), UDim2.new(0.25, 5, 0.82, 0))
local startButton = UiKit.button(lobbyFrame, "Start now", UiKit.BLUE,
	UDim2.new(0.35, -15, 0.13, 0), UDim2.new(0.65, 5, 0.82, 0))

lobbyBackButton.Activated:Connect(function()
	goTo("modes") -- the server clears our Ready, so we stop holding up the countdown
end)
readyButton.Activated:Connect(function()
	remotes.LobbyAction:FireServer(player:GetAttribute("Ready") and "unready" or "ready")
end)
startButton.Activated:Connect(function()
	remotes.LobbyAction:FireServer("start")
end)

---------------------------------------------------------------- podium

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

	-- only people actually in the lobby, not everyone on the server
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("InLobby") then
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
	end
	playersLabel.Text = #lines > 0 and table.concat(lines, "\n") or "Nobody else here yet"

	local mode = activeMode()
	titleLabel.Text = mode and mode.name:upper() or "NICHE"
	blurbLabel.Text = mode and mode.blurb or ""

	local isHost = player.UserId == hostId
	local needed = minPlayersFor(ReplicatedStorage:GetAttribute("ActiveMode"))

	if state == "Lobby" then
		if total < needed then
			statusLabel.Text = ("%s needs %d players, %d here"):format(
				mode and mode.name or "This game", needed, total)
		else
			statusLabel.Text = ("%d/%d ready. Starts when everyone's ready%s"):format(
				ready, total, isHost and ", or hit Start" or "")
		end
	elseif state == "Countdown" then
		statusLabel.Text = ("Starting in %d..."):format(ReplicatedStorage:GetAttribute("Countdown") or 0)
	else
		statusLabel.Text = "Match in progress, you'll be in the next one"
	end

	readyButton.Visible = not matchRunning
	readyButton.Text = player:GetAttribute("Ready") and "Unready" or "Ready up"
	readyButton.BackgroundColor3 = player:GetAttribute("Ready") and UiKit.GRAY or UiKit.GREEN
	startButton.Visible = isHost and state == "Lobby"
	-- Back stays available even while someone else's match runs, otherwise a spectator
	-- in the lobby has no way out until it finishes
end

local function render()
	local state = ReplicatedStorage:GetAttribute("GameState") or "Lobby"
	local inMatch = player:GetAttribute("InMatch")
	local mode = activeMode()

	-- a match we are in always beats wherever we had browsed to
	local screen
	if inMatch and state == "InMatch" then
		screen = "game"
	elseif inMatch and state == "Podium" then
		screen = "podium"
	else
		screen = nav
	end

	menuFrame.Visible = screen == "menu"
	modesFrame.Visible = screen == "modes"
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
