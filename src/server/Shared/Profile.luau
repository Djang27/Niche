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

local function blank()
	return { banner = nil, revealEffect = nil }
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
