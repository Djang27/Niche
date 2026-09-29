-- ModuleScript: StarterPlayerScripts > Modes > DeepDive
-- Type words against a timer. Your own list lives on this client, so the server only ever
-- sends back the scoring, never your words.

local UiKit = require(script.Parent.Parent.UiKit)

local DeepDive = {
	name = "Deep Dive",
	blurb = "Score only what nobody else thought of",
}

local api
local frame, roundLabel, categoryLabel, input, doneButton
local yourLabel, statusLabel, resultLabel

local myWords = {}
local maxWords = 20
local roundActive = false -- the round is still accepting words
local iAmDone = false     -- I pressed Done; reversible while roundActive
local phaseId = 0

---------------------------------------------------------------- helpers

local function paintWords()
	yourLabel.Text = #myWords > 0
		and ("<b>%d/%d</b>  %s"):format(#myWords, maxWords, UiKit.escape(table.concat(myWords, ", ")))
		or ("<b>0/%d</b>  nothing yet"):format(maxWords)
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

local function addWord()
	local text = input.Text
	if not roundActive or iAmDone or text == "" then return end
	if #myWords >= maxWords then
		statusLabel.Text = "That's the limit"
		return
	end

	-- the server dedupes for real; this only stops the list looking wrong locally
	local lower = text:lower()
	for _, w in ipairs(myWords) do
		if w:lower() == lower then
			input.Text = ""
			input:CaptureFocus()
			return
		end
	end

	table.insert(myWords, text)
	api.send("word", text)
	input.Text = ""
	paintWords()
	input:CaptureFocus()
end

-- Done is a toggle, not a one-way door. Tapping it by mistake used to cost you the
-- whole round with no way back.
local function setDone(state)
	if not roundActive then return end
	iAmDone = state
	if iAmDone then
		api.send("done")
		input.TextEditable = false
		doneButton.Text = "Keep typing"
		doneButton.BackgroundColor3 = UiKit.GRAY
		statusLabel.Text = ("Done with %d. Tap to come back"):format(#myWords)
	else
		api.send("resume")
		input.TextEditable = true
		doneButton.Text = "Done"
		doneButton.BackgroundColor3 = UiKit.GREEN
		input:CaptureFocus()
	end
end

---------------------------------------------------------------- server messages

local function onRound(info)
	roundLabel.Text = ("Round %d / %d"):format(info.round, info.rounds)
	categoryLabel.Text = info.category
	maxWords = info.maxWords or 20
	myWords = {}
	roundActive = true
	iAmDone = false
	input.Text = ""
	input.TextEditable = true
	doneButton.Visible = true
	doneButton.Text = "Done"
	doneButton.BackgroundColor3 = UiKit.GREEN
	resultLabel.Text = ""
	paintWords()
	startTimer(info.seconds, "Type away")
end

local function onReveal(info)
	phaseId += 1
	roundActive = false
	iAmDone = false
	input.TextEditable = false
	doneButton.Visible = false
	statusLabel.Text = ""

	local lines = {}
	for _, row in ipairs(info.rows) do
		table.insert(lines, ("%s  %d words, <b>%d unique</b>  +%d  (%d)"):format(
			UiKit.escape(row.name), row.words, row.unique, row.unique, row.total))
	end
	if info.shared ~= "" then
		table.insert(lines, ("\nShared, so worth nothing: %s%s"):format(
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
	myWords = {}
	roundLabel.Text = ""
	categoryLabel.Text = "Get ready..."
	statusLabel.Text = ""
	resultLabel.Text = ""
	input.Text = ""
	doneButton.Visible = false
	paintWords()
end

---------------------------------------------------------------- build

function DeepDive.build(parent, modeApi)
	api = modeApi
	frame = UiKit.panel(parent)

	roundLabel = UiKit.label(frame, {
		Size = UDim2.new(1, -20, 0.07, 0), Position = UDim2.new(0, 10, 0.02, 0),
		TextScaled = true, TextColor3 = UiKit.DIM, Text = "",
	})

	categoryLabel = UiKit.label(frame, {
		Size = UDim2.new(1, -20, 0.14, 0), Position = UDim2.new(0, 10, 0.1, 0),
		TextScaled = true, Font = Enum.Font.GothamBlack, Text = "Get ready...",
	})

	input = UiKit.make("TextBox", {
		Size = UDim2.new(0.68, -15, 0.12, 0), Position = UDim2.new(0, 10, 0.27, 0),
		PlaceholderText = "A word, then Enter...", Text = "", ClearTextOnFocus = false,
		TextScaled = true, Font = Enum.Font.Gotham, TextColor3 = UiKit.WHITE,
		BackgroundColor3 = Color3.fromRGB(45, 45, 60), Parent = frame,
	})
	UiKit.make("UICorner", { CornerRadius = UDim.new(0, 8), Parent = input })

	doneButton = UiKit.button(frame, "Done", UiKit.GREEN,
		UDim2.new(0.32, -15, 0.12, 0), UDim2.new(0.68, 5, 0.27, 0))
	doneButton.Visible = false

	yourLabel = UiKit.label(frame, {
		Size = UDim2.new(1, -20, 0.16, 0), Position = UDim2.new(0, 10, 0.41, 0),
		TextWrapped = true, RichText = true, TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = "",
	})

	statusLabel = UiKit.label(frame, {
		Size = UDim2.new(1, -20, 0.07, 0), Position = UDim2.new(0, 10, 0.58, 0),
		TextScaled = true, Font = Enum.Font.GothamMedium, TextColor3 = UiKit.YELLOW, Text = "",
	})

	resultLabel = UiKit.label(frame, {
		Size = UDim2.new(1, -20, 0.27, 0), Position = UDim2.new(0, 10, 0.67, 0),
		TextWrapped = true, RichText = true, TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = "",
	})

	doneButton.Activated:Connect(function()
		setDone(not iAmDone)
	end)
	input.FocusLost:Connect(function(enterPressed)
		if enterPressed then addWord() end
	end)

	paintWords()
	return frame
end

return DeepDive
