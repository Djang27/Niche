-- ModuleScript: ServerScriptService > Modes > Brainstorm
--
-- A category appears and everyone types as many related words as they can at once.
-- You score 1 point per word nobody else wrote. Anything two people both thought of is
-- worth nothing to either of them.
--
-- Matching is normalisation only, never fuzzy. Edit distance would merge "cat" and "bat",
-- which are one edit apart and plainly different words, and stealing a point from someone
-- feels far worse than handing out an extra one. Under-merging is the safe direction.

local Categories = require(script.Parent.Parent.Shared.Categories)
local TextFilter = require(script.Parent.Parent.Shared.TextFilter)

local Brainstorm = {
	name = "Brainstorm",
	blurb = "Score only what nobody else thought of",
	minPlayers = 2, -- with one player every word is unique, so there is no game
	rounds = 3,
}

-- tweak these
local WRITE_TIME = 45
local REVEAL_TIME = 9
local MAX_WORDS = 20     -- per player per round, stops spam scoring
local MAX_WORD_LEN = 30
local SHOW_SHARED = 8    -- how many duplicated words the reveal names

-- per-match state
local categories = {}
local currentCategory = nil
local accepting = false
local order = {}   -- [player] = { normalised word, ... } in the order typed
local seen = {}    -- [player] = { [normalised] = true } for fast dedupe
local firstBy = {} -- [normalised] = the player who typed it first, for filter attribution
local done = {}

---------------------------------------------------------------- matching

-- Lowercase, drop punctuation, collapse spaces, and strip a plural "s". The plural rule
-- skips short words and double-s endings so "bus" and "glass" survive intact.
local function normalize(s)
	s = s:lower()
	s = s:gsub("[^%w%s']", "")
	s = s:gsub("%s+", " ")
	s = s:gsub("^%s+", ""):gsub("%s+$", "")
	if #s > 3 and s:sub(-1) == "s" and s:sub(-2) ~= "ss" then
		s = s:sub(1, -2)
	end
	return s
end

local function prettify(s)
	return (s:gsub("(%a)([%w']*)", function(first, rest)
		return first:upper() .. rest
	end))
end

---------------------------------------------------------------- match hooks

function Brainstorm.beginMatch(ctx)
	accepting = false
	currentCategory = nil
	order, seen, firstBy, done = {}, {}, {}, {}

	categories = Categories.pick(ctx.rounds)
	ctx.rounds = #categories
end

function Brainstorm.runRound(ctx, round)
	currentCategory = categories[round]
	if not currentCategory then return end

	order, seen, firstBy, done = {}, {}, {}, {}
	accepting = true

	ctx.send("round", {
		round = round,
		rounds = ctx.rounds,
		category = currentCategory,
		seconds = WRITE_TIME,
		maxWords = MAX_WORDS,
	})

	ctx.waitUntil(WRITE_TIME, function()
		for _, p in ipairs(ctx.players()) do
			if not done[p] then
				return false
			end
		end
		return true
	end)
	accepting = false

	-- how many players wrote each word
	local counts = {}
	for _, p in ipairs(ctx.players()) do
		for _, w in ipairs(order[p] or {}) do
			counts[w] = (counts[w] or 0) + 1
		end
	end

	local rows = {}
	for _, p in ipairs(ctx.players()) do
		local list = order[p] or {}
		local unique = 0
		for _, w in ipairs(list) do
			if counts[w] == 1 then
				unique += 1
			end
		end
		ctx.award(p, unique)
		table.insert(rows, {
			name = p.DisplayName,
			words = #list,
			unique = unique,
			total = ctx.scoreOf(p),
		})
	end
	table.sort(rows, function(a, b)
		if a.unique ~= b.unique then
			return a.unique > b.unique
		end
		return a.name < b.name
	end)

	-- the duplicated words are the fun part of the reveal, and the only player-typed text
	-- that leaves this server. Batch them by whoever typed each one first: TextService
	-- wants a real author, and one call per author beats one call per word.
	local dup = {}
	for w, n in pairs(counts) do
		if n > 1 then
			table.insert(dup, { word = w, n = n })
		end
	end
	table.sort(dup, function(a, b)
		if a.n ~= b.n then
			return a.n > b.n
		end
		return a.word < b.word
	end)

	local byAuthor = {}
	for i = 1, math.min(#dup, SHOW_SHARED) do
		local w = dup[i].word
		local author = firstBy[w]
		if author then
			byAuthor[author] = byAuthor[author] or {}
			table.insert(byAuthor[author], prettify(w))
		end
	end

	local parts = {}
	for author, list in pairs(byAuthor) do
		table.insert(parts, (TextFilter.forBroadcast(table.concat(list, ", "), author.UserId)))
	end

	ctx.send("reveal", {
		rows = rows,
		shared = table.concat(parts, ", "),
		sharedCount = #dup,
	})

	task.wait(REVEAL_TIME)
end

function Brainstorm.endMatch()
	accepting = false
	currentCategory = nil
	-- these are keyed by Player, so they must be dropped here and not only in playerLeft
	order, seen, firstBy, done = {}, {}, {}, {}
end

function Brainstorm.playerLeft(_, player)
	order[player] = nil
	seen[player] = nil
	done[player] = nil
end

---------------------------------------------------------------- client messages

function Brainstorm.onEvent(_, player, kind, value)
	if kind == "word" then
		if not accepting then return end
		if typeof(value) ~= "string" or #value > MAX_WORD_LEN then return end

		local w = normalize(value)
		if w == "" then return end

		order[player] = order[player] or {}
		seen[player] = seen[player] or {}
		if seen[player][w] or #order[player] >= MAX_WORDS then return end

		seen[player][w] = true
		table.insert(order[player], w)
		if not firstBy[w] then
			firstBy[w] = player
		end
	elseif kind == "done" then
		if not accepting then return end
		done[player] = true
	end
end

return Brainstorm
