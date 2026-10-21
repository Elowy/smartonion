# SmartOnion

Brotato-szerű, WoW-hangulatú arena survivor Godot 4-ben, 1–4 fős helyi co-oppal – a hősök hagymák WoW-páncélban.

- Tervezés: [docs/GDD.md](docs/GDD.md)
- Kódszerkezet: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- Képernyőképek: [docs/screenshots/](docs/screenshots/)
- Forrásmegjelölések (hang- és zenecsomagok, licencek): [CREDITS.md](CREDITS.md)

## Kipróbálás

1. Töltsd le a **Godot 4.7.2**-t (standard, nem .NET): https://godotengine.org/download
2. Indítsd el a Godotot, **Import** → válaszd ki ennek a mappának a `project.godot` fájlját → **Import & Edit**.
   Az első megnyitáskor a Godot pár másodpercig importálja a projektet.
3. Csatlakoztasd a kontrollereket (Xbox, PlayStation vagy más XInput / SDL-kompatibilis kontroller).
4. Nyomd meg az **F5**-öt (Run Project).

### Irányítás

| | Kontroller | Billentyűzet |
|---|---|---|
| Csatlakozás a lobbyban | A | Enter / Space / F |
| Kaszt váltása | bal kar / d-pad ◀ ▶ | A / D vagy nyilak |
| Társ (companion) váltása, ha a kasztnak van | RB | E |
| Ready / megerősítés | A | Enter / Space / F |
| Mód váltása (Normal / Endless) | Y | C |
| Hardcore be / ki | X | R |
| Vissza / unready / kilépés a lobbyból | B | Esc / Backspace |
| Mozgás | bal kar | WASD / nyilak |
| Szünet | Start | P / Esc |
| Nehézség váltása (lobby, az egész csapatra) | SELECT | Tab |
| Loadout: Seasoning / Heirloom / Look (lobby, a saját kártyádon) | LT | jobb egérgomb |
| Alternatív kezdőfegyver (lobby, 12. szint után) | LB | Q |
| The Onion Patch fülei (főmenü) | LB / RB | Q / E |
| Meghívás a Steam Remote Play Together-be (lobby, csak a házigazda) | L3 | I |

A fegyverek automatikusan támadnak. Elesett társat úgy lehet feléleszteni, hogy 5 másodpercig mellette állsz. Ha te esel el, a pálya közepén megjelenő Grave Tender-nél térhetsz vissza (Hardcore módban nincs Grave Tender).

A lobbyban bármelyik csatlakozott játékos átválthatja a módot (Y) és bekapcsolhatja a Hardcore-t (X); a fejlécen látszik a választás. A nehézség (SELECT) a csapaté; a Loadout (LT) és az alternatív fegyver (LB) a hős saját kártyáján áll. Új profilon a Hunter és a Shaman achievementtel nyílik meg (GDD 17.5).

A főmenüben a **Settings** és a **Credits** oldal érhető el, a szünetmenüből a Settings. Az oldalakon a fel / le lépteti a sorokat, a bal / jobb (vagy a d-pad) állítja az értéket, az A (billentyűzeten Enter / Space) választ, a B (Esc) visszalép. A Credits oldalt a bal kar, a d-pad vagy a nyilak görgetik.

### Ami ebben a verzióban van (M0–M9)

- **Kör:** főmenü → lobby (1–4 játékos, 7 kaszt, mód és Hardcore) → hullámok (Normal: 25 hullám, Endless: végtelen) → győzelem / vereség → eredmény és ranglista → lobby.
- **Hősök:** 7 kaszt (Warrior, Mage, Paladin, Rogue, Warlock, Hunter, Shaman). Szintlépéskor ability- és stat-kártyát választasz; 48 ability van, auto-cast slotokkal és rangokkal (Trainer). Kasztonként 3 talentfa.
- **Hunter és Shaman (M8):** a Hunter Focus-erőforrással, Arrow Fan és Backstep alapképességekkel harcol, és állandó társa van (Wolf, Boar vagy Owl; a lobbyban RB-vel, billentyűzeten E-vel választható). A Shaman Surge-erőforrással, Forking Bolt és Totem Rite alapképességekkel harcol; a totemjei a Fire, Water, Earth és Air elemek között váltanak. Mindkettőnek 3 talentfája, tier setje, Artifactja és 8 kaszt-specifikus itemje van.
- **Új fegyverek és setek (M8):** Crossbow, Polearm és Fist Weapon, mindegyiknek saját Forge Legendary-vel; öt kaszt-független tier set (egy Cloth, egy Leather, két Mail és egy Plate), amelyet bármelyik kaszt viselhet, aki a páncéltípusát hordhatja.
- **Itemek és loot:** generált itemek (alaptípus, ritkaság, utótag, enchant és proc), kézzel tervezett Rare / Epic és kaszt-specifikus itemek, trinketek, Legendary-k és setek. Forrás: normál drop, elit, Coin Gremlin és boss; a dobás Need / Greed / Pass.
- **Kovácsolás és Enchanter:** fegyverkovácsolás (Legendary-hatások), enchantolás a Glimmer Dust kasszából.
- **Artifact fegyverek:** kasztonként egy; ritka, véletlen loot a 10. hullámtól, hullámonként fejlődnek.
- **Bolt-nyelők:** fogyóeszközök (7 elixír és étel), Black Market, újragörgetés, talent-visszaállítás.
- **Ellenfelek:** 7 ellenségtípus és a Coin Gremlin (a menekülő, ritka különleges ellenség); elit-hullámok; két wave-boss (Lich Commander Morvain a 10., Vor'thalax a 25. hullámon).
- **Módok:** Normal, Endless, és bármelyikhez kapcsolható Hardcore (nincs Grave Tender).
- **Környezetek:** 5 pálya (Cemetery, Forest Ruin, Ice Cave, Swamp, Volcano), saját veszélyekkel; a futam elején sorsolódik.
- **Események és szentélyek:** hullámon belüli események (őrzött láda, totem-védelem, goblin-karaván); 6 szentély a hullámszünetekben, amelyeket a csapat elfogadhat vagy elutasíthat.
- **Dungeon-portál:** bizonyos hullámok után megnyílik; 4 szobás dungeon, a végén a Dungeon Warden.
- **Statisztika:** damage meter (sebzés, gyógyítás, elnyelés, kapott sebzés, felélesztés, elesés, ölés, bossok) és futamkártya (run card) a végső képernyőn.
- **Helyi ranglista:** a saját gépen, módonként, Hardcore-ral és nélküle, valamint játékosszám szerint külön lista.
- **Hang és beállítások (M7a):** UI-, fegyver-, harc- és zenei hangok (CC0-s csomagok); a Settings oldalon hangerők (Master / Music / Effects / Interface), ablakmód, VSync, FPS-limit, képernyőrázkódás, sebzésszámok és FPS-kijelző; a Credits oldal a forrásokat mutatja.
- **Grafika (M7b):** Cinzel-címek; game-icons.net ikonok a képességeken, talentfákon, fogyóeszközökön és szentélyeken; a hősön látszik a viselt sisak, váll és mellvért (páncéltípus, fokozat, ritkaság, setek); az öt aréna végleges látványa (élő talaj, környezeti részecskék, animált víz és láva) és a kripta-jellegű dungeon; új harci effektek (spawn, hullák, iskolaszínű találatok, kritikus találat, loot-pattanás, arany- és XP-nyomvonal, boss-belépő).
- **Meta-progresszió (M9):** egy fő mentés (`user://profile.json`), kasztonként 1–30-as Class Level, szintenként új képességek és jutalmak. 56 Seasoning (kaszt-képesség oldalirányú módosítója), 10 Heirloom (megmaradó tárgy, rangokkal), 40 achievement és a Seeds-pénznem, amit a főmenü **The Onion Patch** pontjában lehet elkölteni; a **Wardrobe** a gyűjtött páncélkinézeteket és kozmetikumokat adja, három nehézség (Normal, Pungent, Tear-Jerker) a Tear-Jerker nyomással. Az automatikus futamok (smoke, demo, nézetek) nem használják a mentést (GDD 17).
- **Online co-op (RPT):** a helyi co-op a Steam Remote Play Together-en át is játszható. A kiesett játékos helyét bármelyik szabad kontroller átveheti; a vendég nem léphet ki és nem dobhat ki játékost. Részletek lent.

Az M7a (hang, menük, beállítások, IP-tisztítás), az M7b (grafika) és az M8 (Hunter, Shaman, új fegyvertípusok, kaszt-független setek) kész; az M9 (meta-progresszió) is kész (GDD 17. fejezet). A végleges balansz még hátra van; a Questek és a háttértörténet a legvégén készül (GDD 17.8).

## Online co-op (Steam Remote Play Together)

A helyi co-op a Steam **Remote Play Together** funkciójával online is játszható: a házigazda a játékot a Steam-könyvtárából indítja, a vendégek a Steamen át csatlakoznak a saját kontrolleruktól. A szabályok (kiesés, átvétel, házigazda-jogok) a GDD 11. fejezetében vannak.

- **Steam nélkül is működik:** a kontroller-kezelés (kiesés, visszacsatlakozás, átvétel a lobbyban és menet közben, türelmi idő) és a szünet ugyanúgy működik. Vendég ilyenkor nincs, így a vendég-funkciók (név a kártyán, meghívó, a vendég jogainak korlátozása) nem aktívak.
- **GodotSteam (opcionális):** a `tools/steam/fetch_godotsteam.sh` letölti a GodotSteam v4.23.2-gde bővítményt az `addons/godotsteam/` mappába (csak Windows 64 és Linux 64; a letöltött fájl sha256-összegét ellenőrzi). Utána egyszer: `godot --headless --path . --import`. A mappa a `.gitignore`-ban van: a benne lévő Valve-könyvtárak nem kerülhetnek a repóba.
- **Steam-alkalmazásazonosító:** a `smartonion/steam/app_id` projektbeállítás alapértéke 480 (a Valve tesztalkalmazása, Spacewar), csak fejlesztéshez. A Steamworks-regisztráció után ide kell a saját azonosító. A játékot a Steam-könyvtárból kell indítani, különben a vendégek kontrollerei nem jelennek meg.
- **Export:** a Steam-es exportban a bővítmény könyvtárai (`libgodotsteam…`, `steam_api64.dll` / `libsteam_api.so`) a futtatható mellé kerülnek; a depotban együtt kell lenniük.
- **GodotSteam-licenc (MIT):** a Steam-es buildhez tartozik a GodotSteam szerzői jogi és engedélyszövege. A `CREDITS.md` „Libraries” része tartalmazza, és a játékon belüli Credits oldal megmutatja; ezért a `CREDITS.md`-nek (`*.md` az export include-szűrőjében) a Steam-es exportban benne kell lennie. A telepített `addons/godotsteam/license.md` nem kerül a futtatható mellé.

### Fejlesztői kapcsolók (RPT)

- `--fake-rpt[=N]` – N (1–3, alapból 2) vendég szimulálása Steam nélkül: a kontrollerek vagy a botok vendégként játszanak, nevekkel (pl. „Remote · Mira”). Nem változtatja meg, hogy egy futam automatikus-e.
- `--hotplug-test` – smoke-futamban a 2. hullámban P2 kontrollerének kihúzása, az átvétel és a folytatás végigpróbálása; a `SMOKE_RESULT` egy `hotplug` blokkot kap. Példa: `godot --headless --fixed-fps 60 --path . -- --smoke --waves=3 --seed=5 --hotplug-test`.
- Képernyőkép a lobbyról vendéggel és kihúzott kontrollerrel: `xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 -- --view=lobby --fake-rpt=2 --hotplug-test --screenshot=/tmp/rpt_lobby.png --shot-time=6`.

Az éles, több gépes Steam-próba lépéseit (előfeltételek, a 11 ellenőrzés, mit kell visszajelezni) a [docs/REMOTE_PLAY_TEST.md](docs/REMOTE_PLAY_TEST.md) tartalmazza.

## Steam-feltöltés (SteamPipe)

A kész játék két depotban kerül a Steamre: egy Windows- és egy Linux-buildben (utóbbi a Steam Decken is fut). A tulajdonos lépésről lépésre útmutatója (angolul): [docs/STEAM_RELEASE.md](docs/STEAM_RELEASE.md); a szkriptek működése: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), „Builds and Steam upload” fejezet.

1. **Steamworks (te intézed):** app és **App ID**, két depot (Windows, Linux) és azok azonosítója, launch optionök (`SmartOnion.exe`, `SmartOnion.x86_64`, mindkettő 64 bites), a depotok bekerülnek a csomagba (package), Steam Input, Remote Play Together, címkék, store-oldal képei.
2. **App ID a projektben:** a `project.godot` `[smartonion]` szakaszában a `steam/app_id`. Alapértéke 480 (a Valve tesztalkalmazása, Spacewar), ezzel nem lehet feltölteni. Az éles exportban a játék ezzel az azonosítóval indítja újra magát a Steamen át, ha dupla kattintással indították (`restartAppIfNecessary`; a szerkesztőben, debug exportban, automatikus futamban és 480-nál soha).
3. **Build:** egyszer `tools/build/install_templates.sh` (a Godot 4.7.2 export template-jei, ellenőrzőösszeggel), utána `tools/build/export.sh --steam`, ami a `build/steam/content/windows/` és a `build/steam/content/linux/` mappát készíti el (a futtatható és a Steam-könyvtárak együtt), és lefuttat egy smoke-tesztet az exportált Linux-buildön. Steam nélküli, letölthető változat: `tools/build/export.sh` → `build/dist/SmartOnion-<verzió>-windows.zip` és `-linux.tar.gz`. A verziószám a `project.godot` `application/config/version` értéke (a főmenü sarkában látszik); a Windows-exe cég- és copyright-mezője még `TODO`, ezeket az `export_presets.cfg`-ben kell kitölteni. Az ikon forrása `tools/build/icon/`, újragenerálás: `python3 tools/build/make_icon.py`. A Linux depót Linuxon vagy WSL-ben (a Linux fájlrendszeren, nem `/mnt/c` alatt) kell építeni és feltölteni: Git Bash-ből a `SmartOnion.x86_64` elveszíti a futtatási bitjét, és a Linux-smoke is kimarad.
4. **Feltöltés:** `tools/steam/upload.sh`. A depot-azonosítókat és a build-fiókot kapcsolóval vagy környezeti változóval kell megadni (`DEPOT_WIN`, `DEPOT_LINUX`, `STEAM_USER`; `--help` mindent felsorol). Sorrend:

   ```bash
   tools/steam/upload.sh --dry-run     # a VDF-ek elkészítése és a tartalom ellenőrzése: nincs belépés, nincs hálózat
   tools/steam/upload.sh --preview     # SteamPipe-előnézet: belép, ellenőriz, de nem tölt fel semmit
   tools/steam/upload.sh               # a valódi feltöltés (a build még sehol sincs élesítve)
   tools/steam/upload.sh --branch beta # ugyanez, és a buildet egy meglévő béta-ágon élesíti
   ```

   A szkript visszautasítja a feltöltést, ha az App ID 480 vagy eltér a `project.godot` értékétől, ha hiányzik egy tartalom-mappa vagy a futtatható, ha hiányoznak a Steam-könyvtárak (`steam_api64.dll`, `libsteam_api.so`, `libgodotsteam*`), vagy ha `steam_appid.txt` van a tartalomban. A steamcmd-t, ha hiányzik, a `build/steamcmd/` mappába tölti le.
5. **Jelszó és Steam Guard:** a szkript soha nem kér és nem tárol jelszót. Az első belépéskor a steamcmd kéri a jelszót és a Steam Guard-kódot a terminálban, utána eltárolt belépési token kell csak. Az alapértelmezett (default) ágat a Steam nem engedi automatikusan élesíteni: azt a Steamworks Builds oldalán kell kézzel megtenni, ezért a szkript `--branch default` esetén is hibával áll meg.
6. **Mit ne commitolj:** a `build/` mappát (export, VDF-ek, steamcmd és annak belépési tokenje), az `addons/godotsteam/` mappát (Valve-könyvtárak), a `steam_appid.txt` és az `ssfn*` fájlokat; jelszót vagy Steam Guard-kódot soha. A `.gitignore` mindet lefedi.

## Fejlesztői parancsok

```bash
godot --headless --path . --import                                   # import
godot --headless --path . -s res://tests/run_tests.gd                # unit tesztek
godot --headless --path . -- --smoke --waves=3                       # 4 botos próbajáték
godot --path . -- --demo                                             # botok játszanak (nézhető)
```

Friss klónnál (a `.godot/` mappa nincs a repóban) egyszer futtasd az importot: `godot --headless --path . --import`. Ez importálja a projekt assetjeit (köztük az ikonokat és a Cinzel-betűtípust).

### Fejlesztői kapcsolók (M9)

- `--profile=dev|fresh|max` – a profil: `dev` (automatikus futamokon alapértelmezett: minden nyitva, nem ment), `fresh` (új játékos), `max` (minden kaszt 30. szinten, minden nyitva, 5. rangú Heirloomok).
- `--profile-path=FILE` – a profil fájlja; ilyenkor egy automatikus futam is ebből olvas, és ide ír.
- `--seasonings=ssn_a,ssn_b,ssn_c` – a botok Seasoning-jei (minden bot a saját kasztjának Seasoning-jeit kapja).
- `--heirloom=heir_…` – minden hős Heirloomja.
- `--difficulty=normal|pungent|tear_jerker` – a nehézségi szint.
- `--alt-weapon[=0|1]` – a botok alternatív kezdőfegyvert kapnak.
- `--view=patch --patch-tab=classes|seasonings|heirlooms|achievements|wardrobe` – The Onion Patch képernyőképe; `--view=lobby --loadout-tab=seasonings|heirloom|look` – a második játékos Loadout-ja (`--loadout-player=1..4` másik játékosét nyitja).

Példa: `godot --headless --path . -- --smoke --waves=11 --seed=9 --profile=max --difficulty=pungent --heirloom=heir_old_layers`

A kapcsolók teljes leírása: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), M9 fejezet.

### Fejlesztői kapcsolók (M6)

A teljes lista: [scenes/main/launch_options.gd](scenes/main/launch_options.gd). Az M6 kapcsolói:

- `--boss-hp=X` – a bossok HP-szorzója (smoke / debug).
- `--artifact-chance=X` – az Artifact-dobás esélye minden rollon (0–1).
- `--end-page=NAME` – a végképernyő oldala: `summary`, `meter` vagy `leaderboard`.
- `--save-card` – a `--view` által kikényszerített végképernyő menti a futamkártyát (`user://cards/`), és megy tovább.
- `--mode=NAME` – a futam módja: `normal` vagy `endless`.
- `--hardcore[=0|1]` – Hardcore futam (nincs Grave Tender).
- `--env=ID` – a környezet kényszerítése, pl. `forest_ruin`.
- `--event=ID` – minden hullámon ez az esemény: `guarded_chest`, `defend_totem`, `goblin_caravan` (röviden `chest`, `totem`, `caravan`).
- `--shrine-chance=X` – a szentély esélye minden hullámszünetben (0–1).
- `--dungeon[=0|1]` – a dungeon-portál a következő hullám után nyílik (`=0`: ki).
- `--leaderboard=PATH` – a ranglista fájlja; smoke, demo és nézet-futam is ebbe írja az eredményt.

### Fejlesztői kapcsolók (M8)

- `--companion=wolf|boar|owl` – minden bot, amelyiknek a kasztja kínál társat, a megadott társat választja (ha a kaszt nem kínálja, az első választás marad). Ismeretlen értéknél a smoke `bad_args` hibával, exit 1-gyel lép ki. Példa: `godot --headless --path . -- --smoke --waves=3 --classes=hunter,hunter,warrior,mage --companion=owl`.
- Az ismeretlen kaszt-azonosító a `--classes=` kapcsolóban is `bad_args` (korábban figyelmeztetés és kihagyás volt).

### Fejlesztői kapcsolók (M7a)

- `--view=menu` a főmenüt, a `--view=settings` és a `--view=credits` a főmenüt a Settings, illetve a Credits oldallal mutatja (képernyőképhez).
- Automatikus futtatásban (`--smoke`, `--demo`, `--view`, `--screenshot`) a beállításokat nem olvassuk és nem írjuk (`user://settings.cfg`), az alapértékek érvényesek.

### Fejlesztői kapcsolók és nézetek (M7b)

- Képernyőkép-nézetek a `tools/showcase` futtatóval (Xvfb alatt): `--view=equip` (páncéltípusok és fokozatok), `--view=sets` (a kaszt-setek), `--view=equip_game` (felszerelt hősök a játékkamerából), `--view=live --geared=0..4` (élő futam, a botok III. fokozatú felszereléssel), `--view=fx --phase=spawn|death|impacts|loot|boss|banner` (harci effektek), `--view=arena --env=ID [--dungeon=1]` (környezetek). Példa:

  ```bash
  xvfb-run -a -s "-screen 0 1920x1080x24" godot --fixed-fps 60 --path . --rendering-driver opengl3 -s res://tools/showcase/showcase.gd -- --view=fx --phase=boss --out=/tmp/fx.png
  ```

- Teljesítmény-stressz (`tools/showcase/stress.gd`): kb. 150 ellenség folyamatos halállal és találatszikrákkal; a kiírt `STRESS` sorok a draw-call és a folyamatidő számait adják, bármelyik commiton futtatható (az összehasonlításhoz).

  ```bash
  xvfb-run -a -s "-screen 0 1280x720x24" godot --fixed-fps 60 --path . --resolution 1280x720 --rendering-driver opengl3 -s res://tools/showcase/stress.gd -- --frames=360
  ```

### Trailer (fejlesztői eszköz)

A Steam-oldal trailerét a `tools/trailer/` csomag készíti az igazi játékból: botok játszanak, a Movie Maker rögzít, az ffmpeg vág. Indítás: `tools/trailer/make_trailer.sh` (követelmények és a jelenetek: [tools/trailer/README.md](tools/trailer/README.md)). A játékkódot nem módosítja, a videó nem kerül a repóba.
