-- ModuleScript: StarterPlayerScripts > Modes > WavelengthSolo
-- The Wavelength dial. One player picks a category and writes a clue, one player drags
-- the marker, the rest watch.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local UiKit = require(script.Parent.Parent.UiKit)

local localPlayer = Players.LocalPlayer

local WavelengthSolo = {
	name = "Wavelength Solo",
	blurb = "Two players, one dial, one clue",
	group = "Wavelength", -- collapses into the Wavelength button on the modes screen
	variant = "Solo",
}

local api
local frame, roundLabel, roleLabel, leftLabel, rightLabel
local bar, marker, targetMarker, clueBox, submitButton, statusLabel, resultLabel
local categoryButtons = {}

local myGuess = 0.5
local dragging = false
local canDrag = false
local role = "watch" -- "hint" | "guess" | "watch"
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

local function onRound(round, total, left, right, hinterId, hinterName, guesserId, guesserName, seconds, categories)
	roundLabel.Text = ("Round %d / %d"):format(round, total)
	leftLabel.Text = left
	rightLabel.Text = right
	resultLabel.Text = ""
	submitted = false
	canDrag = false
	myGuess = 0.5
	setMarker(marker, 0.5)
	marker.Visible = false
	targetMarker.Visible = false

	-- by UserId, never DisplayName: two players can share a display name
	if hinterId == localPlayer.UserId then
		role = "hint"
		roleLabel.Text = "Pick a category, then write your clue"
		roleLabel.TextColor3 = UiKit.YELLOW
		showCategories(categories)
		clueBox.Visible = true
		clueBox.Text = ""
		clueBox.TextEditable = true
		submitButton.Visible = true
		submitButton.Text = "Send clue"
	elseif guesserId == localPlayer.UserId then
		role = "guess"
		roleLabel.Text = ("You're guessing. %s is writing a clue"):format(hinterName)
		roleLabel.TextColor3 = UiKit.GREEN
		hideCategories()
		clueBox.Visible = false
		submitButton.Visible = false
	else
		role = "watch"
		roleLabel.Text = ("%s gives the clue, %s guesses"):format(hinterName, guesserName)
		roleLabel.TextColor3 = UiKit.DIM
		hideCategories()
		clueBox.Visible = false
		submitButton.Visible = false
	end

	startTimer(seconds, role == "hint" and "Your turn" or "Clue coming")
end

-- only the clue giver gets this, and only they ever see the target before the reveal
local function onTarget(value)
	targetMarker.Visible = true
	setMarker(targetMarker, value)
end

local function onClue(category, text, seconds)
	hideCategories()
	resultLabel.Text = ("<b>%s</b>\n\"%s\""):format(
		UiKit.escape(category ~= "" and category or "No category"), UiKit.escape(text))

	if role == "guess" and seconds > 0 then
		canDrag = true
		marker.Visible = true
		submitted = false
		submitButton.Visible = true
		submitButton.Text = "Lock in guess"
		clueBox.Visible = false
		roleLabel.Text = "Drag the marker, then lock it in"
		roleLabel.TextColor3 = UiKit.GREEN
		startTimer(seconds, "Guessing")
	else
		if role == "hint" then
			clueBox.TextEditable = false
			clueBox.Visible = false
			submitButton.Visible = false
		end
		startTimer(seconds, "Waiting on the guess")
	end
end

local function onReveal(targetValue, guessValue, points, label, hinterName, guesserName, hinterTotal, guesserTotal)
	phaseId += 1 -- stop any running timer
	canDrag = false
	submitButton.Visible = false
	clueBox.Visible = false
	hideCategories()
	statusLabel.Text = ""

	targetMarker.Visible = true
	setMarker(targetMarker, targetValue)
	if guessValue then
		marker.Visible = true
		setMarker(marker, guessValue)
	else
		marker.Visible = false
	end

	roleLabel.Text = label
	roleLabel.TextColor3 = points > 0 and UiKit.GREEN or UiKit.RED
	resultLabel.Text = ("+%d each\n%s: %d    %s: %d"):format(
		points,
		UiKit.escape(hinterName), hinterTotal,
		UiKit.escape(guesserName), guesserTotal)
end

function WavelengthSolo.onEvent(kind, ...)
	if kind == "round" then
		onRound(...)
	elseif kind == "target" then
		onTarget(...)
	elseif kind == "clue" then
		onClue(...)
	elseif kind == "reveal" then
		onReveal(...)
	end
end

function WavelengthSolo.reset()
	phaseId += 1
	canDrag = false
	submitted = false
	role = "watch"
	roundLabel.Text = ""
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
end

---------------------------------------------------------------- build

local function submit()
	if role == "hint" and not submitted then
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
	elseif role == "guess" and canDrag and not submitted then
		submitted = true
		canDrag = false
		api.send("guess", myGuess)
		submitButton.Visible = false
		statusLabel.Text = "Locked in"
	end
end

function WavelengthSolo.build(parent, modeApi)
	api = modeApi
	frame = UiKit.panel(parent)

	roundLabel = UiKit.label(frame, {
		Size = UDim2.new(1, -20, 0.07, 0), Position = UDim2.new(0, 10, 0.02, 0),
		TextScaled = true, TextColor3 = UiKit.DIM, Text = "",
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
		Visible = false, ZIndex = 2, Parent = bar,
	})
	UiKit.make("UICorner", { CornerRadius = UDim.new(0, 3), Parent = targetMarker })

	marker = UiKit.make("Frame", {
		Size = UDim2.new(0, 8, 1, 8), BackgroundColor3 = UiKit.WHITE,
		Visible = false, ZIndex = 3, Parent = bar,
	})
	UiKit.make("UICorner", { CornerRadius = UDim.new(0, 3), Parent = marker })

	-- three category choices, clue giver only
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
			if role ~= "hint" or submitted then return end
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
		TextWrapped = true, RichText = true, TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = "",
	})

	-- dial dragging: click anywhere on the bar, and keep tracking while held
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

return WavelengthSolo
