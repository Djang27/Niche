-- ModuleScript: ServerScriptService > Shared > Profile
--
-- Per-player saved data. The first thing in this project to persist anything about a
-- *person* - AnswerLog is anonymous aggregate data keyed by prompt, with no player rows.
-- That makes this the file to be careful in.
--
-- Three rules it enforces:
--   1. **A failed load never saves.** If GetAsync errors we do not know what the player
--      owns, so writing defaults would destroy real data. A profile that failed to load
--      is read-only for the session.
--   2. **Versioned key.** `STORE_NAME` carries a version so a bad schema can be abandoned
--      wholesale rather than migrated under pressure.
--   3. **Never block the game.** Loading is async and the game runs on defaults until it
--      lands. A DataStore outage must not stop anyone playing.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Profile = {}

local STORE_NAME = "Profile_v1"
local SAVE_RETRIES = 3

local enabled = true
local store = nil

local cache = {}  -- [player] = { data = {}, loaded = bool, dirty = bool }

-- Development only, and the twin of DEV_UNLOCK_ALL in Cosmetics: a new profile starts
-- with enough to open crates. Gold is otherwise only earned by finishing matches, so
-- without this the shop takes a dozen playtests to reach even once. **Both must be zero
-- before anything is sold.** Only ever applied to a genuinely new profile, so flipping
-- them back does not take anything off an existing player.
local DEV_START_GOLD = 2000
local DEV_START_GEMS = 200

local function blank()
	return {
		version = 1,
		banner = nil,
		revealEffect = nil,
		gold = DEV_START_GOLD, -- earned by playing
		gems = DEV_START_GEMS, -- bought with Robux
		owned = {},            -- [cosmeticId] = true
	}
end

if game.GameId == 0 then
	enabled = false
	warn("[Profile] place isn't published, saving off")
else
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		enabled = false
		warn(("[Profile] couldn't open the DataStore, saving off: %s"):format(tostring(result)))
	end
end

local function keyFor(player)
	return ("p_%d"):format(player.UserId)
end

---------------------------------------------------------------- reading

-- Yields. Call it in a spawned thread; the game runs on defaults meanwhile.
function Profile.load(player)
	cache[player] = cache[player] or { data = blank(), loaded = false, dirty = false }
	if not enabled or not store then
		return cache[player].data
	end

	local ok, result = pcall(function()
		return store:GetAsync(keyFor(player))
	end)

	local entry = cache[player]
	if not entry then return blank() end -- left while we were reading

	if not ok then
		-- read-only for the session: we do not know what they own, so we must not write
		warn(("[Profile] load failed for %s, saving disabled for this session: %s")
			:format(player.Name, tostring(result)))
		return entry.data
	end

	if type(result) == "table" then
		entry.data = result
	end
	entry.loaded = true
	return entry.data
end

function Profile.get(player)
	local entry = cache[player]
	return entry and entry.data or blank()
end

function Profile.set(player, key, value)
	local entry = cache[player]
	if not entry then return end
	if entry.data[key] == value then return end
	entry.data[key] = value
	entry.dirty = true
end

---------------------------------------------------------------- writing

function Profile.save(player)
	local entry = cache[player]
	if not enabled or not store or not entry then return end
	-- the important guard: never overwrite data we failed to read
	if not entry.loaded or not entry.dirty then return end

	for attempt = 1, SAVE_RETRIES do
		local ok, err = pcall(function()
			store:SetAsync(keyFor(player), entry.data)
		end)
		if ok then
			entry.dirty = false
			return
		end
		warn(("[Profile] save attempt %d failed for %s: %s"):format(attempt, player.Name, tostring(err)))
		task.wait(attempt)
	end
end

-- Currency and grants go through UpdateAsync, not SetAsync.
--
-- SetAsync is last-write-wins, which is fine for "which banner am I wearing" - lose that
-- race and you lose a preference. It is not fine for a balance: a rejoin race or a second
-- server can duplicate or destroy gold. UpdateAsync is a read-modify-write on the stored
-- copy, so deducting and granting happen as one atomic step against the real value.
--
-- `mutate(data)` returns true to commit, false to abort (can't afford it, already owned).
-- It may run more than once under contention, so it must decide purely from `data`.
-- Yields; call it in a spawned thread.
function Profile.transact(player, mutate)
	local entry = cache[player]
	if not entry then
		return false, "gone"
	end
	-- same rule as saving: if we never read their data, we must not write over it
	if not entry.loaded and enabled and store then
		return false, "unloaded"
	end

	if not enabled or not store then
		-- no DataStore (Studio without API access, unpublished place). Apply in memory so
		-- the game is still playable, but the caller can tell it will not persist.
		local ok = mutate(entry.data)
		return ok, "offline"
	end

	local committed = false
	local ok, err = pcall(function()
		store:UpdateAsync(keyFor(player), function(stored)
			local data = stored or entry.data
			committed = mutate(data) and true or false
			if not committed then
				return nil -- abort the write entirely
			end
			entry.data = data
			return data
		end)
	end)

	if not ok then
		warn(("[Profile] transaction failed for %s: %s"):format(player.Name, tostring(err)))
		return false, "error"
	end
	return committed, committed and "ok" or "refused"
end

function Profile.forget(player)
	cache[player] = nil
end

Players.PlayerRemoving:Connect(function(player)
	Profile.save(player)
	Profile.forget(player)
end)

game:BindToClose(function()
	if RunService:IsStudio() then return end
	for player in pairs(cache) do
		pcall(Profile.save, player)
	end
end)

return Profile
