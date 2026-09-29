-- ModuleScript: StarterPlayerScripts > Modes > Niche
-- The Niche game screen: a prompt, one answer, then the round's results.
--
-- The shell (GameUI) builds this once and shows or hides the frame it returns.
-- Everything below the build is this mode's own business.

local UiKit = require(script.Parent.Parent.UiKit)
local PlayerCards = require(script.Parent.Parent.PlayerCards)

local Niche = {
	name = "Niche",
	blurb = "The rarer your answer, the more points",
}

-- Color3 rather than RichText hex: the reveal is player cards now, not markup
local TIER_COLORS = {
	Common = Color3.fromRGB(176, 176, 176),
	Rare = Color3.fromRGB(77, 166, 255),
	SuperRare = Color3.fromRGB(179, 102, 255),
	Epic = Color3.fromRGB(255, 153, 51),
	Legendary = Color3.fromRGB(255, 215, 0),
	Invalid = Color3.fromRGB(255, 77, 77),
}

local api
local frame, promptLabel, timerLabel, input, submit, hintLabel
local cards
local curRound, curTotal = 0, 0

local locked = true
local checking = false
local roundId = 0
local pendingSuggestion = nil
local suggestionText = nil

---------------------------------------------------------------- answering

local function setHint(text, color)
	hintLabel.Text = text
	hintLabel.TextColor3 = color or UiKit.YELLOW
end

local function send(canonical, display)
	locked = true
	pendingSuggestion = nil
	input.TextEditable = false
	input.Text = display
	submit.Text = "Locked!"
	setHint("")
	api.send("submit", canonical)
end

local function lockIn()
	if locked or checking or input.Text == "" then return end

	-- second Enter on a "did you mean X?" accepts the correction
	if pendingSuggestion then
		send(pendingSuggestion, suggestionText)
		return
	end

	checking = true
	local ok, status, canonical, display = pcall(api.request, "check", input.Text)
	checking = false
	if not ok or locked then return end

	if status == "valid" then
		send(canonical, display)
	elseif status == "suggest" then
		input.Text = display
		pendingSuggestion = canonical
		suggestionText = display
		setHint(("Did you mean %s? Press Enter to confirm"):format(display), UiKit.YELLOW)
		input:CaptureFocus()
	elseif status == "invalid" then
		setHint("Not an answer, try again", UiKit.RED)
		input:CaptureFocus()
	elseif status == "slow" then
		setHint("Slow down a second", UiKit.RED)
		input:CaptureFocus()
	end
end

---------------------------------------------------------------- server messages

local function onPrompt(text, seconds, round, total)
	roundId += 1
	local myRound = roundId

	locked = false
	pendingSuggestion = nil
	input.Text = ""
	input.TextEditable = true
	submit.Text = "Lock in"
	setHint("")
	promptLabel.Text = text
	curRound, curTotal = round, total
	cards.clear()

	task.spawn(function()
		for t = seconds, 0, -1 do
			if roundId ~= myRound then return end
			-- the round counter lives here now that the cards own the space below
			timerLabel.Text = ("Round %d/%d   %ds"):format(curRound, curTotal, t)
			task.wait(1)
		end
	end)
end

local function onResults(results)
	locked = true
	pendingSuggestion = nil
	input.TextEditable = false
	timerLabel.Text = ""
	setHint("")

	local rows = {}
	for _, r in ipairs(results) do
		table.insert(rows, {
			userId = r.userId,
			name = r.name,
			headline = ('"%s"'):format(r.answer),
			trailing = ("+%d"):format(r.points),
			sub = ("%s   total %d"):format(r.tier, r.total),
			accent = TIER_COLORS[r.tier] or UiKit.WHITE,
			-- rare answers are the entire point of Niche, so they get a beat of their own
			emphasis = r.tier == "Epic" or r.tier == "Legendary",
		})
	end
	cards.show(rows, "Nobody answered")
end

function Niche.onEvent(kind, ...)
	if kind == "prompt" then
		onPrompt(...)
	elseif kind == "results" then
		onResults(...)
	end
end

-- the shell calls this when the match ends, so the screen is clean next time
function Niche.reset()
	roundId += 1
	locked = true
	pendingSuggestion = nil
	promptLabel.Text = "Get ready..."
	cards.clear()
	timerLabel.Text = ""
	input.Text = ""
	setHint("")
end

---------------------------------------------------------------- build

function Niche.build(parent, modeApi)
	api = modeApi
	frame = UiKit.panel(parent)

	promptLabel = UiKit.label(frame, {
		Size = UDim2.new(1, -20, 0.18, 0), Position = UDim2.new(0, 10, 0, 10),
		TextScaled = true, Font = Enum.Font.GothamBold, Text = "Get ready...",
	})

	timerLabel = UiKit.label(frame, {
		Size = UDim2.new(1, -20, 0.08, 0), Position = UDim2.new(0, 10, 0.2, 0),
		TextScaled = true, TextColor3 = UiKit.YELLOW, Text = "",
	})

	input = UiKit.field(frame, {
		Size = UDim2.new(0.7, -15, 0.12, 0), Position = UDim2.new(0, 10, 0.31, 0),
		PlaceholderText = "Your most niche answer...", Text = "",
	})

	submit = UiKit.button(frame, "Lock in", UiKit.BLUE,
		UDim2.new(0.3, -15, 0.12, 0), UDim2.new(0.7, 5, 0.31, 0))

	hintLabel = UiKit.label(frame, {
		Size = UDim2.new(1, -20, 0.06, 0), Position = UDim2.new(0, 10, 0.44, 0),
		TextScaled = true, Font = Enum.Font.GothamMedium,
		TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = UiKit.YELLOW, Text = "",
	})

	cards = PlayerCards.new(frame,
		UDim2.new(0, 10, 0.52, 0), UDim2.new(1, -20, 0.46, -10))

	input:GetPropertyChangedSignal("Text"):Connect(function()
		if pendingSuggestion and input.Text ~= suggestionText then
			pendingSuggestion = nil
			setHint("")
		elseif hintLabel.TextColor3 == UiKit.RED then
			setHint("")
		end
	end)

	submit.Activated:Connect(lockIn)
	input.FocusLost:Connect(function(enterPressed)
		if enterPressed then lockIn() end
	end)

	return frame
end

return Niche
