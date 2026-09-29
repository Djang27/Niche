-- ModuleScript: StarterPlayerScripts > UiKit
-- Shared building blocks so the shell and every mode's screen look like one game.
--
-- The scales below exist so screens stop inventing their own spacing and text sizes.
-- Use them rather than raw numbers: a value that appears twice should come from here.

local TweenService = game:GetService("TweenService")

local UiKit = {}

local HOVER = TweenInfo.new(0.12, Enum.EasingStyle.Quad)

---------------------------------------------------------------- palette

UiKit.WHITE = Color3.new(1, 1, 1)
UiKit.YELLOW = Color3.fromRGB(255, 210, 80)
UiKit.RED = Color3.fromRGB(255, 90, 90)
UiKit.BLUE = Color3.fromRGB(70, 130, 255)
UiKit.GREEN = Color3.fromRGB(60, 180, 90)
UiKit.GRAY = Color3.fromRGB(70, 70, 90)
UiKit.DIM = Color3.fromRGB(170, 170, 190)

UiKit.ACCENT = Color3.fromRGB(124, 92, 255) -- primary actions and highlights
UiKit.EDGE = Color3.fromRGB(120, 120, 155)  -- panel and control outlines
UiKit.PANEL = Color3.fromRGB(25, 25, 35)
UiKit.FIELD = Color3.fromRGB(45, 45, 60)
UiKit.BACKDROP = Color3.fromRGB(15, 15, 22)

---------------------------------------------------------------- scales

UiKit.SPACE = { xs = 4, sm = 8, md = 14, lg = 22, xl = 34 }
UiKit.RADIUS = 10

-- Ceilings for TextScaled text, NOT fixed sizes. TextScaled alone grows text to fill its
-- box, so a one-word label renders huge and a long one tiny - the same label changing
-- size between rounds is the single most placeholder-looking thing in the UI. Capping it
-- keeps a role's text one size until it genuinely has to shrink to fit.
UiKit.TEXT = {
	display = 40, -- the one big thing on a screen: NICHE, the category, the dial ends
	title = 28,
	heading = 21, -- buttons, prompts
	body = 16,
	small = 13,
}

---------------------------------------------------------------- primitives

function UiKit.make(class, props)
	local inst = Instance.new(class)
	local parent = props.Parent
	props.Parent = nil
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

-- RichText labels render markup, so anything a player typed has to be escaped first
function UiKit.escape(s)
	return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

function UiKit.corner(inst, radius)
	UiKit.make("UICorner", { CornerRadius = UDim.new(0, radius or UiKit.RADIUS), Parent = inst })
	return inst
end

-- caps how large TextScaled text is allowed to get
local function capText(inst, max)
	if max then
		UiKit.make("UITextSizeConstraint", { MaxTextSize = max, Parent = inst })
	end
	return inst
end

-- outline + a top-lit gradient. The gradient multiplies the frame's own colour, so a
-- surface keeps whatever BackgroundColor3 it was given and just gains depth.
function UiKit.surface(inst, strokeTransparency)
	UiKit.make("UIStroke", {
		Color = UiKit.EDGE, Thickness = 1,
		Transparency = strokeTransparency or 0.45, Parent = inst,
	})
	UiKit.make("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 168)),
		Parent = inst,
	})
	return inst
end

function UiKit.panel(parent)
	local f = UiKit.make("Frame", {
		Size = UDim2.fromScale(0.5, 0.6), Position = UDim2.fromScale(0.25, 0.2),
		BackgroundColor3 = UiKit.PANEL, Visible = false, Parent = parent,
	})
	return UiKit.surface(UiKit.corner(f, 14))
end

-- `max` caps TextScaled growth; everything else passes straight through
function UiKit.label(parent, props)
	local max = props.max
	props.max = nil
	props.BackgroundTransparency = 1
	props.TextColor3 = props.TextColor3 or UiKit.WHITE
	props.Font = props.Font or Enum.Font.Gotham
	props.Parent = parent
	-- default ceiling: a label only grows past `title` if it explicitly asks to
	if props.TextScaled and not max then
		max = UiKit.TEXT.title
	end
	return capText(UiKit.make("TextLabel", props), max)
end

function UiKit.button(parent, text, color, size, pos, max)
	local b = UiKit.make("TextButton", {
		Size = size, Position = pos, Text = text, TextScaled = true,
		Font = Enum.Font.GothamBold, TextColor3 = UiKit.WHITE, BackgroundColor3 = color, Parent = parent,
	})
	local stroke = UiKit.make("UIStroke", {
		Color = UiKit.WHITE, Thickness = 1, Transparency = 0.86, Parent = b,
	})
	-- AutoButtonColor already dips the fill on press, so hover is the missing half
	b.MouseEnter:Connect(function()
		TweenService:Create(stroke, HOVER, { Transparency = 0.45 }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(stroke, HOVER, { Transparency = 0.86 }):Play()
	end)

	-- buttons are short words in tall boxes, so uncapped they balloon worst of all
	return capText(UiKit.corner(b, 8), max or UiKit.TEXT.heading)
end

function UiKit.field(parent, props)
	props.ClearTextOnFocus = false
	props.TextScaled = true
	props.Font = props.Font or Enum.Font.Gotham
	props.TextColor3 = props.TextColor3 or UiKit.WHITE
	props.BackgroundColor3 = props.BackgroundColor3 or UiKit.FIELD
	local max = props.max
	props.max = nil
	props.Parent = parent
	local box = UiKit.corner(UiKit.make("TextBox", props), 8)
	local stroke = UiKit.make("UIStroke", {
		Color = UiKit.EDGE, Thickness = 1, Transparency = 0.6, Parent = box,
	})
	-- an accent outline while focused, so it is obvious where typing goes
	box.Focused:Connect(function()
		TweenService:Create(stroke, HOVER, { Transparency = 0, Color = UiKit.ACCENT }):Play()
	end)
	box.FocusLost:Connect(function()
		TweenService:Create(stroke, HOVER, { Transparency = 0.6, Color = UiKit.EDGE }):Play()
	end)
	return capText(box, max or UiKit.TEXT.heading)
end

-- the full-screen backdrop behind every panel
function UiKit.backdrop(parent)
	local f = UiKit.make("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = UiKit.BACKDROP,
		BorderSizePixel = 0, ZIndex = 0, Parent = parent,
	})
	UiKit.make("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromRGB(150, 150, 180), Color3.new(1, 1, 1)),
		Parent = f,
	})
	return f
end

return UiKit
