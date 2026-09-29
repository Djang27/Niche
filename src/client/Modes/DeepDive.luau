-- ModuleScript: StarterPlayerScripts > Modes > DeepDive
-- Type answers against a clock. Every answer is checked by the server before it appears,
-- so what you see on screen is exactly what you are scored on. Tap one to drop it.

local UiKit = require(script.Parent.Parent.UiKit)
local PlayerCards = require(script.Parent.Parent.PlayerCards)

local DeepDive = {
	name = "Deep Dive",
	blurb = "Score only what nobody else thought of",
}

local api
local frame, roundLabel, categoryLabel, input, actionButton
local wordsFrame, statusLabel, answersLabel
local meterFill, meterText
local cards

local myWords = {}
local maxWords = 10
local roundActive = false
local iAmDone = false
local checking = false
local phaseId = 0

---------------------------------------------------------------- word list

local rows = {}

local function paintMeter()
	local n = #myWords
	meterFill.Size = UDim2.fromScale(maxWords > 0 and math.min(n / maxWords, 1) or 0, 1)
	meterFill.BackgroundColor3 = n >= maxWords and UiKit.GREEN or UiKit.ACCENT
	meterText.Text = ("%d / %d"):format(n, maxWords)
end

-- One button, three jobs. On a phone the keyboard's return key is fiddly and easy to
-- miss, so the same control submits the answer you are typing, then finishes the round
-- once the box is empty.
local function paintButton()
	if not roundActive then
		actionButton.Visible = false
		return
	end
	actionButton.Visible = true
	if iAmDone then
		actionButton.Text = "Keep going"
		actionButton.BackgroundColor3 = UiKit.GRAY
	elseif input.Text ~= "" then
		actionButton.Text = "Submit"
		actionButton.BackgroundColor3 = UiKit.ACCENT
	else
		actionButton.Text = "Done"
		actionButton.BackgroundColor3 = UiKit.GREEN
	end
end

local function paintWords()
	for _, r in ipairs(rows) do
		r:Destroy()
	end
	table.clear(rows)

	for i, word in ipairs(myWords) do
		local b = UiKit.button(wordsFrame, ("%d.   %s      \u{2715}"):format(i, word),
			UiKit.FIELD, UDim2.new(1, -12, 0, 32), UDim2.new())
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
			paintMeter()
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
		paintMeter()
	elseif status == "dupe" then
		statusLabel.Text = ("You already have %s"):format(display or "that")
		input.Text = ""
	elseif status == "full" then
		statusLabel.Text = ("That's all %d"):format(maxWords)
	else
		statusLabel.Text = ("\"%s\" isn't on the list"):format(text)
	end
	paintButton()
	input:CaptureFocus()
end

local function setDone(state)
	if not roundActive then return end
	iAmDone = state
	if iAmDone then
		api.send("done")
		input.TextEditable = false
		statusLabel.Text = ("Done with %d. Tap to come back"):format(#myWords)
	else
		api.send("resume")
		input.TextEditable = true
		input:CaptureFocus()
	end
	paintButton()
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
	wordsFrame.Visible = true
	cards.frame.Visible = false
	cards.clear()
	answersLabel.Visible = false
	paintWords()
	paintMeter()
	paintButton()
	startTimer(info.seconds, "Name as many as you can")
end

local function onReveal(info)
	phaseId += 1
	roundActive = false
	iAmDone = false
	input.TextEditable = false
	actionButton.Visible = false
	wordsFrame.Visible = false
	cards.frame.Visible = true
	answersLabel.Visible = true
	statusLabel.Text = ""

	local best = 0
	for _, row in ipairs(info.rows) do
		best = math.max(best, row.unique)
	end

	local list = {}
	for _, row in ipairs(info.rows) do
		table.insert(list, {
			userId = row.userId,
			name = row.name,
			headline = ("%d unique"):format(row.unique),
			trailing = ("+%d"):format(row.unique),
			sub = ("of %d   total %d"):format(row.words, row.total),
			accent = row.unique > 0 and UiKit.GREEN or UiKit.DIM,
			emphasis = best > 0 and row.unique == best,
		})
	end
	cards.show(list, "Nobody wrote anything")

	-- everyone's answers, bright if only they had it and dim if somebody matched them.
	-- That replaces the old separate "shared words" line: the dim ones are the shared ones.
	local blocks = {}
	for _, row in ipairs(info.rows) do
		local words = {}
		for _, a in ipairs(row.answers or {}) do
			table.insert(words, a.solo
				and ('<font color="#ffffff">%s</font>'):format(UiKit.escape(a.word))
				or ('<font color="#7d7d92">%s</font>'):format(UiKit.escape(a.word)))
		end
		table.insert(blocks, ("<b>%s</b>   %s"):format(
			UiKit.escape(row.name),
			#words > 0 and table.concat(words, ", ") or "nothing"))
	end
	answersLabel.Text = table.concat(blocks, "\n")
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
	input.Text = ""
	cards.clear()
	cards.frame.Visible = false
	answersLabel.Visible = false
	wordsFrame.Visible = true
	paintWords()
	paintMeter()
	paintButton()
end

---------------------------------------------------------------- build

function DeepDive.build(parent, modeApi)
	api = modeApi
	frame = UiKit.panel(parent)

	roundLabel = UiKit.label(frame, {
		Size = UDim2.new(1, -20, 0.06, 0), Position = UDim2.new(0, 10, 0.02, 0),
		max = UiKit.TEXT.small, TextScaled = true, TextColor3 = UiKit.DIM, Text = "",
	})

	categoryLabel = UiKit.label(frame, {
		max = UiKit.TEXT.display, Size = UDim2.new(1, -20, 0.13, 0), Position = UDim2.new(0, 10, 0.08, 0),
		TextScaled = true, Font = Enum.Font.GothamBlack, Text = "Get ready...",
	})

	input = UiKit.field(frame, {
		Size = UDim2.new(0.62, -14, 0.11, 0), Position = UDim2.new(0, 10, 0.23, 0),
		PlaceholderText = "An answer...", Text = "",
	})

	actionButton = UiKit.button(frame, "Done", UiKit.GREEN,
		UDim2.new(0.38, -14, 0.11, 0), UDim2.new(0.62, 4, 0.23, 0))
	actionButton.Visible = false

	-- how full your list is, so the cap is visible rather than a surprise
	local meterBack = UiKit.make("Frame", {
		Size = UDim2.new(1, -20, 0.045, 0), Position = UDim2.new(0, 10, 0.36, 0),
		BackgroundColor3 = UiKit.FIELD, Parent = frame,
	})
	UiKit.corner(meterBack, 6)
	meterFill = UiKit.make("Frame", {
		Size = UDim2.fromScale(0, 1), BackgroundColor3 = UiKit.ACCENT,
		BorderSizePixel = 0, Parent = meterBack,
	})
	UiKit.corner(meterFill, 6)
	meterText = UiKit.label(meterBack, {
		Size = UDim2.fromScale(1, 1), TextSize = 13, Font = Enum.Font.GothamBold, Text = "",
	})

	statusLabel = UiKit.label(frame, {
		Size = UDim2.new(1, -20, 0.06, 0), Position = UDim2.new(0, 10, 0.42, 0),
		max = UiKit.TEXT.body, TextScaled = true, Font = Enum.Font.GothamMedium,
		TextColor3 = UiKit.YELLOW, Text = "",
	})

	wordsFrame = UiKit.make("ScrollingFrame", {
		Size = UDim2.new(1, -20, 0.48, 0), Position = UDim2.new(0, 10, 0.49, 0),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
		Parent = frame,
	})
	UiKit.make("UIListLayout", {
		Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = wordsFrame,
	})

	cards = PlayerCards.new(frame,
		UDim2.new(0, 10, 0.49, 0), UDim2.new(1, -20, 0.22, 0))
	cards.frame.Visible = false

	answersLabel = UiKit.label(frame, {
		Size = UDim2.new(1, -20, 0.24, 0), Position = UDim2.new(0, 10, 0.73, 0),
		TextWrapped = true, RichText = true, TextSize = 14, Visible = false,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = "",
	})

	actionButton.Activated:Connect(function()
		if iAmDone then
			setDone(false)
		elseif input.Text ~= "" then
			addWord()
		else
			setDone(true)
		end
	end)
	input.FocusLost:Connect(function(enterPressed)
		if enterPressed then addWord() end
	end)
	-- the button changes meaning as you type, so it has to follow the box
	input:GetPropertyChangedSignal("Text"):Connect(paintButton)

	paintMeter()
	return frame
end

return DeepDive
