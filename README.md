# SelfFound

A self-found challenge tracker for World of Warcraft. Play a character using only what you find, craft, or earn yourself — no trades, no mail, no auction house — and let other players with the addon see that your run is clean.

## Features

- **Self-found tracking** — a run starts automatically on a fresh level 1 character and is tracked for the life of that character.
- **Trade, mail and auction house detection** — completing a trade, taking items or gold mailed by another player, or buying from the auction house ends the run. Selling on the auction house and mail from NPCs are allowed. A warning appears first, so you can back out.
- **Peer verification** — players running the addon share their status with each other and report what they witness, so a run is not just your own word.
- **Guild, server-wide and solo modes** — talk only to your guild and party, join a hidden server-wide channel to see everyone, or turn sharing off and only track yourself.
- **Badge and panel UI** — a movable badge shows your status, level and played time; the panel lists guildmates or everyone seen, with their status.
- **Tooltips** — hover over a player to see their Self-Found status.
- **Settings** — show, hide or lock the badge, badge size, window size, warnings, alerts, alert sound, and network mode.

## Statuses

| Status | Meaning |
| --- | --- |
| **Self-Found** | Clean run, tracked since level 1. |
| **UNVERIFIED** | The addon was installed after the character had already been played. |
| **SUSPECT** | Something could not be confirmed, such as play time with the addon off, or one report from another player. |
| **BROKEN** | The run has ended: a trade, mail, auction purchase, edited save file, or reports from two or more players. |

A status can only get worse, never better.

## Slash commands

| Command | What it does |
| --- | --- |
| `/sf` | Open or close the player panel. |
| `/sf settings` | Open the settings. |
| `/sf reset` | Put the badge back in its default position. |
| `/sf list` | Print every known player and their status to chat. |

## Manual install

1. Download the latest zip from the Releases page (or from CurseForge).
2. Extract it. You should get a folder named exactly `SelfFound`.
3. Move that folder into your addons directory, for example:
   - Retail: `World of Warcraft\_retail_\Interface\AddOns\`
   - Classic Era: `World of Warcraft\_classic_era_\Interface\AddOns\`
   - Other clients: `<game folder>\Interface\AddOns\`
4. Restart the game, or type `/reload` if it was already running.
5. At the character select screen, check that SelfFound is enabled under AddOns.

The folder must be named `SelfFound`, with `SelfFound.toc` directly inside it.

## How verification works

1. **Signed save data.** Your status is saved with a signature. If the saved file is edited by hand, the signature no longer matches and the run is marked BROKEN.
2. **Played time check.** On login the addon compares the server's `/played` time with what it last recorded. Time going backwards means an old save was restored (BROKEN). A large unexplained gap means the character was played with the addon off (SUSPECT).
3. **Heartbeats.** Every five minutes, and whenever your status changes, your addon tells your guild, your group, and optionally the server-wide channel what your status is. Other players' addons remember the worst status they have seen for you, so reinstalling does not clear it for them.
4. **Witness reports.** When you trade with someone or send them mail with attachments, your addon reports it. One report marks that player SUSPECT; reports from two or more different players mark them BROKEN.
5. **Missing addon.** A guildmate who used the addon before and is now online without it for several minutes is marked SUSPECT.

## Limitations

SelfFound runs entirely on your own computer, and addons cannot be made cheat-proof. Please read this before relying on it:

- **It is client-side.** The code is readable Lua. Someone determined can edit the addon itself, and the save signature is obfuscation, not real security.
- **It only sees what happens while it is running.** Activity with the addon disabled shows up only as a gap in played time, which results in SUSPECT, not proof.
- **Peer reports need witnesses.** Verification is only as strong as the number of honest players around you running the addon. A solo player on a quiet server is mostly self-reported.
- **False reports are possible.** A single player can make you SUSPECT with a fake report. It takes two to mark you BROKEN, but two people working together can do that.
- **Crashes can look suspicious.** A game crash or disconnect can lose a little tracked time. There is a tolerance built in, but a long gap will still show as SUSPECT.
- **Mail detection is a best guess.** Mail is treated as coming from a player when it can be replied to. Unusual system mail could be misjudged either way.
- **Solo mode is unverified.** With sharing turned off, nobody else can confirm your run.
- **Records are local.** What your addon knows about other players is stored on your machine and is not shared between your accounts or computers.

Treat it as an honor system with extra eyes, not as an anti-cheat.

## License

MIT — see [LICENSE](LICENSE).
