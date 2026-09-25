-- ModuleScript: ServerScriptService > Modes > Niche > PromptData
-- Builds every prompt automatically from the modules in the sibling Lists folder.
-- To add a new category, just add a new ModuleScript to Lists.

local PromptData = {}

PromptData.Tiers = {
	Common = 10,
	Rare = 30,
	SuperRare = 60,
	Epic = 80,
	Legendary = 100,
}

local MIN_ANSWERS = 8        -- prompts with fewer possible answers get skipped (too easy/boring)
local MIN_LETTER_ANSWERS = 8 -- same thing for "starting with X" prompts
local LETTER_CHANCE = 0.35   -- how often a letter prompt gets picked over a normal one
local RECENT_LIMIT = 20      -- a prompt won't come back until this many others were played on this server

PromptData.Prompts = {}

---------------------------------------------------------------- building

local function hasTag(item, tag)
	return item.tags ~= nil and table.find(item.tags, tag) ~= nil
end

-- turns a set of items into the { text, answers, aliases } format AnswerJudge expects
local function addPrompt(listId, kind, text, items, tierTag)
	local answers, aliases = {}, {}
	for _, item in ipairs(items) do
		-- tierIn lets an answer be rarer/commoner inside a specific tagged prompt
		answers[item.name] = (tierTag and item.tierIn and item.tierIn[tierTag]) or item.tier
		for _, a in ipairs(item.aliases or {}) do
			aliases[string.lower(a)] = item.name
		end
	end
	table.insert(PromptData.Prompts, {
		id = listId .. ":" .. text, -- stable across restarts, used as the answer-log key
		text = text,
		answers = answers,
		aliases = aliases,
		list = listId,
		kind = kind,
		count = #items,
	})
end

local function addList(listId, list)
	-- clean up + catch typos in the data
	local items, seen = {}, {}
	for _, item in ipairs(list.items or {}) do
		item.name = string.lower(item.name)
		if not PromptData.Tiers[item.tier] then
			warn(("[%s] '%s' has unknown tier '%s'"):format(listId, item.name, tostring(item.tier)))
		elseif seen[item.name] then
			warn(("[%s] duplicate answer '%s'"):format(listId, item.name))
		else
			seen[item.name] = true
			table.insert(items, item)
		end
	end

	-- normal prompts: every item, or only items with a tag
	for _, p in ipairs(list.prompts or {}) do
		local matching = {}
		for _, item in ipairs(items) do
			if not p.tag or hasTag(item, p.tag) then
				table.insert(matching, item)
			end
		end
		if #matching >= MIN_ANSWERS then
			addPrompt(listId, "normal", p.text, matching, p.tag)
		else
			warn(("[%s] skipped '%s' (only %d answers)"):format(listId, p.text, #matching))
		end
	end

	-- letter prompts: "Name a country starting with B", made automatically
	if list.letterPrompts then
		local byLetter = {}
		for _, item in ipairs(items) do
			local letter = item.name:sub(1, 1)
			byLetter[letter] = byLetter[letter] or {}
			table.insert(byLetter[letter], item)
		end
		for letter, matching in pairs(byLetter) do
			if #matching >= MIN_LETTER_ANSWERS then
				addPrompt(listId, "letter", ("Name %s starting with %s"):format(list.noun, letter:upper()), matching, nil)
			end
		end
	end
end

local listsFolder = script.Parent:WaitForChild("Lists")
local listCount = 0
for _, mod in ipairs(listsFolder:GetChildren()) do
	if mod:IsA("ModuleScript") then
		local ok, list = pcall(require, mod)
		if ok and type(list) == "table" then
			addList(mod.Name, list)
			listCount += 1
		else
			warn(("Couldn't load list %s: %s"):format(mod.Name, tostring(list)))
		end
	end
end
print(("[PromptData] built %d prompts from %d lists"):format(#PromptData.Prompts, listCount))

---------------------------------------------------------------- picking

local recent = {}

local function available()
	local byList, total = {}, 0
	for _, p in ipairs(PromptData.Prompts) do
		if not table.find(recent, p) then
			byList[p.list] = byList[p.list] or {}
			table.insert(byList[p.list], p)
			total += 1
		end
	end
	return byList, total
end

-- picks one prompt from a category, keeping letter prompts from flooding the game
local function pickFrom(pool)
	local wantKind = math.random() < LETTER_CHANCE and "letter" or "normal"
	local options = {}
	for i, p in ipairs(pool) do
		if p.kind == wantKind then
			table.insert(options, i)
		end
	end
	if #options == 0 then
		for i in ipairs(pool) do
			table.insert(options, i)
		end
	end
	return table.remove(pool, options[math.random(#options)])
end

-- n prompts for a match: different categories each round when possible, no recent repeats
function PromptData.pickPrompts(n)
	local byList, total = available()
	if total < n then
		table.clear(recent)
		byList = available()
	end

	local picked, usedLists = {}, {}
	while #picked < n do
		local candidates = {}
		for id, pool in pairs(byList) do
			if #pool > 0 and not usedLists[id] then
				table.insert(candidates, id)
			end
		end

		if #candidates == 0 then
			if next(usedLists) == nil then
				break -- nothing left at all
			end
			usedLists = {} -- every category used once, allow repeats of categories
		else
			local id = candidates[math.random(#candidates)]
			usedLists[id] = true
			table.insert(picked, pickFrom(byList[id]))
		end
	end

	for _, p in ipairs(picked) do
		table.insert(recent, p)
		if #recent > RECENT_LIMIT then
			table.remove(recent, 1)
		end
	end
	return picked
end

return PromptData
