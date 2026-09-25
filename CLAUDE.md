# Niche (Roblox game) - context for Claude Code

## What the game is
Multiplayer party game. Each round shows a prompt ("Name a fruit", "Name a country in Africa",
"Name an animal starting with P"). Players type an answer; rarer answers score more:
Common 10, Rare 30, SuperRare 60, Epic 80, Legendary 100. If two players give the same answer,
both get half points. Highest total after the match wins.

Menu-based game: no characters spawn (Players.CharacterAutoLoads = false), all UI is built in code.

## Workflow
- Code lives in `src/`, synced into Roblox Studio live by Rojo (`rojo serve` + Rojo plugin connected).
- Language is Luau. Files: `*.server.luau` = Script, `*.client.luau` = LocalScript, plain `*.luau` = ModuleScript.
  Instance name = file name without the suffix (so `PromptData.luau` -> ModuleScript "PromptData"). Names are case sensitive.
- The owner tests in Studio with Play (F5) or multi-client test (2+ players). Claude cannot run Studio,
  so after changes, say exactly what to test and what to look for in Output.
- The owner is newer to Roblox dev: explain Studio-side steps plainly when a change needs them.
- Publishing happens from Studio (File > Publish to Roblox). The game is currently in Limited (friends) audience.

## File map
src/server/ (-> ServerScriptService)
- `RoundManager.server.luau`: main server loop and state machine. Lobby -> Countdown -> InMatch -> Podium -> Lobby.
  Creates all remotes in ReplicatedStorage.Remotes. Handles ready-up, host start, answer checking, scoring.
- `PromptData.luau`: builds every prompt at startup from the modules in `Lists/`, and `pickPrompts(n)`
  (different category per round when possible, letter prompts ~35%, no repeats within the last 20 on a server).
- `AnswerJudge.luau`: normalizes answers, exact match (aliases + simple plurals), suggestions
  (unique 4+ letter prefix, or typo within edit distance 1 for 3-5 letters / 2 for 6+), scoring.
- `Lists/*.luau`: one module per category. Pure data.

src/client/ (-> StarterPlayer.StarterPlayerScripts)
- `GameUI.client.luau`: builds all UI in code. Three screens (lobby, game, podium). Screen switching polls state
  every 0.2s from attributes. Answer flow: Enter -> CheckAnswer (RemoteFunction) -> valid submits,
  suggestion shows "Did you mean X?" and Enter again confirms, invalid shows "Not an answer".

## State the client reads (attributes)
- ReplicatedStorage: `GameState` ("Lobby" | "Countdown" | "InMatch" | "Podium"), `Countdown`, `HostUserId`
- Each Player: `Ready`, `InMatch`

## Remotes (ReplicatedStorage.Remotes)
- RemoteEvents: NewPrompt, SubmitAnswer, RoundResults, MatchOver, LobbyAction
  (LobbyAction actions: "ready", "unready", "start", "playAgain", "toLobby")
- RemoteFunction: CheckAnswer (returns status, canonicalAnswer, displayText; status is valid | suggest | invalid | slow | closed)

## List format
```lua
return {
  noun = "a country",          -- used for auto letter prompts
  letterPrompts = true,        -- auto "Name a country starting with X" for letters with 8+ answers
  prompts = {
    { text = "Name a country" },                          -- all items
    { text = "Name a country in Africa", tag = "africa" } -- only items with that tag
  },
  items = {
    { name = "egypt", tier = "Rare", tags = { "africa" }, tierIn = { africa = "Common" }, aliases = { "misr" } },
  },
}
```
- `name` is the canonical answer, lowercase. Results display it title-cased, so prefer full names
  ("united states" with alias "usa", not the reverse).
- `tierIn` overrides the tier inside one tagged prompt.
- Prompts with fewer than 8 possible answers are skipped with a warning.
- Adding a category = adding a new module in `Lists/`. No other code changes needed.

## Rules to keep
- Server authoritative. Answer lists stay on the server (never in ReplicatedStorage). The server re-validates every
  submission; never trust the client for scores or answers.
- Only canonical list answers are ever shown to other players, so no text filtering is needed today.
  If any free-form player text is ever broadcast, it must go through TextService filtering.
- Never sell anything that affects scoring (future monetization is cosmetic / host controls only).
- Keep tunables as constants at the top of files (timers, rounds, MIN_PLAYERS, etc).

## Roadmap (rough order)
1. Playtest fixes (tiers, missing answers/aliases)
2. Answer logging to DataStore (what people type, including rejected answers)
3. Data-driven tiers from real answer frequency
4. Round modifiers (double points, Epic+ only, speed round)
5. Ranked-lite: rating per player (pairwise Elo scaled by opponent count), ranks in lobby, global leaderboard.
   Private servers and matches under 3 players do not count.
6. Real ranked queue (MemoryStoreService + TeleportService) only once concurrent players can support it
7. Cosmetic passes: Legendary reveal effects, Party Host pass (custom lobby settings, non-ranked only)
