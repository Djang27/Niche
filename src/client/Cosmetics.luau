-- ModuleScript: StarterPlayerScripts > Cosmetics
--
-- How each cosmetic looks. The server catalogue in Shared/Cosmetics decides what a player
-- is allowed to wear and replicates only an id; this file turns that id into pixels. Same
-- split the modes already use, and it means a client cannot grant itself anything by
-- editing visuals.
--
-- Ids must match the server catalogue exactly.

local Cosmetics = {}

Cosmetics.Banners = {
	slate = {
		from = Color3.fromRGB(58, 58, 78), to = Color3.fromRGB(34, 34, 48),
		edge = Color3.fromRGB(120, 120, 155),
	},
	storm = {
		from = Color3.fromRGB(96, 100, 128), to = Color3.fromRGB(44, 46, 68),
		edge = Color3.fromRGB(150, 155, 190),
	},
	deep = {
		from = Color3.fromRGB(78, 118, 255), to = Color3.fromRGB(92, 50, 188),
		edge = Color3.fromRGB(140, 160, 255),
	},
	ocean = {
		from = Color3.fromRGB(58, 190, 210), to = Color3.fromRGB(24, 78, 140),
		edge = Color3.fromRGB(130, 220, 235),
	},
	forest = {
		from = Color3.fromRGB(64, 176, 112), to = Color3.fromRGB(26, 88, 70),
		edge = Color3.fromRGB(120, 210, 158),
	},
	mint = {
		from = Color3.fromRGB(150, 230, 180), to = Color3.fromRGB(58, 150, 130),
		edge = Color3.fromRGB(190, 245, 215),
	},
	sunrise = {
		from = Color3.fromRGB(255, 146, 78), to = Color3.fromRGB(194, 58, 112),
		edge = Color3.fromRGB(255, 176, 120),
	},
	ember = {
		from = Color3.fromRGB(255, 108, 60), to = Color3.fromRGB(134, 26, 30),
		edge = Color3.fromRGB(255, 150, 110),
	},
	rose = {
		from = Color3.fromRGB(255, 138, 176), to = Color3.fromRGB(168, 48, 110),
		edge = Color3.fromRGB(255, 180, 205),
	},
	aurora = {
		from = Color3.fromRGB(122, 232, 212), to = Color3.fromRGB(112, 92, 240),
		edge = Color3.fromRGB(180, 250, 235),
	},
	gold = {
		from = Color3.fromRGB(255, 214, 110), to = Color3.fromRGB(170, 116, 20),
		edge = Color3.fromRGB(255, 236, 170),
	},
	void = {
		from = Color3.fromRGB(70, 40, 120), to = Color3.fromRGB(12, 10, 24),
		edge = Color3.fromRGB(150, 110, 230),
	},
}

-- unknown or missing id falls back rather than erroring: a player wearing something this
-- client has not heard of should still render
function Cosmetics.banner(id)
	return Cosmetics.Banners[id] or Cosmetics.Banners.slate
end

return Cosmetics
