-- ModuleScript: ServerScriptService > Shared > Cosmetics
--
-- The entitlement seam. Nothing here is monetised yet; this exists so that when it is,
-- ownership is already checked in one server-side place instead of being bolted on.
--
-- Three rules this module enforces, and they are not negotiable:
--   1. Cosmetic only. Never put anything here that changes scoring, timing or what a
--      player can do. See "Rules to keep" in CLAUDE.md.
--   2. Server decides. A client may ask to equip something; only this module says yes.
--      Never let a client assert what it owns.
--   3. Ids replicate, not visuals. The client has its own catalogue keyed by the same
--      ids and decides how each one looks, the same split modes already use.

local Profile = require(script.Parent.Profile)

local Cosmetics = {}

-- profile field per kind, so a saved choice survives a rejoin
local FIELD = { Banner = "banner", RevealEffect = "revealEffect" }

-- kind -> what a player wears/uses. Add kinds here as they are built; the locker builds a
-- tab per kind from this list, so a new kind needs no UI work.
Cosmetics.KINDS = { "Banner", "RevealEffect" }
Cosmetics.KIND_LABELS = { Banner = "Banners", RevealEffect = "Effects" }

-- Rarity reuses the answer tiers rather than inventing a second vocabulary for the same
-- idea. Cosmetic only - rarity never affects scoring.
Cosmetics.RARITIES = { "Common", "Rare", "Epic", "Legendary" }

-- DEVELOPMENT ONLY. Makes ownedBy pass everything so the whole catalogue is wearable while
-- building. Each item keeps its real `free` flag, so turning this off restores the true
-- lock states rather than needing them reconstructed. **Must be false before anything is
-- sold**, or the gate is decorative.
local DEV_UNLOCK_ALL = true

-- `free = true` means everyone has it. Anything else needs an ownership source, which
-- is deliberately not wired yet - see ownedBy below.
Cosmetics.Items = {
	-- banners frame your avatar on the intro screen, the between-round recap, and every
	-- reveal card - three surfaces a round, which is why they are worth owning
	slate    = { kind = "Banner", name = "Slate",   rarity = "Common",    free = true, order = 1 },
	storm    = { kind = "Banner", name = "Storm",   rarity = "Common",    free = true, order = 2 },
	ocean    = { kind = "Banner", name = "Ocean",   rarity = "Common",    free = true, order = 3 },
	forest   = { kind = "Banner", name = "Forest",  rarity = "Common",    free = true, order = 4 },
	deep     = { kind = "Banner", name = "Deep",    rarity = "Rare",      free = true, order = 5 },
	mint     = { kind = "Banner", name = "Mint",    rarity = "Rare",      free = true, order = 6 },
	sunrise  = { kind = "Banner", name = "Sunrise", rarity = "Rare",      free = true, order = 7 },
	ember    = { kind = "Banner", name = "Ember",   rarity = "Epic",      free = true, order = 8 },
	rose     = { kind = "Banner", name = "Rose",    rarity = "Epic",      free = true, order = 9 },
	-- `free` omitted: these are the ones that would be earned or bought. Wearable right
	-- now only because DEV_UNLOCK_ALL is on.
	aurora   = { kind = "Banner", name = "Aurora",  rarity = "Legendary", order = 10 },
	gold     = { kind = "Banner", name = "Gold",    rarity = "Legendary", order = 11 },
	void     = { kind = "Banner", name = "Void",    rarity = "Legendary", order = 12 },

	-- reveal effects: how your answer lands at a reveal. Catalogued and listed in the
	-- locker so the shape is proven, but nothing renders them yet.
	plain    = { kind = "RevealEffect", name = "Plain", rarity = "Common", free = true, order = 1 },
	emberise = { kind = "RevealEffect", name = "Ember", rarity = "Epic", order = 2 },
}

Cosmetics.Defaults = { Banner = "slate", RevealEffect = "plain" }

---------------------------------------------------------------- ownership

-- The single place that decides what a player may wear.
--
-- When monetisation arrives this is where it goes: a MarketplaceService gamepass check
-- (cached - UserOwnsGamePassAsync yields and is rate limited), or a DataStore of granted
-- items. Until then only free items pass, which keeps the gate honest rather than
-- permissive-by-default.
function Cosmetics.ownedBy(_player, id)
	local item = Cosmetics.Items[id]
	if not item then
		return false
	end
	return DEV_UNLOCK_ALL or item.free == true
end

-- what the locker should show as locked, independent of the dev override
function Cosmetics.isFree(id)
	local item = Cosmetics.Items[id]
	return item ~= nil and item.free == true
end

function Cosmetics.devUnlockAll()
	return DEV_UNLOCK_ALL
end

function Cosmetics.isKind(id, kind)
	local item = Cosmetics.Items[id]
	return item ~= nil and item.kind == kind
end

-- What the player currently has on. Equipped state lives on attributes so it replicates
-- to everyone: your banner is something the whole room sees, not just you.
function Cosmetics.equipped(player, kind)
	local id = player:GetAttribute(kind)
	if id and Cosmetics.isKind(id, kind) and Cosmetics.ownedBy(player, id) then
		return id
	end
	return Cosmetics.Defaults[kind]
end

-- Returns true if it took. Refuses silently on an unowned or wrong-kind id, because a
-- client asking for something it does not own is not an error worth surfacing to it.
function Cosmetics.equip(player, kind, id)
	if not Cosmetics.isKind(id, kind) or not Cosmetics.ownedBy(player, id) then
		return false
	end
	player:SetAttribute(kind, id)
	Profile.set(player, FIELD[kind], id)
	return true
end

-- Called the moment a player joins, before anything has loaded, so no attribute is ever
-- unset and the client never has to handle nil.
function Cosmetics.applyDefaults(player)
	for _, kind in ipairs(Cosmetics.KINDS) do
		player:SetAttribute(kind, Cosmetics.equipped(player, kind))
	end
end

-- Yields on the DataStore, so call it in a spawned thread. Until it lands the player
-- wears defaults, which is why applyDefaults runs first rather than instead.
function Cosmetics.restore(player)
	local data = Profile.load(player)
	for _, kind in ipairs(Cosmetics.KINDS) do
		local saved = data[FIELD[kind]]
		if saved and player.Parent then
			Cosmetics.equip(player, kind, saved)
		end
	end
end

return Cosmetics
