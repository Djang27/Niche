# Niche (Roblox game) - context for Claude Code

## What the game is
Multiplayer party game. Each round shows a prompt ("Name a fruit", "Name a country in Africa",
"Name an animal starting with P"). Players type an answer; rarer answers score more:
Common 10, Rare 30, SuperRare 60, Epic 80, Legendary 100. If two players give the same answer,
both get half points. Highest total after the match wins.

Menu-based game: no characters spawn (Players.CharacterAutoLoads = false), all UI is built in code.

Niche is becoming a collection of party games sharing one lobby (Wavelength and a "say words related
to a topic" game are planned), so the code is split into a shell and swappable modes. "Niche" is both
the place name and the name of the first mode.

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
- `RoundManager.server.luau`: the shell. Lobby -> Countdown -> InMatch -> Podium -> Lobby. Creates every
  remote, loads each mode in `Modes/`, runs the active one, owns scores/standings/podium. Knows nothing
  about prompts or answers. The whole match runs inside a pcall: an error drops back to the lobby rather
  than hanging the server forever.
- `Modes/<Name>/init.luau`: one game, server side. See the mode interface below.
- `Modes/Niche/PromptData.luau`: builds every prompt at startup from the modules in `Lists/`, and `pickPrompts(n)`
  (different category per round when possible, letter prompts ~35%, no repeats within the last 20 on a server).
- `Modes/Niche/AnswerJudge.luau`: normalizes answers, exact match (aliases + simple plurals), suggestions
  (unique 4+ letter prefix, or typo within edit distance 1 for 3-5 letters / 2 for 6+), scoring.
- `Modes/Niche/AnswerLog.luau`: counts what players type, buffered in memory and batch-written to a
  DataStore every 2 min and on shutdown. Read it from the command bar (Server context) with
  `require(game.ServerScriptService.Modes.Niche.AnswerLog).report()`. Owner-only diagnostics: the
  rejected bucket is raw player text and must never reach a client unfiltered.
- `Modes/Niche/Lists/*.luau`: one module per category. Pure data.

src/client/ (-> StarterPlayer.StarterPlayerScripts)
- `GameUI.client.luau`: the shell's UI. Lobby and podium screens plus screen switching (polls attributes
  every 0.2s). Builds every mode in `Modes/` at startup and shows only the active one's frame.
- `UiKit.luau`: shared make/panel/label/button/escape helpers and the colour palette.
- `Modes/<Name>.luau`: one game's screen, client side. See the mode interface below.

## Mode interface
Adding a game = one server module + one client module. No shell changes.

Server, `src/server/Modes/<Name>/init.luau` returns:
  { name, blurb, minPlayers, rounds,
    beginMatch(ctx), runRound(ctx, round), endMatch(), playerLeft(ctx, player),
    onEvent(ctx, player, kind, ...), onRequest(ctx, player, kind, ...) }
Only `runRound` is required. `ctx` gives the mode: `players()`, `isPlaying(p)`, `send(kind, ...)`,
`sendTo(player, kind, ...)` (for per-player secrets, e.g. Wavelength's target), `award(player, points)`,
`scoreOf(player)`, `waitUntil(seconds, predicate)`, and `rounds` (a mode may shorten it in `beginMatch`).

Client, `src/client/Modes/<Name>.luau` returns:
  { name, blurb, build(parent, api) -> frame, onEvent(kind, ...), reset() }
`build` returns the frame the shell shows/hides; `api.send(kind, ...)` and `api.request(kind, ...)`
reach the server half. The shell calls `reset()` when a match ends.

## State the client reads (attributes)
- ReplicatedStorage: `GameState` ("Lobby" | "Countdown" | "InMatch" | "Podium"), `Countdown`, `HostUserId`,
  `ActiveMode` (module name of the mode currently loaded, e.g. "Niche")
- Each Player: `Ready`, `InMatch`
- `ReplicatedStorage.AvailableModes`: one StringValue per loadable mode (Name = module name,
  Value = display name, attribute `MinPlayers`). The client builds the lobby's game picker from
  this intersected with the modes it has screens for, so nothing is hardcoded per game.

## Remotes (ReplicatedStorage.Remotes)
All shell-owned and mode-agnostic. Modes never create their own remotes.
- RemoteEvent `LobbyAction`: client -> server, actions "ready", "unready", "start", "playAgain", "toLobby",
  and "setMode" (second arg is a mode id; host only, lobby only)
- RemoteEvent `MatchOver`: server -> client, final standings
- RemoteEvent `ModeEvent`: both directions, first arg is a kind string the active mode defines
- RemoteFunction `ModeRequest`: client asks the active mode something, first arg is a kind string

Niche's kinds: "prompt" and "results" (server -> client), "submit" (client -> server), and "check" on
ModeRequest (returns status, canonicalAnswer, displayText; status is valid | suggest | invalid | slow | closed).

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
  If any free-form player text is ever broadcast, it must go through TextService filtering. Both planned
  modes broadcast free-form text (Wavelength clues, related-words answers), so a `TextFilter` module is a
  hard prerequisite for either one, not a polish item.
- Modes never create remotes, touch scores directly, or reach into the shell: everything goes through
  `ctx` and ModeEvent / ModeRequest. Keeping that boundary is what makes adding a game cheap.
- Never sell anything that affects scoring (future monetization is cosmetic / host controls only).
- Keep tunables as constants at the top of files (timers, rounds, MIN_PLAYERS, etc).

## Roadmap (rough order)
Done: answer logging to DataStore; the shell/mode split; lobby mode picker.
The planned games below are provisional - the owner expects to swap them out and add others, so
nothing should hardcode a specific game outside its own module.
1. Playtest fixes (tiers, missing answers/aliases) - use `AnswerLog.report()` to find them
2. `TextFilter` module wrapping TextService:FilterStringAsync (see Rules to keep)
4. Wavelength as the second mode. Built before the related-words game on purpose: asymmetric roles,
   two-phase rounds and slider input stress-test the mode interface hardest, and its scoring is simpler.
5. Data-driven tiers from real answer frequency
6. "Say words related to a topic" mode. Blocked on a design answer first: how to match free-form words
   across players with no canonical list ("dog" vs "dogs" vs "Dog").
7. Ranked-lite: rating per player (pairwise Elo scaled by opponent count), ranks in lobby, global leaderboard.
   Private servers and matches under 3 players do not count.
8. Real ranked queue (MemoryStoreService + TeleportService) only once concurrent players can support it
9. Cosmetic passes: Legendary reveal effects, Party Host pass (custom lobby settings, non-ranked only)
