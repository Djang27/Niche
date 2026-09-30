# Niche — handoff

Written for whoever picks this up next, human or AI. `CLAUDE.md` is the living reference
(architecture, interfaces, rules); this file is the narrative: what happened, what went
wrong, and what not to repeat.

Last updated: 2026-09-29.

---

## Where things stand

Four games run on a shared shell: **Niche**, **Wavelength** (Solo / Teams / Co-op), and
**Deep Dive**. The shell owns the lobby, countdown, intro, scores, between-round recap and
podium; a mode owns only its round. Adding a game is one server module plus one client
module, no shell changes.

Everything is playable in Studio. The place is published to a Limited (friends) audience.
**There are still no real players**, which is what blocks the tier work.

---

## What got built, roughly in order

1. **Answer logging** to a DataStore — buffered in memory, batch-written. Records what
   players type, including rejections, so answer lists can be improved from evidence.
2. **The shell/mode split.** The biggest structural change. Done while there was only one
   game to migrate, which was far cheaper than retrofitting later.
3. **Menu → modes → lobby screens**, with an `InLobby` attribute so someone browsing the
   menu can't block a countdown.
4. **Wavelength**, all three variants, sharing a factory for the two rotating ones.
5. **Deep Dive**, the fourth game — later reworked to validate against the answer lists.
6. **Presentation**: running score strip, "waiting on N players", player-card reveals,
   match intro screen, between-round recap, a UI foundation pass and a repaint.
7. **The cosmetics entitlement seam** — catalogue, ownership gate, replication. No
   monetisation and no equip UI yet, deliberately.

---

## Problems we hit, and what they taught us

**Rojo wouldn't connect — "Can't parse JSON".** The Rojo client connecting was an old copy
bundled inside a third-party obfuscated plugin, not the official one. Rojo 7.7.0 serves
MessagePack and will not fall back to JSON, so an older client can never connect. *Use the
panel titled `Rojo 7.7.0`.* An obfuscated plugin with live access to a published place is
also worth a deliberate decision rather than an accidental one.

**Publishing failed repeatedly.** It was a platform-wide Roblox Studio outage, not the
project. *Check status.roblox.com before debugging your own code* — the symptom (a 4-minute
polling timeout, then "Internal server error") looks local but isn't.

**GitHub looked stale.** Work was committed but never pushed. Commits are local until
pushed; say so explicitly rather than letting someone discover it.

**Ties invented a winner.** Standings were built from a hash-ordered table and sorted with
a strict `>`, so tied players landed in arbitrary — and run-to-run different — order, and
position 1 got a medal regardless. Now ties share a rank and a medal.

**"asdf" scored points in Deep Dive.** Worse than missing validation: gibberish is
*guaranteed* unique, so typing nonsense was the optimal strategy. Fixed by validating
against the shared answer lists.

**2-player Wavelength Solo could only ever tie.** Both players scored identically every
round by construction. Fixed by requiring 3.

**The UI was unusable on a phone.** One root cause: `UiKit.panel` was hardcoded to 0.5 x
0.6 of the screen. Fixing the panel fixed every screen, because children are positioned in
scale units.

**A memory file was destroyed by `open(p,'w').write(open(p).read()...)`.** Python truncates
on open-for-write *before* the read runs. It reported success. Always read into a variable
first, or use a heredoc.

---

## Do not do these

- **Do not add `UIPadding` to panels.** Every child is absolutely positioned; padding
  shifts the entire UI. That is a layout migration, not a styling change.
- **Do not restore Deep Dive's old "normalisation only, never fuzzy" matching.** It is
  superseded by list validation. Edit-distance matching was rejected on purpose: "cat" and
  "bat" are one edit apart.
- **Do not set Wavelength Solo's `minPlayers` back to 2.** See above.
- **Do not add a tiebreaker.** Ties are shown as ties by choice.
- **Do not let a mode reach into another mode.** Anything two games need goes in `Shared/`.
- **Do not broadcast player-typed text without `Shared/TextFilter`.** Modes that only send
  canonical list entries are exempt; anything else is not.
- **Do not churn working, playtested code for performance wins too small to measure.** At
  4-12 players, per-tick table allocations are noise. What actually costs: DataStore quotas,
  TextService limits, per-tick work in `while true` loops.
- **Do not animate real avatars without costing it.** It needs a ViewportFrame, a loaded rig
  per player, and real emote asset IDs. On a phone that is the most expensive thing here.

---

## Do these

- **Gate commits behind a scripted check**, and check the thing most likely to drift rather
  than the thing you are confident about. Asserting on every edit anchor caught several
  silent mis-writes, including one where a doc edit failed while the code edit succeeded.
- **Say plainly that changes are untested.** Studio cannot be run from the agent side and
  there is no Luau toolchain, so everything ships unverified. End with what to playtest and
  what to look for in Output.
- **Clear player-keyed tables in `endMatch`, not just `playerLeft`** — the shell only calls
  `playerLeft` on the *active* mode, so an inactive one keeps pinning Player instances.
- **Anything positioned outside a panel must subscribe to `UiKit.onViewport`**, or it will
  overlap the panel on a phone.
- **Use the answer log instead of guessing.** Rejected answers are recorded; run
  `require(game.ServerScriptService.Shared.AnswerLog).report()` from the command bar
  (Server context) to see which real answers the lists are missing.

---

## What's next, and what each is waiting on

| Item | Blocked on |
|---|---|
| Grow the lists — depth (~200 entries; Jobs 140, Sports 116) and breadth (no pop culture at all) | Nothing. Pure data. |
| Playtest fixes and data-driven tiers | **Real players** generating answer-log data |
| ~~Equip UI / inventory~~ | **Done 2026-09-29** — locker off the menu, 12 banners, choices saved via `Shared/Profile.luau` |
| Ranked-lite (Elo, ranks, leaderboard) | Deferred: nobody to calibrate against. Co-op can never be ranked; Teams must be team-vs-team. |
| Deep Dive `minPlayers` | A decision. At 2 players almost nothing collides, so nearly everything scores. |

---

## Working on this

- Code lives in `src/`, synced into Studio by `rojo serve` plus the **official** Rojo plugin.
- **Multi-client testing is entirely local**: Test tab → Clients and Servers → 2-4 → Start.
  Publishing is only needed for other people to play.
- Player counts differ per game: Deep Dive 2, Co-op 2, Solo 3, Teams 4, Niche 1.
- Mobile is a supported target and is tested on a real phone.
