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
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local UiKit = require(script.Parent:WaitForChild("UiKit"))
local Cosmetics = require(script.Parent:WaitForChild("Cosmetics"))

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

-- Games we intend to build, shown greyed out on the modes screen. As soon as a real
-- module with the same name exists it is picked up as playable and drops off this list.
local PLANNED = { "Wavelength", "???", "???" }

-- Running order on the modes grid. Matched against a mode's id, or a group's name for
-- grouped games. Anything not listed falls in after these, alphabetically.
local ORDER = { "Niche", "Wavelength", "DeepDive" }

---------------------------------------------------------------- base

local gui = UiKit.make("ScreenGui", {
	Name = "NicheGui", ResetOnSpawn = false, IgnoreGuiInset = true,
	Parent = player:WaitForChild("PlayerGui"),
})

UiKit.backdrop(gui)

---------------------------------------------------------------- running score

-- Sits above whichever mode is playing. The shell owns scores, so every game gets a
-- visible running total for free instead of each one remembering to print one - and it
-- stays up through the whole round rather than flashing past in a reveal.
local scoreStrip = UiKit.surface(UiKit.corner(UiKit.make("Frame", {
	BackgroundColor3 = UiKit.PANEL, Visible = false, Parent = gui,
}), 8))

local scoreLabel = UiKit.label(scoreStrip, {
	Size = UDim2.new(1, -16, 1, 0), Position = UDim2.new(0, 8, 0, 0),
	TextScaled = true, Font = Enum.Font.GothamBold, Text = "",
})

-- Sits below the panel, so it reads as a footer rather than competing with the game.
local waitingLabel = UiKit.label(gui, {
	Size = UDim2.fromScale(0.5, 0.045), Position = UDim2.fromScale(0.25, 0.815),
	-- repositioned just below by onViewport
	TextScaled = true, max = UiKit.TEXT.body, Font = Enum.Font.GothamMedium,
	TextColor3 = UiKit.DIM, Visible = false, Text = "",
})

-- these bracket the panel, so they have to move when the panel grows
UiKit.onViewport(function(compact)
	local w = compact and 0.96 or 0.5
	scoreStrip.Size = UDim2.fromScale(w, compact and 0.05 or 0.055)
	scoreStrip.Position = UDim2.fromScale((1 - w) / 2, compact and 0.005 or 0.135)

	waitingLabel.Size = UDim2.fromScale(w, 0.045)
	waitingLabel.Position = UDim2.fromScale((1 - w) / 2, compact and 0.948 or 0.815)
end)

local function renderScore()
	-- a mode may phrase it itself (Teams: "Red 14 - 9 Blue")
	local custom = ReplicatedStorage:GetAttribute("Scoreboard")
	if custom and custom ~= "" then
		scoreLabel.Text = custom
		return
	end

	local rows = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("InMatch") then
			table.insert(rows, { name = p.DisplayName, score = p:GetAttribute("Score") or 0 })
		end
	end
	table.sort(rows, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.name < b.name
	end)

	local parts = {}
	for _, r in ipairs(rows) do
		table.insert(parts, ("%s %d"):format(r.name, r.score))
	end
	scoreLabel.Text = table.concat(parts, "   \u{00B7}   ")
end

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

-- 0 means the mode has no cap
local function maxPlayersFor(id)
	local entry = availableModes:FindFirstChild(id or "")
	local max = entry and entry:GetAttribute("MaxPlayers") or 0
	return max > 0 and max or nil
end

remotes.ModeEvent.OnClientEvent:Connect(function(kind, ...)
	local mode = activeMode()
	if mode and mode.onEvent then
		mode.onEvent(kind, ...)
	end
end)

---------------------------------------------------------------- match intro

-- Wider than a normal panel because it holds a row of avatars rather than a column of
-- text. Shown between the countdown and the first round.
local introFrame = UiKit.surface(UiKit.corner(UiKit.make("Frame", {
	BackgroundColor3 = UiKit.PANEL, Visible = false, Parent = gui,
}), 14))
UiKit.fit(introFrame, 0.72, 0.52)

UiKit.label(introFrame, {
	Size = UDim2.new(1, -20, 0.14, 0), Position = UDim2.new(0, 10, 0.04, 0),
	max = UiKit.TEXT.display, TextScaled = true, Font = Enum.Font.GothamBlack,
	Text = "Get ready",
})

local introSubtitle = UiKit.label(introFrame, {
	Size = UDim2.new(1, -20, 0.07, 0), Position = UDim2.new(0, 10, 0.18, 0),
	TextScaled = true, max = UiKit.TEXT.body, TextColor3 = UiKit.DIM, Text = "",
})

local introGrid = UiKit.make("Frame", {
	Size = UDim2.new(1, -40, 0.66, 0), Position = UDim2.new(0, 20, 0.28, 0),
	BackgroundTransparency = 1, Parent = introFrame,
})
UiKit.make("UIGridLayout", {
	CellSize = UDim2.fromOffset(108, 130), CellPadding = UDim2.fromOffset(12, 12),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder, Parent = introGrid,
})

-- Shared by the intro and the between-round recap. `caption` is the points line; without
-- it the avatar simply takes more of the tile.
local function makeTile(grid, p, caption, accent)
	-- the server replicates only an id; this client decides how it looks
	local skin = Cosmetics.banner(p:GetAttribute("Banner"))

	local tile = UiKit.make("Frame", {
		BackgroundColor3 = UiKit.WHITE, Parent = grid,
	})
	UiKit.corner(tile, 10)
	UiKit.make("UIGradient", {
		Rotation = 90, Color = ColorSequence.new(skin.from, skin.to), Parent = tile,
	})
	UiKit.make("UIStroke", { Color = skin.edge, Thickness = 2, Transparency = 0.2, Parent = tile })

	local avatarBottom = caption and 0.56 or 0.72
	local avatar = UiKit.make("ImageLabel", {
		Size = UDim2.new(0.78, 0, avatarBottom - 0.06, 0),
		Position = UDim2.new(0.5, 0, 0.04, 0), AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1, Image = "", Parent = tile,
	})
	UiKit.aspect(avatar) -- thumbnails are square; don't let the tile shape distort the face
	UiKit.label(tile, {
		Size = UDim2.new(1, -8, caption and 0.18 or 0.22, 0),
		Position = UDim2.new(0, 4, avatarBottom, 0),
		TextScaled = true, max = UiKit.TEXT.small, Font = Enum.Font.GothamBold,
		Text = p.DisplayName,
	})
	if caption then
		UiKit.label(tile, {
			Size = UDim2.new(1, -8, 0.22, 0), Position = UDim2.new(0, 4, 0.75, 0),
			TextScaled = true, max = UiKit.TEXT.heading, Font = Enum.Font.GothamBlack,
			TextColor3 = accent or UiKit.WHITE, Text = caption,
		})
	end

	-- thumbnails yield and can fail; an empty frame beats a broken screen
	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(p.UserId,
				Enum.ThumbnailType.AvatarBust, Enum.ThumbnailSize.Size150x150)
		end)
		if ok and avatar.Parent then
			avatar.Image = content
		end
	end)

	return tile
end

-- Reactions are on the tile, not the avatar. Animating the real avatar would mean a
-- ViewportFrame and a loaded rig per player, which is a lot of 3D rendering for a phone.
local function celebrate(tile)
	local scale = UiKit.make("UIScale", { Scale = 1, Parent = tile })
	TweenService:Create(scale,
		TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 3, true),
		{ Scale = 1.14 }):Play()
end

local function slump(tile)
	TweenService:Create(tile,
		TweenInfo.new(0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 5, true),
		{ Rotation = -6 }):Play()
end

local introTiles = {}

local function buildIntro()
	for _, t in ipairs(introTiles) do
		t:Destroy()
	end
	table.clear(introTiles)

	local mode = activeMode()
	introSubtitle.Text = mode and mode.name or ""

	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("InMatch") then
			table.insert(introTiles, makeTile(introGrid, p))
		end
	end
end

---------------------------------------------------------------- between-round recap

local recapFrame = UiKit.surface(UiKit.corner(UiKit.make("Frame", {
	BackgroundColor3 = UiKit.PANEL, Visible = false, Parent = gui,
}), 14))
UiKit.fit(recapFrame, 0.72, 0.52)

UiKit.label(recapFrame, {
	Size = UDim2.new(1, -20, 0.13, 0), Position = UDim2.new(0, 10, 0.04, 0),
	max = UiKit.TEXT.title, TextScaled = true, Font = Enum.Font.GothamBlack,
	Text = "Standings",
})

local recapGrid = UiKit.make("Frame", {
	Size = UDim2.new(1, -40, 0.72, 0), Position = UDim2.new(0, 20, 0.2, 0),
	BackgroundTransparency = 1, Parent = recapFrame,
})
UiKit.make("UIGridLayout", {
	CellSize = UDim2.fromOffset(108, 152), CellPadding = UDim2.fromOffset(12, 12),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder, Parent = recapGrid,
})

local recapTiles = {}

local function buildRecap()
	for _, t in ipairs(recapTiles) do
		t:Destroy()
	end
	table.clear(recapTiles)

	local playing = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("InMatch") then
			table.insert(playing, p)
		end
	end
	table.sort(playing, function(a, b)
		local sa, sb = a:GetAttribute("Score") or 0, b:GetAttribute("Score") or 0
		if sa ~= sb then
			return sa > sb
		end
		return a.DisplayName < b.DisplayName
	end)

	-- react to what the round was worth, not the running total: last place can still
	-- have had a good round
	local best = 0
	for _, p in ipairs(playing) do
		best = math.max(best, p:GetAttribute("RoundDelta") or 0)
	end

	for i, p in ipairs(playing) do
		local delta = p:GetAttribute("RoundDelta") or 0
		local total = p:GetAttribute("Score") or 0
		local tile = makeTile(recapGrid, p,
			("+%d"):format(delta),
			delta > 0 and UiKit.GREEN or UiKit.DIM)
		tile.LayoutOrder = i

		UiKit.label(tile, {
			Size = UDim2.new(1, -8, 0.14, 0), Position = UDim2.new(0, 4, 0.955, 0),
			TextScaled = true, max = UiKit.TEXT.small, TextColor3 = UiKit.DIM,
			Text = ("total %d"):format(total),
		})

		table.insert(recapTiles, tile)
		if best > 0 and delta == best then
			celebrate(tile)
		elseif delta == 0 then
			slump(tile)
		end
	end
end

---------------------------------------------------------------- locker

local cosmeticsFolder = ReplicatedStorage:WaitForChild("Cosmetics")

local function currencyText()
	return ("%d gold   %d gems"):format(
		player:GetAttribute("Gold") or 0, player:GetAttribute("Gems") or 0)
end

-- what this player owns beyond the free set, replicated as one comma list
local function ownedSet()
	local set = {}
	for id in string.gmatch(player:GetAttribute("OwnedCosmetics") or "", "[^,]+") do
		set[id] = true
	end
	return set
end

local lockerFrame = UiKit.panel(gui)

UiKit.label(lockerFrame, {
	Size = UDim2.new(1, -20, 0.1, 0), Position = UDim2.new(0, 10, 0.02, 0),
	max = UiKit.TEXT.title, TextScaled = true, Font = Enum.Font.GothamBold, Text = "Locker",
})

local lockerWallet = UiKit.label(lockerFrame, {
	Size = UDim2.new(0.5, -10, 0.06, 0), Position = UDim2.new(0.5, 0, 0.04, 0),
	max = UiKit.TEXT.body, TextScaled = true, Font = Enum.Font.GothamBold,
	TextColor3 = UiKit.YELLOW, TextXAlignment = Enum.TextXAlignment.Right, Text = "",
})
-- One tab per cosmetic kind, then TBD slots for categories that don't exist yet. `false`
-- means a placeholder rather than a kind.
local KIND_LABELS = { Banner = "Banners", RevealEffect = "Effects" }
local LOCKER_TABS = { "Banner", "RevealEffect", false, false }
local lockerTab = 1

-- the tab handlers need this before it is written
local buildLocker
local tabButtons = {}

for i, kind in ipairs(LOCKER_TABS) do
	local b = UiKit.button(lockerFrame,
		kind and (KIND_LABELS[kind] or kind) or "TBD",
		UiKit.FIELD,
		UDim2.new(0.25, -8, 0.105, 0), UDim2.new(0.25 * (i - 1), 4, 0.135, 0),
		UiKit.TEXT.body)
	b.Activated:Connect(function()
		lockerTab = i
		buildLocker()
	end)
	tabButtons[i] = b
end

local function paintTabs()
	for i, b in ipairs(tabButtons) do
		b.BackgroundColor3 = (i == lockerTab) and UiKit.ACCENT or UiKit.FIELD
	end
end

local lockerGrid = UiKit.make("ScrollingFrame", {
	Size = UDim2.new(0.62, -20, 0.47, 0), Position = UDim2.new(0.37, 0, 0.26, 0),
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
	AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Parent = lockerFrame,
})
local lockerLayout = UiKit.make("UIGridLayout", {
	CellPadding = UDim2.fromOffset(8, 8),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder, Parent = lockerGrid,
})

-- Cells in scale, not pixels: a fixed 112px cell wastes space on a laptop and crowds a
-- phone. Column count drops on a small screen so a swatch never gets too narrow to read.
UiKit.onViewport(function(compact)
	local cols = compact and 2 or 3
	lockerLayout.CellSize = UDim2.new(1 / cols, -10, 0, compact and 112 or 120)
end)

local lockerHint = UiKit.label(lockerFrame, {
	Size = UDim2.new(1, -20, 0.055, 0), Position = UDim2.new(0, 10, 0.745, 0),
	max = UiKit.TEXT.body, TextScaled = true, Font = Enum.Font.GothamMedium,
	TextColor3 = UiKit.YELLOW, Text = "",
})

-- A live preview beside the grid: equipping blind is the main thing a locker should fix.
-- It shows what is actually equipped, repainted when the attribute comes back, so it can
-- never show something the server refused.
local previewTile = UiKit.make("Frame", {
	Size = UDim2.new(0.36, 0, 0.47, 0), Position = UDim2.new(0, 10, 0.26, 0),
	BackgroundColor3 = UiKit.WHITE, Parent = lockerFrame,
})
UiKit.corner(previewTile, 10)
local previewGradient = UiKit.make("UIGradient", { Rotation = 90, Parent = previewTile })
local previewStroke = UiKit.make("UIStroke", { Thickness = 2, Transparency = 0.15, Parent = previewTile })

local previewAvatar = UiKit.make("ImageLabel", {
	Size = UDim2.new(0.84, 0, 0.62, 0),
	Position = UDim2.new(0.5, 0, 0.05, 0), AnchorPoint = Vector2.new(0.5, 0),
	BackgroundTransparency = 1, Image = "", Parent = previewTile,
})
UiKit.aspect(previewAvatar)
UiKit.label(previewTile, {
	Size = UDim2.new(1, -8, 0.13, 0), Position = UDim2.new(0, 4, 0.69, 0),
	TextScaled = true, max = UiKit.TEXT.body, Font = Enum.Font.GothamBold,
	Text = player.DisplayName,
})
local previewBannerName = UiKit.label(previewTile, {
	Size = UDim2.new(1, -8, 0.12, 0), Position = UDim2.new(0, 4, 0.83, 0),
	TextScaled = true, max = UiKit.TEXT.small, TextColor3 = UiKit.WHITE, Text = "",
})

-- the avatar never changes, so fetch it once
task.spawn(function()
	local ok, content = pcall(function()
		return Players:GetUserThumbnailAsync(player.UserId,
			Enum.ThumbnailType.AvatarBust, Enum.ThumbnailSize.Size420x420)
	end)
	if ok then
		previewAvatar.Image = content
	end
end)

local function paintPreview()
	local id = player:GetAttribute("Banner")
	local skin = Cosmetics.banner(id)
	previewGradient.Color = ColorSequence.new(skin.from, skin.to)
	previewStroke.Color = skin.edge

	local entry = cosmeticsFolder:FindFirstChild(id or "")
	previewBannerName.Text = entry and entry.Value or ""
end

local lockerSwatches = {}

local lockerEmpty = UiKit.label(lockerFrame, {
	Size = UDim2.new(0.62, -20, 0.47, 0), Position = UDim2.new(0.37, 0, 0.26, 0),
	TextWrapped = true, TextSize = 15, TextColor3 = UiKit.DIM, Visible = false, Text = "",
})

buildLocker = function()
	paintPreview()
	paintTabs()

	for _, sw in ipairs(lockerSwatches) do
		sw:Destroy()
	end
	table.clear(lockerSwatches)

	lockerWallet.Text = currencyText()

	local mine = ownedSet()
	local kind = LOCKER_TABS[lockerTab]
	if not kind then
		lockerGrid.Visible = false
		lockerEmpty.Visible = true
		lockerEmpty.Text = "Another category will live here.\nNothing to show yet."
		return
	end

	local items = {}
	for _, entry in ipairs(cosmeticsFolder:GetChildren()) do
		if entry:GetAttribute("Kind") == kind then
			table.insert(items, entry)
		end
	end
	table.sort(items, function(a, b)
		return (a:GetAttribute("Order") or 99) < (b:GetAttribute("Order") or 99)
	end)

	lockerGrid.Visible = #items > 0
	lockerEmpty.Visible = #items == 0
	lockerEmpty.Text = "Nothing in this category yet."

	local equipped = player:GetAttribute(kind)
	local wearable = kind == "Banner" -- effects are catalogued but nothing renders them

	for i, entry in ipairs(items) do
		local id = entry.Name
		-- globally free (or dev-unlocked), or personally owned
		local owned = entry:GetAttribute("Owned") == true or mine[id] == true
		local isOn = equipped == id
		local rarity = entry:GetAttribute("Rarity") or "Common"
		local rarityColor = Cosmetics.rarity(rarity)

		local sw = UiKit.make("TextButton", {
			BackgroundColor3 = kind == "Banner" and UiKit.WHITE or UiKit.FIELD,
			Text = "", AutoButtonColor = owned and wearable,
			LayoutOrder = i, Parent = lockerGrid,
		})
		UiKit.corner(sw, 8)
		if kind == "Banner" then
			local skin = Cosmetics.banner(id)
			UiKit.make("UIGradient", {
				Rotation = 90, Color = ColorSequence.new(skin.from, skin.to), Parent = sw,
			})
		end
		-- the outline carries rarity, so it is scannable without reading; thickness
		-- carries equipped, so the two never fight for the same channel
		UiKit.make("UIStroke", {
			Color = rarityColor, Thickness = isOn and 3 or 1,
			Transparency = owned and (isOn and 0 or 0.35) or 0.7, Parent = sw,
		})

		if not owned then
			UiKit.make("Frame", {
				Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(),
				BackgroundTransparency = 0.55, BorderSizePixel = 0, ZIndex = 2, Parent = sw,
			})
		end

		UiKit.label(sw, {
			Size = UDim2.new(1, -8, 0, 16), Position = UDim2.new(0, 4, 1, -48),
			TextSize = 14, Font = Enum.Font.GothamBold, ZIndex = 3, Text = entry.Value,
		})
		UiKit.label(sw, {
			Size = UDim2.new(1, -8, 0, 14), Position = UDim2.new(0, 4, 1, -31),
			TextSize = 12, Font = Enum.Font.GothamMedium, ZIndex = 3,
			TextColor3 = rarityColor, Text = rarity,
		})
		UiKit.label(sw, {
			Size = UDim2.new(1, -8, 0, 13), Position = UDim2.new(0, 4, 1, -16),
			TextSize = 11, ZIndex = 3,
			TextColor3 = isOn and UiKit.GREEN or UiKit.DIM,
			Text = (not owned and "Locked")
				or (not wearable and "Not in game yet")
				or (isOn and "Equipped")
				or "Tap to wear",
		})

		sw.Activated:Connect(function()
			if not owned then
				lockerHint.Text = ("%s isn't unlocked yet"):format(entry.Value)
				return
			end
			if not wearable then
				lockerHint.Text = ("%s exists but nothing renders it yet"):format(entry.Value)
				return
			end
			lockerHint.Text = ""
			-- the server validates ownership and saves; the attribute comes back to us
			remotes.LobbyAction:FireServer("equip", id)
		end)

		table.insert(lockerSwatches, sw)
	end
end

-- repaint when the equip lands, rather than guessing it worked
for _, kind in ipairs(LOCKER_TABS) do
	if kind then
		player:GetAttributeChangedSignal(kind):Connect(function()
			if nav == "locker" then
				buildLocker()
			end
		end)
	end
end
-- and when what you own or can afford changes
for _, attr in ipairs({ "OwnedCosmetics", "Gold", "Gems" }) do
	player:GetAttributeChangedSignal(attr):Connect(function()
		if nav == "locker" then
			buildLocker()
		end
	end)
end

local lockerBack = UiKit.button(lockerFrame, "Back", UiKit.GRAY,
	UDim2.new(1, -20, 0.13, 0), UDim2.new(0, 10, 0.82, 0))
lockerBack.Activated:Connect(function()
	lockerHint.Text = ""
	goTo("menu")
end)

---------------------------------------------------------------- store

local cratesFolder = ReplicatedStorage:WaitForChild("Crates")
local shopRequest = remotes:WaitForChild("ShopRequest")

-- How long the reveal spins before it lands. The server usually answers faster than
-- this, and that is the point: a crate that resolves the instant you tap has no opening
-- to it at all. If the DataStore is slow the spin simply keeps going until it answers.
local SPIN_MIN = 1.6

local shopFrame = UiKit.panel(gui)

UiKit.label(shopFrame, {
	Size = UDim2.new(0.5, -10, 0.095, 0), Position = UDim2.new(0, 10, 0.02, 0),
	max = UiKit.TEXT.title, TextScaled = true, Font = Enum.Font.GothamBold,
	TextXAlignment = Enum.TextXAlignment.Left, Text = "Store",
})

local shopWallet = UiKit.label(shopFrame, {
	Size = UDim2.new(0.5, -10, 0.06, 0), Position = UDim2.new(0.5, 0, 0.04, 0),
	max = UiKit.TEXT.body, TextScaled = true, Font = Enum.Font.GothamBold,
	TextColor3 = UiKit.YELLOW, TextXAlignment = Enum.TextXAlignment.Right, Text = "",
})

UiKit.label(shopFrame, {
	Size = UDim2.new(1, -20, 0.05, 0), Position = UDim2.new(0, 10, 0.125, 0),
	max = UiKit.TEXT.small, TextScaled = true, TextColor3 = UiKit.DIM,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "Chances are shown on every crate. You never get a duplicate.",
})

local shopList = UiKit.make("ScrollingFrame", {
	Size = UDim2.new(1, -20, 0.55, 0), Position = UDim2.new(0, 10, 0.19, 0),
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
	AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Parent = shopFrame,
})
UiKit.make("UIListLayout", {
	Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = shopList,
})

local shopHint = UiKit.label(shopFrame, {
	Size = UDim2.new(1, -20, 0.05, 0), Position = UDim2.new(0, 10, 0.755, 0),
	max = UiKit.TEXT.body, TextScaled = true, Font = Enum.Font.GothamMedium,
	TextColor3 = UiKit.YELLOW, Text = "",
})

---------------------------------------------------------------- the opening

-- Full screen rather than inside the panel: the open is the payoff, and a reveal boxed
-- inside the shop card reads like a tooltip.
local openFrame = UiKit.make("Frame", {
	Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.4, Visible = false, ZIndex = 20, Parent = gui,
})

local openCard = UiKit.make("Frame", {
	BackgroundColor3 = UiKit.PANEL, ZIndex = 21, Parent = openFrame,
})
UiKit.fit(openCard, 0.4, 0.62)
UiKit.surface(UiKit.corner(openCard, 14))

local openTitle = UiKit.label(openCard, {
	Size = UDim2.new(1, -20, 0.09, 0), Position = UDim2.new(0, 10, 0.04, 0),
	max = UiKit.TEXT.heading, TextScaled = true, Font = Enum.Font.GothamBold,
	ZIndex = 22, Text = "",
})

-- the swatch doubles as the spinner and as the prize, so the landing is the same object
-- coming to rest rather than one thing being swapped for another
local openSwatch = UiKit.make("Frame", {
	Size = UDim2.new(0.74, 0, 0.36, 0), Position = UDim2.new(0.5, 0, 0.16, 0),
	AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = UiKit.WHITE,
	ZIndex = 22, Parent = openCard,
})
UiKit.corner(openSwatch, 10)
local openGradient = UiKit.make("UIGradient", { Rotation = 90, Parent = openSwatch })
local openStroke = UiKit.make("UIStroke", { Thickness = 2, Transparency = 0.15, Parent = openSwatch })

local openRarity = UiKit.label(openCard, {
	Size = UDim2.new(1, -20, 0.07, 0), Position = UDim2.new(0, 10, 0.55, 0),
	max = UiKit.TEXT.body, TextScaled = true, Font = Enum.Font.GothamBold, ZIndex = 22, Text = "",
})
local openName = UiKit.label(openCard, {
	Size = UDim2.new(1, -20, 0.1, 0), Position = UDim2.new(0, 10, 0.63, 0),
	max = UiKit.TEXT.title, TextScaled = true, Font = Enum.Font.GothamBlack, ZIndex = 22, Text = "",
})

local openEquip = UiKit.button(openCard, "Equip", UiKit.ACCENT,
	UDim2.new(0.44, 0, 0.11, 0), UDim2.new(0.03, 0, 0.76, 0))
local openClose = UiKit.button(openCard, "Close", UiKit.GRAY,
	UDim2.new(0.44, 0, 0.11, 0), UDim2.new(0.53, 0, 0.76, 0))
openEquip.ZIndex, openClose.ZIndex = 22, 22

local spinGeneration = 0

local function closeOpen()
	spinGeneration += 1 -- any spin still running belongs to a dead reveal
	openFrame.Visible = false
end
openClose.Activated:Connect(closeOpen)

-- Only banners exist as art today; if a crate ever rolls a kind this client cannot draw,
-- `Cosmetics.banner` falls back rather than erroring.
local function bannerIds()
	local out = {}
	for _, entry in ipairs(cosmeticsFolder:GetChildren()) do
		if entry:GetAttribute("Kind") == "Banner" then
			table.insert(out, entry.Name)
		end
	end
	return out
end

local function paintSwatch(id)
	local skin = Cosmetics.banner(id)
	openGradient.Color = ColorSequence.new(skin.from, skin.to)
	openStroke.Color = skin.edge
end

local shopBusy = false
local buildShop

local function runOpen(crateId, currency, crateName)
	if shopBusy then
		return
	end
	shopBusy = true
	shopHint.Text = ""

	spinGeneration += 1
	local gen = spinGeneration

	openTitle.Text = "Opening " .. crateName
	openRarity.Text = ""
	openName.Text = ""
	openEquip.Visible = false
	openClose.Visible = false
	openFrame.Visible = true

	local answered, status, prize = false, nil, nil
	task.spawn(function()
		local ok, a, b = pcall(function()
			return shopRequest:InvokeServer("open", crateId, currency)
		end)
		status = ok and a or "failed"
		prize = ok and b or nil
		answered = true
	end)

	task.spawn(function()
		local ids = bannerIds()
		local elapsed, step = 0, 0.05
		while gen == spinGeneration and (elapsed < SPIN_MIN or not answered) do
			if #ids > 0 then
				paintSwatch(ids[math.random(#ids)])
			end
			task.wait(step)
			elapsed += step
			-- slow down as it approaches the landing, so it settles rather than stops dead
			if elapsed > SPIN_MIN * 0.55 then
				step = math.min(0.2, step * 1.14)
			end
		end

		shopBusy = false
		if gen ~= spinGeneration then
			return -- the player closed it, or started another open
		end

		if status ~= "ok" or not prize then
			local reason = ({
				poor = "You can't afford that yet",
				empty = "You already own everything in this crate",
				currency = "That crate can't be bought that way",
				unknown = "That crate isn't available",
			})[status] or "Something went wrong - nothing was charged"
			openTitle.Text = "No luck"
			openRarity.Text = ""
			openName.Text = reason
			openName.TextColor3 = UiKit.DIM
			openClose.Visible = true
			buildShop()
			return
		end

		local entry = cosmeticsFolder:FindFirstChild(prize)
		local rarity = entry and entry:GetAttribute("Rarity") or "Common"
		paintSwatch(prize)
		openTitle.Text = "You unboxed"
		openRarity.Text = rarity:upper()
		openRarity.TextColor3 = Cosmetics.rarity(rarity)
		openName.Text = entry and entry.Value or prize
		openName.TextColor3 = UiKit.WHITE
		openEquip.Visible = entry ~= nil
		openClose.Visible = true

		openEquip.Activated:Once(function()
			remotes.LobbyAction:FireServer("equip", prize)
			closeOpen()
		end)

		buildShop() -- the balance just changed
	end)
end

---------------------------------------------------------------- crate cards

local shopCards = {}

local function crateCard(entry, order)
	local gold = entry:GetAttribute("Gold") or 0
	local gems = entry:GetAttribute("Gems") or 0

	local card = UiKit.make("Frame", {
		Size = UDim2.new(1, -8, 0, 124), BackgroundColor3 = UiKit.FIELD,
		LayoutOrder = order, Parent = shopList,
	})
	UiKit.corner(card, 10)
	UiKit.make("UIStroke", { Color = UiKit.EDGE, Thickness = 1, Transparency = 0.5, Parent = card })

	UiKit.label(card, {
		Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 8),
		max = UiKit.TEXT.heading, TextScaled = true, Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left, Text = entry.Value,
	})

	-- The odds row, in its own container so the quarter-width chips divide the padded
	-- width rather than the card's - laying them out against the card directly overflows
	-- it by the padding. Rarity is carried by the text colour on a plain chip, not a
	-- coloured fill: at this size coloured text on dark reads and dark text on colour
	-- does not. Name above percentage rather than beside it, because these have to stay
	-- legible on a phone and "Legendary" abbreviated to fit is a worse disclosure.
	local oddsRow = UiKit.make("Frame", {
		Size = UDim2.new(1, -20, 0, 28), Position = UDim2.fromOffset(10, 38),
		BackgroundTransparency = 1, Parent = card,
	})
	for i, rarity in ipairs({ "Common", "Rare", "Epic", "Legendary" }) do
		local pct = entry:GetAttribute("Odds" .. rarity) or 0
		local chip = UiKit.make("Frame", {
			Size = UDim2.new(0.25, -5, 1, 0), Position = UDim2.new(0.25 * (i - 1), 3, 0, 0),
			BackgroundColor3 = UiKit.PANEL, BackgroundTransparency = pct > 0 and 0 or 0.65,
			Parent = oddsRow,
		})
		UiKit.corner(chip, 6)
		local tint = pct > 0 and Cosmetics.rarity(rarity) or UiKit.DIM
		UiKit.label(chip, {
			Size = UDim2.new(1, -6, 0, 13), Position = UDim2.fromOffset(3, 2),
			max = UiKit.TEXT.small, TextScaled = true, Font = Enum.Font.GothamBold,
			TextColor3 = tint, Text = rarity,
		})
		UiKit.label(chip, {
			Size = UDim2.new(1, -6, 0, 11), Position = UDim2.fromOffset(3, 15),
			max = UiKit.TEXT.small, TextScaled = true, Font = Enum.Font.GothamMedium,
			TextColor3 = tint, Text = ("%d%%"):format(pct),
		})
	end

	local function priceButton(label, colour, size, pos, currency, amount)
		local b = UiKit.button(card, label, colour, size, pos, UiKit.TEXT.body)
		local afford = (player:GetAttribute(currency == "gold" and "Gold" or "Gems") or 0) >= amount
		if not afford then
			b.BackgroundColor3 = UiKit.GRAY
			b.TextTransparency = 0.35
		end
		b.Activated:Connect(function()
			if not afford then
				shopHint.Text = ("You need %d %s"):format(amount, currency)
				return
			end
			runOpen(entry.Name, currency, entry.Value)
		end)
		return b
	end

	local both = gold > 0 and gems > 0
	local halfSize = UDim2.new(0.48, -13, 0, 40)
	local fullSize = UDim2.new(1, -20, 0, 40)
	if gold > 0 then
		priceButton(("%d gold"):format(gold), UiKit.YELLOW:Lerp(UiKit.GRAY, 0.4),
			both and halfSize or fullSize, UDim2.fromOffset(10, 74), "gold", gold)
	end
	if gems > 0 then
		priceButton(("%d gems"):format(gems), UiKit.BLUE,
			both and halfSize or fullSize,
			both and UDim2.new(0.52, 3, 0, 74) or UDim2.fromOffset(10, 74), "gems", gems)
	end

	return card
end

buildShop = function()
	shopWallet.Text = currencyText()

	for _, c in ipairs(shopCards) do
		c:Destroy()
	end
	table.clear(shopCards)

	local entries = cratesFolder:GetChildren()
	table.sort(entries, function(a, b)
		return (a:GetAttribute("Order") or 99) < (b:GetAttribute("Order") or 99)
	end)
	for i, entry in ipairs(entries) do
		table.insert(shopCards, crateCard(entry, i))
	end
end

for _, attr in ipairs({ "Gold", "Gems", "OwnedCosmetics" }) do
	player:GetAttributeChangedSignal(attr):Connect(function()
		if nav == "shop" then
			buildShop()
		end
	end)
end

local shopBack = UiKit.button(shopFrame, "Back", UiKit.GRAY,
	UDim2.new(1, -20, 0.13, 0), UDim2.new(0, 10, 0.82, 0))
shopBack.Activated:Connect(function()
	shopHint.Text = ""
	goTo("menu")
end)

---------------------------------------------------------------- main menu

local menuFrame = UiKit.panel(gui)

UiKit.label(menuFrame, {
	Size = UDim2.new(1, -20, 0.2, 0), Position = UDim2.new(0, 10, 0.06, 0),
	max = UiKit.TEXT.display, TextScaled = true, Font = Enum.Font.GothamBlack, Text = "NICHE",
})
UiKit.label(menuFrame, {
	Size = UDim2.new(1, -20, 0.07, 0), Position = UDim2.new(0, 10, 0.28, 0),
	TextScaled = true, TextColor3 = UiKit.DIM, Text = "Party games, one lobby",
})

local menuWallet = UiKit.label(menuFrame, {
	Size = UDim2.new(1, -20, 0.05, 0), Position = UDim2.new(0, 10, 0.345, 0),
	max = UiKit.TEXT.body, TextScaled = true, Font = Enum.Font.GothamBold,
	TextColor3 = UiKit.YELLOW, Text = "",
})

local playButton = UiKit.button(menuFrame, "Play", UiKit.ACCENT,
	UDim2.new(1, -40, 0.15, 0), UDim2.new(0, 20, 0.40, 0))
local lockerButton = UiKit.button(menuFrame, "Locker", UiKit.BLUE,
	UDim2.new(1, -40, 0.12, 0), UDim2.new(0, 20, 0.57, 0))
local storeButton = UiKit.button(menuFrame, "Store", UiKit.GRAY,
	UDim2.new(1, -40, 0.12, 0), UDim2.new(0, 20, 0.71, 0))

local menuHint = UiKit.label(menuFrame, {
	Size = UDim2.new(1, -20, 0.06, 0), Position = UDim2.new(0, 10, 0.85, 0),
	TextScaled = true, Font = Enum.Font.GothamMedium, TextColor3 = UiKit.YELLOW, Text = "",
})

playButton.Activated:Connect(function()
	menuHint.Text = ""
	goTo("modes")
end)
lockerButton.Activated:Connect(function()
	menuHint.Text = ""
	goTo("locker")
end)
storeButton.Activated:Connect(function()
	menuHint.Text = ""
	goTo("shop")
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

-- Modes that declare the same `group` collapse into one grid button which opens a
-- submenu of its variants. A mode with no group gets its own button as before.
local function modeEntries()
	local entries = {}
	local byGroup = {}
	local taken = {}

	for _, id in ipairs(playableModes()) do
		local group = modes[id].group
		if group then
			if not byGroup[group] then
				byGroup[group] = { kind = "group", label = group, members = {} }
				table.insert(entries, byGroup[group])
				taken[group] = true
			end
			table.insert(byGroup[group].members, id)
		else
			table.insert(entries, { kind = "mode", id = id, label = modes[id].name or id })
			taken[modes[id].name or id] = true
			taken[id] = true
		end
	end

	table.sort(entries, function(a, b)
		local ia = table.find(ORDER, a.id or a.label) or #ORDER + 1
		local ib = table.find(ORDER, b.id or b.label) or #ORDER + 1
		if ia ~= ib then
			return ia < ib
		end
		return a.label < b.label
	end)

	-- placeholders always trail the real games
	-- a planned name drops off once something real claims it, group or single mode
	for _, name in ipairs(PLANNED) do
		if not taken[name] then
			table.insert(entries, { kind = "soon", label = name })
		end
	end
	return entries
end

---------------------------------------------------------------- variant submenu

local groupFrame = UiKit.panel(gui)

local groupTitle = UiKit.label(groupFrame, {
	Size = UDim2.new(1, -20, 0.11, 0), Position = UDim2.new(0, 10, 0.03, 0),
	TextScaled = true, Font = Enum.Font.GothamBold, Text = "",
})
-- ends at 0.20, clear of the button grid that starts at 0.22
local groupBlurb = UiKit.label(groupFrame, {
	Size = UDim2.new(1, -20, 0.055, 0), Position = UDim2.new(0, 10, 0.145, 0),
	TextScaled = true, TextColor3 = UiKit.DIM, Text = "Pick a format",
})

local groupButtons = {}

local function openGroup(entry)
	for _, old in ipairs(groupButtons) do
		old:Destroy()
	end
	table.clear(groupButtons)

	groupTitle.Text = entry.label

	for i, id in ipairs(entry.members) do
		if not GRID[i] then break end
		local mode = modes[id]
		local b = UiKit.button(groupFrame, mode.variant or mode.name or id, UiKit.BLUE,
			UDim2.new(0.5, -15, 0.2, 0), GRID[i])
		b.Activated:Connect(function()
			-- the server ignores this unless we're the host, which is the intended gate
			remotes.LobbyAction:FireServer("setMode", id)
			goTo("lobby")
		end)
		table.insert(groupButtons, b)
	end

	goTo("group")
end

local groupBackButton = UiKit.button(groupFrame, "Back", UiKit.GRAY,
	UDim2.new(1, -20, 0.13, 0), UDim2.new(0, 10, 0.82, 0))
groupBackButton.Activated:Connect(function()
	goTo("modes")
end)

---------------------------------------------------------------- the grid itself

local modeButtons = {}

local function rebuildModeGrid()
	for _, old in ipairs(modeButtons) do
		old:Destroy()
	end
	table.clear(modeButtons)

	for i, entry in ipairs(modeEntries()) do
		if not GRID[i] then break end

		local playable = entry.kind ~= "soon"
		local b = UiKit.button(modesFrame, entry.label,
			playable and UiKit.BLUE or Color3.fromRGB(38, 38, 50),
			UDim2.new(0.5, -15, 0.2, 0), GRID[i])
		b.AutoButtonColor = playable
		if not playable then
			b.TextColor3 = Color3.fromRGB(120, 120, 140)
		end

		b.Activated:Connect(function()
			modesHint.Text = ""
			if entry.kind == "soon" then
				modesHint.Text = ("%s isn't built yet"):format(entry.label)
			elseif entry.kind == "group" then
				openGroup(entry)
			else
				remotes.LobbyAction:FireServer("setMode", entry.id)
				goTo("lobby")
			end
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
	max = UiKit.TEXT.display, TextScaled = true, Font = Enum.Font.GothamBlack, Text = "NICHE",
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
	max = UiKit.TEXT.display, TextScaled = true, Font = Enum.Font.GothamBlack, Text = "Match over!",
})

local standingsLabel = UiKit.label(podiumFrame, {
	Size = UDim2.new(1, -40, 0.52, 0), Position = UDim2.new(0, 20, 0.18, 0),
	TextSize = 22, RichText = true, TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = "",
})

-- whatever the mode wanted to say that per-player standings couldn't
local summaryLabel = UiKit.label(podiumFrame, {
	Size = UDim2.new(1, -20, 0.08, 0), Position = UDim2.new(0, 10, 0.72, 0),
	TextScaled = true, Font = Enum.Font.GothamBold, TextColor3 = UiKit.YELLOW, Text = "",
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

remotes.MatchOver.OnClientEvent:Connect(function(standings, summary)
	local medals = { "🥇", "🥈", "🥉" }
	local lines = {}

	-- Rank comes from the score, not the row number, so equal scores share a place and a
	-- medal and the next distinct score skips past them: 1, 1, 3 rather than 1, 2, 3.
	-- Ranking by row would hand one of two tied players gold for no reason.
	local rank = 0
	for i, s in ipairs(standings) do
		if i == 1 or s.score ~= standings[i - 1].score then
			rank = i
		end
		table.insert(lines, ("%s %d. %s  <b>%d pts</b>"):format(
			medals[rank] or "  ", rank, UiKit.escape(s.name), s.score))
	end

	local mode = activeMode()
	local earned = player:GetAttribute("LastEarned") or 0
	local tail = {}
	if summary then
		table.insert(tail, summary)
	end
	if earned > 0 then
		table.insert(tail, ("+%d gold"):format(earned))
	end

	if mode and mode.hideStandings then
		-- no meaningful individual ranking in this mode, so the summary is the result
		standingsLabel.Text = summary or ""
		summaryLabel.Text = earned > 0 and ("+%d gold"):format(earned) or ""
	else
		standingsLabel.Text = table.concat(lines, "\n")
		summaryLabel.Text = table.concat(tail, "   ")
	end
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

	local cap = maxPlayersFor(ReplicatedStorage:GetAttribute("ActiveMode"))

	if state == "Lobby" then
		if total < needed then
			statusLabel.Text = ("%s needs %d players, %d here"):format(
				mode and mode.name or "This game", needed, total)
		elseif cap and total > cap then
			statusLabel.Text = ("%s takes at most %d players, %d here"):format(
				mode and mode.name or "This game", cap, total)
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

local lastScreen = nil

local function render()
	local state = ReplicatedStorage:GetAttribute("GameState") or "Lobby"
	local inMatch = player:GetAttribute("InMatch")
	local mode = activeMode()

	-- a match we are in always beats wherever we had browsed to
	local screen
	if inMatch and state == "Intro" then
		screen = "intro"
	elseif inMatch and state == "Recap" then
		screen = "recap"
	elseif inMatch and state == "InMatch" then
		screen = "game"
	elseif inMatch and state == "Podium" then
		screen = "podium"
	else
		screen = nav
	end

	introFrame.Visible = screen == "intro"
	recapFrame.Visible = screen == "recap"
	lockerFrame.Visible = screen == "locker"
	shopFrame.Visible = screen == "shop"
	menuFrame.Visible = screen == "menu"
	modesFrame.Visible = screen == "modes"
	groupFrame.Visible = screen == "group"
	lobbyFrame.Visible = screen == "lobby"
	podiumFrame.Visible = screen == "podium"
	scoreStrip.Visible = screen == "game"

	if openFrame.Visible and screen ~= "shop" then
		closeOpen()
	end

	local waiting = ReplicatedStorage:GetAttribute("Waiting")
	waitingLabel.Visible = screen == "game" and waiting ~= nil and waiting ~= ""
	waitingLabel.Text = waiting or ""

	-- only the active mode's screen is ever visible
	for _, m in pairs(modes) do
		if m.frame then
			m.frame.Visible = (screen == "game" and m == mode)
		end
	end

	-- rebuild the roster once on arrival, not every 0.2s tick
	if screen ~= lastScreen then
		lastScreen = screen
		if screen == "intro" then
			buildIntro()
		elseif screen == "recap" then
			buildRecap()
		elseif screen == "locker" then
			buildLocker()
		elseif screen == "shop" then
			buildShop()
		end
	end

	if screen == "lobby" then
		renderLobby(state)
	elseif screen == "game" then
		renderScore()
	elseif screen == "menu" then
		menuWallet.Text = currencyText()
	elseif screen == "shop" then
		shopWallet.Text = currencyText()
	end
end

while true do
	render()
	task.wait(0.2)
end
