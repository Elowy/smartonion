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
| Vissza / unready / kilépés a lobbyból | B | Esc / Backspace |
| Mozgás | bal kar | WASD / nyilak |
| Szünet | Start | P / Esc |

A fegyverek automatikusan támadnak. Elesett társat úgy lehet feléleszteni, hogy 5 másodpercig mellette állsz.

### Ami ebben a verzióban van (M0 + M1)

- **Kör:** főmenü → lobby (1–4 játékos, 5 kaszt) → 25 hullám → győzelem / vereség → lobby.
- **Harc:** automatikus közelharci és lövedékes fegyverek, 4 ellenségtípus, közös gold és XP.
- **Co-op:** felélesztés cast barral; kontroller lecsatlakozásakor szünet.

A bolt, az itemek, a loot, az abilityk és a talentek a következő mérföldkövekben jönnek (lásd a GDD 16. fejezetét). Addig a hősök szintenként egy kis ideiglenes bónuszt kapnak.

## Fejlesztői parancsok

```bash
godot --headless --path . --import                                   # import
godot --headless --path . -s res://tests/run_tests.gd                # unit tesztek
godot --headless --path . -- --smoke --waves=3                       # 4 botos próbajáték
godot --path . -- --demo                                             # botok játszanak (nézhető)
```
