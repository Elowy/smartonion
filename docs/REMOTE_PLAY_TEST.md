# Remote Play Together: manual test checklist

This checklist is for the owner, who runs the Steam side on real hardware. The automated tests cover the game
logic with fake pads and a fake Steam singleton; they cannot show what Steam itself does. Work through the checks
in order: first with one guest, then with two. Record the result of every number.

Design background: GDD chapter 11 ("Online co-op (Remote Play Together)") and ARCHITECTURE, chapter "Remote Play
Together". The Steam layer is optional: without it the game plays exactly as local co-op.

## Prerequisites

1. **A Steamworks app** with its real app id, with **Remote Play Together** enabled: Store page admin → Basic Info →
   Features → tick *Remote Play Together*. Until the store page is live, use a password-protected Steam Remote Play
   branch (Application → Steam Remote Play). Each session then needs a fresh invitation from the developer account,
   and the test machines need a Steam client from 23 May 2020 or newer.
2. **Steam Input** for the app: Application → Steam Input → opt in the controller types you test with (Valve
   recommends all types except Xbox for a game with native Xbox support), and pick a premade template (Gamepad).
   Guests' pads reach the game as Steam Input virtual Xbox pads. With Steam Input switched off for the app, they may
   not appear at all.
3. **The real app id in the project.** Set `smartonion/steam/app_id` in `project.godot` to the registered id. The
   default 480 is Valve's test app (Spacewar): it only proves that the plug-in loads and Steam starts.
4. **The GodotSteam plug-in.** In your checkout, run `tools/steam/fetch_godotsteam.sh` (it fetches the Windows 64-bit
   and Linux 64-bit libraries, about 18 MB into `addons/godotsteam/`), then run `godot --headless --path . --import`
   once. The folder is gitignored; do not commit it.
5. **Export** with `tools/build/install_templates.sh` (once) and `tools/build/export.sh --steam` (it also runs step 4).
   The builds land in `build/steam/content/windows/` and `build/steam/content/linux/`, with the GodotSteam libraries
   (`libgodotsteam.*`) and Valve's Steamworks library (`steam_api64.dll` on Windows, `libsteam_api.so` on Linux) next to
   the executable; they must ship in the same folder in the Steam depot (`tools/steam/upload.sh` checks it). See
   `docs/STEAM_RELEASE.md`.
6. **Launch through Steam.** Start the game from your Steam library, with the Steam client running. Started from the
   Godot editor, from a terminal, or by double-clicking the executable, guests' pads may not appear: a guest then
   connects, but no pad shows up on the host.
7. **A second device for each guest:** a phone with the Steam Link app (*Invite Anyone* needs no Steam account), or a
   second PC with the Steam client or Steam Link. Host plus three guests is four players, the maximum.

## Inviting a guest

- In the lobby, press **L3** (keyboard: **I**). The footer offers "Invite friends" once somebody has joined. It opens
  the Steam Remote Play Together panel: pick the friend and invite them. For a link guest, use *Copy link* (Invite
  Anyone) and open the link on the phone or the second PC.
- Or use the Steam overlay: Shift+Tab → Friends → the friend → Remote Play Together.
- Keyboard and mouse sharing: the host may share the host's keyboard and mouse with a guest in the overlay. Leave
  sharing **off** for checks 1 to 10. Then repeat check 2 once with it **on**.

## Checks

Each check says what to do and what to expect. Record pass, fail or not done, and for a failure, the number, what the
screen showed, and what you expected.

1. **Each pad appears once.** The host's pad is connected; then a guest connects a pad. Expect the lobby to show the
   host's pad once and the guest's pad once: none missing, none doubled. The guest presses A and joins as the next
   player. The card header reads "Remote · *name*", where *name* is the guest's Steam name, or "Remote · Guest N" for a
   link guest without a Steam account. A "Guest N" that changes to the real name within a few seconds is expected;
   report one that does not.

2. **Playing.** The guest moves, aims and uses abilities with their own pad. Expect each hero to respond only to its
   own pad: the guest's presses do not move the host's hero, and the host's pad does not move the guest's hero. The
   guest may notice streaming lag; the host should notice none. Then repeat with keyboard and mouse sharing **on**.
   Expect no new player to appear for the shared keyboard or mouse: their input acts as the host's (a known limit).

3. **Guest leaves in the lobby.** Close the guest's Steam Link (or disconnect the pad). Expect the guest's card to stay
   with the header "Disconnected" and the banner "Press A to take over", and the countdown not to run. Reconnect the
   guest. Expect the card to return to normal by itself, with the same hero, class and ready state. If it does not
   return by itself, press A on another free controller: it takes the seat over. Separately, leave the guest away for
   more than a minute with nobody taking the seat over: expect the seat to be freed.

4. **Guest leaves mid-wave.** During a wave, the guest closes Steam Link. Expect:
   - the game pauses at once;
   - the HUD names the guest, e.g. "Mira (P3) disconnected – waiting for them to come back";
   - the pause menu says to press A on any free controller to take over, or to wait for the guest;
   - START does not resume the game while the guest is missing.

   Reconnect the guest. Expect the notice to clear, the pad to return, and START to resume the game.

   Repeat the drop during the market, a loot roll, a level-up and a shrine or dungeon-portal vote. Expect the screen to
   show "Reconnecting…" for the guest and to wait about 5 seconds before it decides for them. If the guest returns
   within those seconds, the screen carries on with their choices. If they stay away longer, the screen decides for
   them (auto-ready, auto-pick, vote by the data, or abstain) and carries on without them. Also expect the next wave
   to pause at once if someone is missing when it starts.

5. **Take-over by another pad.** While a guest is missing during a run, a different guest, or the host's second pad,
   presses A. Expect that pad to take over the missing player's hero: same class, level, gear and ready state, and the
   notice clears. START then resumes the game. If the first guest returns afterwards, expect them to be a free pad
   now: during a wave, their A shows "Joins at the next lobby", and their pad does not take the hero back.

6. **A guest cannot quit or drop players.** With a guest connected, use the guest's pad:
   - main menu → Quit: refused, with "Only the host can do that";
   - pause menu → Quit to Menu: refused, with the same line;
   - pause menu → "Continue without Pn" for any player: refused;
   - Settings → Window Mode, VSync or Max FPS: refused.

   The host's pad can do all of these. Mode, Hardcore and difficulty in the lobby may still be changed by any player.
   On the Settings page the host's mouse still changes the video rows.

7. **Overlay pause.** During a wave, press Shift+Tab to open the Steam overlay. Expect the run to pause as the overlay
   opens. Close the overlay: the game stays paused until a joined player presses START.

8. **Focus pause.** During a wave, alt-tab away from the game. With Settings → Gameplay → "Pause when the window loses
   focus" on (the default), expect the game to be paused when you come back. Note what the guest sees meanwhile. With
   the setting off, expect the wave to keep running while the window is unfocused.

9. **Capacity.** Host plus three guests, four pads: all four join. Then try a fifth pad, for example a fourth guest.
   Expect the one-time line "The party is full – a fifth controller cannot join" and no fifth player. On Windows a
   fifth emulated pad may never reach the game at all; if that happens, say so in your report.

10. **Cleanup.** After all guests leave, the host's own pads still play locally: join with a local pad and play a
    wave. Quitting the game ends the Remote Play session. Expect no errors in the log.

11. **Not launched through Steam.** Start the executable by hand with the Steam client not running. Expect the game to
    play normally with local pads. The log should hold at most one warning that starts with
    `SteamRemotePlayBackend:` and no errors. Then start it by hand with the Steam client running but not from the
    library. Guests' pads may not appear (see prerequisite 6); note what you see.

## Known limits to keep in mind

- No separate guest keyboard or mouse: a guest's shared keyboard or mouse acts as the host's.
- Guests always arrive as Xbox-style pads (Steam Input emulation), whatever their own device is.
- Two identical pad models with no Steam handle cannot be told apart.
- macOS is not supported.

## What to report back

- The Steam client version; the host's OS; the build (Windows or Linux, debug or release); the guest devices (a phone
  with Steam Link, a PC, and the app version if you know it); the app id used, and whether it was the private
  Remote Play branch.
- For each check (1 to 11): pass, fail or not done. For a failure: the check number, what the lobby card or the notice
  showed, what you expected, and what happened. A screenshot helps.
- The log lines that mention `SteamRemotePlayBackend`, and any `ERROR` or `WARNING` lines. The log is the Godot console
  output or the log file in the user data folder (`user://logs/`). The Steam warnings are "Steam did not start
  (status N …)" and "Steam Input did not start"; report their exact text.
- Any pad that appeared twice, or never appeared (check 1), with its name as the lobby shows it.
- Whether the Steam overlay or alt-tab paused the game (checks 7 and 8).
