-- ModuleScript: ServerScriptService > Shared > Crates
--
-- Crates roll a rarity by published odds, then a random unowned item of that rarity.
--
-- **Odds are disclosed in game.** Gems are bought with Robux and can open crates, so real
-- money reaches a random roll - that makes these paid random items, and the odds must be
-- visible before a purchase. `ReplicatedStorage.Crates` carries them for exactly that.
--
-- No duplicates: a crate only ever rolls something you do not own, and refuses the sale
-- once you own everything in it. That avoids the duplicate-compensation question entirely
-- and keeps the published rarity odds literally true for every roll that happens.

local Cosmetics = require(script.Parent.Cosmetics)
local Profile = require(script.Parent.Profile)

local Crates = {}

-- `gold` and `gems` are prices; 0 means that currency cannot buy this crate.
-- `odds` are percentages by rarity and must total 100.
Crates.All = {
	standard = {
		name = "Standard Crate", order = 1,
		gold = 150, gems = 15,
		kinds = { "Banner" },
		odds = { Common = 65, Rare = 25, Epic = 8, Legendary = 2 },
	},
	prime = {
		name = "Prime Crate", order = 2,
		gold = 400, gems = 35,
		kinds = { "Banner" },
		odds = { Common = 25, Rare = 45, Epic = 24, Legendary = 6 },
	},
	vault = {
		name = "Vault Crate", order = 3,
		gold = 900, gems = 75,
		kinds = { "Banner" },
		odds = { Common = 0, Rare = 30, Epic = 50, Legendary = 20 },
	},
}

-- catch a mistyped table at startup rather than shipping wrong odds
for id, crate in pairs(Crates.All) do
	local total = 0
	for _, pct in pairs(crate.odds) do
		total += pct
	end
	if total ~= 100 then
		warn(("[Crates] '%s' odds total %d, not 100"):format(id, total))
	end
end

---------------------------------------------------------------- rolling

local function kindAllowed(crate, kind)
	for _, k in ipairs(crate.kinds) do
		if k == kind then
			return true
		end
	end
	return false
end

-- Everything this crate could give that the player does not already own, grouped by rarity.
local function poolFor(player, crate)
	local byRarity, total = {}, 0
	for id, item in pairs(Cosmetics.Items) do
		if kindAllowed(crate, item.kind) and not Cosmetics.trulyOwnedBy(player, id) then
			byRarity[item.rarity] = byRarity[item.rarity] or {}
			table.insert(byRarity[item.rarity], id)
			total += 1
		end
	end
	for _, list in pairs(byRarity) do
		table.sort(list) -- deterministic order in, random choice out
	end
	return byRarity, total
end

-- Roll a rarity by the published odds. If nothing unowned is left at that rarity, fall
-- through to another that still has something, so a purchase never silently gives nothing.
local function roll(byRarity, odds)
	local ticket, running = math.random() * 100, 0
	for _, rarity in ipairs(Cosmetics.RARITIES) do
		running += odds[rarity] or 0
		if ticket <= running and byRarity[rarity] then
			local list = byRarity[rarity]
			return list[math.random(#list)]
		end
	end
	for _, rarity in ipairs(Cosmetics.RARITIES) do
		local list = byRarity[rarity]
		if list and #list > 0 and (odds[rarity] or 0) > 0 then
			return list[math.random(#list)]
		end
	end
	return nil
end

-- Returns status, itemId.  ok | unknown | currency | poor | empty | failed
-- Yields on the DataStore; call it in a spawned thread.
function Crates.open(player, crateId, currency)
	local crate = Crates.All[crateId]
	if not crate then
		return "unknown"
	end
	if currency ~= "gold" and currency ~= "gems" then
		return "currency"
	end

	local price = crate[currency]
	if not price or price <= 0 then
		return "currency"
	end
	if (Profile.get(player)[currency] or 0) < price then
		return "poor"
	end

	local byRarity, left = poolFor(player, crate)
	if left == 0 then
		return "empty"
	end

	local prize = roll(byRarity, crate.odds)
	if not prize then
		return "empty"
	end

	-- One atomic step: the balance check happens against the stored value, not the cached
	-- one, so a second server or a rejoin race cannot spend the same gold twice.
	local ok = Profile.transact(player, function(data)
		if (data[currency] or 0) < price then
			return false
		end
		data.owned = data.owned or {}
		if data.owned[prize] then
			return false -- raced us to it
		end
		data[currency] = data[currency] - price
		data.owned[prize] = true
		return true
	end)

	if not ok then
		return "failed"
	end

	Cosmetics.publish(player)
	return "ok", prize
end

return Crates
