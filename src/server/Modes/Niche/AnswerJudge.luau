-- ModuleScript: ServerScriptService > Modes > Niche > AnswerJudge

local PromptData = require(script.Parent.PromptData)

local AnswerJudge = {}

local PREFIX_MIN = 4 -- need at least this many letters for "vene" -> venezuela style suggestions

local function normalize(s)
	s = string.lower(s)
	s = s:gsub("^%s+", "")
	s = s:gsub("%s+$", "")
	s = s:gsub("%s+", " ")
	return s
end

-- how many typos we forgive, based on how long the typed answer is
local function maxTypos(len)
	if len < 3 then
		return 0
	elseif len <= 5 then
		return 1
	else
		return 2
	end
end

-- edit distance where a swapped pair of letters ("cron" vs "corn") counts as 1
local function editDistance(a, b)
	local la, lb = #a, #b
	if math.abs(la - lb) > 2 then
		return 99
	end
	local d = {}
	for i = 0, la do
		d[i] = { [0] = i }
	end
	for j = 0, lb do
		d[0][j] = j
	end
	for i = 1, la do
		for j = 1, lb do
			local cost = (a:sub(i, i) == b:sub(j, j)) and 0 or 1
			d[i][j] = math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
			if i > 1 and j > 1 and a:sub(i, i) == b:sub(j - 1, j - 1) and a:sub(i - 1, i - 1) == b:sub(j, j) then
				d[i][j] = math.min(d[i][j], d[i - 2][j - 2] + 1)
			end
		end
	end
	return d[la][lb]
end

-- exact lookup (with aliases + simple plurals). returns canonical answer or nil
local function exactMatch(prompt, answer)
	if prompt.aliases and prompt.aliases[answer] then
		answer = prompt.aliases[answer]
	end
	if prompt.answers[answer] then
		return answer
	end
	if answer:sub(-1) == "s" and prompt.answers[answer:sub(1, -2)] then
		return answer:sub(1, -2)
	end
	return nil
end

-- every accepted spelling paired with the answer it points to
local function allSpellings(prompt)
	local list = {}
	for ans in pairs(prompt.answers) do
		table.insert(list, { ans, ans })
	end
	if prompt.aliases then
		for alias, canon in pairs(prompt.aliases) do
			table.insert(list, { alias, canon })
		end
	end
	return list
end

local function findSuggestion(prompt, answer)
	local spellings = allSpellings(prompt)

	-- 1) unfinished word: "vene" -> venezuela, only if exactly one answer fits
	if #answer >= PREFIX_MIN then
		local found = nil
		for _, s in ipairs(spellings) do
			if s[1]:sub(1, #answer) == answer then
				if found and found ~= s[2] then
					found = false -- more than one answer starts like this, too ambiguous
					break
				end
				found = s[2]
			end
		end
		if found then
			return found
		end
	end

	-- 2) typo: closest answer within the allowed number of mistakes
	local best, bestDist = nil, maxTypos(#answer) + 1
	for _, s in ipairs(spellings) do
		local dist = editDistance(answer, s[1])
		if dist < bestDist then
			best, bestDist = s[2], dist
		end
	end
	return best
end

-- "buddha's hand" -> "Buddha's Hand"
function AnswerJudge.prettify(s)
	return (s:gsub("(%a)([%w']*)", function(first, rest)
		return first:upper() .. rest
	end))
end

-- returns status, canonicalAnswer, displayText
-- status is "valid", "suggest", or "invalid"
function AnswerJudge.check(prompt, raw)
	local answer = normalize(raw)
	if answer == "" then
		return "invalid"
	end

	local exact = exactMatch(prompt, answer)
	if exact then
		return "valid", exact, AnswerJudge.prettify(exact)
	end

	local suggestion = findSuggestion(prompt, answer)
	if suggestion then
		return "suggest", suggestion, AnswerJudge.prettify(suggestion)
	end

	return "invalid"
end

-- returns canonicalAnswer, tierName, points (only exact matches score)
function AnswerJudge.judge(prompt, raw)
	local answer = exactMatch(prompt, normalize(raw))
	if not answer then
		return nil, nil, 0
	end
	local tier = prompt.answers[answer]
	return answer, tier, PromptData.Tiers[tier]
end

return AnswerJudge
