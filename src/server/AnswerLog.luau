-- ModuleScript: ServerScriptService > AnswerLog
-- Records what players actually type, per prompt, into a DataStore.
--
-- Two things this is for:
--   * finding missing answers and aliases (the "rejected" and "nearMiss" buckets)
--   * rebuilding tiers from real frequency instead of guesses (the "accepted" bucket)
--
-- Counts are buffered in memory and written in batches, so a busy server does a
-- handful of DataStore writes per match instead of one per keystroke.
--
-- Rejected answers are raw free-form player text. They are owner-only diagnostics:
-- never send any of this to a client without running it through TextService first.

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local PromptData = require(script.Parent.PromptData)

local AnswerLog = {}

-- tweak these
local STORE_NAME = "AnswerLog_v1"
local FLUSH_INTERVAL = 120      -- seconds between batched writes
local WRITE_GAP = 1             -- seconds between individual writes inside one flush
local MAX_UNIQUE_REJECTED = 300 -- distinct rejected/near-miss strings kept per prompt
local MAX_TEXT = 50             -- longest rejected string we keep
local MAX_FAILURES = 5          -- stop logging after this many failed writes in a row
local LOG_IN_STUDIO = true      -- false keeps solo Studio tests out of the real data

local enabled = true
local store = nil
local failures = 0
local buffer = {} -- [key] = bucket

---------------------------------------------------------------- setup

if game.GameId == 0 then
	-- unpublished place: DataStore calls always fail here
	enabled = false
	warn("[AnswerLog] place isn't published yet, logging off")
elseif RunService:IsStudio() and not LOG_IN_STUDIO then
	enabled = false
else
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		enabled = false
		warn(("[AnswerLog] couldn't open the DataStore, logging off: %s"):format(tostring(result)))
	end
end

---------------------------------------------------------------- buffering

-- DataStore keys max out at 50 chars, prompt text doesn't, so: readable stub + hash
local function hashString(s)
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + string.byte(s, i)) % 4294967296
	end
	return h
end

local function keyFor(id)
	local stub = id:lower():gsub("[^%w]+", "_"):sub(1, 30)
	return ("%s_%d"):format(stub, hashString(id))
end

local function bucketFor(prompt)
	local key = keyFor(prompt.id)
	local b = buffer[key]
	if not b then
		b = { id = prompt.id, text = prompt.text, plays = 0, seen = 0,
			accepted = {}, rejected = {}, nearMiss = {} }
		buffer[key] = b
	end
	return b
end

-- adds `from` into `into`, refusing new keys once `cap` distinct ones are stored
local function mergeCounts(into, from, cap)
	into = into or {}
	local size = 0
	if cap then
		for _ in pairs(into) do
			size += 1
		end
	end
	for k, n in pairs(from) do
		if into[k] then
			into[k] += n
		elseif not cap or size < cap then
			into[k] = n
			size += 1
		end
	end
	return into
end

-- raw player text: trim it and drop anything that isn't valid UTF-8, since
-- DataStores reject malformed strings and would fail the whole write
local function cleanText(s)
	-- lowercase + collapse whitespace so "Egypt" and " egypt " count as one entry
	s = s:lower():gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
	s = s:sub(1, MAX_TEXT)
	if s == "" or utf8.len(s) == nil then
		return nil
	end
	return s
end

---------------------------------------------------------------- logging

-- one round of one prompt: how many players saw it, and what got locked in
function AnswerLog.logRound(prompt, seen, submitted)
	if not enabled then return end
	local b = bucketFor(prompt)
	b.plays += 1
	b.seen += seen
	for _, answer in ipairs(submitted) do
		b.accepted[answer] = (b.accepted[answer] or 0) + 1
	end
end

-- typed something the list doesn't know at all: probably a missing answer
function AnswerLog.logMiss(prompt, raw)
	if not enabled then return end
	local text = cleanText(raw)
	if not text then return end
	local b = bucketFor(prompt)
	b.rejected[text] = (b.rejected[text] or 0) + 1
end

-- typed something we auto-corrected: probably a missing alias or spelling
function AnswerLog.logNearMiss(prompt, raw, canonical)
	if not enabled then return end
	local text = cleanText(raw)
	if not text then return end
	local b = bucketFor(prompt)
	local pair = text .. " -> " .. canonical
	b.nearMiss[pair] = (b.nearMiss[pair] or 0) + 1
end

---------------------------------------------------------------- writing

local function restore(key, b)
	local cur = buffer[key]
	if not cur then
		buffer[key] = b
		return
	end
	cur.plays += b.plays
	cur.seen += b.seen
	cur.accepted = mergeCounts(cur.accepted, b.accepted)
	cur.rejected = mergeCounts(cur.rejected, b.rejected, MAX_UNIQUE_REJECTED)
	cur.nearMiss = mergeCounts(cur.nearMiss, b.nearMiss, MAX_UNIQUE_REJECTED)
end

function AnswerLog.flush()
	if not enabled or not store then return end

	local pending = buffer
	buffer = {}

	local first = true
	for key, b in pairs(pending) do
		if not first then
			task.wait(WRITE_GAP)
		end
		first = false

		local ok, err = pcall(function()
			store:UpdateAsync(key, function(old)
				old = old or {}
				old.id = b.id
				old.text = b.text
				old.plays = (old.plays or 0) + b.plays
				old.seen = (old.seen or 0) + b.seen
				old.accepted = mergeCounts(old.accepted, b.accepted)
				old.rejected = mergeCounts(old.rejected, b.rejected, MAX_UNIQUE_REJECTED)
				old.nearMiss = mergeCounts(old.nearMiss, b.nearMiss, MAX_UNIQUE_REJECTED)
				return old
			end)
		end)

		if ok then
			failures = 0
		else
			failures += 1
			warn(("[AnswerLog] write failed for %s: %s"):format(key, tostring(err)))
			restore(key, b) -- keep the counts for the next flush
			if failures >= MAX_FAILURES then
				enabled = false
				warn("[AnswerLog] too many failed writes, logging off for this server")
				return
			end
		end
	end
end

if enabled then
	task.spawn(function()
		while true do
			task.wait(FLUSH_INTERVAL)
			AnswerLog.flush()
		end
	end)
	game:BindToClose(function()
		AnswerLog.flush()
	end)
end

---------------------------------------------------------------- reading

local function sortedPairs(t, limit)
	local list = {}
	for k, n in pairs(t or {}) do
		table.insert(list, { k, n })
	end
	table.sort(list, function(a, b) return a[2] > b[2] end)
	if limit and #list > limit then
		for i = #list, limit + 1, -1 do
			list[i] = nil
		end
	end
	return list
end

-- Run this from the Studio command bar (Server context) to see what's been collected:
--   require(game.ServerScriptService.AnswerLog).report()
--   require(game.ServerScriptService.AnswerLog).report("africa")
-- `share` is how often a player who saw the prompt gave that answer, which is the
-- number tiers should eventually be derived from.
function AnswerLog.report(filter, topN)
	if not store then
		warn("[AnswerLog] no DataStore available")
		return
	end
	topN = topN or 10

	for _, prompt in ipairs(PromptData.Prompts) do
		if not filter or prompt.text:lower():find(filter:lower(), 1, true) then
			local ok, data = pcall(function()
				return store:GetAsync(keyFor(prompt.id))
			end)
			if ok and data and (data.plays or 0) > 0 then
				print(("\n=== %s  (%d plays, %d player-rounds)"):format(prompt.text, data.plays, data.seen or 0))

				print("  answered:")
				for _, e in ipairs(sortedPairs(data.accepted, topN)) do
					local share = data.seen and data.seen > 0 and (e[2] / data.seen * 100) or 0
					print(("    %-28s %4d  %5.1f%%  (%s)"):format(e[1], e[2], share, prompt.answers[e[1]] or "?"))
				end

				local rejected = sortedPairs(data.rejected, topN)
				if #rejected > 0 then
					print("  rejected (missing answers?):")
					for _, e in ipairs(rejected) do
						print(("    %-28s %4d"):format(e[1], e[2]))
					end
				end

				local near = sortedPairs(data.nearMiss, topN)
				if #near > 0 then
					print("  auto-corrected (missing aliases?):")
					for _, e in ipairs(near) do
						print(("    %-40s %4d"):format(e[1], e[2]))
					end
				end
			end
			task.wait(0.1) -- stay inside the GetAsync budget
		end
	end
	print("\n[AnswerLog] report done")
end

return AnswerLog
