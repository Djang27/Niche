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
	sunrise = {
		from = Color3.fromRGB(255, 146, 78), to = Color3.fromRGB(194, 58, 112),
		edge = Color3.fromRGB(255, 176, 120),
	},
	deep = {
		from = Color3.fromRGB(78, 118, 255), to = Color3.fromRGB(92, 50, 188),
		edge = Color3.fromRGB(140, 160, 255),
	},
	forest = {
		from = Color3.fromRGB(64, 176, 112), to = Color3.fromRGB(26, 88, 70),
		edge = Color3.fromRGB(120, 210, 158),
	},
	aurora = {
		from = Color3.fromRGB(122, 232, 212), to = Color3.fromRGB(112, 92, 240),
		edge = Color3.fromRGB(180, 250, 235),
	},
}

-- unknown or missing id falls back rather than erroring: a player wearing something this
-- client has not heard of should still render
function Cosmetics.banner(id)
	return Cosmetics.Banners[id] or Cosmetics.Banners.slate
end

return Cosmetics
