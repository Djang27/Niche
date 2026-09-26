-- ModuleScript: ServerScriptService > Shared > Spectrums
-- Content for the Wavelength modes: the two ends of a dial.
--
-- Server only, like the Niche answer lists. The two labels do get sent to clients each
-- round (players have to see what they are judging), but the target position never does
-- except to the one player giving the clue.
--
-- `onlyWith` is the fix for mismatched rounds. Most dials sort anything, so they leave it
-- off and any category may be offered. A dial that only makes sense for certain subjects
-- lists them, and then only those are offered - otherwise "Salty <-> Sweet" turns up
-- beside Vehicles and Buildings and the clue giver has no usable option at all.
--
-- Adding a dial: keep both ends short enough to read on a dial end, and genuinely
-- opposed, or there is no middle worth arguing about. Add `onlyWith` only if the dial
-- really cannot sort most subjects, and give it at least 3 entries so a full set of
-- choices can still be offered.

local Categories = require(script.Parent.Categories)

local Spectrums = {}

Spectrums.All = {
	-- sorts anything
	{ left = "Cold", right = "Hot" },
	{ left = "Bad", right = "Good" },
	{ left = "Cheap", right = "Expensive" },
	{ left = "Quiet", right = "Loud" },
	{ left = "Small", right = "Big" },
	{ left = "Ugly", right = "Beautiful" },
	{ left = "Boring", right = "Exciting" },
	{ left = "Useless", right = "Useful" },
	{ left = "Old", right = "New" },
	{ left = "Slow", right = "Fast" },
	{ left = "Weak", right = "Strong" },
	{ left = "Sad", right = "Happy" },
	{ left = "Easy", right = "Hard" },
	{ left = "Common", right = "Rare" },
	{ left = "Dirty", right = "Clean" },
	{ left = "Dark", right = "Bright" },
	{ left = "Simple", right = "Complicated" },
	{ left = "Underrated", right = "Overrated" },
	{ left = "Temporary", right = "Permanent" },
	{ left = "Forgettable", right = "Memorable" },
	{ left = "Cursed", right = "Blessed" },
	{ left = "Childish", right = "Mature" },
	{ left = "Scary", right = "Comforting" },
	{ left = "Fake", right = "Authentic" },
	{ left = "Ordinary", right = "Weird" },
	{ left = "Overpriced", right = "Worth it" },
	{ left = "Forgotten", right = "Iconic" },

	-- needs a physical thing to sort
	{ left = "Soft", right = "Hard",
		onlyWith = { "Food", "Snacks", "Animals", "Household objects", "Clothing", "Toys" } },
	{ left = "Light", right = "Heavy",
		onlyWith = { "Animals", "Vehicles", "Household objects", "Technology", "Toys", "Musical instruments" } },
	{ left = "Round", right = "Pointy",
		onlyWith = { "Food", "Household objects", "Toys", "Technology", "Vehicles", "Musical instruments" } },
	{ left = "Smooth", right = "Rough",
		onlyWith = { "Food", "Animals", "Household objects", "Clothing", "Music" } },

	-- needs something you consume
	{ left = "Salty", right = "Sweet",
		onlyWith = { "Food", "Snacks", "Drinks" } },
	{ left = "Wet", right = "Dry",
		onlyWith = { "Food", "Snacks", "Drinks", "Animals", "Sports" } },
	{ left = "Unhealthy", right = "Healthy",
		onlyWith = { "Food", "Snacks", "Drinks", "Hobbies", "Sports" } },
	{ left = "Natural", right = "Artificial",
		onlyWith = { "Food", "Snacks", "Drinks", "Animals", "Clothing", "Technology" } },

	-- needs a person or character
	{ left = "Introvert", right = "Extrovert",
		onlyWith = { "Famous people", "Fictional characters", "Animals", "Jobs" } },
	{ left = "Villain", right = "Hero",
		onlyWith = { "Movies", "TV shows", "Video games", "Fictional characters", "Famous people" } },
	{ left = "Impulsive", right = "Overthought",
		onlyWith = { "Famous people", "Fictional characters", "Jobs", "Hobbies", "Board games" } },

	-- needs a place
	{ left = "Rural", right = "Urban",
		onlyWith = { "Countries", "Cities", "Jobs", "Animals", "Vehicles" } },

	-- needs something with taste or reputation attached
	{ left = "Casual", right = "Formal",
		onlyWith = { "Clothing", "Jobs", "Food", "Music", "Hobbies", "Movies" } },
	{ left = "Messy", right = "Organised",
		onlyWith = { "Jobs", "Hobbies", "Household objects", "Food" } },
	{ left = "Lowbrow", right = "Highbrow",
		onlyWith = { "Movies", "TV shows", "Music", "Food", "Hobbies", "Board games" } },
	{ left = "Flop", right = "Masterpiece",
		onlyWith = { "Movies", "TV shows", "Music", "Video games", "Board games" } },
	{ left = "Guilty pleasure", right = "Openly loved",
		onlyWith = { "Food", "Snacks", "Movies", "TV shows", "Music", "Video games", "Hobbies" } },
	{ left = "Night in", right = "Night out",
		onlyWith = { "Hobbies", "Movies", "Music", "Food", "Drinks", "Video games", "Board games" } },
}

---------------------------------------------------------------- data check

-- A typo in an onlyWith list would silently narrow a dial, or empty it, so catch it at
-- startup the way the answer lists catch bad tiers.
do
	local known = {}
	for _, name in ipairs(Categories.All) do
		known[name] = true
	end
	for _, s in ipairs(Spectrums.All) do
		if s.onlyWith then
			for _, name in ipairs(s.onlyWith) do
				if not known[name] then
					warn(("[Spectrums] '%s <-> %s' lists unknown category '%s'")
						:format(s.left, s.right, name))
				end
			end
			if #s.onlyWith < 3 then
				warn(("[Spectrums] '%s <-> %s' allows only %d categories, fewer than the 3 offered")
					:format(s.left, s.right, #s.onlyWith))
			end
		end
	end
end

---------------------------------------------------------------- picking

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
