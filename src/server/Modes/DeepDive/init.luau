-- ModuleScript: ServerScriptService > Modes > DeepDive
--
-- A category appears and everyone races to name things in it. You score 1 point per
-- answer nobody else wrote. Anything two people both thought of is worth nothing to
-- either of them, so the game rewards going deep rather than obvious.
--
-- Answers are checked against the shared answer lists, the same data Niche uses. That
-- is what stops "asdf" scoring: gibberish is guaranteed unique, so without a real check
-- the optimal strategy is to type nonsense. AnswerJudge also canonicalises, so "dogs",
-- "puppy" and "Dog" all collapse to the same entry and collide properly.
--
-- Because every accepted answer is a canonical list entry rather than typed text, this
-- mode needs no TextFilter - the same exemption Niche has. Rejected words ARE raw player
-- text, and they only ever go to AnswerLog, which is owner-only.

local PromptData = require(script.Parent.Parent.Shared.PromptData)
local AnswerJudge = require(script.Parent.Parent.Shared.AnswerJudge)
local AnswerLog = require(script.Parent.Parent.Shared.AnswerLog)

local DeepDive = {
	name = "Deep Dive",
	blurb = "Score only what nobody else thought of",
	minPlayers = 2,
	rounds = 3,
}

-- tweak these
local WRITE_TIME = 40
local REVEAL_TIME = 9
local MAX_WORDS = 10      -- per player per round
local MAX_INPUT_LEN = 30
local SHOW_SHARED = 8     -- how many duplicated answers the reveal names
-- A round of 4 players draws players * MAX_WORDS answers from one list. Below roughly
-- 3x that, nearly everything collides and nobody scores, so thin lists sit this out.
local MIN_LIST_SIZE = 110

-- per-match state
local categories = {}
local current = nil    -- the ByList entry in play
local accepting = false
local order = {}       -- [player] = { canonical, ... } in the order accepted
local seen = {}        -- [player] = { [canonical] = true }
local done = {}

---------------------------------------------------------------- helpers

-- "PizzaToppings" -> "Pizza Toppings"
local function titleOf(listId)
	return (listId:gsub("(%l)(%u)", "%1 %2"))
end

local function eligibleLists()
	local out = {}
	for _, entry in pairs(PromptData.ByList) do
		if entry.count >= MIN_LIST_SIZE then
			table.insert(out, entry)
		end
	end
	table.sort(out, function(a, b) return a.list < b.list end)
	return out
end

---------------------------------------------------------------- match hooks

function DeepDive.beginMatch(ctx)
	accepting = false
	current = nil
	order, seen, done = {}, {}, {}

	local pool = eligibleLists()
	if #pool == 0 then
		warn("[DeepDive] no list is big enough to play; check MIN_LIST_SIZE")
		ctx.rounds = 0
		return
	end

	categories = {}
	for _ = 1, math.min(ctx.rounds, #pool) do
		table.insert(categories, table.remove(pool, math.random(#pool)))
	end
	ctx.rounds = #categories
end

function DeepDive.runRound(ctx, round)
	current = categories[round]
	if not current then return end

	order, seen, done = {}, {}, {}
	accepting = true

	ctx.send("round", {
		round = round,
		rounds = ctx.rounds,
		category = titleOf(current.list),
		seconds = WRITE_TIME,
		maxWords = MAX_WORDS,
	})

	-- end as soon as nobody can or wants to add more, rather than waiting out the clock
	ctx.waitUntil(WRITE_TIME, function()
		for _, p in ipairs(ctx.players()) do
			local typed = order[p] and #order[p] or 0
			if not done[p] and typed < MAX_WORDS then
				return false
			end
		end
		return true
	end)
	accepting = false

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

	-- duplicated answers are the fun part of the reveal, and safe to broadcast because
	-- they are canonical list entries, never what someone typed
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

	local shared = {}
	for i = 1, math.min(#dup, SHOW_SHARED) do
		table.insert(shared, AnswerJudge.prettify(dup[i].word))
	end

	local submitted = {}
	for _, p in ipairs(ctx.players()) do
		for _, w in ipairs(order[p] or {}) do
			table.insert(submitted, w)
		end
	end
	AnswerLog.logRound(current, #ctx.players(), submitted)

	ctx.send("reveal", {
		rows = rows,
		shared = table.concat(shared, ", "),
		sharedCount = #dup,
	})

	task.wait(REVEAL_TIME)
end

function DeepDive.endMatch()
	accepting = false
	current = nil
	-- keyed by Player, so they must be dropped here and not only in playerLeft
	order, seen, done = {}, {}, {}
end

function DeepDive.playerLeft(_, player)
	order[player] = nil
	seen[player] = nil
	done[player] = nil
end

---------------------------------------------------------------- client messages

-- Answering is a request, not an event, so the client only ever shows words the server
-- actually accepted. Fire-and-forget let the on-screen list drift from the real score.
-- Returns status, displayText, count.
--   ok | dupe | full | unknown | closed
function DeepDive.onRequest(_, player, kind, value)
	if kind ~= "word" then return nil end
	if not accepting or not current then return "closed" end
	if typeof(value) ~= "string" or #value > MAX_INPUT_LEN then return "unknown" end

	order[player] = order[player] or {}
	seen[player] = seen[player] or {}
	if #order[player] >= MAX_WORDS then
		return "full", nil, #order[player]
	end

	-- "suggest" means a near miss, so a typo is corrected rather than thrown away.
	-- There is no did-you-mean step here; you are typing against a clock.
	local status, canonical = AnswerJudge.check(current, value)
	if status ~= "valid" and status ~= "suggest" then
		AnswerLog.logMiss(current, value)
		return "unknown", nil, #order[player]
	end

	if seen[player][canonical] then
		return "dupe", AnswerJudge.prettify(canonical), #order[player]
	end

	seen[player][canonical] = true
	table.insert(order[player], canonical)
	return "ok", AnswerJudge.prettify(canonical), #order[player]
end

function DeepDive.onEvent(_, player, kind, value)
	if kind == "done" then
		if not accepting then return end
		done[player] = true
	elseif kind == "resume" then
		-- Done is reversible while the round is live; hitting it by accident should not
		-- cost the rest of the round
		if not accepting then return end
		done[player] = nil
	elseif kind == "remove" then
		if not accepting then return end
		if typeof(value) ~= "number" then return end
		local list = order[player]
		if not list then return end
		local w = list[value]
		if not w then return end
		table.remove(list, value)
		seen[player][w] = nil
	end
end

return DeepDive
