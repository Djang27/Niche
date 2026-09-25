-- ModuleScript: StarterPlayerScripts > UiKit
-- Shared building blocks so the shell and every mode's screen look like one game.

local UiKit = {}

UiKit.WHITE = Color3.new(1, 1, 1)
UiKit.YELLOW = Color3.fromRGB(255, 210, 80)
UiKit.RED = Color3.fromRGB(255, 90, 90)
UiKit.BLUE = Color3.fromRGB(70, 130, 255)
UiKit.GREEN = Color3.fromRGB(60, 180, 90)
UiKit.GRAY = Color3.fromRGB(70, 70, 90)
UiKit.DIM = Color3.fromRGB(170, 170, 190)

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

function UiKit.panel(parent)
	local f = UiKit.make("Frame", {
		Size = UDim2.fromScale(0.5, 0.6), Position = UDim2.fromScale(0.25, 0.2),
		BackgroundColor3 = Color3.fromRGB(25, 25, 35), Visible = false, Parent = parent,
	})
	UiKit.make("UICorner", { CornerRadius = UDim.new(0, 12), Parent = f })
	return f
end

function UiKit.label(parent, props)
	props.BackgroundTransparency = 1
	props.TextColor3 = props.TextColor3 or UiKit.WHITE
	props.Font = props.Font or Enum.Font.Gotham
	props.Parent = parent
	return UiKit.make("TextLabel", props)
end

function UiKit.button(parent, text, color, size, pos)
	local b = UiKit.make("TextButton", {
		Size = size, Position = pos, Text = text, TextScaled = true,
		Font = Enum.Font.GothamBold, TextColor3 = UiKit.WHITE, BackgroundColor3 = color, Parent = parent,
	})
	UiKit.make("UICorner", { CornerRadius = UDim.new(0, 8), Parent = b })
	return b
end

return UiKit
