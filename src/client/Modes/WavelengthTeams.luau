-- ModuleScript: StarterPlayerScripts > Modes > WavelengthTeams
-- Same dial as Solo, but you only ever see your own team's clue. Both teams play the
-- round at the same time; the other team's target and clue appear only at the reveal.

local UserInputService = game:GetService("UserInputService")

local UiKit = require(script.Parent.Parent.UiKit)

local WavelengthTeams = {
	name = "Wavelength Teams",
	blurb = "Two teams, two clues, one dial",
	group = "Wavelength", -- shares the Wavelength button with Solo
	variant = "Teams",
}

local TEAM_COLORS = {
	Red = Color3.fromRGB(255, 100, 100),
	Blue = Color3.fromRGB(100, 160, 255),
}

local api
local frame, roundLabel, teamLabel, roleLabel, leftLabel, rightLabel
local bar, marker, targetMarker, clueBox, submitButton, statusLabel, resultLabel
local categoryButtons = {}
local revealMarkers = {}

local myGuess = 0.5
local dragging = false
local canDrag = false
local isGiver = false
local submitted = false
local phaseId = 0
local pickedCategory = nil

---------------------------------------------------------------- dial

local function setMarker(m, frac)
	m.Position = UDim2.new(math.clamp(frac, 0, 1), -4, 0, -4)
end

local function updateFromInput(input)
	if bar.AbsoluteSize.X <= 0 then return end
	local frac = (input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X
	myGuess = math.clamp(frac, 0, 1)
	setMarker(marker, myGuess)
end

local function clearRevealMarkers()
	for _, m in ipairs(revealMarkers) do
		m:Destroy()
	end
	table.clear(revealMarkers)
end

---------------------------------------------------------------- categories

local function paintCategories()
	for i, b in ipairs(categoryButtons) do
		b.BackgroundColor3 = (pickedCategory == i) and UiKit.GREEN or Color3.fromRGB(45, 45, 60)
	end
end

local function showCategories(options)
	pickedCategory = nil
	for i, b in ipairs(categoryButtons) do
		local name = options and options[i]
		b.Text = name or ""
		b.Visible = name ~= nil
	end
	paintCategories()
end

local function hideCategories()
	for _, b in ipairs(categoryButtons) do
		b.Visible = false
	end
	pickedCategory = nil
end

---------------------------------------------------------------- phases

local function startTimer(seconds, prefix)
	phaseId += 1
	local mine = phaseId
	task.spawn(function()
		for t = seconds, 0, -1 do
			if phaseId ~= mine then return end
			statusLabel.Text = ("%s  %ds"):format(prefix, t)
			task.wait(1)
		end
	end)
end

local function onRound(info)
	roundLabel.Text = ("Round %d / %d"):format(info.round, info.rounds)
	leftLabel.Text = info.left
	rightLabel.Text = info.right
	resultLabel.Text = ""
	submitted = false
	canDrag = false
	myGuess = 0.5
	setMarker(marker, 0.5)
	marker.Visible = false
	targetMarker.Visible = false
	clearRevealMarkers()

	teamLabel.Text = ("Team %s"):format(info.teamName)
	teamLabel.TextColor3 = TEAM_COLORS[info.teamName] or UiKit.WHITE

	isGiver = info.isGiver == true
	if isGiver then
		roleLabel.Text = "Pick a category, then write your clue"
		roleLabel.TextColor3 = UiKit.YELLOW
		showCategories(info.categories)
		clueBox.Visible = true
		clueBox.Text = ""
		clueBox.TextEditable = true
		submitButton.Visible = true
		submitButton.Text = "Send clue"
	else
		roleLabel.Text = ("%s is writing your team's clue"):format(info.giverName)
		roleLabel.TextColor3 = UiKit.DIM
		hideCategories()
		clueBox.Visible = false
		submitButton.Visible = false
	end

	startTimer(info.seconds, isGiver and "Your turn" or "Clue coming")
end

-- only your own team's clue giver ever gets this
local function onTarget(value)
	targetMarker.Visible = true
	setMarker(targetMarker, value)
end

local function onClue(info)
	hideCategories()
	resultLabel.Text = ("<b>%s</b>\n\"%s\""):format(
		UiKit.escape(info.category ~= "" and info.category or "No category"),
		UiKit.escape(info.text))

	if not isGiver and info.seconds > 0 then
		canDrag = true
		marker.Visible = true
		submitted = false
		submitButton.Visible = true
		submitButton.Text = "Lock in guess"
		roleLabel.Text = "Drag the marker, then lock it in"
		roleLabel.TextColor3 = UiKit.GREEN
		startTimer(info.seconds, "Guessing")
	else
		if isGiver then
			clueBox.TextEditable = false
			clueBox.Visible = false
			submitButton.Visible = false
		end
		startTimer(info.seconds, "Waiting on your team")
	end
end

local function onReveal(info)
	phaseId += 1 -- stop any running timer
	canDrag = false
	submitButton.Visible = false
	clueBox.Visible = false
	hideCategories()
	statusLabel.Text = ""
	marker.Visible = false
	targetMarker.Visible = false
	clearRevealMarkers()

	-- both teams' targets and every guess, colour coded, now that it is all public
	for team = 1, 2 do
		local name = info.teamNames[team]
		local color = TEAM_COLORS[name] or UiKit.WHITE

		if info.targets[team] and info.targets[team] >= 0 then
			local t = UiKit.make("Frame", {
				Size = UDim2.new(0, 8, 1, 8), BackgroundColor3 = color,
				ZIndex = 3, Parent = bar,
			})
			UiKit.make("UICorner", { CornerRadius = UDim.new(0, 3), Parent = t })
			setMarker(t, info.targets[team])
			table.insert(revealMarkers, t)
		end

		for _, g in ipairs(info.guesses[team] or {}) do
			local m = UiKit.make("Frame", {
				Size = UDim2.new(0, 4, 0.6, 0), Position = UDim2.new(0, 0, 0.2, 0),
				BackgroundColor3 = color, BackgroundTransparency = 0.4,
				ZIndex = 2, Parent = bar,
			})
			m.Position = UDim2.new(math.clamp(g, 0, 1), -2, 0.2, 0)
			table.insert(revealMarkers, m)
		end
	end

	local lead
	if info.totals[1] > info.totals[2] then
		lead = ("%s leads"):format(info.teamNames[1])
	elseif info.totals[2] > info.totals[1] then
		lead = ("%s leads"):format(info.teamNames[2])
	else
		lead = "All square"
	end

	roleLabel.Text = lead
	roleLabel.TextColor3 = UiKit.WHITE
	resultLabel.Text = ('%s: "%s" +%d  (total %d)\n%s: "%s" +%d  (total %d)'):format(
		UiKit.escape(info.teamNames[1]), UiKit.escape(info.clues[1] or ""),
		info.points[1], info.totals[1],
		UiKit.escape(info.teamNames[2]), UiKit.escape(info.clues[2] or ""),
		info.points[2], info.totals[2])
end

function WavelengthTeams.onEvent(kind, payload)
	if kind == "round" then
		onRound(payload)
	elseif kind == "target" then
		onTarget(payload)
	elseif kind == "clue" then
		onClue(payload)
	elseif kind == "reveal" then
		onReveal(payload)
	end
end

function WavelengthTeams.reset()
	phaseId += 1
	canDrag = false
	submitted = false
	isGiver = false
	roundLabel.Text = ""
	teamLabel.Text = ""
	roleLabel.Text = "Get ready..."
	roleLabel.TextColor3 = UiKit.WHITE
	leftLabel.Text = ""
	rightLabel.Text = ""
	statusLabel.Text = ""
	resultLabel.Text = ""
	hideCategories()
	clueBox.Visible = false
	submitButton.Visible = false
	marker.Visible = false
	targetMarker.Visible = false
	clearRevealMarkers()
end

---------------------------------------------------------------- build

local function submit()
	if isGiver and not submitted then
		if not pickedCategory then
			statusLabel.Text = "Pick a category first"
			return
		end
		if clueBox.Text == "" then return end
		submitted = true
		api.send("clue", pickedCategory, clueBox.Text)
		clueBox.TextEditable = false
		submitButton.Visible = false
		statusLabel.Text = "Clue sent"
	elseif not isGiver and canDrag and not submitted then
		submitted = true
		canDrag = false
		api.send("guess", myGuess)
		submitButton.Visible = false
		statusLabel.Text = "Locked in"
	end
end

function WavelengthTeams.build(parent, modeApi)
	api = modeApi
	frame = UiKit.panel(parent)

	roundLabel = UiKit.label(frame, {
		Size = UDim2.new(0.5, -10, 0.07, 0), Position = UDim2.new(0, 10, 0.02, 0),
		TextScaled = true, TextColor3 = UiKit.DIM,
		TextXAlignment = Enum.TextXAlignment.Left, Text = "",
	})
	teamLabel = UiKit.label(frame, {
		Size = UDim2.new(0.5, -10, 0.07, 0), Position = UDim2.new(0.5, 0, 0.02, 0),
		TextScaled = true, Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Right, Text = "",
	})

	roleLabel = UiKit.label(frame, {
		Size = UDim2.new(1, -20, 0.1, 0), Position = UDim2.new(0, 10, 0.1, 0),
		TextScaled = true, Font = Enum.Font.GothamBold, Text = "Get ready...",
	})

	leftLabel = UiKit.label(frame, {
		Size = UDim2.new(0.45, 0, 0.07, 0), Position = UDim2.new(0, 10, 0.23, 0),
		TextScaled = true, TextColor3 = UiKit.BLUE,
		TextXAlignment = Enum.TextXAlignment.Left, Text = "",
	})
	rightLabel = UiKit.label(frame, {
		Size = UDim2.new(0.45, 0, 0.07, 0), Position = UDim2.new(0.55, -10, 0.23, 0),
		TextScaled = true, TextColor3 = UiKit.YELLOW,
		TextXAlignment = Enum.TextXAlignment.Right, Text = "",
	})

	bar = UiKit.make("Frame", {
		Size = UDim2.new(1, -40, 0.06, 0), Position = UDim2.new(0, 20, 0.32, 0),
		BackgroundColor3 = Color3.fromRGB(45, 45, 60), Parent = frame,
	})
	UiKit.make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = bar })

	targetMarker = UiKit.make("Frame", {
		Size = UDim2.new(0, 8, 1, 8), BackgroundColor3 = UiKit.GREEN,
		Visible = false, ZIndex = 4, Parent = bar,
	})
	UiKit.make("UICorner", { CornerRadius = UDim.new(0, 3), Parent = targetMarker })

	marker = UiKit.make("Frame", {
		Size = UDim2.new(0, 8, 1, 8), BackgroundColor3 = UiKit.WHITE,
		Visible = false, ZIndex = 5, Parent = bar,
	})
	UiKit.make("UICorner", { CornerRadius = UDim.new(0, 3), Parent = marker })

	local CAT_POS = {
		UDim2.new(0, 10, 0.42, 0),
		UDim2.new(0.3333, 4, 0.42, 0),
		UDim2.new(0.6667, 4, 0.42, 0),
	}
	for i = 1, 3 do
		local b = UiKit.button(frame, "", Color3.fromRGB(45, 45, 60),
			UDim2.new(0.3333, -14, 0.09, 0), CAT_POS[i])
		b.Font = Enum.Font.GothamMedium
		b.Visible = false
		b.Activated:Connect(function()
			if not isGiver or submitted then return end
			pickedCategory = i
			statusLabel.Text = ""
			paintCategories()
		end)
		categoryButtons[i] = b
	end

	clueBox = UiKit.make("TextBox", {
		Size = UDim2.new(0.66, -15, 0.11, 0), Position = UDim2.new(0, 10, 0.53, 0),
		PlaceholderText = "One word or phrase...", Text = "", ClearTextOnFocus = false,
		TextScaled = true, Font = Enum.Font.Gotham, TextColor3 = UiKit.WHITE,
		BackgroundColor3 = Color3.fromRGB(45, 45, 60), Visible = false, Parent = frame,
	})
	UiKit.make("UICorner", { CornerRadius = UDim.new(0, 8), Parent = clueBox })

	submitButton = UiKit.button(frame, "Send clue", UiKit.BLUE,
		UDim2.new(0.34, -15, 0.11, 0), UDim2.new(0.66, 5, 0.53, 0))
	submitButton.Visible = false

	statusLabel = UiKit.label(frame, {
		Size = UDim2.new(1, -20, 0.07, 0), Position = UDim2.new(0, 10, 0.66, 0),
		TextScaled = true, Font = Enum.Font.GothamMedium, TextColor3 = UiKit.YELLOW, Text = "",
	})

	resultLabel = UiKit.label(frame, {
		Size = UDim2.new(1, -20, 0.2, 0), Position = UDim2.new(0, 10, 0.75, 0),
		TextWrapped = true, RichText = true, TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = "",
	})

	bar.InputBegan:Connect(function(input)
		if not canDrag then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			updateFromInput(input)
		end
	end)
	bar.InputChanged:Connect(function(input)
		if not canDrag or not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			updateFromInput(input)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	submitButton.Activated:Connect(submit)
	clueBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then submit() end
	end)

	return frame
end

return WavelengthTeams
