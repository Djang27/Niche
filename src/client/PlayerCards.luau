-- ModuleScript: StarterPlayerScripts > PlayerCards
--
-- A reveal as a row of players rather than a paragraph of text: avatar, name, what they
-- answered, what it scored, framed by whatever banner they have equipped.
--
-- Shared so every mode's reveal looks like the same game, and so banners earn their keep
-- every round instead of only on the intro screen.
--
-- Rows are mode-agnostic; each mode maps its own reveal payload into this shape:
--   { userId, name, headline, trailing, sub, accent, emphasis }
-- headline is the big middle text (an answer), trailing the big right text (+100), sub
-- the quiet line under it, accent the colour for trailing, emphasis whether it flashes.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local UiKit = require(script.Parent.UiKit)
local Cosmetics = require(script.Parent.Cosmetics)

local PlayerCards = {}

local ROW_H = 48
local STAGGER = 0.09 -- seconds between rows appearing
local FLASH = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 1, true)

function PlayerCards.new(parent, position, size)
	local scroller = UiKit.make("ScrollingFrame", {
		Position = position, Size = size,
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
		Parent = parent,
	})
	UiKit.make("UIListLayout", {
		Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroller,
	})

	local self = {}
	local live = {}
	local generation = 0

	local function clear()
		generation += 1 -- pending staggered reveals from a previous round must not fire
		for _, r in ipairs(live) do
			r:Destroy()
		end
		table.clear(live)
	end
	self.clear = clear

	function self.show(rows, emptyText)
		clear()
		local mine = generation

		if #rows == 0 then
			table.insert(live, UiKit.label(scroller, {
				Size = UDim2.new(1, 0, 0, ROW_H), TextScaled = true, max = UiKit.TEXT.body,
				TextColor3 = UiKit.DIM, Text = emptyText or "Nobody answered",
			}))
			return
		end

		for i, row in ipairs(rows) do
			local p = row.userId and Players:GetPlayerByUserId(row.userId)
			local skin = Cosmetics.banner(p and p:GetAttribute("Banner"))

			local card = UiKit.make("Frame", {
				Size = UDim2.new(1, 0, 0, ROW_H), BackgroundColor3 = UiKit.WHITE,
				LayoutOrder = i, Visible = false, Parent = scroller,
			})
			UiKit.corner(card, 8)
			UiKit.make("UIGradient", {
				Color = ColorSequence.new(skin.from, skin.to), Parent = card,
			})
			local stroke = UiKit.make("UIStroke", {
				Color = skin.edge, Thickness = 1, Transparency = 0.35, Parent = card,
			})

			local avatar = UiKit.make("ImageLabel", {
				Size = UDim2.fromOffset(36, 36), Position = UDim2.fromOffset(6, 6),
				BackgroundColor3 = Color3.fromRGB(18, 18, 26), BackgroundTransparency = 0.25,
				Image = "", Parent = card,
			})
			UiKit.corner(avatar, 6)

			UiKit.label(card, {
				Size = UDim2.new(0.55, -50, 0, 15), Position = UDim2.fromOffset(50, 7),
				TextSize = 13, Font = Enum.Font.GothamMedium, TextColor3 = UiKit.DIM,
				TextXAlignment = Enum.TextXAlignment.Left, Text = row.name or "",
			})
			UiKit.label(card, {
				Size = UDim2.new(0.55, -50, 0, 21), Position = UDim2.fromOffset(50, 22),
				TextSize = 17, Font = Enum.Font.GothamBold,
				TextXAlignment = Enum.TextXAlignment.Left, Text = row.headline or "",
			})

			UiKit.label(card, {
				Size = UDim2.new(0.45, -12, 0, 21), Position = UDim2.new(0.55, 0, 0, 6),
				TextSize = 19, Font = Enum.Font.GothamBlack, TextColor3 = row.accent or UiKit.WHITE,
				TextXAlignment = Enum.TextXAlignment.Right, Text = row.trailing or "",
			})
			UiKit.label(card, {
				Size = UDim2.new(0.45, -12, 0, 14), Position = UDim2.new(0.55, 0, 0, 28),
				TextSize = 12, Font = Enum.Font.GothamMedium, TextColor3 = UiKit.DIM,
				TextXAlignment = Enum.TextXAlignment.Right, Text = row.sub or "",
			})

			table.insert(live, card)

			-- thumbnails yield and can fail; an empty square beats a broken reveal
			task.spawn(function()
				local ok, content = pcall(function()
					return Players:GetUserThumbnailAsync(row.userId,
						Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
				end)
				if ok and avatar.Parent then
					avatar.Image = content
				end
			end)

			-- one at a time, so a good answer gets a beat of its own instead of the whole
			-- round appearing at once
			task.delay(i * STAGGER, function()
				if generation ~= mine or not card.Parent then return end
				card.Visible = true
				if row.emphasis then
					TweenService:Create(stroke, FLASH, {
						Thickness = 3, Transparency = 0, Color = row.accent or skin.edge,
					}):Play()
				end
			end)
		end
	end

	return self
end

return PlayerCards
