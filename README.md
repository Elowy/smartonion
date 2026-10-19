# SmartOnion

Brotato-szerű, WoW-hangulatú arena survivor Godot 4-ben, 1–4 fős helyi co-oppal – a hősök hagymák WoW-páncélban.

- Tervezés: [docs/GDD.md](docs/GDD.md)
- Kódszerkezet: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- Képernyőképek: [docs/screenshots/](docs/screenshots/)

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
| Ready / megerősítés | A | Enter / Space / F |
| Mód váltása (Normal / Endless) | Y | C |
| Hardcore be / ki | X | R |
| Vissza / unready / kilépés a lobbyból | B | Esc / Backspace |
| Mozgás | bal kar | WASD / nyilak |
| Szünet | Start | P / Esc |

A fegyverek automatikusan támadnak. Elesett társat úgy lehet feléleszteni, hogy 5 másodpercig mellette állsz. Ha te esel el, a pálya közepén megjelenő Spirit Healernél térhetsz vissza (Hardcore módban nincs Spirit Healer).

A lobbyban bármelyik csatlakozott játékos átválthatja a módot (Y) és bekapcsolhatja a Hardcore-t (X); a fejlécen látszik a választás.

### Ami ebben a verzióban van (M0–M6)

- **Kör:** főmenü → lobby (1–4 játékos, 5 kaszt, mód és Hardcore) → hullámok (Normal: 25 hullám, Endless: végtelen) → győzelem / vereség → eredmény és ranglista → lobby.
- **Hősök:** 5 kaszt (Warrior, Mage, Paladin, Rogue, Warlock). Szintlépéskor ability- és stat-kártyát választasz; 36 ability van, auto-cast slotokkal és rangokkal (Trainer). Kasztonként 3 talentfa.
- **Itemek és loot:** generált itemek (alaptípus, ritkaság, utótag, enchant és proc), kézzel tervezett Rare / Epic és kaszt-specifikus itemek, trinketek, Legendary-k és setek. Forrás: normál drop, elit, Loot Goblin és boss; a dobás Need / Greed / Pass.
- **Kovácsolás és Enchanter:** fegyverkovácsolás (Legendary-hatások), enchantolás az Arcane Dust kasszából.
- **Artifact fegyverek:** kasztonként egy; ritka, véletlen loot a 10. hullámtól, hullámonként fejlődnek.
- **Bolt-nyelők:** fogyóeszközök (7 elixír és étel), Black Market, újragörgetés, talent-visszaállítás.
- **Ellenfelek:** 7 ellenségtípus és a Loot Goblin (a menekülő, ritka különleges ellenség); elit-hullámok; két wave-boss (Lich Commander Morvain a 10., Vor'thalax a 25. hullámon).
- **Módok:** Normal, Endless, és bármelyikhez kapcsolható Hardcore (nincs Spirit Healer).
- **Környezetek:** 5 pálya (Cemetery, Forest Ruin, Ice Cave, Swamp, Volcano), saját veszélyekkel; a futam elején sorsolódik.
- **Események és szentélyek:** hullámon belüli események (őrzött láda, totem-védelem, goblin-karaván); 6 szentély a hullámszünetekben, amelyeket a csapat elfogadhat vagy elutasíthat.
- **Dungeon-portál:** bizonyos hullámok után megnyílik; 4 szobás dungeon, a végén a Dungeon Warden.
- **Statisztika:** damage meter (sebzés, gyógyítás, elnyelés, kapott sebzés, felélesztés, elesés, ölés, bossok) és futamkártya (run card) a végső képernyőn.
- **Helyi ranglista:** a saját gépen, módonként, Hardcore-ral és nélküle, valamint játékosszám szerint külön lista.

A hátralévő tartalom (M7: grafika, hangok, menük; M8: Hunter és Shaman, új fegyvertípusok; M9: meta-progresszió) a GDD 16. fejezetében van. A végleges balansz még hátra van.

## Fejlesztői parancsok

```bash
godot --headless --path . --import                                   # import
godot --headless --path . -s res://tests/run_tests.gd                # unit tesztek
godot --headless --path . -- --smoke --waves=3                       # 4 botos próbajáték
godot --path . -- --demo                                             # botok játszanak (nézhető)
```

### Fejlesztői kapcsolók (M6)

A teljes lista: [scenes/main/launch_options.gd](scenes/main/launch_options.gd). Az M6 kapcsolói:

- `--boss-hp=X` – a bossok HP-szorzója (smoke / debug).
- `--artifact-chance=X` – az Artifact-dobás esélye minden rollon (0–1).
- `--end-page=NAME` – a végképernyő oldala: `summary`, `meter` vagy `leaderboard`.
- `--save-card` – a `--view` által kikényszerített végképernyő menti a futamkártyát (`user://cards/`), és megy tovább.
- `--mode=NAME` – a futam módja: `normal` vagy `endless`.
- `--hardcore[=0|1]` – Hardcore futam (nincs Spirit Healer).
- `--env=ID` – a környezet kényszerítése, pl. `forest_ruin`.
- `--event=ID` – minden hullámon ez az esemény: `guarded_chest`, `defend_totem`, `goblin_caravan` (röviden `chest`, `totem`, `caravan`).
- `--shrine-chance=X` – a szentély esélye minden hullámszünetben (0–1).
- `--dungeon[=0|1]` – a dungeon-portál a következő hullám után nyílik (`=0`: ki).
- `--leaderboard=PATH` – a ranglista fájlja; smoke, demo és nézet-futam is ebbe írja az eredményt.
