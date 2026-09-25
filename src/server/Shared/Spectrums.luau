-- ModuleScript: ServerScriptService > Shared > Spectrums
-- Content for the Wavelength modes: the two ends of a dial.
--
-- Server only, like the Niche answer lists. The two labels do get sent to clients each
-- round (players have to see what they are judging), but the target position never does
-- except to the one player giving the clue.
--
-- Adding a spectrum = adding a line. Keep both ends short enough to read on a dial end,
-- and genuinely opposed, or the dial has no middle worth arguing about.

local Spectrums = {}

Spectrums.All = {
	{ left = "Cold", right = "Hot" },
	{ left = "Bad", right = "Good" },
	{ left = "Cheap", right = "Expensive" },
	{ left = "Quiet", right = "Loud" },
	{ left = "Small", right = "Big" },
	{ left = "Ugly", right = "Beautiful" },
	{ left = "Boring", right = "Exciting" },
	{ left = "Useless", right = "Useful" },
	{ left = "Unhealthy", right = "Healthy" },
	{ left = "Old", right = "New" },
	{ left = "Slow", right = "Fast" },
	{ left = "Weak", right = "Strong" },
	{ left = "Sad", right = "Happy" },
	{ left = "Easy", right = "Hard" },
	{ left = "Common", right = "Rare" },
	{ left = "Dirty", right = "Clean" },
	{ left = "Soft", right = "Hard" },
	{ left = "Light", right = "Heavy" },
	{ left = "Dark", right = "Bright" },
	{ left = "Simple", right = "Complicated" },
	{ left = "Underrated", right = "Overrated" },
	{ left = "Temporary", right = "Permanent" },
	{ left = "Round", right = "Pointy" },
	{ left = "Casual", right = "Formal" },
	{ left = "Introvert", right = "Extrovert" },
	{ left = "Villain", right = "Hero" },
	{ left = "Forgettable", right = "Memorable" },
	{ left = "Cursed", right = "Blessed" },
	{ left = "Childish", right = "Mature" },
	{ left = "Messy", right = "Organised" },
	{ left = "Scary", right = "Comforting" },
	{ left = "Fake", right = "Authentic" },
	{ left = "Wet", right = "Dry" },
	{ left = "Smooth", right = "Rough" },
	{ left = "Ordinary", right = "Weird" },
	{ left = "Lowbrow", right = "Highbrow" },
	{ left = "Rural", right = "Urban" },
	{ left = "Natural", right = "Artificial" },
	{ left = "Salty", right = "Sweet" },
	{ left = "Flop", right = "Masterpiece" },
	{ left = "Impulsive", right = "Overthought" },
	{ left = "Guilty pleasure", right = "Openly loved" },
	{ left = "Night in", right = "Night out" },
	{ left = "Overpriced", right = "Worth it" },
	{ left = "Forgotten", right = "Iconic" },
}

local RECENT_LIMIT = 15 -- a spectrum won't come back until this many others have played
local recent = {}

-- n spectrums for a match, avoiding anything played recently on this server
function Spectrums.pick(n)
	local pool = {}
	for _, s in ipairs(Spectrums.All) do
		if not table.find(recent, s) then
			table.insert(pool, s)
		end
	end
	if #pool < n then
		table.clear(recent)
		pool = table.clone(Spectrums.All)
	end

	local picked = {}
	for _ = 1, math.min(n, #pool) do
		local s = table.remove(pool, math.random(#pool))
		table.insert(picked, s)
		table.insert(recent, s)
		if #recent > RECENT_LIMIT then
			table.remove(recent, 1)
		end
	end
	return picked
end

return Spectrums
