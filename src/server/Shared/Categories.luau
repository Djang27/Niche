-- ModuleScript: ServerScriptService > Shared > Categories
-- Broad subject areas the Wavelength clue giver picks from.
--
-- Three are offered each round and the clue giver takes one, so their clue has to come
-- from it. That is the whole point: without a category the clue giver is clueing about
-- everything that exists, which is far too wide for the guesser to place.
--
-- Two rules for anything added here:
--   1. BROAD. A category so narrow that only a handful of clues fit makes the round
--      worse, not harder. "Food" is right; "Breakfast cereals" is not.
--   2. PLACEABLE ON ALMOST ANY DIAL. Weather, Holidays and School subjects were removed
--      for failing this - they have too few members to sort by cheap/expensive, scary/
--      comforting and most other dials. If a subject only works on a couple of dials,
--      it belongs in a dial's `onlyWith` list in Spectrums, not in this pool.

local Categories = {}

Categories.All = {
	"Food",
	"Snacks",
	"Drinks",
	"Animals",
	"Sports",
	"Movies",
	"TV shows",
	"Music",
	"Musical instruments",
	"Famous people",
	"Fictional characters",
	"Countries",
	"Cities",
	"Jobs",
	"Vehicles",
	"Clothing",
	"Technology",
	"Apps and websites",
	"Video games",
	"Board games",
	"Household objects",
	"Hobbies",
	"Toys",
}

local function shuffledTake(pool, n)
	local picked = {}
	for _ = 1, math.min(n, #pool) do
		table.insert(picked, table.remove(pool, math.random(#pool)))
	end
	return picked
end

-- n distinct categories that actually fit this dial.
--
-- A dial with an `onlyWith` list draws from that list instead of the whole pool. That is
-- what stops "Salty <-> Sweet" from being offered alongside Vehicles and Buildings, where
-- the clue giver has no usable option at all.
function Categories.pickFor(spectrum, n)
	local pool = (spectrum and spectrum.onlyWith)
		and table.clone(spectrum.onlyWith)
		or table.clone(Categories.All)
	return shuffledTake(pool, n)
end

-- whole-pool pick, for anything that has no dial in hand
function Categories.pick(n)
	return shuffledTake(table.clone(Categories.All), n)
end

return Categories
