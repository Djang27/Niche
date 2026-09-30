# Niche — handoff

Written for whoever picks this up next, human or AI. `CLAUDE.md` is the living reference
(architecture, interfaces, rules); this file is the narrative: what happened, what went
wrong, and what not to repeat.

Last updated: 2026-09-29 (end of the economy/shop session).

---

## Where things stand

Four games run on a shared shell: **Niche**, **Wavelength** (Solo / Teams / Co-op), and
**Deep Dive**. The shell owns the lobby, countdown, intro, scores, between-round recap and
podium; a mode owns only its round. Adding a game is one server module plus one client
module, no shell changes.

All four games are playable in Studio and have been tested on desktop and on a phone. The
place is published to a Limited (friends) audience. **There are still no real players**,
which is what blocks the tier work.

**Start here tomorrow: the economy and the store have never been run.** Gold, gems, crates,
the shop screen and the opening reveal were all written and pushed in one session without a
single playtest — there is no Luau toolchain on the agent side, so they are syntax-checked
by a block-balance script and nothing more. Everything before them has been played. Assume
the store has bugs and playtest it first; the list of what to check is at the bottom of this
file.

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
7. **The cosmetics entitlement seam** — catalogue, ownership gate, replication.
8. **The locker** — 12 banners with rarities, a tab per cosmetic kind, a live avatar
   preview, and `Shared/Profile.luau`, the first thing here to persist anything about a
   person.
9. **The economy** — gold earned by finishing a match (10 for turning up, 40 more for a
   win, ties share first), gems bought with Robux, per-player ownership, all behind
   `Profile.transact`.
10. **The store** — three crates with published odds, a server-side roll, and a
    full-screen opening reveal. *Untested.*

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

## Before shipping anything paid

**`DEV_UNLOCK_ALL` in `src/server/Shared/Cosmetics.luau` is currently `true`.** It makes
`ownedBy` pass every item so the whole catalogue is wearable during development. Ship it
like that and the ownership gate is decorative — everyone gets everything. Each item keeps
its real `free` flag, so flipping the one constant restores the true lock states.

**`DEV_START_GOLD` (2000) and `DEV_START_GEMS` (200) in `src/server/Shared/Profile.luau`
are its twin.** A new profile starts rich so the shop can be opened on the first playtest
instead of after a dozen matches. Both must be `0` before anything is sold. They only ever
apply to a genuinely new profile, so setting them back does not take currency off anyone
who already has some.

**Crates deliberately ignore `DEV_UNLOCK_ALL`.** They roll against
`Cosmetics.trulyOwnedBy`, not `ownedBy`. If they honoured the override every crate pool
would read as fully owned and the shop could never sell anything while it is on. The
side effect during development: unboxing something does not visibly change the locker,
because the locker already shows everything as unlocked.

**Gems have no purchase path yet.** They exist, they can open crates, and nothing sells
them. That needs **Developer Products created by the owner** in Studio or on the website —
the numeric IDs cannot be invented or guessed, so this is blocked on him, not on code.
Until then the only gems in the game come from `DEV_START_GEMS`.

**Crates never give a duplicate.** The pool is unowned-only, and the sale is refused with
`"empty"` once a player owns everything in that crate. This is the reason there is no
duplicate-compensation rule to design or explain, and it is what keeps the published odds
literally true for every roll that actually happens. Adding duplicates back would mean
publishing a second set of numbers for what a duplicate is worth.

**The odds are on the crate card, not behind a link.** Gems are bought with Robux, so a
crate is a paid random item; see the rule in `CLAUDE.md`. Do not move the chances somewhere
that takes a tap to reach.

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
- **Do not aspect-constrain containers, only images.** Avatar thumbnails are square and need
  `UiKit.aspect`; a card or panel does not, and constraining one just leaves dead space beside it.
  That was a real regression in the locker preview.
- **Watch pixel minimums against scale slots.** `UiKit.button` carries a 38px minimum height for
  touch. On a short panel that can exceed the button's scale-sized slot and overlap whatever is
  below. Budget vertical space with real gaps, and check the arithmetic rather than eyeballing it.
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
| **Playtest the store** | Nothing. This is the next thing to do. See the checklist below. |
| Selling gems | **The owner** — Developer Products must be created in Studio/website; the numeric IDs cannot be guessed. |
| Grow the lists — depth (~200 entries; Jobs 140, Sports 116) and breadth (no pop culture at all) | Nothing. Pure data. |
| Playtest fixes and data-driven tiers | **Real players** generating answer-log data |
| ~~Equip UI / inventory~~ | **Done** — locker with a tab per cosmetic kind, 12 banners with rarities, live avatar preview, choices saved via `Shared/Profile.luau` |
| ~~An unlock path~~ | **Done** — crates. Every banner including the 3 Legendaries is now obtainable, so `ownedBy` does real work. |
| ~~Per-player ownership~~ | **Done** — `Profile`'s `owned` set, replicated per player via the `OwnedCosmetics` attribute. |
| More cosmetics worth owning | Nothing. 12 banners across 3 crates is thin — a Vault crate empties in a handful of opens. `RevealEffect` has 2 items that **nothing renders**, catalogued to prove the shape only; every crate sets `kinds = { "Banner" }` to keep them out of the pool, so do not widen that until something draws them. |
| Ranked-lite (Elo, ranks, leaderboard) | Deferred: nobody to calibrate against. Co-op can never be ranked; Teams must be team-vs-team. |
| Deep Dive `minPlayers` | **A decision from the owner.** At 2 players almost nothing collides, so nearly everything scores. Flagged four times now, never answered — either answer it or drop it. |
| Wavelength submenu order | A decision. It sorts by module name, so it reads Co-op / Solo / Teams. Offered an explicit order twice, no reply. Do not reorder unprompted. |

---

## Playtest the store first (none of it has run)

In Studio, press F5 and open **Store** from the menu.

1. **Three cards appear**, each with four chips reading Common / Rare / Epic / Legendary and
   a percentage. The Vault crate's Common chip should be dimmed at 0%.
2. **Buy with gold.** The swatch spins ~1.6s, slows, and lands on a banner with its rarity
   shown in that rarity's colour. Tap **Equip**, then open the Locker and check the preview
   is wearing it.
3. **Buy the Vault crate repeatedly.** Once all 12 banners are owned it must say *"You
   already own everything in this crate"* — and **no gold may be deducted** on that attempt.
   This is the path most likely to be wrong.
4. **Watch the wallet** top-right drop by the right amount after each buy, and the buttons
   grey out once you cannot afford them.
5. **On a phone:** the two price buttons must not overlap and the chip text must not clip.
   Only ~2 of the 3 cards fit without scrolling — that is expected, the list scrolls.
6. **Start a match while the reveal overlay is open.** It should close rather than sit on
   top of the game. That path is handled explicitly in `render()` because the overlay is not
   one of its screens.

In Output, look for a `[Crates]` odds warning at startup (there should be none) and
`[Profile] transaction failed`.

**If every purchase fails, check API access before debugging the code.** `Profile` only
falls back to in-memory mode when the place is *unpublished* (`GameId == 0`) or
`GetDataStore` itself throws. This place **is** published, so in Studio with *Enable Studio
Access to API Services* switched off, `GetDataStore` succeeds but `UpdateAsync` throws at
call time — `transact` catches it, warns `[Profile] transaction failed`, and the store shows
*"Something went wrong — nothing was charged"*. That is the correct behaviour (nothing is
charged), but it looks like a store bug. Turn API access on: Home → Game Settings →
Security.

---

## Working on this

- Code lives in `src/`, synced into Studio by `rojo serve` plus the **official** Rojo plugin.
- **Multi-client testing is entirely local**: Test tab → Clients and Servers → 2-4 → Start.
  Publishing is only needed for other people to play.
- Player counts differ per game: Deep Dive 2, Co-op 2, Solo 3, Teams 4, Niche 1.
- Mobile is a supported target and is tested on a real phone.
