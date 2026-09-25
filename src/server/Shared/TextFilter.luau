-- ModuleScript: ServerScriptService > Shared > TextFilter
--
-- Wraps TextService so free-form player text can safely be shown to other players.
-- Roblox requires this for anything a player typed that other people will see: Wavelength
-- clues, related-words answers, custom names. Niche itself does not need it, because it
-- only ever broadcasts canonical answers that came from its own lists.
--
-- Require it from a mode with:
--   local TextFilter = require(script.Parent.Parent.Shared.TextFilter)
--
-- The one rule these functions enforce: they never return the original string. If filtering
-- fails for any reason the caller gets a mask instead, because quietly falling back to raw
-- player text is the only outcome here that is actually dangerous.

local TextService = game:GetService("TextService")

local TextFilter = {}

local MASK = "[filtered]"

-- FilterStringAsync is rate limited per server, so filter once per thing a player submits.
-- Never per keystroke, and never in a loop over the words of a long answer: if a mode needs
-- many short strings from one player, join them and filter the joined string once.

local function filterOnce(text, fromUserId)
	local ok, result = pcall(function()
		return TextService:FilterStringAsync(text, fromUserId, Enum.TextFilterContext.PublicChat)
	end)
	if not ok then
		warn(("[TextFilter] FilterStringAsync failed: %s"):format(tostring(result)))
		return nil
	end
	return result
end

local function render(result, fn, label)
	if not result then
		return MASK, false
	end
	local ok, safe = pcall(fn, result)
	if not ok or typeof(safe) ~= "string" then
		warn(("[TextFilter] %s failed: %s"):format(label, tostring(safe)))
		return MASK, false
	end
	return safe, true
end

-- Text safe to show to everyone. Returns safeText, ok.
-- `ok` is false when the text had to be masked, so a caller can say "clue unavailable"
-- rather than showing "[filtered]" as if the player typed it.
function TextFilter.forBroadcast(text, fromUserId)
	if typeof(text) ~= "string" or text == "" then
		return "", true
	end
	return render(filterOnce(text, fromUserId), function(result)
		return result:GetNonChatStringForBroadcastAsync()
	end, "GetNonChatStringForBroadcastAsync")
end

-- Text safe to show to one specific player. Filtering is per viewer (age, settings,
-- whether the two are friends), so the same text can render differently for each person.
function TextFilter.forUser(text, fromUserId, toUserId)
	if typeof(text) ~= "string" or text == "" then
		return "", true
	end
	return render(filterOnce(text, fromUserId), function(result)
		return result:GetNonChatStringForUserAsync(toUserId)
	end, "GetNonChatStringForUserAsync")
end

-- Per-viewer text for a whole group, filtering once instead of once per viewer.
-- Use this rather than calling forUser in a loop, which would burn the rate limit.
-- Returns a [player] = safeText map.
function TextFilter.forViewers(text, fromUserId, viewers)
	local out = {}
	if typeof(text) ~= "string" or text == "" then
		for _, viewer in ipairs(viewers) do
			out[viewer] = ""
		end
		return out
	end

	local result = filterOnce(text, fromUserId)
	for _, viewer in ipairs(viewers) do
		out[viewer] = (render(result, function(r)
			return r:GetNonChatStringForUserAsync(viewer.UserId)
		end, "GetNonChatStringForUserAsync"))
	end
	return out
end

return TextFilter
