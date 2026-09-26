# Niche (Roblox game) - context for Claude Code

## What the game is
Multiplayer party game. Each round shows a prompt ("Name a fruit", "Name a country in Africa",
"Name an animal starting with P"). Players type an answer; rarer answers score more:
Common 10, Rare 30, SuperRare 60, Epic 80, Legendary 100. If two players give the same answer,
both get half points. Highest total after the match wins.

Menu-based game: no characters spawn (Players.CharacterAutoLoads = false), all UI is built in code.

Niche is a collection of party games sharing one lobby, so the code is split into a shell and
swappable modes. "Niche" is both the place name and the name of the first mode. Wavelength is built
(Solo / Teams / Co-op); a "say words related to a topic" game is still planned.

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
- `Shared/TextFilter.luau`: TextService wrapper for any player-typed text other players will see.
  `forBroadcast(text, fromUserId)`, `forUser(text, fromUserId, toUserId)`, `forViewers(text, fromUserId, viewers)`.
  Require from a mode as `require(script.Parent.Parent.Shared.TextFilter)`.
- `Shared/Wavelength.luau`: rules every Wavelength mode agrees on - `score(distance)` proximity bands,
  `newTarget()`, `cleanClue(text, maxLen)`, `orderedPlayers(ctx)` - plus `newRotatingMode(config)`, the
  factory Solo and Co-op are both built from. Those two run an identical round (one clue giver,
  everyone else guessing, the giver rotating) and differ only in who banks the points
  (`shared = true` pays the whole room), so neither is a copy. Round count is derived, not fixed:
  `players * rotations`, capped at 10. Teams has a different flow and writes its own round.
- `Shared/Spectrums.luau`: Wavelength dial content, pairs of opposed labels, plus `pick(n)` with
  no-repeat memory. Server only, like the answer lists. A dial may carry `onlyWith = { ... }` naming
  the categories it can sort; most dials sort anything and leave it off. That pairing is what stops
  "Salty <-> Sweet" being offered beside Vehicles, where the clue giver has no usable option at all.
  Startup warns if an `onlyWith` names an unknown category or lists fewer than the 3 offered.
- `Shared/Categories.luau`: broad subject areas (Food, Sports, Movies...) plus `pickFor(spectrum, n)`,
  which respects a dial's `onlyWith`, and a whole-pool `pick(n)`. Three are offered each Wavelength
  round and the clue giver takes one, which is what stops the clue being about anything in existence.
  Entries must be broad AND placeable on almost any dial - Weather, Holidays and School subjects were
  removed for failing the second test. A subject that only suits a couple of dials belongs in those
  dials' `onlyWith`, not in this pool.
- The Wavelength round, common to all three variants: a hidden target sits on a dial. The clue giver
  alone is sent it via `ctx.sendTo`, picks one of 3 random categories, and writes a clue, which is
  filtered before anyone else sees it. Guessers drag a marker; points come from how close it lands.
  Picking the category is folded into the clue step so rounds don't grow a phase.
- `Modes/WavelengthSolo/init.luau`: competitive rotating pairs - one clue giver, one guesser, both
  scoring the same, everyone else watching. A ~20-line config over `newPairMode`. 3-4 players; the
  minimum is 3 *on purpose*, because at 2 the pair is the same two people every round scoring
  identically, so the match could only ever end in a tie. Do not "fix" that back to 2.
- `Modes/WavelengthCoop/init.luau`: the same rotating-pair round, but one score for the whole room and
  a `matchSummary` reporting the total instead of a winner. 2-4 players, and the honest home for two.
- `Modes/WavelengthTeams/init.luau`: two teams play the same dial at once, each with its own hidden
  target and its own clue giver. **Every clue goes out via `ctx.sendTo`, never `ctx.send`** - one
  stray broadcast during the clue or guess phase hands the other team the answer, so the reveal is the
  only public message in the file. Each round every member of a team banks the team's points, which is
  what makes the shell's per-player standings already read as team standings. 4+ players.

src/client/ (-> StarterPlayer.StarterPlayerScripts)
- `GameUI.client.luau`: the shell's UI. Screens are menu -> modes -> lobby -> the active mode's own
  screen -> podium, switched by polling attributes every 0.2s. Menu/modes/lobby are *local* navigation
  (each player browses independently); a match the player is in overrides it. Builds every mode in
  `Modes/` at startup and shows only the active one's frame. The modes screen lists playable games
  first, then greyed-out entries from its `PLANNED` list - a planned name drops off automatically once
  a real module with that name exists.
- `UiKit.luau`: shared make/panel/label/button/escape helpers and the colour palette.
- `Modes/<Name>.luau`: one game's screen, client side. See the mode interface below.
- `WavelengthDial.luau`: the dial screen shared by Solo and Co-op, as `new(config)`. Each call builds
  its own widgets and its own state, so the two modes never tread on each other. They render an
  identical round and differ only in how the reveal is worded.
- `Modes/WavelengthSolo.luau` and `Modes/WavelengthCoop.luau`: thin wrappers - `WavelengthDial.new`
  plus name/blurb/group/variant.
- `Modes/WavelengthTeams.luau`: its own screen. Same dial, but you only ever see your own team's clue;
  the other team's target, clue and guesses appear only at the reveal, colour coded per team.

## Mode interface
Adding a game = one server module + one client module. No shell changes.

Server, `src/server/Modes/<Name>/init.luau` returns:
  { name, blurb, minPlayers, maxPlayers, rounds,
    beginMatch(ctx), runRound(ctx, round), endMatch(), playerLeft(ctx, player),
    matchSummary(ctx) -> string, onEvent(ctx, player, kind, ...), onRequest(ctx, player, kind, ...) }
`matchSummary` is optional and adds one line to the podium for whatever the per-player standings
can't express - which team won, a co-op total. Return nil or omit it for a normal ranked podium.

Ties are shown as ties, never broken. The shell sorts by score then name so the order is stable,
and the podium takes each row's rank from its score, so equal scores share a place and a medal
(1, 1, 3). There is deliberately no tiebreaker: inventing a winner out of hash order was the bug
this replaced.
Only `runRound` is required. `ctx` gives the mode: `players()`, `isPlaying(p)`, `send(kind, ...)`,
`sendTo(player, kind, ...)` (for per-player secrets, e.g. Wavelength's target), `award(player, points)`,
`scoreOf(player)`, `waitUntil(seconds, predicate)`, and `rounds` (a mode may shorten it in `beginMatch`).

`maxPlayers` caps a mode: the countdown refuses to start above it rather than quietly leaving
someone out, and the lobby says so. Omit it for no cap.

Client, `src/client/Modes/<Name>.luau` returns:
  { name, blurb, group, variant, hideStandings, build(parent, api) -> frame, onEvent(kind, ...), reset() }
`hideStandings` suppresses the ranked list on the podium, leaving the `matchSummary` line as the
whole result. Set it when ranking individuals is meaningless - Co-op, where every player finishes
on the same score by construction.
`group` and `variant` are optional: modes sharing a `group` collapse into one button on the modes
screen that opens a submenu of their `variant` names (Wavelength -> Solo / Teams / Co-op). A mode with
no group gets its own grid button.
`build` returns the frame the shell shows/hides; `api.send(kind, ...)` and `api.request(kind, ...)`
reach the server half. The shell calls `reset()` when a match ends.

## State the client reads (attributes)
- ReplicatedStorage: `GameState` ("Lobby" | "Countdown" | "InMatch" | "Podium"), `Countdown`, `HostUserId`,
  `ActiveMode` (module name of the mode currently loaded, e.g. "Niche")
- Each Player: `Ready`, `InMatch`, `InLobby` (client-reported: is this player sitting in the lobby
  rather than browsing the menu or store). Only `InLobby` players count towards starting a match and
  only they get pulled into one, so an idle player on the menu can never block a countdown.
- `ReplicatedStorage.AvailableModes`: one StringValue per loadable mode (Name = module name,
  Value = display name, attributes `MinPlayers` and `MaxPlayers`, where 0 means no cap). The client
  builds the modes screen from this intersected with the modes it has screens for, so nothing is
  hardcoded per game.

## Remotes (ReplicatedStorage.Remotes)
All shell-owned and mode-agnostic. Modes never create their own remotes.
- RemoteEvent `LobbyAction`: client -> server, actions "ready", "unready", "start", "playAgain", "toLobby",
  "setMode" (second arg is a mode id; host only, lobby only), and "inLobby" (second arg is a boolean;
  leaving the lobby also clears Ready)
- RemoteEvent `MatchOver`: server -> client, final standings plus the optional `matchSummary` line
- RemoteEvent `ModeEvent`: both directions, first arg is a kind string the active mode defines
- RemoteFunction `ModeRequest`: client asks the active mode something, first arg is a kind string

Niche's kinds: "prompt" and "results" (server -> client), "submit" (client -> server), and "check" on
ModeRequest (returns status, canonicalAnswer, displayText; status is valid | suggest | invalid | slow | closed).

Wavelength's kinds: "round", "target" (clue giver only), "clue" and "reveal" (server -> client), plus
"clue" and "guess" (client -> server). Teams sends table payloads because its messages carry more
fields; Solo and Co-op send positional arguments.

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
- Any player-typed text that another player will see must go through `Shared/TextFilter.luau` first.
  Niche is exempt only because it broadcasts canonical answers from its own lists, never what was typed.
  The moment a mode shows one player what another player wrote (Wavelength clues, related-words answers),
  it goes through TextFilter. Those functions never return the original string - they mask it on failure -
  so never "fall back" to the raw text when filtering errors.
- Modes never create remotes, touch scores directly, or reach into the shell: everything goes through
  `ctx` and ModeEvent / ModeRequest. Keeping that boundary is what makes adding a game cheap.
- Never sell anything that affects scoring (future monetization is cosmetic / host controls only).
- Keep tunables as constants at the top of files (timers, rounds, MIN_PLAYERS, etc).

## Roadmap (rough order)
Done: answer logging to DataStore; the shell/mode split; `Shared/TextFilter.luau`; the
menu -> modes -> lobby screens; all three Wavelength variants (Solo / Teams / Co-op) with category
picks, the mode-group submenu, and the `matchSummary` podium hook.
The planned games below are provisional - the owner expects to swap them out and add others, so
nothing should hardcode a specific game outside its own module.
1. Playtest fixes (tiers, missing answers/aliases) - use `AnswerLog.report()` to find them. Blocked on
   real players generating data, not on code.
2. Data-driven tiers from real answer frequency. Same blocker as 1.
3. "Say words related to a topic" mode. Blocked on a design answer first: how to match free-form words
   across players with no canonical list ("dog" vs "dogs" vs "Dog").
4. Ranked-lite: rating per player (pairwise Elo scaled by opponent count), ranks in lobby, global leaderboard.
   Private servers and matches under 3 players do not count. The first item here that is genuinely
   unblocked and could just be built.
5. Real ranked queue (MemoryStoreService + TeleportService) only once concurrent players can support it
6. Cosmetic passes: Legendary reveal effects, Party Host pass (custom lobby settings, non-ranked only)

Open and undecided: the Wavelength submenu sorts by module name, so it reads Co-op / Solo / Teams.
The owner has been told and has not asked for an explicit order - don't reorder unprompted. Two `???`
placeholder slots remain on the modes grid for a fourth game.
