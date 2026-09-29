-- ModuleScript: StarterPlayerScripts > Modes > DeepDive
-- Type answers against a clock. Every answer is checked by the server before it appears,
-- so what you see on screen is exactly what you are scored on. Tap one to drop it.

local UiKit = require(script.Parent.Parent.UiKit)

local DeepDive = {
	name = "Deep Dive",
	blurb = "Score only what nobody else thought of",
}

local api
local frame, roundLabel, categoryLabel, input, doneButton
local wordsFrame, statusLabel, resultLabel

local myWords = {}        -- display text, in server order
local maxWords = 10
local roundActive = false
local iAmDone = false
local checking = false
local phaseId = 0

---------------------------------------------------------------- word list

local rows = {}

local function paintWords()
	for _, r in ipairs(rows) do
		r:Destroy()
	end
	table.clear(rows)

	for i, word in ipairs(myWords) do
		local b = UiKit.button(wordsFrame, ("%d.   %s      \u{2715}"):format(i, word),
			Color3.fromRGB(45, 45, 60), UDim2.new(1, -12, 0, 30), UDim2.new())
		b.TextScaled = false
		b.TextSize = 16
		b.Font = Enum.Font.Gotham
		b.TextXAlignment = Enum.TextXAlignment.Left
		b.LayoutOrder = i
		b.Activated:Connect(function()
			if not roundActive or iAmDone then return end
			-- optimistic: the server ignores removes once the round is over, and the
			-- reveal overwrites this view anyway
			api.send("remove", i)
			table.remove(myWords, i)
			paintWords()
		end)
		table.insert(rows, b)
	end
end

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

---------------------------------------------------------------- answering

local function addWord()
	local text = input.Text
	if not roundActive or iAmDone or checking or text == "" then return end

	checking = true
	local ok, status, display = pcall(api.request, "word", text)
	checking = false
	if not ok or not roundActive then return end

	if status == "ok" then
		table.insert(myWords, display)
		input.Text = ""
		paintWords()
	elseif status == "dupe" then
		statusLabel.Text = ("You already have %s"):format(display or "that")
		input.Text = ""
	elseif status == "full" then
		statusLabel.Text = ("That's all %d"):format(maxWords)
	else
		statusLabel.Text = ("\"%s\" isn't on the list"):format(text)
	end
	input:CaptureFocus()
end

-- Done is a toggle, not a one-way door
local function setDone(state)
	if not roundActive then return end
	iAmDone = state
	if iAmDone then
		api.send("done")
		input.TextEditable = false
		doneButton.Text = "Keep going"
		doneButton.BackgroundColor3 = UiKit.GRAY
		statusLabel.Text = ("Done with %d. Tap to come back"):format(#myWords)
	else
		api.send("resume")
		input.TextEditable = true
		doneButton.Text = "Done"
		doneButton.BackgroundColor3 = UiKit.GREEN
		input:CaptureFocus()
	end
	paintWords()
end

---------------------------------------------------------------- server messages

local function onRound(info)
	roundLabel.Text = ("Round %d / %d"):format(info.round, info.rounds)
	categoryLabel.Text = info.category
	maxWords = info.maxWords or 10
	myWords = {}
	roundActive = true
	iAmDone = false
	checking = false
	input.Text = ""
	input.TextEditable = true
	doneButton.Visible = true
	doneButton.Text = "Done"
	doneButton.BackgroundColor3 = UiKit.GREEN
	wordsFrame.Visible = true
	resultLabel.Visible = false
	resultLabel.Text = ""
	paintWords()
	startTimer(info.seconds, "Name as many as you can")
end

local function onReveal(info)
	phaseId += 1
	roundActive = false
	iAmDone = false
	input.TextEditable = false
	doneButton.Visible = false
	wordsFrame.Visible = false
	resultLabel.Visible = true
	statusLabel.Text = ""

	local lines = {}
	for _, row in ipairs(info.rows) do
		table.insert(lines, ("%s  %d answers, <b>%d unique</b>  +%d  (%d)"):format(
			UiKit.escape(row.name), row.words, row.unique, row.unique, row.total))
	end
	if info.shared ~= "" then
		table.insert(lines, ("\nEveryone had these, so nobody scored them: %s%s"):format(
			UiKit.escape(info.shared),
			info.sharedCount > 8 and (" (+%d more)"):format(info.sharedCount - 8) or ""))
	end
	resultLabel.Text = table.concat(lines, "\n")
end

function DeepDive.onEvent(kind, payload)
	if kind == "round" then
		onRound(payload)
	elseif kind == "reveal" then
		onReveal(payload)
	end
end

function DeepDive.reset()
	phaseId += 1
	roundActive = false
	iAmDone = false
	checking = false
	myWords = {}
	roundLabel.Text = ""
	categoryLabel.Text = "Get ready..."
	statusLabel.Text = ""
	resultLabel.Text = ""
	resultLabel.Visible = false
	wordsFrame.Visible = true
	input.Text = ""
	doneButton.Visible = false
	paintWords()
end

---------------------------------------------------------------- build

function DeepDive.build(parent, modeApi)
	api = modeApi
	frame = UiKit.panel(parent)

	roundLabel = UiKit.label(frame, {
		Size = UDim2.new(1, -20, 0.06, 0), Position = UDim2.new(0, 10, 0.02, 0),
		TextScaled = true, TextColor3 = UiKit.DIM, Text = "",
	})

	categoryLabel = UiKit.label(frame, {
		Size = UDim2.new(1, -20, 0.13, 0), Position = UDim2.new(0, 10, 0.09, 0),
		TextScaled = true, Font = Enum.Font.GothamBlack, Text = "Get ready...",
	})

	input = UiKit.make("TextBox", {
		Size = UDim2.new(0.66, -15, 0.11, 0), Position = UDim2.new(0, 10, 0.24, 0),
		PlaceholderText = "An answer, then Enter...", Text = "", ClearTextOnFocus = false,
		TextScaled = true, Font = Enum.Font.Gotham, TextColor3 = UiKit.WHITE,
		BackgroundColor3 = Color3.fromRGB(45, 45, 60), Parent = frame,
	})
	UiKit.make("UICorner", { CornerRadius = UDim.new(0, 8), Parent = input })

	doneButton = UiKit.button(frame, "Done", UiKit.GREEN,
		UDim2.new(0.34, -15, 0.11, 0), UDim2.new(0.66, 5, 0.24, 0))
	doneButton.Visible = false

	statusLabel = UiKit.label(frame, {
		Size = UDim2.new(1, -20, 0.07, 0), Position = UDim2.new(0, 10, 0.37, 0),
		TextScaled = true, Font = Enum.Font.GothamMedium, TextColor3 = UiKit.YELLOW, Text = "",
	})

	-- your answers, each tappable to drop it
	wordsFrame = UiKit.make("ScrollingFrame", {
		Size = UDim2.new(1, -20, 0.5, 0), Position = UDim2.new(0, 10, 0.46, 0),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
		Parent = frame,
	})
	UiKit.make("UIListLayout", {
		Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = wordsFrame,
	})

	resultLabel = UiKit.label(frame, {
		Size = UDim2.new(1, -20, 0.5, 0), Position = UDim2.new(0, 10, 0.46, 0),
		TextWrapped = true, RichText = true, TextSize = 16, Visible = false,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = "",
	})

	doneButton.Activated:Connect(function()
		setDone(not iAmDone)
	end)
	input.FocusLost:Connect(function(enterPressed)
		if enterPressed then addWord() end
	end)

	return frame
end

return DeepDive
