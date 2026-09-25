-- ModuleScript: ServerScriptService > Shared > Categories
-- Broad subject areas the Wavelength clue giver picks from.
--
-- Three are offered at random each round and the clue giver takes one, so their clue has
-- to come from it. That is the whole point: without a category the clue giver is clueing
-- about everything that exists, which is far too wide for the guesser to place.
--
-- Keep these BROAD. A category so narrow that only a handful of clues fit makes the round
-- worse, not harder. "Food" is right; "Breakfast cereals" is not.

local Categories = {}

Categories.All = {
	"Food",
	"Drinks",
	"Animals",
	"Sports",
	"Movies",
	"TV shows",
	"Music",
	"Countries",
	"Cities",
	"Jobs",
	"Vehicles",
	"Clothing",
	"Technology",
	"Video games",
	"School subjects",
	"Household objects",
	"Nature",
	"Holidays",
	"Hobbies",
	"Buildings",
	"Toys",
	"Weather",
}

-- n distinct categories, freshly shuffled. No recent-memory here on purpose: categories
-- are broad enough that repeats across rounds play fine, unlike the dials.
function Categories.pick(n)
	local pool = table.clone(Categories.All)
	local picked = {}
	for _ = 1, math.min(n, #pool) do
		table.insert(picked, table.remove(pool, math.random(#pool)))
	end
	return picked
end

return Categories
