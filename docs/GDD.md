# Game Design Document – munkacím: „SmartOnion”

> Felülnézetes, hullámalapú arena survivor (Brotato-szerű) World of Warcraft-hangulatú
> fantasy stílusban, 1–4 fős helyi co-oppal.
>
> Státusz: **tervezés** – kód még nincs. Ez a dokumentum a fejlesztés alapja; minden
> szám kiinduló érték, a balanszolás során változni fog.

---

## 0. Rögzített döntések

| Téma | Döntés |
|---|---|
| Motor | **Godot 4** (legfrissebb stabil 4.x, a projekt indításakor rögzítjük), GDScript |
| Platform | Csak **PC** (Windows / Linux, később Steam) |
| Co-op | Helyi, **1–4 játékos**, kontrollerrel (+1 opcionális billentyű+egér) |
| Fegyverek | **WoW-szerű: Main Hand + Off Hand** (kétkezes fegyver mindkét slotot foglalja) |
| Aktív képességek | **Igen**, kasztonként saját erőforrással (Rage, Mana, Energy, Holy Power, Soul Shard) |
| Menet hossza | **25 hullám** |
| Nehézség | Egyelőre **egy** (Normal), adatvezérelten bővíthető (lásd 9.1) |
| Szintlépés | **Abilityk** (3 véletlen közül) **és** véletlen statok közül lehet választani; az abilityk **goldért fejleszthetők** (lásd 6. fejezet) |
| Talentek | WoW-szerű **talentfák** (kasztonként 3); a **10. szinttől szintenként 1 talentpont**, a hullámok között költhető (lásd 7. fejezet) |
| Fegyverkovácsolás | Brotato-szerűen: **2 azonos fegyver, azonos ritkaságban → 1, eggyel magasabb ritkaságú** (lásd 4.1) |
| Loot / erőforrás | **Közös**: a gold és az XP a csapaté, mindenki osztozik rajta (részletek: 10. fejezet) |
| Grafika | WoW-szerű stilizált low-poly 3D, felülnézeti kamera (részletek: 13. fejezet) |
| Kasztok (MVP) | Warrior, Mage, Paladin, Rogue, Warlock – adatvezérelten bővíthető |

---

## 1. Játékmenet-ciklus

```
Főmenü → Csatlakozás (Press A to join) → Kasztválasztás
  → [ Hullám (harc) → Szintlépés (ability / stat) → Bolt + Trainer + Karakterpanel → Ready ] × 25
  → Győzelem / Vereség képernyő (statisztikák)
```

- **Egy menet = 25 hullám.**
- Hullámhossz: `20 + 5 × (hullám − 1)` másodperc, maximum 60 mp (a 9. hullámtól 60 mp).
- **Különleges hullámok:**
  - **10.** – boss-hullám (mini-raid boss),
  - **20.** – elit-hullám (minden ellenség elit-affixet kap),
  - **25.** – végső boss.

  A boss-hullám addig tart, amíg a boss él (nincs időkorlát, de 90 mp után Enrage).
- Hullám közben a karakterek **automatikusan támadnak** a fegyvereikkel a legközelebbi
  ellenségre; a játékos **mozog** és **képességeket** használ.
- A hullám végén a földön maradt gold és XP automatikusan begyűjtődik.
- Hullám után: szintlépés-választások (ability vagy stat) → bolt / trainer / karakterpanel
  → minden játékos „Ready” → következő hullám.

### Elesés és halál (co-op)

- 0 HP-nál a játékos **elesik** (szellem-alak, lassan mozoghat, nem támad).
- Egy élő társ **3 mp-ig mellette állva** felélesztheti (30% HP-val).
- Ha a hullám végéig nem élesztik fel, a következő hullám elején **50% HP-val** visszatér.
- Ha **mindenki** elesik egyszerre → a menet véget ér.
- Egyjátékos módban az elesés = halál (mint a Brotatóban).

---

## 2. Statok

A WoW stat-nevei, Brotato-szerű, könnyen olvasható számokkal (nincs „rating → %” átváltás,
a százalékos statok közvetlenül %-ban értendők).

### 2.1 Elsődleges statok

| Stat | Hatás | Alapérték |
|---|---|---|
| **Stamina** | +1 Max HP / pont | Max HP alap: 10 |
| **Strength** | Közelharci fegyverek skálázása (flat sebzés) | 0 |
| **Agility** | Fizikai távolsági és tőr fegyverek skálázása (flat sebzés) | 0 |
| **Intellect** | Varázsfegyverek és varázslatok skálázása (flat sebzés), +Mana max | 0 |

### 2.2 Másodlagos statok

| Stat | Hatás | Alap | Plafon |
|---|---|---|---|
| **Critical Strike** | Kritikus esély (%), a krit ×2 sebzés (fegyverenként módosulhat) | 0% | 100% |
| **Haste** | +% támadási sebesség, −% képesség-cooldown (fele hatással), +% erőforrás-regeneráció | 0% | – |
| **Mastery** | Kasztonként más hatás (lásd 3. fejezet) | 0 | – |
| **Versatility** | +% minden sebzés **és** −(fele)% elszenvedett sebzés | 0% | csökkentés max 30% |

### 2.3 Védekező és harmadlagos statok

| Stat | Hatás | Alap | Plafon |
|---|---|---|---|
| **Armor** | Sebzéscsökkentés: `armor / (armor + 15)` | 0 | – (negatív is lehet) |
| **Dodge** | Esély a találat teljes elkerülésére | 0% | 60% |
| **Avoidance** | −% sebzés AoE-ből és lövedékekből | 0% | 50% |
| **Leech** | % esély, hogy egy találat 1 HP-t gyógyít | 0% | 100% |
| **Speed** | +% mozgási sebesség | 0% | – |
| **Spirit** | HP-regeneráció (Brotato-képlet szerint, kb. 5 Spirit ≈ 1 HP / 3 mp) | 0 | – |

### 2.4 Saját (nem WoW) statok

| Stat | Hatás |
|---|---|
| **Fortune** | Jobb ritkaság a boltban és a szintlépésnél, nagyobb esély elit drop-ra |
| **Gold Find** | +% felszedett gold |

> A **Range** nem stat, hanem a fegyver tulajdonsága.

### 2.5 Sebzés képlete

```
alap = fegyver_alapsebzés + Σ (skálázó_stat × skálázási_szorzó)
végső = alap × (1 + Versatility% + egyéb_%) × (krit ? krit_szorzó : 1)
kapott = bejövő × (1 − armor_csökkentés) × (1 − Versatility%/2) × (1 − Avoidance%, ha AoE/lövedék)
```

---

## 3. Kasztok

Minden kaszt tartalmaz:
- **alapstatokat és hátrányt** (Brotato-szerű kompromisszum),
- **páncéltípust** (Armor Specialization bónuszhoz),
- **fegyver-jártasságot** (mit vehet fel),
- **kezdőfegyvert**,
- **erőforrást**,
- **2 alap aktív képességet** (mindig megvannak; a szintlépéskor tanult abilityk ezek mellé jönnek, lásd 6. fejezet),
- **Mastery-hatást**,
- **ability-készletet** (a szintlépéskor felajánlható kaszt-abilityk, lásd 6. fejezet).

### 3.1 Warrior
| | |
|---|---|
| Szerep | Közelharci bruiser |
| Páncél | Plate |
| Kezdőfegyver | One-Hand Sword |
| Jártasság | Minden közelharci fegyver, Shield, kétkezes fegyverek, **Dual Wield** |
| Alap | +5 Max HP, +2 Armor, **−5% Speed** |
| Erőforrás | **Rage** (0–100): +4 / kiosztott találat, +10 / elszenvedett találat, −3 / mp ha nincs találat |
| Képesség 1 | **Whirlwind** – 40 Rage: körkörös csapás, 150% fegyversebzés a környező ellenségekre |
| Képesség 2 | **Charge** – 8 mp CD: rohamozás mozgásirányba, a beérkezéskor 1 mp kábítás |
| Mastery | **Battle Fury** – minél kevesebb a HP, annál több sebzés (pontonként +0,5% minden hiányzó 10% HP után) |

### 3.2 Mage
| | |
|---|---|
| Szerep | Távolsági varázsló, AoE |
| Páncél | Cloth |
| Kezdőfegyver | Wand |
| Jártasság | Wand, Staff, One-Hand Sword, Dagger, Off-hand Tome |
| Alap | **−3 Max HP**, **−2 Armor**, +3 Intellect |
| Erőforrás | **Mana** (100 + 2 × Int), +10 / mp (Haste-tel nő) |
| Képesség 1 | **Blizzard** – 50 Mana: jégeső a legsűrűbb ellenségcsoportra, 3 mp, lassít |
| Képesség 2 | **Blink** – 6 mp CD: rövid teleport mozgásirányba |
| Mastery | **Ignite** – a kritikus találat égést okoz (a krit sebzés pontonként +1%-a 3 mp alatt) |

### 3.3 Paladin
| | |
|---|---|
| Szerep | Tank / támogató – **co-op erősség** |
| Páncél | Plate |
| Kezdőfegyver | Mace + Shield |
| Jártasság | Sword, Mace, kétkezes Sword / Mace, Shield, Off-hand Tome |
| Alap | +3 Max HP, +3 Armor, **−10% sebzés** |
| Erőforrás | **Holy Power** (0–3 pip): +1 minden 5. fegyvertalálat után |
| Képesség 1 | **Consecration** – 10 mp CD: megszentelt föld a lába alatt, 4 mp-ig sebez |
| Képesség 2 | **Word of Glory** – 3 Holy Power: gyógyítja magát és a legközelebbi társat |
| Mastery | **Aura of Devotion** – a közelben lévő társak HP-regenerációt és Armort kapnak (pontonként) |

### 3.4 Rogue
| | |
|---|---|
| Szerep | Gyors, kritikus sebzés, kitérés |
| Páncél | Leather |
| Kezdőfegyver | 2 × Dagger |
| Jártasság | Dagger, One-Hand Sword, Mace, Bow, Gun, **Dual Wield** |
| Alap | +10% Crit, +10% Dodge, **−3 Max HP**, **−1 Armor** |
| Erőforrás | **Energy** (0–100), +15 / mp; **Combo Points** (0–5): +1 minden kritikus találatnál |
| Képesség 1 | **Fan of Knives** – 35 Energy: tőrök minden irányba; minden elhasznált Combo Point +20% sebzés |
| Képesség 2 | **Vanish** – 15 mp CD: 2 mp láthatatlanság, az ellenség elveszti a célt, a következő találat garantált krit |
| Mastery | **Deadly Poison** – a krit mérget tesz az ellenségre (pontonkénti DoT) |

### 3.5 Warlock
| | |
|---|---|
| Szerep | DoT és pet (idéző) |
| Páncél | Cloth |
| Kezdőfegyver | Staff |
| Jártasság | Wand, Staff, Dagger, One-Hand Sword, Off-hand Tome |
| Alap | Állandó **Imp** pet (Intellect-tel skálázódó tűzlövedékek), **−2 Armor**, **−5% Speed** |
| Erőforrás | **Soul Shard** (0–5): +1 minden 12. ölés után |
| Képesség 1 | **Rain of Fire** – 1 Soul Shard: tűzeső a legsűrűbb csoportra, 4 mp |
| Képesség 2 | **Drain Life** – 8 mp CD: 2 mp-es csatornázás a legközelebbi ellenségre, a sebzést gyógyításként kapja vissza |
| Mastery | **Demonic Pact** – +% DoT- és pet-sebzés pontonként |

### 3.6 Bővíthetőség

Új kaszt (pl. Hunter, Priest, Druid, Shaman, Death Knight) = új **ClassData** adatfájl
+ a két képesség saját logikája. A Mail páncéltípus már most létezik a későbbi
Hunter / Shaman miatt.

---

## 4. Fegyverek (MVP: 10 db)

Slotok: **Main Hand**, **Off Hand**. Kétkezes (2H) fegyver mindkettőt elfoglalja.
Dual Wield (Warrior, Rogue): egykezes fegyver az Off Handbe is tehető; mindkettő támad.

| Fegyver | Típus | Skálázás | Range | Jellemző |
|---|---|---|---|---|
| One-Hand Sword | 1H közelharci | 100% Str | rövid | Közepes sebesség, ív alakú csapás |
| Two-Hand Axe | 2H közelharci | 160% Str | rövid | Lassú, széles ív, nagy sebzés |
| Mace | 1H közelharci | 80% Str + 40% Int | rövid | 10% esély 0,5 mp kábításra |
| Dagger | 1H közelharci | 100% Agi | nagyon rövid | Nagyon gyors, krit ×2,5 |
| Bow | 2H távolsági | 120% Agi | hosszú | Közepes sebesség, egy cél |
| Gun | 2H távolsági | 140% Agi | hosszú | Lassú, átlövi az első ellenséget |
| Wand | 1H varázs | 100% Int | közepes | Gyors varázslövedék |
| Staff | 2H varázs | 150% Int | közepes | Lövedék kis robbanással (AoE) |
| Shield | Off Hand | – | – | +Armor, 10% Block (a találat felét elnyeli) |
| Tome | Off Hand | – | – | +Int, +Crit |

- A fegyverek is **ritkaságot** kapnak (lásd 5.2): magasabb ritkaság = nagyobb alapsebzés + bónusz stat.
- A bolt minden játékosnak **csak olyan fegyvert kínál, amit a kasztja használhat**.

### 4.1 Fegyverkovácsolás (Brotato-szerű egyesítés)

**Szabály:** **2 azonos típusú fegyver, azonos ritkaságban → 1 fegyver eggyel magasabb ritkaságban.**

> Példa: 2 × Uncommon Dagger → 1 × Rare Dagger.

**Hol lehet kovácsolni:**
- **Karakterpanel / backpack:** a fegyvert kiválasztva (A) megjelenő menüben „Forge”
  opció, ha van hozzá párja a backpackben vagy a felszerelt slotok között.
- **Boltban, automatikusan:** ha a backpack tele van, és olyan fegyvert veszel, amiből van
  azonos ritkaságú példányod, a vásárlás egyből kovácsol (mint a Brotatóban).
- **Bolti jelzés:** az ilyen ajánlatot üllő-ikon jelöli.

**Költség:** **ingyenes**.

**Ritkaság-szorzók (alapsebzés):**

| Ritkaság | Alapsebzés | Bónusz |
|---|---|---|
| Common | ×1,0 | – |
| Uncommon | ×1,3 | +1 véletlen stat |
| Rare | ×1,7 | +2 stat |
| Epic | ×2,2 | +2 stat, +10% támadási sebesség |
| Legendary | ×3,0 | +3 stat és a fegyvertípus **egyedi Legendary hatása** (pl. Dagger: minden 4. találat mérgező pengét lő) |

**Korlátok:**
- Legendary fölé nem lehet kovácsolni.
- **Artifact** fegyver nem kovácsolható (az hullámonként magától fejlődik, lásd 5.5).
- A kovácsolt fegyver új véletlen bónusz statokat kap a ritkaságának megfelelően.

**Dual Wield szinergia:** két azonos fegyver felszerelve (pl. 2 tőr) erős a Rogue-nak,
de kovácsolva egy erősebb fegyver lesz belőlük. Ez Brotato-szerű döntés:
**szélesség vagy erő?**

---

## 5. Felszerelés

### 5.1 Karakterpanel slotjai

Head, Neck, Shoulders, Chest, Wrist, Hands, Waist, Legs, Feet, Ring 1, Ring 2,
Trinket 1, Trinket 2, Main Hand, Off Hand.

### 5.2 Ritkaság

| Ritkaság | Szín | Stat-keret* | Különlegesség | Elérhető |
|---|---|---|---|---|
| Common | fehér | 4 | – | 1. hullámtól |
| Uncommon | zöld | 7 | – | 2. hullámtól |
| Rare | kék | 11 | – | 4. hullámtól |
| Epic | lila | 16 | kis effekt vagy set-tag | 9. hullámtól |
| Legendary | narancs | 22 | egyedi proc, kézzel tervezett | 14. hullámtól |
| Artifact | világos arany | – | kasztfegyver, fejlődik | csak boss dropból |

\* A **stat-keret** az a pontszám, amiből a generált item a statjait „vásárolja”
(lásd 5.4). A slot szorzója módosítja.

**A bolt ritkasági esélyei (Fortune nélkül)**

| Hullám | Common | Uncommon | Rare | Epic | Legendary |
|---|---|---|---|---|---|
| 1 | 100% | – | – | – | – |
| 5 | 60% | 30% | 10% | – | – |
| 10 | 40% | 35% | 20% | 5% | – |
| 15 | 25% | 32% | 28% | 12% | 3% |
| 20 | 15% | 28% | 32% | 19% | 6% |
| 25 | 8% | 22% | 35% | 25% | 10% |

A köztes hullámokra lineárisan interpolálunk; a Fortune a magasabb ritkaságok felé tolja az eloszlást.

### 5.3 Páncéltípusok

- **Típusok:** Cloth, Leather, Mail, Plate.
- **Mely slotokra vonatkozik:** Head, Shoulders, Chest, Wrist, Hands, Waist, Legs, Feet.
- **Implicit Armor (a slot szorzójával):** Cloth +0, Leather +1, Mail +2, Plate +3.
- **Bármelyik kaszt bármilyen páncélt felvehet.**
- **Armor Specialization:** ha mind a 8 páncélslotban a saját kaszt páncéltípusa van,
  **+10% elsődleges stat** jár érte.
- **Nincs páncéltípusa:** Neck, Ring, Trinket.

### 5.4 Item-generálás

A legtöbb item **generált**: alaptípus + ritkaság + WoW-szerű utótag.

> Példa: *Runed Plate Helm of the Bear* (Rare) → +5 Strength, +6 Stamina, +3 Armor

**Slot-szorzók**

| Slot | Szorzó |
|---|---|
| Head, Chest, Legs | 1,0 |
| Shoulders, Hands, Waist, Feet | 0,8 |
| Neck, Ring | 0,7 (csak másodlagos és harmadlagos statok) |
| Wrist | 0,6 |

**Stat-árak (keretpont / egység)**

| Stat | Ár |
|---|---|
| Str, Agi, Int, Stamina | 1 |
| Crit %, Haste %, Mastery, Speed %, Avoidance % | 1 |
| Versatility %, Dodge %, Spirit | 1,5 |
| Armor, Leech % | 2 |
| Fortune, Gold Find % | 0,5 |

**Utótagok (példák)**

| Utótag | Statok |
|---|---|
| of the Bear | Str + Sta |
| of the Monkey | Agi + Sta |
| of the Eagle | Int + Sta |
| of the Tiger | Str + Agi |
| of the Owl | Int + Spirit |
| of the Wolf | Agi + Spirit |
| of the Boar | Str + Spirit |
| of the Falcon | Agi + Int |
| of Striking | Crit |
| of Swiftness | Haste + Speed |
| of the Sentinel | Armor + Dodge |
| of Fortune | Fortune + Gold Find |

Epic ritkaságtól fölfelé egy plusz másodlagos stat kerül rá.

### 5.5 Kézzel tervezett itemek (MVP)

#### Trinketek (10 db, mind kézzel tervezett, proc- vagy aktiválós hatással)

| Név | Hatás |
|---|---|
| Ember of the Forge | 10% esély találatkor: tűzrobbanás |
| Shard of the Frozen Throne* | Elesés helyett 1× jégbörtön (2 mp sebezhetetlenség), hullámonként egyszer |
| Gnomish Pocket Battery | Minden 10. képesség-használat után 3 mp-ig +30% Haste |
| Vial of Troll Blood | +3 Spirit, alacsony HP alatt dupla regeneráció |
| Goblin Coin Purse | +15% Gold Find, de −1 Armor |
| Idol of the Moon | +5% Crit, éjszakai arénán dupla |
| Banner of the Horde-ish* | A közeli társak +5% sebzést kapnak (co-op) |
| Hourglass of Echoes | A képességek 15% eséllyel nem indítanak cooldownt |
| Lucky Rabbit Foot | +8 Fortune |
| Heart of the Mountain | +8 Max HP, −3% Speed |

\* Munkanevek – a végleges nevek nem utalhatnak Blizzard-márkákra (lásd 14. fejezet).

#### Legendary itemek (8 db)

| Név | Slot | Hatás |
|---|---|---|
| Stormcaller | Main Hand | 5% esély láncvillámra (4 célpont) |
| Crown of Ashes | Head | Az ellenség halálakor 10% eséllyel tűz-AoE |
| Boots of the Wanderer | Feet | +15% Speed, mozgás közben +10% Dodge |
| Ring of Endless Hunger | Ring | +5% Leech, ölésenként 0,5% sebzés a hullám végéig |
| Mantle of the Archmage | Shoulders | A Mana / Energy / Rage költségek −25% |
| Bulwark of the Last Stand | Off Hand | 25% HP alatt 3 mp-es pajzs (hullámonként 1×) |
| Sash of Twin Souls | Waist | A második képesség cooldownja −30% |
| Gauntlets of the Titan | Hands | +20% közelharci sebzés, −10% támadási sebesség |

#### Tier setek (kasztonként 1, Epic ritkaság, 5 darab: Head, Shoulders, Chest, Hands, Legs)

| Kaszt | Set | 2 darab | 4 darab |
|---|---|---|---|
| Warrior | Battlegear of Fury | +10% Rage-termelés | A Whirlwind 30%-ban ingyenes |
| Mage | Regalia of the Arcane | +10% Haste | A Blink után 3 mp-ig +30% sebzés |
| Paladin | Lightforged Plate | +3 Armor | A Word of Glory az összes társat gyógyítja |
| Rogue | Shadowcraft Garb | +5% Crit | A Vanish után 4 mp-ig +50% krit sebzés |
| Warlock | Felheart Raiment | +10% pet-sebzés | A Rain of Fire 20%-ban nem fogyaszt Soul Shardot |

#### Artifact fegyverek (kasztonként 1)

- A 10. hullám bossa dobja: minden játékos megkapja a **saját kasztja** Artifactját.
- Main Hand fegyver (a kétkezes variánsok mindkét slotot foglalják).
- Minden hullám végén **fejlődik** (+statok); a 15. és a 20. hullám után egy-egy új tulajdonságot nyit meg.

| Kaszt | Artifact | Hatás |
|---|---|---|
| Warrior | *Earthsplitter* (2H Axe) | A Whirlwind földrengést hagy maga után |
| Mage | *Staff of the Frostwyrm* (Staff) | A Blizzard minden 4. alkalommal dupla méretű |
| Paladin | *Dawnbreaker* (Mace) | A Consecration gyógyítja a benne álló társakat |
| Rogue | *Fangs of the Shadow* (2 tőr, mindkét slot) | Minden 5. krit ingyen Fan of Knives-t lő |
| Warlock | *Skull of the Damned* (Staff) | Egy második pet: Voidwalker (tank) |

### 5.6 Backpack

- **10 hely játékosonként.**
- **Megvásárlás:** a megvett item a backpackbe kerül, onnan lehet felvenni.
- **Csere:** felvételkor a régi item a backpackbe kerül; ha tele van, el kell adni valamit.
- **Eladás:** a vételár 35%-a, a közös kasszába.

---

## 6. Szintlépés és abilityk

Ez a játék fő újítása a Brotatóhoz képest: a szintlépés nem csak statot ad, hanem
**abilityket**, és ezek a menet során **goldért fejleszthetők**.

### 6.1 Szintlépés

- **XP:** közös csapat-XP. Az `n.` szinthez szükséges XP: `(n + 3)²` (Brotato-képlet).
- **Választás:** a hullám végén, minden megszerzett szint után, minden játékos **1 kártyát
  választ 5 közül**:
  - **3 ability-kártya:** véletlenül húzva a kaszt saját és az általános ability-készletből.
    Ha egy már megtanult ability jön, az **ingyenes rangemelést** jelent (+1 Rank).
  - **2 stat-kártya:** véletlen stat-fejlesztések ritkasággal, pl. Common: +3 Stamina,
    Rare: +3% Crit és +2 Agility.
- **Reroll:** ára `hullám + 2` gold, minden további reroll ugyanabban a körben +2.
- **Kompromisszum:** ability helyett statot választani akkor éri meg, ha a slotok már
  tele vannak, vagy ha a build egy konkrét statra épül.

### 6.2 Ability-slotok

| Slot | Darab | Irányítás | Tartalom |
|---|---|---|---|
| Alap képesség | 2 | RT, LT | A kaszt 2 fix képessége (3. fejezet) |
| Tanult aktív | 2 | RB, LB | Szintlépéskor tanult **Active** abilityk |
| Tanult automatikus | 4 | – | **Auto-cast** abilityk: cooldown lejártakor maguktól sülnek el |

- Minden abilitynek fix típusa van: **Active** vagy **Auto-cast**.
- Ha a megfelelő slotok tele vannak, egy új ability felvételekor **le kell cserélni** egy
  régit. A régi rangjainak goldra váltott értékének 50%-a visszajár.
- Ha a slotok tele vannak és a játékos nem akar cserélni, a felajánlott kártyák között
  a megtanult abilityk rangemelései súlyozottan gyakrabban jönnek.

### 6.3 Rangok és fejlesztés goldért (Trainer)

WoW-hangulatban az abilityknek **rangjaik** vannak: **Rank I–V**.

- **Hogyan nő a rang:**
  - **szintlépéskor ingyen**, ha ugyanazt az abilityt választod újra,
  - vagy **goldért** a hullám utáni képernyő **Trainer** fülén (mint a WoW-os kaszt-trainer).
- **Ár:** `25 × jelenlegi rang × (1 + 0,08 × (hullám − 1))`.
- **Mit ad egy rang:**

  | Rang | Hatás |
  |---|---|
  | II, IV | +25% sebzés / hatás, −10% cooldown |
  | III | +1 extra hatás (pl. +1 lövedék, nagyobb terület, extra lassítás) |
  | V | **Specializáció:** választás 2 módosítás közül, ami megváltoztatja az ability működését (pl. a Fireball pattog vagy robban) |

- A rangok és a gold-ár együtt adják a gazdasági döntést: **új item vagy erősebb ability?**

### 6.4 Ability-készlet (MVP)

Kasztonként 6 saját ability + 6 általános, amit minden kaszt megkaphat.

| Kaszt | Ability | Típus | Hatás (Rank I) |
|---|---|---|---|
| Warrior | Thunder Clap | Auto | Körkörös csapás, 2 mp lassítás |
| Warrior | Heroic Leap | Active | Ugrás a célpontra, AoE becsapódás |
| Warrior | Execute | Active | Hatalmas csapás; 20% HP alatti ellenséget azonnal megöl (bossra: dupla sebzés) |
| Warrior | Battle Shout | Auto | 6 mp-re +10% sebzés neked és a közeli társaknak |
| Warrior | Shield Wall | Active | 4 mp-ig −50% elszenvedett sebzés |
| Warrior | Bladestorm | Auto | 3 mp-es forgás, közben nem lehet lassítani |
| Mage | Fireball | Auto | Tűzgolyó a legközelebbi ellenségre, égést okoz |
| Mage | Frost Nova | Auto | Ha ellenség ér hozzád: fagyasztás a környezetben |
| Mage | Arcane Missiles | Auto | 5 kis lövedék véletlen célpontokra |
| Mage | Ice Barrier | Auto | Elnyelő pajzs, amíg el nem fogy |
| Mage | Pyroblast | Active | 1 mp felkészülés, óriási tűzgolyó |
| Mage | Meteor | Active | Meteor a legsűrűbb csoportra, égő földet hagy |
| Paladin | Hammer of Justice | Auto | Kalapácsdobás, 1,5 mp kábítás |
| Paladin | Avenger's Shield | Auto | Pattogó pajzs, 3 célpont |
| Paladin | Divine Storm | Auto | Körkörös szent csapás, a közeli társakat gyógyítja |
| Paladin | Blessing of Kings | Auto | Minden társ +5% minden statot kap 10 mp-re |
| Paladin | Divine Shield | Active | 3 mp sebezhetetlenség |
| Paladin | Lay on Hands | Active | Teljesen gyógyítja a legkevesebb HP-jú társat (hosszú CD) |
| Rogue | Shuriken Toss | Auto | 3 shuriken legyezőben |
| Rogue | Blade Flurry | Auto | 5 mp-ig a találatok egy második célpontot is érnek |
| Rogue | Poison Bomb | Auto | Méregfelhő a földön |
| Rogue | Cheat Death | Auto (passzív) | Halálos találat helyett 1 HP, 60 mp-enként |
| Rogue | Shadowstep | Active | Teleport a célpont mögé, a következő találat krit |
| Rogue | Killing Spree | Active | 2 mp-ig ugrálás az ellenségek között |
| Warlock | Corruption | Auto | DoT, ami az ellenség halálakor átterjed |
| Warlock | Shadow Bolt | Auto | Erős árnylövedék |
| Warlock | Seed of Corruption | Auto | Mag egy ellenségbe; a halálakor AoE robbanás |
| Warlock | Summon Voidwalker | Auto (pet) | Második pet, magára vonja az ellenségeket |
| Warlock | Fear | Active | Az ellenségek 2 mp-ig menekülnek a közeledből |
| Warlock | Summon Infernal | Active | 8 mp-re démon idézése (hosszú CD, 1 Soul Shard) |
| Általános | Bandage | Active | 3 mp alatt 30% HP gyógyítás |
| Általános | Sprint | Active | 3 mp-ig +50% Speed |
| Általános | Engineer's Bomb | Auto | Robbanó bomba dobása |
| Általános | War Stomp | Auto | Kis AoE kábítás |
| Általános | Spirit Wolf | Auto (pet) | Szellemfarkas társ |
| Általános | Berserking | Active | 6 mp-ig +20% Haste |

**Iskolák (tagek):** minden ability kap egy iskola-taget:
- Physical,
- Fire,
- Frost,
- Arcane,
- Holy,
- Shadow,
- Nature.

A talentek ezekre az iskolákra is hatnak (pl. „+10% Fire sebzés”), így az ability-választás
és a talentfa összeépül.

---

## 7. Talentrendszer (WoW-szerű talentfák)

A szintlépési kártyák mellett **külön talentpontok** is járnak, a klasszikus WoW
talentfák mintájára.

### 7.1 Pontok

- **A 10. szinttől minden szintlépés +1 talentpontot ad**, a kártyaválasztás mellé.
- A pontok **a hullámok között**, a **Talents** fülön költhetők el. Nem kötelező
  azonnal elkölteni.
- **Várható pontszám egy menet alatt:** kb. 15–20 (a menet végére a 25.–30. szint körül).
- **XP-skálázás co-opban:** az XP-igény a játékosszámmal nő (`× (1 + 0,6 × (játékosok − 1))`),
  hogy a szintlépés üteme 1–4 játékossal hasonló legyen.

### 7.2 A fák felépítése

Minden kasztnak **3 fája** van (a WoW-os specializációk szerint):

| Kaszt | Fa 1 | Fa 2 | Fa 3 |
|---|---|---|---|
| Warrior | Arms | Fury | Protection |
| Mage | Arcane | Fire | Frost |
| Paladin | Holy | Protection | Retribution |
| Rogue | Assassination | Combat | Subtlety |
| Warlock | Affliction | Demonology | Destruction |

Egy fa **5 szintből (tier)** áll:

| Tier | Feltétel (pont ebben a fában) | Tartalom |
|---|---|---|
| 1 | 0 | 2 talent, egyenként max 3 pont |
| 2 | 3 | 2 talent, egyenként max 3 pont |
| 3 | 6 | 1 talent (max 2 pont) + 1 **képesség-módosító** (1 pont) |
| 4 | 9 | 2 talent, egyenként max 3 pont |
| 5 | 12 | **Capstone** (1 pont) – nagy, buildet meghatározó hatás |

- Egy fa teljes kitöltése **22 pont**, tehát egy menetben **egy fát lehet majdnem
  végigvinni**, vagy két fa között el lehet osztani a pontokat (hibrid build), ahogy a
  klasszikus WoW-ban.
- Egyes talentek **előfeltételhez** kötöttek (nyíl a fában, mint a WoW-ban).

### 7.3 Respec

- A Talents fülön „Reset Talents”: minden pont visszajár.
- **Ár:** az első reset 20 gold, utána minden reset az előző ár duplája
  (a WoW-os respec-díj mintájára).

### 7.4 Példa: Warrior – Arms fa

| Tier | Talent | Pont | Hatás / pont |
|---|---|---|---|
| 1 | Deflection | 3 | +2% Dodge |
| 1 | Tactical Mastery | 3 | +5 Rage induláskor és +3% Rage-termelés |
| 2 | Improved Charge | 3 | A Charge +0,3 mp kábítás és −1 mp CD |
| 2 | Deep Wounds | 3 | A krit 3 mp-es vérzést okoz (a sebzés 10%-a) |
| 3 | Two-Handed Specialization | 2 | +5% sebzés kétkezes fegyverrel |
| 3 | *Sweeping Strikes* (módosító) | 1 | A Whirlwind után 5 mp-ig a csapások +1 célpontot érnek |
| 4 | Impale | 3 | +10% krit sebzés |
| 4 | Sudden Death | 3 | 3% esély találatkor, hogy az Execute CD-je lenulláz |
| 5 | **Mortal Strike** (capstone) | 1 | Minden 5. fegyvertalálat 250%-os csapás, ami a célpontot −50% gyógyulásra ítéli; Execute-tal szinergiában |

### 7.5 Capstone-ok (minden kaszt, minden fa)

| Kaszt | Fa | Capstone | Hatás |
|---|---|---|---|
| Warrior | Arms | Mortal Strike | lásd 7.4 |
| Warrior | Fury | Rampage | Ölésenként +2% sebzés (max 20%), 5 mp-ig tart |
| Warrior | Protection | Last Stand | Halálos találat helyett +30% Max HP 10 mp-re (hullámonként 1×) |
| Mage | Arcane | Arcane Power | A Mana-költségek +30%-kal nőnek, de minden sebzés +25% |
| Mage | Fire | Combustion | Minden krit tűzbe borítja a célpont környékét |
| Mage | Frost | Ice Lance | A fagyott célpontokra tett minden találat dupla és garantált krit |
| Paladin | Holy | Holy Shock | Automatikus: 4 mp-enként gyógyítja a legsérültebb társat, vagy sebzi a legközelebbi ellenséget |
| Paladin | Protection | Holy Shield | +20% Block, és a blokkolt találat szent sebzést ad vissza |
| Paladin | Retribution | Seal of Command | 15% esély találatkor 70%-os extra szent csapásra |
| Rogue | Assassination | Cold Blood | A Fan of Knives minden 3. használata garantált krit, +50% krit sebzéssel |
| Rogue | Combat | Adrenaline Rush | Az Energy-regeneráció dupla, ha 3+ ellenség van közel |
| Rogue | Subtlety | Shadow Dance | A Vanish után 5 mp-ig minden találat krit |
| Warlock | Affliction | Unstable Affliction | Ha egy DoT-ot lejárat előtt eltávolít egy ellenség, AoE-robbanás és 1 mp-es Silence |
| Warlock | Demonology | Soul Link | A sebzés 20%-át a pet viseli el; a pet +30% sebzés |
| Warlock | Destruction | Conflagrate | A Rain of Fire égő földet hagy, és minden kritje +1 Soul Shardot ad (10% eséllyel) |

> **MVP-terjedelem:** mind az 5 kaszt × 3 fa váza, és mind a 15 capstone. A részletes
> tier 1–4 talenteket a Warrior Arms mintája alapján, fánként egyenként tervezzük ki a
> fejlesztés során (`TalentTreeData` adatfájlokban).

### 7.6 Kapcsolat a többi rendszerrel

- A szintlépési **ability-kártyák** szélességet adnak: új eszközöket.
- A **Trainer-rangok** goldért erősítik az abilityket.
- A **talentfa** az irányt adja meg: a kaszt identitását és a buildet.
- Az ability-iskolák (tagek) miatt a talentek a tanult abilitykre is hatnak
  (pl. a Fire fa erősíti a Fireball és a Meteor abilityt).

---

## 8. Ellenségek

A fajok WoW-hangulatúak, de saját nevűek.

| Név | Leírás | Viselkedés | Megjelenik |
|---|---|---|---|
| **Skeleton Grunt** | Csontváz kardos | Egyenesen a legközelebbi játékosra jön | 1. hullámtól |
| **Candlekin** | Kis gyertyás bányász-lény | Gyors, gyenge, rajban jön | 2. hullámtól |
| **Marsh Gurgler** | Hal-ember | 4–6-os csoportban, rövid nekirugaszkodás | 3. hullámtól |
| **Troll Axethrower** | Troll | Távolról baltát dob, tartja a távolságot | 5. hullámtól |
| **Plague Ghoul** | Ghoul | Halálakor méregtócsát hagy | 7. hullámtól |
| **Cultist Acolyte** | Kultista | Gyógyítja / pajzsolja a többieket, elsődleges célpont | 9. hullámtól |
| **Flesh Golem** | Varrott óriás | Lassú, sok HP, időnként maga felé húz | 12. hullámtól |

**Loot Goblin** (ritka, különleges ellenség)

- **Megjelenés:** a 3. hullámtól hullámonként 15% eséllyel jelenik meg (a Fortune növeli),
  hullámonként legfeljebb 1. Elit- és boss-hullámon nem jön.
- **Bejelentés:** csilingelő hang és kiírás: „*A Loot Goblin appeared!*”.
- **Viselkedés:** **nem támad, menekül** a játékosoktól, gyors, sok HP-ja van.
  15 mp után portált nyit, és eltűnik.
- **Találatkor:** minden találatnál goldérmék szóródnak belőle.
- **Ha megölik:**
  - 30× a hullám átlagos ellenség-goldja,
  - nagy XP-csomag (kb. 25 normál ellenségnyi),
  - garantált item (Rare+), Need / Greed / Pass dobással.
- **Ritka változat (később):** *Golden Goblin* – 1% eséllyel, csak goldot dob, de
  nagyon sokat.
- **Co-op:** a csapatnak össze kell hangolnia, hogy körbezárják (pl. Frost Nova,
  Hammer of Justice, Fear).

**Elitek**

- Az 5. hullámtól véletlenszerűen jelennek meg, ezüst sárkányos portrékerettel és névvel.
- 3× HP, 1 véletlen affix (Shielding, Enraged, Frenzied, Vampiric).
- Garantált itemet dobnak (Uncommon+), amit a hullám végén **Need / Greed / Pass** dobással
  osztunk el (lásd 10. fejezet).

**Bossok**

- **10. hullám – Lich Commander Morvain**
  - Jégkörök a földön: „ne állj benne”.
  - Csontváz-idézés.
  - Kúp alakú fagylehelet: „szóródjatok szét”.
  - 50% HP-nál fázisváltás.
- **20. hullám – Elit-hullám:** nincs boss, de minden ellenség elit-affixet kap, és több
  elit is jön.
- **25. hullám – Vor'thalax, the Burning Tyrant** (démon, végső boss)
  - Tűzmezők.
  - Meteor, amit **meg kell osztani**: minél többen állnak a jelölt körben, annál kisebb a sebzés (co-op mechanika).
  - Add-hullámok.
  - Enrage 90 mp után.

---

## 9. Hullámok és skálázás

- **25 hullám**; a hullámhossz a 9. hullámtól 60 mp.

- **Ellenség HP és sebzés:** hullámonként nő (kiinduló érték: +12% HP és +8% sebzés hullámonként, összeadódva).
- **Spawn:** a spawnpontok a pálya szélén és véletlen belső pontokon vannak, 1 mp-es
  figyelmeztető jellel (piros rúna a földön), mint a Brotatóban.
- **Co-op skálázás:** minden további játékos után
  - +60% ellenségszám,
  - +20% ellenség-HP,
  - a boss HP-ja ×(1 + 0,75 × (játékosok − 1)).
- **Teljesítménycél:** egyszerre legfeljebb ~150 ellenség a képernyőn (szükség esetén LOD és
  egyszerűsített animáció).

### 9.1 Nehézségi szintek

- **MVP:** csak **Normal**.
- **Adatvezérelt:** a nehézség egy `DifficultyData` fájl, ami tartalmazza:
  - ellenség-HP és -sebzés szorzó,
  - spawn-sűrűség,
  - elit-esély,
  - bolti árak szorzója,
  - extra affixek.
- **Később tervezett:**
  - **Heroic:** +HP és +sebzés, több elit.
  - **Mythic:** hullámonként változó affixek (pl. „Bolstering”, „Volcanic”), és feloldható
    jutalmak.

---

## 10. Közös loot és gazdaság

**Gold**

- **Csapat-kassza:** minden felszedett gold (bárki szedi fel) a közös kasszába kerül.
- **Szétosztás:** a hullám végén a kassza **egyenlő arányban** szétoszlik a játékosok
  pénztárcáiba. A maradék a következő körre a kasszában marad.
- **Miért így:** mindenki osztozik a lootban, de a boltban senki nem költheti el a másik
  részét. (Alternatíva: egyetlen közös pénztárca, amiből bárki vásárol – a
  playtesteken eldönthetjük.)
- **Ellenségenkénti gold:** 1 alap, elit 10, boss 50, Loot Goblin lásd 8. fejezet. A Gold Findet minden játékos
  külön adja hozzá a felszedéshez.

**XP**

- **Közös XP-sáv:** az egész csapat egyszerre lép szintet, mindenki kap választást.

**Elit- és boss-drop**

- Need / Greed / Pass dobás, WoW-stílusban (1–100 közötti dobás, a Need erősebb a Greednél).
- Need csak akkor választható, ha a játékos kasztja használni tudja az itemet.

**Gold felhasználása:** item vásárlás (bolt), **ability rangemelés (Trainer, 6.3)**,
szintlépési reroll, bolti reroll.

**Bolt**

- Játékosonként saját bolt-panel, **4 ajánlattal**.
- **Lock:** egy ajánlat zárolható a következő körre.
- **Reroll:** ára `hullám × 2 + 2`, körönként minden további reroll +2-vel drágább.
- **Árak:** ritkaság alapár × `(1 + 0,08 × (hullám − 1))`.

  | Ritkaság | Alapár |
  |---|---|
  | Common | 15 |
  | Uncommon | 30 |
  | Rare | 55 |
  | Epic | 90 |
  | Legendary | 140 |

- **Ajándék:** gold átadható egy társnak, kis összegekben.

---

## 11. Irányítás

### Kontroller (Xbox-elnevezéssel)

| Gomb | Harcban | Menüben |
|---|---|---|
| Bal kar | Mozgás | Navigáció |
| Jobb kar | (Opció) kézi célzás; alapból auto-aim | Tooltip görgetés |
| RT | Alap képesség 1 | – |
| LT | Alap képesség 2 | – |
| RB | Tanult aktív ability 1 | Fül váltás jobbra |
| LB | Tanult aktív ability 2 | Fül váltás balra |
| A | Felélesztés (tartva) | Kiválaszt / vásárol / felvesz |
| B | – | Vissza |
| X | – | Eladás |
| Y | – | Összehasonlítás a felvett itemmel |
| Start | Szünet | Ready |

### Billentyű + egér (1 játékos)

| Bemenet | Funkció |
|---|---|
| WASD | Mozgás |
| Egér | Célzás (opcionális) |
| Bal / jobb egérgomb | Alap képesség 1 / 2 |
| Q / E | Tanult aktív ability 1 / 2 |
| F | Felélesztés |
| Esc | Szünet |

A képességek alapból a **legközelebbi ellenségre / a legsűrűbb csoportra** céloznak
(Blizzard, Rain of Fire), a mozgásos képességek (Charge, Blink) pedig **mozgásirányba**
indulnak.

---

## 12. Felület (UI)

**Csatlakozási képernyő**

- 4 hely; „Press A to join”; kasztválasztás karakter-előnézettel.

**Harci HUD**

- **Unit frame-ek** a 4 sarokban, WoW-stílusban:
  - portré, zöld HP-sáv,
  - erőforrás-sáv kaszt-színnel (Rage piros, Mana kék, Energy sárga, Holy Power arany pipek, Soul Shard lila pipek),
  - ability-sáv: 2 alap + 2 tanult aktív + 4 auto-cast ikon, cooldown-animációval és
    rang-jelzéssel (I–V).
- **Felül középen:** hullám száma, visszaszámláló, csapat-kassza.
- **Alul:** közös XP-sáv (WoW-lila).
- **Lebegő számok:** sebzés, krit (nagyobb, sárga), gyógyítás (zöld).

**Hullám utáni képernyő**

- **Elrendezés:** a képernyő 1/2/3/4 panelre oszlik (játékosonként egy).
- **Szintlépés:** előbb egy szintlépés-képernyő jön (3 ability + 2 stat kártya,
  szintenként), utána a fülek.
- **Fülek:** **Shop | Trainer | Talents | Character**.
- **Trainer fül:** a megtanult abilityk listája, a jelenlegi rang, a következő rang
  hatása, ára és egy „Train” gomb. A Rank V-nél a 2 specializáció közül lehet választani.
- **Talents fül:** WoW-szerű elrendezés – a 3 fa egymás mellett, tierenként sorokban.
  - Kontrollerrel rácsban lehet lépkedni; „A” = pont elköltése, „X” = pont visszavétele
    a fül bezárása előtt.
  - Felül a szabad pontok száma, alul a „Reset Talents” gomb és az ára.
- **Kovácsolás:** a Character fülön a fegyvert kiválasztva (A) egy műveletmenü jelenik meg:
  Equip / Forge / Sell. A Forge csak akkor aktív, ha van azonos párja. A boltban üllő-ikon
  jelzi a kovácsolható ajánlatot.
- **Character fül:** WoW-szerű karakterpanel – bal oldalon a páncélslotok, jobb oldalon az
  ékszerek és trinketek, alul a fegyverek, középen a karakter 3D modellje, alatta a statlista.
- **Backpack:** 10 hely a panel alján.
- **Tooltip:** pergamen / sötét keretes WoW-tooltip. A ritkasághoz illő színű név, a stat-sorok
  után összehasonlítás (+zöld / −piros); a set-bónuszok szürkén vagy aktívan.
- **Indulás:** a „Ready” jelzés után indul a következő hullám, ha mindenki kész van
  (vagy 60 mp-es időkorlát után, beállításokban kikapcsolható).

---

## 13. Grafikai irány

- **Stílus:** WoW-szerű stilizált fantasy.
  - Zömök, nagyfejű, „chibi” arányú hősök (a Brotato-féle kis karakterek hangulata).
  - Telített színek, kézzel festett hatású textúrák.
  - Enyhe toon-shading, rim light, vékony körvonal.
- **Technika:**
  - Godot 4, **3D low-poly** modellek.
  - Kb. 55–60°-os felülnézeti kamera (keskeny FOV vagy ortografikus).
  - A kamera a csapat középpontját követi, és dinamikusan zoomol, hogy mindenki látszódjon.
- **Assetek (első kör, licencek letöltéskor ellenőrizendők):**
  - **KayKit** csomagok (Kay Lousberg, CC0): Adventurers (Knight, Barbarian, Mage, Rogue),
    Skeletons, Dungeon Remastered.
  - **Quaternius** (CC0): szörnyek és fantasy kellékek.
  - Ikonok: **game-icons.net** (CC BY 3.0 – feltüntetéssel), WoW-szerű keretbe és színezésbe
    rakva.
  - Hangok: Kenney (CC0), freesound.org (licenc szerint).
  - Betűtípus: *Cinzel* vagy hasonló, szabadon használható fantasy font.
- **UI-téma:** sötét kő és arany keretek, pergamen tooltip, ritkaság-színek a WoW
  konvenciója szerint.
- **Arénák (MVP: 1):** *Elwynn-szerű erdei tisztás*. Később: havas dombok, sivatag, démoni pusztaság.

---

## 14. Jogi megjegyzés (szellemi tulajdon)

- **Szabadon használható:** a stílus, a kasztnevek (Warrior, Mage, …), az általános
  stat-nevek és a ritkaság-színek.
- **Nem használjuk:** Blizzard-tulajdonnevek (Azeroth, Murloc, Thunderfury, Ashbringer,
  Horde/Alliance stb.), logók, eredeti assetek, a Friz Quadrata font.
- A dokumentumban `*`-gal jelölt nevek munkanevek, publikálás előtt cserélendők.

---

## 15. Technikai architektúra (terv, nem kód)

**Adatvezérelt felépítés:** Godot Custom Resource-ok (`.tres`) a tartalomhoz.

- `ClassData`: alapstatok, páncéltípus, jártasságok, erőforrás, alap képességek, ability-készlet.
- `WeaponData`, `ItemData` (alaptípus + kézzel tervezett itemek), `AffixData` (utótagok).
- `AbilityData`: típus (Active / Auto), iskola-tag, rangok, specializációk, kaszt-kötés.
- `TalentTreeData` / `TalentData`: tierek, pontlimitek, előfeltételek, hatások.
- `SetData`, `EnemyData`, `WaveData`, `BossData`, `DifficultyData`.

**Fő rendszerek**

| Rendszer | Feladat |
|---|---|
| `PlayerManager` | Eszközök (kontroller / billentyűzet) játékoshoz rendelése, csatlakozás / kilépés |
| `RunState` | Hullámszám, közös kassza, közös XP, játékosállapotok |
| `StatBlock` | Alapstatok + módosítók (item, ability, talent, buff) → végső statok |
| `CombatSystem` | Sebzés képlete, krit, DoT, gyógyítás, procok |
| `AbilitySystem` | Erőforrások, cooldownok, slotok, rangok, auto-cast, képességek végrehajtása |
| `LevelUpSystem` | Ability- és stat-kártyák húzása, reroll, talentpontok kiosztása |
| `TalentSystem` | Talentfák, pontköltés, előfeltételek, respec |
| `ForgeSystem` | Fegyverkovácsolás (azonos típus + ritkaság → eggyel magasabb ritkaság) |
| `Spawner` / `WaveDirector` | Hullámok, spawnolás, skálázás |
| `LootSystem` | Item-generálás, ritkaság, Need/Greed |
| `ShopSystem` | Ajánlatok, lock, reroll, árak |
| `Inventory` / `Equipment` | Backpack, slotok, set-bónuszok, Armor Specialization |
| UI | Játékosonkénti panelek |

**Projektstruktúra (tervezett)**

```
/project.godot
/data/        classes/ abilities/ talents/ weapons/ items/ affixes/ sets/ enemies/ waves/ difficulties/
/scenes/      main/ arena/ player/ enemies/ ui/
/scripts/     systems/ abilities/ ai/
/assets/      models/ textures/ icons/ audio/ fonts/
/tests/       (GUT – egységtesztek a statokra, sebzésre és item-generálásra)
/docs/        GDD.md
```

**Mentés (MVP):** csak beállítások. Később meta-progresszió (kaszt- és item-feloldások).

---

## 16. Mérföldkövek

| # | Mérföldkő | Tartalom |
|---|---|---|
| M0 | Váz | Godot projekt, 1–4 kontroller csatlakozása, mozgó placeholder karakterek, kamera |
| M1 | Harc magja | Auto-attack MH/OH fegyverrel, 3 ellenségtípus, gold/XP felszedés, hullám-időzítő |
| M2 | Felszerelés | Statrendszer, item-generálás, ritkaság, bolt, backpack, karakterpanel, tooltip |
| M3 | Kasztok | 5 kaszt, erőforrások, 2-2 alap képesség, Mastery |
| M4 | Abilityk | Szintlépés (ability- és stat-kártyák), ability-slotok, auto-cast, Trainer és rangok |
| M5 | Mélység | Talentfák (5 kaszt × 3 fa), fegyverkovácsolás, setek, elitek, Loot Goblin, Need/Greed, közös kassza |
| M6 | Tartalom | Mind a 7 ellenség, 2 boss + elit-hullám, Artifactok, 25 hullám balansza (Normal) |
| M7 | Csiszolás | Grafikai réteg (assetek, shaderek, VFX), hangok, menük, beállítások |

---

## 17. Nyitott kérdések

1. **Karakterek kinézete:** a repó neve *smartonion* – a Brotato burgonyáihoz hasonlóan a
   hősök **hagymák** legyenek WoW-páncélban, vagy maradjanak kis chibi humanoidok?
2. **Gold:** megfelel-e az „egyenlő szétosztás” értelmezés, vagy egyetlen közös pénztárca legyen?
3. **A játék végleges címe.**
4. **Nyelv:** a játék felülete angol legyen (WoW-terminológia), vagy magyar?
5. **Szintlépés:** a „1 kártya 5-ből (3 ability + 2 stat)” megfelel, vagy legyen külön
   ability- **és** stat-választás minden szintnél?
