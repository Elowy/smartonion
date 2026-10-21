# Releasing SmartOnion on Steam: the owner's step-by-step

This is the checklist for getting SmartOnion from this repository onto Steam. Steps marked **(you)** can only be done
by you, in the Steamworks partner site or on your own machine. Everything else is a command in this repository.
Technical background (what each script does and why): `docs/ARCHITECTURE.md`, chapter "Builds and Steam upload".
Testing Remote Play Together with real people: `docs/REMOTE_PLAY_TEST.md`.

The whole path, in order:

1. Register the app in Steamworks and note the **App ID** (section 1).
2. Put the App ID into `project.godot` (section 2).
3. Create two **depots** (Windows, Linux), their **launch options** and the **package** that owns them (section 3).
4. Set up Steam Input and then **publish** all those Steamworks settings (section 4); Remote Play Together, tags and the
   store page (sections 5 and 6).
5. **Build** the game (section 7).
6. **Upload** it: dry run, preview, real upload, test on a beta branch, then the default branch (section 8).
7. Submit the store page and the build for review, then release (section 9).

Nothing here is done by the game build itself: no step needs a password in a file, and no secret may be committed
(section 10).

## 1. Steamworks account and app (you)

1. Sign up at <https://partner.steamgames.com/>. Becoming a Steamworks developer asks for paperwork and a
   **Steam Direct fee of 100 USD per app** (non-refundable, recouped from the payout once the app has earned
   1,000 USD adjusted gross revenue). Source: Steamworks "Steam Direct Fee".
2. Create the app. Steamworks assigns an **App ID** (a number, e.g. `2345670`). It is shown on the app's page in
   Steamworks. Write it down: it goes into `project.godot` (section 2) and the upload command (section 8).
3. Create a **build account** (optional, recommended): a separate Steam account whose only job is uploading. In the
   Steamworks user management, grant it exactly the permissions **Edit App Metadata** and **Publish App Changes To
   Steam**. If it will set builds live on a released app, it also needs a phone number or the Steam mobile app on the
   account; and after any change of its e-mail or phone number Steam waits 3 days before it may set a build live.
   Source: Steamworks "Uploading to Steam", "Steam Build Account".

## 2. The App ID in the project (you)

Open `project.godot` in a text editor and set, at the end of the file:

```
[smartonion]

steam/app_id=2345670
```

(use your own number). It ships at **480**, Valve's public test app "Spacewar", which proves the Steam plug-in loads but
cannot be uploaded to. The same number is used for three things, so it must be right before you export:

- `SteamRemotePlayBackend` initialises Steam with it (Remote Play Together, guest names);
- the release export asks Steam to relaunch the game with it when you double-click the exe (section 7, "Launching");
- `tools/steam/upload.sh` refuses to upload when it is 480, or when `--app-id` disagrees with it.

The id is compiled into the exported game, so **export again after changing it** (section 7): `upload.sh` reads the
`app_id` that `export.sh` wrote into each `build_info.txt` and refuses content that was built with another id (a build
made while it was still 480 included).

Run the tests afterwards (`godot --headless --path . -s res://tests/run_tests.gd`): they accept any positive id.

## 3. Depots, launch options, package (you)

SteamPipe delivers files in **depots**. SmartOnion has two, one per operating system, because the Windows and the Linux
build are different files (`docs/ARCHITECTURE.md`, "Builds and Steam upload").

### 3.1 Depots

Steamworks → your app → **SteamPipe → Depots** (the page can also be reached as "Edit Steamworks Settings").
A default depot may already exist. Make two (rename the default one) and **Save**. Nothing is live until you publish,
which comes after the launch options, the package and Steam Input (end of section 4):

| Depot name (free text) | Language | OS | Architecture | Depot ID |
|---|---|---|---|---|
| SmartOnion Windows | All languages | **Windows** | leave on all (the build is 64-bit only; the launch option says so) | e.g. `2345671` (**`DEPOT_WIN`**) |
| SmartOnion Linux | All languages | **Linux** | leave on all | e.g. `2345672` (**`DEPOT_LINUX`**) |

Write both depot ids down: `upload.sh` needs them. A depot with its OS set is only mounted on that OS; the Steam Deck
counts as Linux. Source: Steamworks "Depots", "Operating System Depots".

### 3.2 Launch options

Steamworks → **Installation → General Installation Settings → Launch Options**. Add one entry per OS. The executable
path is relative to the install folder, with no leading slash or dot (both executables are in the root of their depot):

| Operating system | Executable | CPU architecture | Arguments |
|---|---|---|---|
| Windows | `SmartOnion.exe` | 64-bit | (none) |
| Linux (the entry may be called "Linux + SteamOS") | `SmartOnion.x86_64` | 64-bit | (none) |

Do not tick "Supported Operating Systems" on the General tab until you are ready to release (Valve does it last);
the store page's own OS checkboxes come with the release checklist (section 9). **Save** here too; publishing is at the
end of section 4. Source: "Uploading to Steam", "Initial Setup for New SteamPipe Apps"; "Platforms".

### 3.3 Package

A depot is only downloadable by someone whose licence includes it. Steamworks → **Associated Packages & DLC** → your
developer comp package (and, later, the package that is sold) → **Add/Remove Depots**: add **both** depots. If you skip
this, the build uploads fine, but nobody (not even you) can install it, or only one of the two systems can. Source:
"Uploading to Steam" ("My Mac and/or Linux Builds aren't installing any files"); "Testing On Steam", "Dev Comp
Packages". If a download does not start, open Steam with `-dev`, go to the console and run
`licenses_for_app <AppID>`: it lists the package and its depots. **Save** the package too; publishing is at the end of
section 4.

## 4. Steam Input and controllers (you)

SmartOnion reads gamepads through Godot's joypad API, not through the Steam Input API. Steam Input is still involved:
a Remote Play Together guest's pad reaches the game as an **emulated Xbox pad** made by Steam Input, and a double-clicked
exe may not see it (hence section 7, "Launching").

- Steamworks → **Application → Steam Input**: opt controller types in as listed in `docs/REMOTE_PLAY_TEST.md`
  ("Prerequisites", point 2) and pick the premade **Gamepad** template.
- Local co-op needs several pads at once: do not turn Steam Input off for the app.
- The game has no text input fields, so Valve's on-screen-keyboard rule for the Steam Deck does not apply.

**Publish all of it now.** Sections 3 and 4 only *saved* your settings: Steam (and SteamPipe) sees none of them until you
publish. Steamworks → your app → **Publish** (the Publish page, also linked from the app's landing page): check the list
of pending changes (depots, launch options, packages, Steam Input configuration) and publish them. Do this **again after
every later change** to the depots, launch options, packages or Steam Input settings. Unpublished launch options or
depots look correct in the app admin, but an install of the build then fails with "Invalid content configuration" (see
the table in section 8). The store page is not published this way: it has its own review (section 9).

## 5. Remote Play Together, co-op tags and the store features (you)

- Store Page admin → **Basic Info → Features**: tick **Remote Play Together** and the local multiplayer features that
  fit (Steam's own Remote Play page says Remote Play Together is switched on automatically for games listed with
  "Local Multiplayer, Local Co-op, or Shared/Split Screen"). Pick the exact checkbox names Steamworks shows you.
- "Remote Play on TV" means full controller support and fonts that read at a distance; "Remote Play on Phone/Tablet"
  means you made a Steam Input touch layout. Do not tick any of these three unless it is true (Valve treats them as promises).
- Tags: Steam wants **at least 5** and shows the top 20 (the first 5 describe the game). Suggestions to check against the
  Tag Wizard (Store Page admin → Basic Info → Tags): Action Roguelite, Top-Down, Local Co-Op, Co-op, Fantasy, Controller.
- Before release, test the real thing with `docs/REMOTE_PLAY_TEST.md` (it needs the build from section 8 on a beta branch).

## 6. Store page assets (you)

Steamworks → Store Page admin → **Graphical Assets**. All sizes are from the Steamworks documentation "Store Graphical
Assets", "Library Assets", "Community and Client Icons" and "Trailers".

| Asset | Size | Required | Notes |
|---|---|---|---|
| Header capsule | 920 x 430 | yes | Game art plus logo or title; no other text |
| Small capsule | 462 x 174 | yes | Logo must stay readable when shrunk to 184 x 69 and 120 x 45 |
| Main capsule | 1232 x 706 | yes | Home page carousel |
| Vertical capsule | 748 x 896 | yes | Sale pages |
| Screenshots | 1920 x 1080 or larger, 16:9 | yes, at least 5 | Gameplay only (no concept art, marketing text, awards). Mark at least 4 as suitable for all ages |
| Page background | 1438 x 810 | no | Ambient, so it does not compete with the page. Made from the last screenshot if missing |
| Library capsule | 600 x 900 | yes | Must contain the game logo |
| Library header | 920 x 430 | yes | Falls back to the header capsule |
| Library hero | 3840 x 1240 | yes | Art only, **no text at all**. Keep the important part inside the central safe area of 860 x 380 |
| Library logo | 1280 px wide or 720 px tall, transparent PNG | yes | Only the logotype; you pick its position after upload |
| Shortcut icon | 256 x 256 or 512 x 512, ICO or PNG | yes | Used for desktop shortcuts |
| App icon | 184 x 184, JPG | yes | Compact lists, notifications |
| Trailer | up to 1920 x 1080, 30 or 60 fps, 5,000+ kbps, .mov / .wmv / .mp4 | yes (a trailer is part of the release checklist) | H.264 + AAC preferred. Gameplay first. `tools/trailer/make_trailer.sh` makes one from the real game (see `tools/trailer/README.md`) |

Rules for capsules (Steamworks "Graphical Asset Rules"): only game art, the game name and an official subtitle; no
review scores, award names, discount text or calls to action ("Wishlist now"); the art must be PG-13; the logo must be
readable. Text about an update goes into a temporary Artwork Override, not into the base capsule.

No Blizzard trademark may appear in any asset or text (project convention).

## 7. Building the game

You need Godot 4.7.2 and a bash terminal: Linux, or on Windows **WSL** (Ubuntu) with the repository cloned into the Linux
file system (for example `~/smartonion`, not under `/mnt/c`). From the repository root:

```bash
tools/build/install_templates.sh          # once: the 4.7.2 export templates, checksum-verified
tools/steam/fetch_godotsteam.sh           # once: GodotSteam + Valve's libraries into addons/godotsteam/
godot --headless --path . --import
tools/build/export.sh --steam             # both platforms, into build/steam/content/{windows,linux}/
```

`export.sh` checks that the export templates are installed and runs a headless smoke test of the exported Linux build. The version number is
`application/config/version` in `project.godot`: change it first, for every upload.

**A version bump is two edits, and the TODOs are a third.**

- `project.godot`: `application/config/version` (the number shown in the main menu), e.g. `0.9.1`.
- `export_presets.cfg`, preset **Windows Desktop**: `application/file_version` and `application/product_version`, both
  the same number plus `.0`, e.g. `0.9.1.0` (the version in the exe's Properties dialog). `export.sh` stops with the
  line to fix when they differ from `application/config/version`, and so does the test suite.
- Before the first upload also replace `TODO Company Name` in the same preset (`application/company_name` and
  `application/copyright`): they are shown in the exe's Properties dialog, and `export.sh` only warns about them.

> **Build and upload the Linux depot from Linux or WSL (on the Linux file system), not from Git Bash.** Git Bash (and
> `/mnt/c` in WSL) is NTFS: `chmod +x` does nothing there, so `SmartOnion.x86_64` loses its Unix executable bit, and a
> Linux depot without it may not start on Linux or the Steam Deck. `upload.sh` cannot check the bit on Windows (it only
> warns), and `export.sh` skips the headless smoke test of the Linux build because that binary cannot run on Windows.
> Both depots go up in one build and must come from the same export (`upload.sh` checks it), so the simple rule is: do
> sections 7 and 8 entirely in Linux or WSL. The Windows exe is exported there too (Godot writes its icon and version
> resources itself; no Wine needed). Git Bash is fine for a `--dry-run` or for trying the Windows build.

After a successful `--steam` export the folders look like this (this layout is what the upload script expects):

```
build/steam/content/windows/   SmartOnion.exe, steam_api64.dll, libgodotsteam.windows.*.dll, build_info.txt
build/steam/content/linux/     SmartOnion.x86_64, libsteam_api.so, libgodotsteam.linux.*.so, build_info.txt
```

The game is a single executable (the data is embedded). The Steamworks library and the GodotSteam library must be
next to it. A build made without `--steam` has no Steam features and `upload.sh` refuses it.

**Launching: why a double-clicked exe restarts.** In a release export with a real App ID (not 480), the game's first
Steam call is `restartAppIfNecessary(app_id)`. If the exe was not started by the Steam client, Steam relaunches the
game itself (installing it if needed) and this process quits. That is needed so Steam Input / Remote Play pads work.
It never happens in the editor, in debug exports, in automated runs (`--smoke`, `--demo`, `--view`, `--screenshot`,
headless) or with App ID 480. To try a **local release build** with a real App ID without Steam restarting it, put a
file `steam_appid.txt` containing the App ID next to the exe (Valve: its presence makes the call answer "no restart").
Delete it again: `upload.sh` refuses to upload content that contains it, and the depot scripts exclude it.

## 8. Uploading with SteamPipe

`tools/steam/upload.sh` fills the templates in `tools/steam/steampipe/*.vdf.in` and runs **steamcmd**, Valve's command
line client. It needs bash (Linux, or WSL on Windows; see the Linux depot note in section 7 about Git Bash), curl or wget, and on Linux the 32-bit C library
(Debian / Ubuntu: `sudo dpkg --add-architecture i386 && sudo apt update && sudo apt install lib32gcc-s1`).
It downloads steamcmd by itself into `build/steamcmd/` (gitignored) if it is missing, or use `--steamcmd PATH`. The
launcher is `build/steamcmd/steamcmd.sh` on Linux / WSL and `build/steamcmd/steamcmd.exe` under Git Bash.

Set the numbers once per terminal (or pass them as flags, `upload.sh --help` lists both):

```bash
export DEPOT_WIN=2345671 DEPOT_LINUX=2345672 STEAM_USER=my_build_account
```

The App ID is taken from `project.godot` (section 2). Then, in this order:

1. **Dry run.** Writes the VDF scripts to `build/steam/scripts/` and checks everything. No login, no network:
   ```bash
   tools/steam/upload.sh --dry-run          # add --print-vdf to see the generated files
   ```
   It refuses, listing every problem, when: App ID is 480 or differs from `project.godot`; a depot id is missing; a content
   folder or its executable is missing; `steam_api64.dll` / `libgodotsteam*.dll` / `libsteam_api.so` /
   `libgodotsteam*.so` are missing; a `steam_appid.txt` is in the content; or a platform's `build_info.txt` (written by
   `export.sh`) is missing, is not from a `--steam` export, or does not match: its `version` is not the current
   `application/config/version`, its `app_id` is not the App ID you upload (the id is compiled into the game, so after
   changing it in `project.godot` you must export again), or Windows and Linux were exported at different versions or
   commits. Fix: run `tools/build/export.sh --steam` again (both platforms). A build made from a modified or older commit
   is only a warning, and the default description (`v<version> <git hash>`) is taken from the content, not from your checkout.
2. **Preview.** Logs in and runs SteamPipe with `"Preview" "1"`: it validates your account, the App ID, the depots and the
   file mappings, and writes the file manifest and logs to `build/steam/output/`, but uploads nothing:
   ```bash
   tools/steam/upload.sh --preview
   ```
   The first time, steamcmd asks for the password and the **Steam Guard** code **in your terminal**. The script never sees
   or stores either. steamcmd then caches a login token (a secret; its `config/config.vdf`), so later runs only need
   `STEAM_USER`. If the login is "denied" because of Steam Guard, read the code from the e-mail Steam sent you and run
   `<steamcmd> +set_steam_guard_code <code>`, then run the script again. `<steamcmd>` is the one the upload uses:
   `build/steamcmd/steamcmd.sh` on Linux / WSL, `build/steamcmd/steamcmd.exe` under Git Bash, or the program you gave with
   `--steamcmd` / `STEAMCMD` (every steamcmd install keeps its own cached login). Open the manifest in
   `build/steam/output/` and check that the file lists make sense (SmartOnion.exe, the libraries; no `.pdb`).
3. **Upload.**
   ```bash
   tools/steam/upload.sh --desc "0.9.0 first Steam build"
   ```
   The description (default: `v<version> <git hash>`) is only shown to you on the Builds page. When it finishes, the
   build exists on <https://partner.steamgames.com/apps/builds/APPID> but is **not live anywhere**.
4. **Test on a beta branch.** Create a branch once on the Builds page ("Create new app branch", a name without spaces,
   e.g. `beta`; optionally with a password). Then either set the new build live there on the Builds page, or let the
   script do it: `tools/steam/upload.sh --branch beta` (the branch must already exist; the script refuses `default`).
   On a machine whose Steam account owns the app (your developer account does through the Dev Comp package): Library →
   right-click SmartOnion → Properties → Game Versions & Betas → select the branch. Steam downloads the build. Start
   it **from the Steam library**, play a wave, and run through `docs/REMOTE_PLAY_TEST.md`. Test the Linux build on a
   Linux machine or a Steam Deck too.
5. **Default branch.** Steam never sets the default branch live automatically, and `upload.sh` never asks it to. When the
   beta build is good, set that same build live on **default** on the Builds page, by hand. Before release, the default
   branch is what the review team looks at (section 9).

A new version later is the same loop: bump the version (`application/config/version` in `project.godot` **and**
`application/file_version` / `application/product_version` = `<version>.0` in the Windows preset of `export_presets.cfg`,
section 7), export (`--steam`), `--preview`, upload with a
new `--desc`, test on `beta`, then move it to default. (If you changed a depot, launch option, package or Steam Input
setting in between, publish in Steamworks first.) Only changed parts are uploaded; `build/steam/output/` holds the
chunk cache that makes this fast, and may be deleted (the next upload is then slower).

### If something goes wrong

| Message or symptom | Usual cause |
|---|---|
| `Failed to get application info for app NNN (check login and subscription)` | Wrong App ID, or the Steamworks changes were never **published** (section 4), or the build account does not belong to the app |
| `Failed 'DepotBuild for ...' - status = 6` | The account lacks the permissions (section 1), or steamcmd cannot find the content (look at `build/steam/scripts/*.vdf`: the ContentRoot paths) |
| `Login Failure: Account Login Denied` | Steam Guard: see step 2 |
| `steamcmd.sh: ... cannot execute: required file not found` (Linux) | The 32-bit C library is missing (section 8, intro) |
| The upload works, nothing installs on a test machine, or only one OS | The depots are not in the package (section 3.3), or the branch has no build set live |
| `An error occurred while installing (Invalid content configuration)` | The depots, launch options or package were saved but **not published** (publish them, section 4; again after every later change), no build live on the branch, wrong launch options, or the depots are not owned |
| The game quits at once when double-clicked | Intended with a real App ID in a release export (section 7); use the Steam library, or a `steam_appid.txt` for local tests |

Every `upload.sh` problem message says what to fix. Valve's own reference: "Uploading to Steam" (SteamPipe), including its
troubleshooting list.

## 9. Review and release (you)

Steam reviews the store page and the build before release; both checklists are on the app's landing page in Steamworks.

- **Store page:** fill in everything on the checklist (assets from section 6, description, tags, system
  requirements, the content survey, the OS checkboxes for Windows and Linux). Press "Mark as ready for review". Review takes typically
  3 to 5 business days; plan 7. The store page may only show features that are in the build, and its screenshots must
  show gameplay. After approval it must be public as "Coming soon" for **at least 2 weeks** before you can release.
- **Build:** a near-final build must be live on the **default** branch (section 8, step 5). "Mark as ready for review"
  works only after the store page was submitted. Review takes typically 3 to 5 business days (plan 7): they check that it
  starts on every OS listed on the store page and that every listed feature works.
- **Release:** the "Release App" button on the landing page, pressed by you. A reviewed game may be updated freely afterwards.
- **Steam Deck / Steam Machine (optional):** Valve rates how a game runs on the Deck (Verified / Playable / Unsupported).
  Request it from the app landing page ("Steam Hardware Compatibility Review" under Technical Tools; not offered to
  every partner). The game has a native Linux build. What the review checks, and where SmartOnion stands:
  controls (all of the game works with a gamepad and the default Steam Input configuration: **you verify**);
  glyphs (button prompts must match the Deck / Xbox pad: **you verify**); text size (at least 9 px, aim for 12 px,
  at 1280 x 800: the UI theme's smallest font is 18 px at 1080p, i.e. 12 px at 800p, but `fitted_font_size` may shrink
  text down to 14 px, i.e. 9.3 px: **check long labels**); 30 fps at 800p by default (**you verify** on a Deck);
  no launcher (there is none); no compatibility warnings. Source: Steamworks "Steam Deck and Steam Machine
  Compatibility Review".

## 10. What not to commit

`build/` (the exports, the VDF scripts, the build output, the steamcmd folder with its login token) is gitignored as a
whole; so are `addons/godotsteam/` (Valve's libraries), `steam_appid.txt` and Steam Guard `ssfn*` files. Never commit:

- a password, a Steam Guard code or anything from steamcmd's `config/` folder (the cached login token);
- Valve's `steam_api64.dll` / `libsteam_api.so` or the GodotSteam binaries (they ship in the depot only);
- a `steam_appid.txt`;
- `export_credentials.cfg`;
- the exported executables, `.pck` files or zips (`build/` covers them).

The App ID and the depot ids are not secrets, but they are not in the repository either (only the App ID in
`project.godot`); keep the depot ids in your shell profile or a notes file.

## Sources

Steamworks documentation (partner.steamgames.com/doc/), read 2026-10-21:

- Uploading to Steam (SteamPipe): `sdk/uploading` (build scripts, steamcmd command, build account, troubleshooting)
- Steam Direct Fee: `gettingstarted/appfee`
- Depots: `store/application/depots`; Platforms: `store/application/platforms`; Branches: `store/application/branches`
- Testing On Steam: `store/testing`; Release Process: `store/releasing`; Review Process: `store/review_process`
- Store, Library and Community graphical assets: `store/assets/standard`, `store/assets/libraryassets`,
  `store/assets/community`; Graphical Asset Rules: `store/assets/rules`; Trailers: `store/trailer`; Tags: `store/tags`
- Steam Remote Play: `features/remoteplay`; Steam Input for developers: `features/steam_controller/getting_started_for_devs`
- Steam Deck and Steam Machine Compatibility Review: `steamdeck/compat`
- Steamworks API overview (`SteamAPI_RestartAppIfNecessary`): `sdk/api`
- GodotSteam, `restartAppIfNecessary`: <https://godotsteam.com/classes/main/>
