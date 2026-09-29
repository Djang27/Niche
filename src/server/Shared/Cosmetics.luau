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

local Cosmetics = {}

-- kind -> what a player wears/uses. Add kinds here as they are built.
Cosmetics.KINDS = { "Banner", "RevealEffect" }

-- `free = true` means everyone has it. Anything else needs an ownership source, which
-- is deliberately not wired yet - see ownedBy below.
Cosmetics.Items = {
	-- banners: the frame around your avatar on the match intro screen
	slate    = { kind = "Banner", name = "Slate", free = true },
	sunrise  = { kind = "Banner", name = "Sunrise", free = true },
	deep     = { kind = "Banner", name = "Deep", free = true },
	forest   = { kind = "Banner", name = "Forest", free = true },
	-- not free, so the gate below has something to actually refuse
	aurora   = { kind = "Banner", name = "Aurora" },

	-- reveal effects: how your answer lands at a reveal. Catalogued so the shape is
	-- proven, but nothing renders them yet - building unowned cosmetics is waste.
	plain    = { kind = "RevealEffect", name = "Plain", free = true },
	emberise = { kind = "RevealEffect", name = "Ember" },
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
	return item ~= nil and item.free == true
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
	return true
end

-- Called when a player joins: put them in valid defaults so no attribute is ever unset.
-- Later this is where saved choices would be loaded.
function Cosmetics.applyDefaults(player)
	for _, kind in ipairs(Cosmetics.KINDS) do
		player:SetAttribute(kind, Cosmetics.equipped(player, kind))
	end
end

return Cosmetics
