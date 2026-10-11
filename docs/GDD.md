# SmartOnion – Game Design Document

> Felülnézetes, hullámalapú arena survivor (Brotato-szerű) World of Warcraft-hangulatú
> fantasy stílusban, 1–4 fős helyi co-oppal. A hősök **hagymák WoW-páncélban**.
>
> Státusz: **tervezés** – kód még nincs. Ez a dokumentum a fejlesztés alapja; minden
> szám kiinduló érték, a balanszolás során változni fog.

---

## 0. Rögzített döntések

| Téma | Döntés |
|---|---|
| Cím | **SmartOnion** |
| Hősök | **Hagymák WoW-páncélban** (mint a Brotato krumplijai) |
| Nyelv | A játék felülete **angol** (WoW-terminológia); a szövegek kulcsokból jönnek, így később lokalizálható |
| Motor | **Godot 4** (legfrissebb stabil 4.x, a projekt indításakor rögzítjük), GDScript |
| Platform | Csak **PC** (Windows / Linux, később Steam) |
| Co-op | Helyi, **1–4 játékos**, kontrollerrel (+1 opcionális billentyű+egér) |
| Fegyverek | **WoW-szerű: Main Hand + Off Hand** (kétkezes fegyver mindkét slotot foglalja) |
| Aktív képességek | **Igen**, kasztonként saját erőforrással (Rage, Mana, Energy, Holy Power, Soul Shard) |
| Menet hossza | **25 hullám** |
| Nehézség | Egyelőre **egy** (Normal), adatvezérelten bővíthető (lásd 9.1) |
| Szintlépés | **5 kártya, abilityk és statok keverve**, 1 választható; goldért rerollolható; az abilityk **goldért fejleszthetők** (lásd 6. fejezet) |
| Talentek | WoW-szerű **talentfák** (kasztonként 3); a **10. szinttől szintenként 1 talentpont**, a hullámok között költhető (lásd 7. fejezet) |
| Loot | Az ellenségek **itemet dobnak**; hullám után a közös képernyőn **Need / Greed / Pass** dobás, mint a WoW-ban. A loot **erősebb**, mint a bolt kínálata (lásd 10.1) |
| Fegyverkovácsolás | Brotato-szerűen: **2 azonos fegyver, azonos ritkaságban → 1, eggyel magasabb ritkaságú** (lásd 4.1) |
| Loot / erőforrás | **Egyetlen közös pénztárca** és közös XP – bárki költhet belőle, ezért koordinációt igényel (részletek: 10. fejezet) |
| Grafika | WoW-szerű stilizált low-poly 3D, felülnézeti kamera (részletek: 13. fejezet) |
| Kasztok (MVP) | Warrior, Mage, Paladin, Rogue, Warlock – adatvezérelten bővíthető |

---

## 1. Játékmenet-ciklus

```
Főmenü → Csatlakozás (Press A to join) → Kasztválasztás
  → [ Hullám (harc) → Loot roll (Need / Greed / Pass) → Szintlépés (ability / stat)
      → Bolt + Trainer + Talents + Karakterpanel → Ready ] × 25
  → Győzelem / Vereség képernyő (statisztikák)
```

- **Egy menet = 25 hullám.**
- Hullámhossz:
  - **1–10. hullám:** `20 + 5 × (hullám − 1)` másodperc, legfeljebb 60 mp (a 9–10. hullám 60 mp).
  - **A 10. hullám felett hullámonként +10 mp:** 11. = 70 mp, 15. = 110 mp, 20. = 160 mp,
    25. = 210 mp.
  - Egy teljes menet így kb. **42 perc** harc, plusz a hullámok közötti idő.
- **Különleges hullámok:**
  - **10.** – boss-hullám (mini-raid boss),
  - **20.** – elit-hullám (minden ellenség elit-affixet kap),
  - **25.** – végső boss.

  A boss-hullám addig tart, amíg a boss él (nincs időkorlát, de 90 mp után Enrage).
- Hullám közben a karakterek **automatikusan támadnak** a fegyvereikkel a legközelebbi
  ellenségre; a játékos **mozog** és **képességeket** használ.
- A hullám végén a földön maradt gold és XP automatikusan begyűjtődik.
- Hullám után: **loot roll** a hullámban szerzett itemekre (közös képernyőn) →
  szintlépés-választások (ability vagy stat) → bolt / trainer / talents / karakterpanel
  → minden játékos „Ready” → következő hullám.

### Elesés és halál (co-op)

- 0 HP-nál a játékos **elesik** (szellem-alak, **normál sebességgel** mozoghat, nem támad;
  az ellenségek nem foglalkoznak vele).
- **Spirit Healer:** a pálya közepén egy lebegő, áttetsző, szárnyas szellemalak áll (arany
  glória, a földön világító rúnakör jelöli a hatósugarát, kb. 1,6 m). Az elesett játékos
  odasétál, és ha **1 mp-ig a körében áll**, **100% HP-val** feléled (fényoszlop az égből,
  „*Resurrected!*” felirat, 1 mp sebezhetetlenség).
  - A szellem feje fölött ugyanaz a „Resurrecting” cast bar jelenik meg, halványkék
    szellemszínben, a hátralévő idővel.
  - Ha a szellem kilép a körből, a számlálás nullázódik. Több szellem egyszerre is éledhet.
  - Élő játékosra nincs hatása. Csak hullám közben számít (hullámkezdéskor amúgy is
    mindenki feléled).
  - Amíg van elesett játékos, a Spirit Healer erősebben izzik és lüktet, fényoszlop jelöli,
    és a kamera mindig képen tartja, így a szellem biztosan látja és eléri.
  - A játékos keretén (unit frame) a „DOWNED” felirat alatt a „*Go to the Spirit Healer*”
    tipp jelenik meg.
- Egy élő társ **5 mp-ig mellette állva** is felélesztheti (30% HP-val) – ez megmaradt,
  WoW-szerű **„Resurrecting…” cast barral**:
  - **Cast bar:** a halott hagyma feje fölött jelenik meg, a felélesztő színében, a
    hátralévő idővel.
  - **Animáció:** a felélesztő hagyma két keze felemelkedik és aranyszínű fénnyel izzik, egy
    fénycsík köti össze a szellemmel.
  - **Befejezéskor:** fényoszlop az égből, „*Resurrected!*” felirat, és 1 mp sebezhetetlenség.
  - **Ha a felélesztő kilép a körből:** a cast bar lassan visszafogy, nem nullázódik azonnal.
  - **Több felélesztő:** minden további társ +50%-kal gyorsítja (co-op).
  - **Sebződés:** nem szakítja meg a felélesztést. A kockázat az, hogy közben állni kell.
  - **Spirit Healerrel együtt:** ha a társ és a Spirit Healer egyszerre éleszt, a cast bar a
    befejezéshez közelebbit mutatja, és amelyik előbb végez, az éleszt fel.
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
| **Mastery** | Kasztonként más hatás (lásd 3. fejezet) | 5 (minden kaszt, hogy a Mastery-passzív az első hullámtól működjön) | – |
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
| **Fortune** | Jobb ritkaság a boltban, a lootban és a szintlépésnél; nagyobb item-drop esély |
| **Gold Find** | +% felszedett gold |

> A **Range** nem stat, hanem a fegyver tulajdonsága.

### 2.4.1 Egzotikus statok (csak itemekről és enchantmentekről)

Ezeket nem lehet szintlépéskor választani: **csak itemeken**, főleg véletlen
**enchantmentekként** (5.7) jelennek meg, ahogy a WoW-ban az „Equip:” sorok.

| Stat | Hatás |
|---|---|
| **Attack Power** | +flat sebzés minden fegyvertalálathoz (a fegyver sebességéhez normalizálva) |
| **Spell Power** | +flat sebzés az abilitykhez, a varázsfegyverekhez és a varázs-procokhoz |
| **Extra Attack** | % esély, hogy a fegyver **azonnal még egyszer üt** („dupla ütés”); az extra ütés nem indíthat újabb extra ütést |
| **Critical Damage** | +% krit szorzó |
| **Thorns** | Közelharci találatkor ennyi sebzést kap vissza a támadó |
| **Parry** | % esély közelharci találat hárítására (nincs sebzés) és egy azonnali visszavágásra |
| **Block Value** | +% a blokk által elnyelt sebzéshez |
| **Cooldown Reduction** | −% ability-cooldown |
| **Resource Regen** | +% kaszt-erőforrás termelés (Rage, Mana, Energy …) |
| **Extra Projectile** | +1 lövedék a lövedékes fegyvereknek (legyezőben) |
| **Pierce** | +1 átütés a lövedékeknek |
| **Area Size** | +% AoE-méret (robbanások, Consecration, Blizzard …) |
| **Iskola-sebzés** | +% Fire / Frost / Arcane / Holy / Shadow / Nature / Physical sebzés iskolánként |
| **Executioner** | +% sebzés a 30% HP alatti célpontokra |
| **Slayer** | +% sebzés elitekre és bossokra |
| **Life on Kill** | Ölésenként ennyi % eséllyel +1 HP |
| **XP Gain** | +% XP |
| **Pickup Range** | +% loot-vonzási távolság |

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
| Mastery | **Ignite** – a kritikus találat égést okoz (a krit sebzés pontonként +1%-a 3 mp alatt). Ha a krit megölte a célt, a legközelebbi élő ellenség kezd égni a tetemtől 2,5 m-en belül (ha nincs ilyen, elvész) |

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
| Képesség 2 | **Word of Glory** – 3 Holy Power: gyógyítja magát és a 8 m-en belüli legsebesültebb társat. **Ha 8 m-en belül van elesett társ, azonnal feléleszti** (40% HP-val, a gyógyítás helyett) – az egyetlen azonnali felélesztés a játékban |
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
| Képesség 1 | **Fan of Knives** – 35 Energy: 10 tőr minden irányba (egyenként 110% fegyversebzés, mindegyik átüt egy ellenségen); minden elhasznált Combo Point +20% sebzés |
| Képesség 2 | **Vanish** – 15 mp CD: 2 mp láthatatlanság, az ellenség elveszti a célt, a Rogue visszanyeri a max HP-ja 30%-át, a következő találat garantált krit |
| Mastery | **Deadly Poison** – a krit mérget tesz az ellenségre (pontonkénti DoT). Ha a krit megölte a célt, a méreg a tetemtől 2,5 m-en belüli legközelebbi élő ellenségre kerül (ha nincs ilyen, elvész) |

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

Új kaszt (pl. Hunter, Shaman, Priest, Druid, Death Knight) = új **ClassData** adatfájl
+ a két képesség saját logikája. A Mail páncéltípus már most létezik a Hunter és a
Shaman miatt.

### 3.7 Tervezett kasztok (backlog, M8): Hunter és Shaman

Mindkettő **Mail** páncélt hord, és a többi kaszttal azonos felépítésű:
- 2 alap képesség,
- erőforrás,
- Mastery,
- 6 saját ability,
- 3 talentfa,
- tier set,
- Artifact.

#### Hunter
| | |
|---|---|
| Szerep | Távolsági sebző + állandó **pet** |
| Hagyma | **Salottahagyma** (rézbarna), tollas vadászkalap, szőrmés Mail-vállvért, tegez a hátán |
| Páncél | Mail |
| Kezdőfegyver | Bow |
| Jártasság | Bow, Gun, Crossbow, Polearm, Axe, Sword, Dagger, **Dual Wield** |
| Alap | +2 Agility, állandó **pet** (a lobbyban választható: farkas / vaddisznó / bagoly), **−3 Max HP** |
| Erőforrás | **Focus** (0–100), +10 / mp |
| Képesség 1 | **Multi-Shot** – 40 Focus: 5 nyíl legyezőben |
| Képesség 2 | **Disengage** – 8 mp CD: hátraugrás, a közeli ellenségek 2 mp-ig lassulnak |
| Mastery | **Master of Beasts** – +% pet-sebzés pontonként |
| Pet | Magától támad, a vadász Stamina-jával és Agility-jével skálázódik. Ha meghal, a hullám végén feltámad |

**Ability-készlet:**

| Ability | Típus | Hatás |
|---|---|---|
| Aimed Shot | Active | Rövid célzás, nagy sebzésű, mindent átütő lövés |
| Volley | Active | Nyílzápor egy területre, 4 mp |
| Rapid Fire | Active | 4 mp-ig +40% Haste |
| Explosive Trap | Auto | Csapdát tesz le, ami robban, ha ellenség lép bele |
| Kill Command | Auto | A pet nagy csapást mér a legerősebb közeli ellenségre |
| Feign Death | Active | Az ellenségek 2 mp-ig elveszítik a célt (menekülés) |

#### Shaman
| | |
|---|---|
| Szerep | Hibrid: elemi varázsló / közelharci / gyógyító **totemekkel** |
| Hagyma | **Fokhagyma** (fehér-lila), faragott fa maszk, csontgyöngyök, kis totem a hátán |
| Páncél | Mail |
| Kezdőfegyver | Mace + Shield |
| Jártasság | Mace, Axe, Dagger, Staff, Fist Weapon, Shield, Two-Hand Mace / Axe; **Dual Wield csak az Enhancement fa talentjével** |
| Alap | +2 Armor, +3 Spirit, **−5% Speed** |
| Erőforrás | **Maelstrom** (0–100): +5 minden fegyvertalálatnál és varázslatnál |
| Képesség 1 | **Chain Lightning** – 30 Maelstrom: villám, ami 4 célpont között ugrál |
| Képesség 2 | **Totemic Call** – 12 mp CD: totemet tesz le a lába elé. Az elemek körben váltják egymást: **Fire** (lövöldöző totem) → **Water** (gyógyít a közelben) → **Earth** (lassít) → **Air** (+Haste a közeli társaknak) |
| Mastery | **Elemental Overload** – % esély, hogy a villám- és tűzhatások duplán sülnek el |

**Ability-készlet:**

| Ability | Típus | Hatás |
|---|---|---|
| Lightning Bolt | Auto | Erős villámcsapás a legközelebbi ellenségre |
| Earthquake | Active | Földrengés-terület, sebez és időnként kábít |
| Lava Lash | Auto | Közelharci tűzcsapás, terjedő égéssel |
| Healing Rain | Active | Gyógyító eső-terület a társaknak (co-op) |
| Thunderstorm | Auto | Ha körbeveszik, villámmal hátralöki az ellenségeket |
| Feral Spirit | Active | 2 szellemfarkas 10 mp-re |

**Co-op szerep:** a Shaman totemjei és a *Healing Rain* az egész csapatot segítik. Egy
talent (*Ancestral Spirit*) a felélesztést is felgyorsítja.

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

| Ritkaság | Szín | Stat-keret* | Különlegesség | Boltban | Lootban |
|---|---|---|---|---|---|
| Common | fehér | 4 | – | 1. hullámtól | 1. hullámtól |
| Uncommon | zöld | 7 | 30% eséllyel 1 Equip-enchant | 2. hullámtól | 1. hullámtól |
| Rare | kék | 11 | 1 enchant | 4. hullámtól | 3. hullámtól |
| Epic | lila | 16 | 1–2 enchant, set-tag lehetséges | 9. hullámtól | 6. hullámtól |
| Legendary | narancs | 22 | 2 enchant + egyedi, kézzel tervezett proc | **soha** | 10. hullámtól (boss, elit, goblin, ritka drop) |
| Artifact | világos arany | – | kasztfegyver, fejlődik | soha | **ritka véletlen loot** a 10. hullámtól (lásd 5.5) |

\* A **stat-keret** az a pontszám, amiből a generált item a statjait „vásárolja”
(lásd 5.4). A slot szorzója módosítja.

**A bolt ritkasági esélyei (Fortune nélkül)** – a bolt legfeljebb Epicet árul.

| Hullám | Common | Uncommon | Rare | Epic |
|---|---|---|---|---|
| 1 | 100% | – | – | – |
| 5 | 60% | 30% | 10% | – |
| 10 | 40% | 35% | 20% | 5% |
| 15 | 26% | 33% | 29% | 12% |
| 20 | 16% | 30% | 34% | 20% |
| 25 | 10% | 25% | 38% | 27% |

**A loot ritkasági esélyei (normál ellenség, Fortune nélkül)** – kb. egy fokozattal jobb a boltnál.

| Hullám | Common | Uncommon | Rare | Epic | Legendary |
|---|---|---|---|---|---|
| 1 | 60% | 40% | – | – | – |
| 5 | 25% | 45% | 30% | – | – |
| 10 | 10% | 35% | 40% | 13% | 2% |
| 15 | – | 25% | 45% | 25% | 5% |
| 20 | – | 15% | 42% | 35% | 8% |
| 25 | – | 8% | 37% | 43% | 12% |

A köztes hullámokra lineárisan interpolálunk; a Fortune a magasabb ritkaságok felé tolja az eloszlást.

**Loot-bónusz:** a lootból származó item („**Looted**” címke a tooltipben) **+25% stat-keretet**
kap az azonos ritkaságú bolti itemhez képest, és a tier set darabok lootban 3× gyakoribbak.

### 5.3 Páncéltípusok

- **Típusok:** Cloth, Leather, Mail, Plate.
- **Mely slotokra vonatkozik:** Head, Shoulders, Chest, Wrist, Hands, Waist, Legs, Feet.
- **Implicit Armor (a slot szorzójával):** Cloth +0, Leather +1, Mail +2, Plate +3.
- **Szigorú, WoW-szerű páncél-jártasság:** minden kaszt a saját páncéltípusát és az annál
  könnyebbeket viselheti.

  | Kaszt | Viselhető |
  |---|---|
  | Warrior, Paladin | Plate, Mail, Leather, Cloth |
  | Hunter, Shaman (M8) | Mail, Leather, Cloth |
  | Rogue | Leather, Cloth |
  | Mage, Warlock | Cloth |

- **Armor Specialization:** ha mind a 8 páncélslotban a saját kaszt páncéltípusa van,
  **+10% elsődleges stat** jár érte. Így a Warrior akkor is Plate-et akar hordani, ha egy
  Leather darab épp jobb statokat ad.
- **Need-szabály:** Needet csak az nyomhat, aki viselni tudja az itemet (10.1).
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

**Anyag-fokozatok (alaptípusok):** minden páncéltípusnak 3 fokozata van. A magasabb
fokozat a későbbi hullámokban jelenik meg, és +10% / +20% stat-keretet ad.

| Páncéltípus | I. (1–8. hullám) | II. (9–16. hullám) | III. (17. hullámtól) |
|---|---|---|---|
| Cloth | Linen | Silk | Moonweave |
| Leather | Rugged | Thick | Shadowhide |
| Mail | Chain | Scaled | Stormforged |
| Plate | Iron | Steel | Runed |

**Teljes névminta:** `[Enchant-előtag] [Anyag] [Alaptípus] [of the Utótag]`

> Példa: *Blazing Runed Plate Helm of the Bear* (Epic, Looted)
> - +8 Strength, +9 Stamina, +4 Armor, +3% Haste
> - *Chance on hit: Hurls a fiery ball that causes 38 Fire damage.*
> - *Equip: Increases your chance to strike twice by 3%.*

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
| Hunter (M8) | Wildrunner's Garb | +10% pet-sebzés | A Multi-Shot +2 nyilat lő |
| Shaman (M8) | Totemkeeper's Mail | +30% totem-időtartam | A Chain Lightning +2 célpontot ér |

#### Artifact fegyverek (kasztonként 1)

Az Artifact **ritka, véletlen loot** – senki nem kapja meg automatikusan. Ha leesik, az
a menet legnagyobb pillanata.

**Honnan eshet (a 10. hullámtól)**

| Forrás | Esély |
|---|---|
| Boss (10. és 25. hullám) | 15% minden boss-lootra |
| Loot Goblin | 5% |
| Elit | 2% |
| Normál ellenség | 0,05% (a „jackpot”) |

A Fortune minden esélyt növel.

**Melyik kaszté:**
- 80% eséllyel a csapatban lévő egyik kaszté, 20% eséllyel bármelyiké.
- Ha senki nem tudja használni, Greed esetén nagyon sok goldot ér.

**Need:** csak a megfelelő kasztú játékos nyomhat rá Needet; a többieknek csak Greed vagy Pass
választható. Egyébként a szokásos Need / Greed / Pass dobás dönt (10.1).

**Korlátok:**
- Egy menetben kasztonként legfeljebb 1 Artifact eshet.
- **Pech-védelem:** minden boss után, ami nem dobott Artifactot, +5% esély.

**Fejlődés:**
- Main Hand fegyver; a kétkezes változatok mindkét slotot foglalják.
- Akkor is értelmes, ha későn esik le: a megszerzés hullámához illő Item Levellel érkezik.
- Utána minden hullám végén **fejlődik** (+statok).
- A felvétele után **3 hullámmal** az első, **6 hullámmal** a második különleges
  tulajdonsága nyílik meg.

| Kaszt | Artifact | Hatás |
|---|---|---|
| Warrior | *Earthsplitter* (2H Axe) | A Whirlwind földrengést hagy maga után |
| Mage | *Staff of the Frostwyrm* (Staff) | A Blizzard minden 4. alkalommal dupla méretű |
| Paladin | *Dawnbreaker* (Mace) | A Consecration gyógyítja a benne álló társakat |
| Rogue | *Fangs of the Shadow* (2 tőr, mindkét slot) | Minden 5. krit ingyen Fan of Knives-t lő |
| Warlock | *Skull of the Damned* (Staff) | Egy második pet: Voidwalker (tank) |
| Hunter (M8) | *Galestrike Longbow* (Bow) | Minden 4. lövés nyílzáporrá hasad |
| Shaman (M8) | *Fist of the Ancestors* (Mace) | A Chain Lightning egy villám-totemet idéz |

#### Kaszt-specifikus itemek

A WoW-hoz hasonlóan vannak **csak egy kaszt által használható** itemek. A tooltipben külön
sor jelzi: „*Classes: Mage*”.

- **Mit tudnak:** az erejük nem a statokban van, hanem abban, hogy a kaszt saját
  képességeit **módosítják**, pl. hosszabb időtartam, extra célpont vagy új mellékhatás.
- **Honnan:** lootból és a boltból. A közös bolt a csapat kasztjaihoz illőket kínálja
  (10. fejezet).
- **Need:** csak az adott kaszt nyomhat rá.
- **Ritkaság:** Rare-től felfelé léteznek. A tier set darabok is ilyenek.

**Példák (MVP: kasztonként 4, összesen 20)**

| Kaszt | Item | Slot | Hatás |
|---|---|---|---|
| Warrior | Gauntlets of the Whirling Blade | Hands | A Whirlwind +1 mp-ig tart, és közben lassít |
| Warrior | Warbringer's Greaves | Feet | A Charge után 3 mp-ig +20% sebzés |
| Mage | Frostweave Cowl | Head | A Blizzard területe +30% |
| Mage | Band of the Blinking Star | Ring | A Blink 2 töltettel használható |
| Paladin | Libram of Devotion | Off Hand (Tome) | A Word of Glory 1 Holy Powerrel olcsóbb |
| Paladin | Sabatons of the Dawn | Feet | A Consecration követi a Paladint |
| Rogue | Shadowstalker Wraps | Wrist | A Vanish 5 mp-mel rövidebb cooldownú |
| Rogue | Blade of the Thousand Cuts | Main Hand (Dagger) | A Fan of Knives +4 tőrt dob |
| Warlock | Grimoire of the Imp Lord | Off Hand (Tome) | Az Imp +50% sebzés, és tűzlövedéke 2 célpontot ér |
| Warlock | Soulbinder's Sash | Waist | Minden 8. ölés ad Soul Shardot (12 helyett) |

A többi 10 a fejlesztés közben készül el, ugyanígy: kasztonként 4.

### 5.6 Backpack

- **10 hely játékosonként.**
- **Megvásárlás:** a megvett item a backpackbe kerül, onnan lehet felvenni.
- **Csere:** felvételkor a régi item a backpackbe kerül; ha tele van, el kell adni valamit.
- **Eladás:** a vételár 35%-a, a közös pénztárcába.
- **Átadás egy társnak (Trade):** a hullámok között bármelyik backpack-item ingyen
  átadható egy másik játékosnak (a fogadónak kell, hogy legyen szabad helye). Ha valaki
  rossz itemet nyert Needdel, vagy egy bolti item másnak jobb, oda lehet adni.
  - A Character fülön az item műveletmenüjében: „Trade → P2 / P3 / P4”.
  - A fogadó panelén megjelenik: „*P1 gave you [Runed Plate Helm]*”.

### 5.6.1 Item Level

- **Megjelenés:** minden item tooltipjében WoW-szerű **Item Level** (ilvl) szám látszik a név
  alatt, hogy ránézésre össze lehessen hasonlítani két itemet.
- **Képlet:** `ilvl = 10 + 3 × hullám + ritkaság-bónusz + (6, ha Looted)`.

  | Ritkaság | Bónusz |
  |---|---|
  | Common | +0 |
  | Uncommon | +4 |
  | Rare | +8 |
  | Epic | +13 |
  | Legendary | +20 |
  | Artifact | +25, és felvétel után hullámonként nő |

- **Karakterpanel:** a statlista tetején a felszerelés átlagos ilvl-je is látszik
  („Avg. Item Level 64”).

---

### 5.7 Enchantmentek és procok (véletlen, WoW-szerű)

Az itemek **véletlen enchantmenteket** kapnak, amelyek a tooltipben **zöld** sorként
jelennek meg, pontosan úgy, mint a WoW-ban:

- *Equip: …* – folyamatos bónusz, gyakran egzotikus stat (2.4.1).
- *Chance on hit: …* – találatkor bizonyos eséllyel elsül (**proc**).
- *On kill: …* – öléskor süthet el.
- *When struck: …* – amikor a viselőjét eltalálják.

**Hány enchant jár:** a ritkaságtól függ (5.2). A **lootolt** itemek enchantjai egy
ranggal erősebbek, és a lootolt Uncommon itemeken mindig van 1 enchant.

**Rangok:** minden enchantnak I–III. rangja van az item hullámszintje szerint (I: 1–8.,
II: 9–16., III: 17. hullámtól). A rang növeli az értékét vagy a proc sebzését.

**Proc-szabályok (WoW-szerűen):**

- **PPM (procs per minute):** az esély fegyvertalálatonként `PPM × fegyver_cooldown / 60`.
  Így egy gyors tőr és egy lassú kétkezes balta percenként nagyjából ugyanannyit procol.
- **Belső cooldown:** minden enchantnak van (0,5–20 mp), hogy ne legyen proc-spam.
- **Skálázás:** a varázs-procok sebzése a **Spell Power**-rel, a fizikaiaké az
  **Attack Power**-rel nő.
- **Lánc-tiltás:** a procból származó sebzés nem indíthat újabb „Chance on hit” procot
  (kivéve, ahol ezt kifejezetten kiírja).

**Melyik slotra mi kerülhet:**

| Enchant-típus | Slotok |
|---|---|
| Chance on hit | fegyverek, gyűrűk, trinketek |
| When struck | Chest, Shoulders, Head, Shield |
| On kill | bármelyik |
| Equip | bármelyik (slothoz illő stat-készletből) |

**Enchant-készlet (MVP: 24 db, saját nevekkel)**

| Előtag | Típus | Hatás (I. rang) | PPM / esély |
|---|---|---|---|
| Zealous | Equip | +3% Extra Attack (dupla ütés) | – |
| Galeforce | Chance on hit | 2 azonnali extra ütés | 1,5 PPM, 3 mp ICD |
| Mighty | Equip | +6 Attack Power | – |
| Arcane-touched | Equip | +6 Spell Power | – |
| Brutal | Equip | +15% Critical Damage | – |
| Splitting | Equip | +1 Extra Projectile (csak lövedékes fegyver) | – |
| Piercing | Equip | +1 Pierce | – |
| Executioner's | Equip | +15% Executioner | – |
| Slayer's | Equip | +10% Slayer | – |
| Blazing | Chance on hit | Tűzgolyó: 20 Fire sebzés (+Spell Power) | 4 PPM |
| Stormbound | Chance on hit | Láncvillám 3 célpontra, 15 Nature sebzés | 3 PPM |
| Frostbite | Chance on hit | Fagynyíl 12 Frost sebzés, 2 mp 30% lassítás | 4 PPM |
| Venomous | Chance on hit | Méreg: 3 mp alatt 12 Nature sebzés, 3× halmozódik | 6 PPM |
| Vampiric | Chance on hit | 10 Shadow sebzés, ugyanennyi gyógyítás neked | 3 PPM |
| Bloodlust | Chance on hit | 6 mp-ig +20% Haste | 1 PPM |
| Crusading | Chance on hit | 10 mp-ig +5 fő stat és 2 HP gyógyítás | 1 PPM |
| Thundering | Chance on hit | Kis AoE lökéshullám, 1 mp kábítás | 2 PPM, 5 mp ICD |
| Hallowed | Chance on hit | Holy villanás: sebez, és a legsérültebb társat gyógyítja (co-op) | 2 PPM |
| Shadowflame | Chance on hit | Árnylövedék, ami ölésnél DoT-ot terjeszt | 3 PPM |
| Soulreaping | On kill | 10% eséllyel +1 kaszt-erőforrás | 10% |
| Detonating | On kill | 8% eséllyel a hulla felrobban (AoE) | 8% |
| Greedy | On kill | 5% eséllyel +1 gold | 5% |
| Frozen Ward | When struck | 10% eséllyel Frost Nova körülötted | 10%, 8 mp ICD |
| Retribution | When struck | 6 Holy sebzés a támadónak | 100%, 0,5 mp ICD |

**Enchanting (későbbi bővítés):**

- A Passolt vagy eladott itemeket **Disenchantolni** lehet, ebből *Arcane Dust* lesz.
- Ebből és goldból az **Enchanter** fülön egy item enchantja **újragörgethető** vagy
  **rangja emelhető**.

### 5.8 Tartalomcél – „sok item”

| Kategória | MVP (M2) | Teljes játék (M6+) |
|---|---|---|
| Fegyver-alaptípus | 10 | 16 (+ kétkezes kard, kétkezes buzogány, polearm, fist weapon, crossbow, orb) |
| Páncél-alaptípus (slot × páncéltípus × anyagfokozat) | 60 | 150+ |
| Ékszer-alaptípus (Neck, Ring) | 8 | 20 |
| Stat-utótag („of the Bear” …) | 12 | 25 |
| Enchantment | 24 | 50+ |
| Kézzel tervezett, névvel ellátott Rare/Epic itemek | 10 | 40 |
| Kaszt-specifikus itemek | 20 (kasztonként 4) | 60+ (kasztonként 8+) |
| Trinket | 10 | 30 |
| Legendary | 8 | 25 |
| Tier set | 5 (kasztonként 1) | 10 (+5 kaszt-független) |

A generált alaptípusok, utótagok és enchantok kombinációjából **több ezer** különböző
item jön ki. A kézzel tervezett itemek adják a „hűha, ez leesett!” pillanatokat.

---

## 6. Szintlépés és abilityk

Ez a játék fő újítása a Brotatóhoz képest: a szintlépés nem csak statot ad, hanem
**abilityket**, és ezek a menet során **goldért fejleszthetők**.

### 6.1 Szintlépés

- **XP:** közös csapat-XP. A csapat az **1. szintről** indul (WoW-osan); az `n.` szintlépéshez
  szükséges XP: `(n + 3)²` (Brotato-képlet; az 1 → 2 szintlépés 16 XP).
  Co-opban ez szorzódik: `(n + 3)² × (1 + 0,6 × (játékosok − 1))`, felfelé kerekítve
  (1 játékos ×1, 2 ×1,6, 3 ×2,2, 4 ×2,8) – ugyanaz a +60% játékosonként, mint az
  ellenségszámé (9. fejezet), így a több ellenségből jövő több XP nem gyorsítja a szintlépést.
- **Választás:** a hullám végén, minden megszerzett szint után, minden játékos **1 kártyát
  választ 5 közül**. Az 5 kártya **vegyesen** jön egy közös húzópakliból:
  - **Ability-kártyák:** a kaszt saját és az általános ability-készletéből.
    Ha egy már megtanult ability jön, az **ingyenes rangemelést** jelent (+1 Rank).
  - **Stat-kártyák:** véletlen stat-fejlesztések ritkasággal, pl. Common: +3 Stamina,
    Rare: +3% Crit és +2 Agility.
  - **Arány:** alapból kb. 50–50% esély ability-re és statra; minden húzásban
    **legalább 1 ability és 1 stat** garantált.
  - **Tele slotok:** ha a slotok tele vannak, az új abilityk helyett gyakrabban jönnek a
    rangemelések és a statok.
- **Reroll goldért:**
  - Mind az 5 kártyát újrahúzza.
  - Ára `hullám + 2` gold, minden további reroll ugyanabban a körben +2-vel drágább.
  - A **közös pénztárcából** fizeti a játékos.
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
- **M4 döntések:**
  - A tanult abilityk cooldown-alapúak és ingyenesek (nem költenek kaszt-erőforrást);
    kivétel: Summon Infernal (1 Soul Shard).
  - A szintlépés-kártyák választására 40 mp jut (+20 mp minden további szintért); aki addig
    nem választ, annak a játék választ (ugyanúgy, mint a botoknak). A lecsatlakozott
    kontroller is automatikusan választ.
  - Minden játékos saját véletlen-sorozatból húz (a menet seedjéből), így az egyik játékos
    rerollja nem változtatja meg a másik kártyáit.

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
- A Trainer a kaszt két alap képességét (RT / LT) is fejleszti. Rank V elérésekor (kártyáról
  vagy a Trainernél) a játékos kiválasztja a specializációt; ha elhalasztja, a Trainer fülön
  később választhat.

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
| Paladin | Lay on Hands | Active | Teljesen gyógyítja a legkevesebb HP-jú társat (hosszú CD); elesett társat nem éleszt fel (azonnal csak a Word of Glory éleszt) |
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
| Hunter (M8) | Beast Mastery | Marksmanship | Survival |
| Shaman (M8) | Elemental | Enhancement | Restoration |

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
| Hunter | Beast Mastery | Bestial Wrath | 30 mp-enként 10 mp-ig a pet +50% sebzést kap és nem lehet lassítani |
| Hunter | Marksmanship | Trueshot Aura | A közeli társak +5% sebzést kapnak; az Aimed Shot cooldownja felére csökken |
| Hunter | Survival | Wildfire Bombs | Az Explosive Trap égő földet hagy, és 3 kisebb bombát szór szét |
| Shaman | Elemental | Elemental Mastery | 20 mp-enként a következő 3 varázslat garantált krit |
| Shaman | Enhancement | Stormstrike | Minden 5. fegyvertalálat dupla villámcsapást vált ki |
| Shaman | Restoration | Spirit Link Totem | Totem, ami kiegyenlíti a közeli társak HP-ját, és 20%-kal csökkenti a sebzésüket (co-op) |

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
  - garantált item (Rare+, 25% eséllyel Epic+), Need / Greed / Pass dobással (lásd 10.1).
- **Ritka változat (később):** *Golden Goblin* – 1% eséllyel, csak goldot dob, de
  nagyon sokat.
- **Co-op:** a csapatnak össze kell hangolnia, hogy körbezárják (pl. Frost Nova,
  Hammer of Justice, Fear).

**Elitek**

- Az 5. hullámtól véletlenszerűen jelennek meg, ezüst sárkányos portrékerettel és névvel.
- 3× HP, 1 véletlen affix (Shielding, Enraged, Frenzied, Vampiric).
- Garantált itemet dobnak (Rare+), amit a hullám végén **Need / Greed / Pass** dobással
  osztunk el (lásd 10.1).

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

- **25 hullám**; a hullámhossz az 1. fejezet képlete szerint (a 10. hullám felett +10 mp hullámonként).

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

**Gold – egyetlen közös pénztárca**

- **Egy kassza:** minden felszedett gold (bárki szedi fel) **egyetlen közös pénztárcába**
  kerül. Ebből **bárki költhet**: bolt, Trainer, reroll, talent-reset.
- **Miért így:** a játék tudatosan koordinációt kíván – a csapatnak meg kell beszélnie, ki
  kapja a drága Epic itemet, és kinek az abilityjét fejlesszék.
- **Mi kerül a kasszába:**
  - **Eladás** (a vételár 35%-a).
  - **Gold Find:** annak a játékosnak a Gold Find-ja számít, aki felszedi a goldot.
- **Ellenségenkénti gold:** 1 alap, elit 10, boss 50, Loot Goblin lásd 8. fejezet.

**Koordinációs eszközök (hogy a közös kassza ne okozzon káoszt)**

- **Kívánságjelzés (Ping):** a játékos megjelölhet egy bolti ajánlatot vagy Trainer-rangot
  (kontrolleren a jobb kar benyomásával). Ekkor a többiek paneljén megjelenik:
  „*P2 wants: Rare Dagger – 62g*”.
- **Vásárlás megerősítése:** ha a vásárlás a kassza **több mint 50%-át** elvinné, 1 mp-ig
  nyomva kell tartani az „A” gombot. Ez véletlen nagy költés ellen véd.
- **Költésnapló:** a képernyő tetején a kassza mellett egy rövid lista látszik: ki mit vett
  és mennyiért ebben a körben.
- **Ready-állapot:** a kassza mellett látszik, ki van már kész. A ready-t meg lehet szüntetni,
  ha valaki még vásárolni akar.
- **Egyidejű vásárlás:** ha két játékos ugyanabban a pillanatban költene, és már csak az
  egyiknek jut fedezet, az nyer, aki előbb nyomta meg a gombot. A másik „*Not enough gold*”
  üzenetet kap.

**XP**

- **Közös XP-sáv:** az egész csapat egyszerre lép szintet, mindenki kap választást.

**Item-loot:** lásd **10.1** (Need / Greed / Pass).

**Gold felhasználása (mind a közös kasszából):** item vásárlás (bolt), **ability rangemelés
(Trainer, 6.3)**, szintlépési reroll, bolti reroll, talent-reset.

**Bolt**

- **Közös bolt:** egyetlen bolt a képernyő közepén – egy goblin kereskedő standja –, amit
  mindenki egyszerre használ.
- **Kínálat:** a játékosszámmal nő: 1 játékos → 4 ajánlat, 2 → 6, 3 → 8, 4 → 10.
- **Mindenkinek jut valami:** a generátor garantálja, hogy minden játékosnak legyen legalább
  1–2 olyan ajánlata, amit a kasztja használni tud (fegyver- és páncél-jártasság,
  kaszt-specifikus itemek).
- **Saját kurzor:** mindenki a saját színes kurzorával mozog a pult ajánlatai között.
  - **A** = megvesz. A közös kasszából fizet, az item a vásárló backpackjébe kerül.
  - Ha másnak jobb, utána tradeléssel tovább lehet adni (5.6).
- **Ping:** a jobb kar benyomásával egy ajánlatra „*P2 wants*” címke kerül a játékos színével,
  így vásárlás előtt látszik, ki mire pályázik.
- **Lock:** bárki zárolhat egy ajánlatot a következő körre. A zárolt ajánlaton látszik,
  ki zárolta.
- **Reroll csak közös szavazással:**
  - Minden játékos külön nyomja meg a saját Reroll gombját (Y). Ezt egy pipa jelzi a pult
    tetején, a játékos színével.
  - **A bolt csak akkor rerollol, ha minden játékos megnyomta.** A szavazat visszavonható.
  - A zárolt és a pingelt ajánlatok rerollnál megmaradnak.
  - Ára `hullám × 2 + 2` a közös kasszából, körönként minden további reroll +2-vel
    drágább.
- **A bolt legfeljebb Epicet árul**; Legendary és Artifact csak lootból szerezhető (10.1).
- **Árak:** ritkaság alapár × `(1 + 0,08 × (hullám − 1))`.

  | Ritkaság | Alapár |
  |---|---|
  | Common | 15 |
  | Uncommon | 30 |
  | Rare | 55 |
  | Epic | 90 |


---

### 10.1 Loot és Need / Greed / Pass dobás

A bolt megmarad, de **a legerősebb itemek lootból jönnek**. A csapatnak a hullám után,
**a közös képernyőn** kell eldöntenie, ki mit kap – ahogy a WoW-ban.

**Mi dob itemet**

| Forrás | Esély | Ritkaság |
|---|---|---|
| Normál ellenség | 1,5% ellenségenként (a Fortune növeli); hullámonként legfeljebb `1 + játékosszám` db | a loot-tábla szerint (5.2) |
| Elit | garantált 1 | Rare+ |
| Loot Goblin | garantált 1 | Rare+, 25% eséllyel Epic+ |
| Boss (10. és 25. hullám) | **játékosonként 1** | Epic+, 20% eséllyel Legendary |
| Artifact (ritka) | lásd 5.5: boss 15%, goblin 5%, elit 2%, normál 0,05% – a 10. hullámtól | Artifact |

**A földön**

- Az item **lootzsákként** esik le, a ritkaság színében világító fénynyalábbal
  (fehér, zöld, kék, lila, narancs), így messziről is látszik, ha valami jó esett.
- Bármelyik játékos felveheti, ha rálép. Ilyenkor a zsák a HUD-on lévő
  „**Team Loot**” számlálóba repül.
- Amit senki nem vett fel, a hullám végén automatikusan begyűjtődik. A loot nem vész el.

**A dobás menete (hullám után, a szintlépés előtt)**

1. **Sorban jönnek az itemek** egy WoW-stílusú dobó-ablakban:
   - ikon, név a ritkaság színében, teljes tooltip;
   - minden játékos chipjén kis nyíl mutatja, hogy **neki** fejlesztés-e
     (zöld ↑ / piros ↓ a jelenleg felvett itemhez képest).
2. **Mindenki a saját kontrollerével választ:**

   | Gomb | Választás | Hatás |
   |---|---|---|
   | A | **Need** (kocka ikon) | „Kell nekem” – ha nyer, az item a **saját backpackjébe** kerül |
   | X | **Greed** (érme ikon) | „Adjuk el” – ha az item Greedre megy, **azonnal eladódik** |
   | B | **Pass** | Nem vesz részt a dobásban |

   - **Időkorlát:** 15 mp; aki nem dönt, az Passnak számít.
   - **Rejtett döntések:** a döntések a végéig rejtve maradnak; csak egy pipa jelzi, ki döntött már.
3. **Need feltétele:**
   - a kaszt használni tudja az itemet (fegyver-jártasság),
   - van hely a backpackben.

   Ha valamelyik nem teljesül, a Need gomb szürke, és kiírja az okát
   („Cannot use” / „Backpack full”).
4. **Kiértékelés** (WoW-szabályok szerint):
   - **Van Need:** csak a needelők dobnak 1–100-at. A legnagyobb nyer, és az item a
     nyertes backpackjébe kerül. Döntetlennél a döntetlenek újra dobnak.
   - **Nincs Need, de van Greed:** a greedelők dobnak (a statisztikához, ki „nyerte” el),
     az item **azonnal eladódik**. Az ár a **közös kasszába** kerül, és **50%**-os
     eladási áron megy, ami jobb a normál 35%-nál, így a Greed is valódi jutalom.
   - **Mindenki Passt nyom:** az item elvész. (Később: *Disenchant*, ami anyagot ad
     a fegyverkovácsoláshoz.)
5. **Eredmény:** WoW-stílusú üzenetsor, pl.:
   „*P2 rolls 87 (Need) for [Stormcaller]*” → „*P2 wins [Stormcaller]*”.

**Különleges esetek**

- **Egy játékos:** nincs dobás, csak Take (A) / Sell (X) / Leave (B).
- **Botok:** Need, ha használni tudják és fejlesztés nekik, különben Greed.
- **Gyorsítás:** minden játékos egy gombbal (Y) **„Greed all remaining”**-et is választhat;
  ekkor a hátralévő itemekre automatikusan Greedet dob.
- **Statisztika:** a játék végén látszik, ki hány itemet nyert Needdel, és mennyi gold
  jött Greedből.

**Miért jó ez a co-opban?**

- A **Need** egyéni erő, a **Greed** a csapat kasszáját tölti. A közös pénztárca miatt a
  Greed mindenkinek jó, így a csapatnak meg kell beszélnie, kinek kell igazán az item.
- A Need és a fegyverkovácsolás összeér: egy lootolt fegyver párja lehet egy bolti
  fegyvernek. A kovácsolt fegyver megtartja a „Looted” bónuszt, ha bármelyik fele lootból jött.

---

## 11. Irányítás

### Kontroller (Xbox-elnevezéssel)

| Gomb | Harcban | Menüben |
|---|---|---|
| Bal kar | Mozgás | Navigáció |
| Jobb kar | – (minden automatikusan céloz) | Tooltip görgetés |
| RT | Alap képesség 1 | – |
| LT | Alap képesség 2 | – |
| RB | Tanult aktív ability 1 | Fül váltás jobbra |
| LB | Tanult aktív ability 2 | Fül váltás balra |
| A | – (felélesztéshez elég a társ mellett állni) | Kiválaszt / vásárol / felvesz |
| B | – | Vissza |
| X | – | Eladás |
| Y | – | Összehasonlítás a felvett itemmel |
| Start | Szünet | Ready |

**Loot roll közben:** A = Need, X = Greed, B = Pass, Y = Greed all remaining.

**Gombfeliratok:** a játék felismeri a kontroller típusát, és ahhoz igazítja a feliratokat:
- Xbox: A B X Y,
- PlayStation: ✕ ○ □ △,
- Nintendo-elrendezés: B A Y X.

Vegyes kontrollereknél minden játékos a saját paneljén a saját kontrollere jeleit látja.

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

**Loot roll képernyő (közös)**

- **Elrendezés:** a hullám után a közös képernyő közepén egy nagy, WoW-szerű dobó-ablak
  jelenik meg: item-ikon, név a ritkaság színében, tooltip és visszaszámláló sáv.
- **Játékos-chipek:** alul 1–4 chip a játékosok színével. Mindegyiken látszik az upgrade-nyíl,
  a döntés állapota (pipa), majd a végén a dobás eredménye (kocka, érme vagy Pass ikon és a szám).
- **Jobb oldal:** üzenetsor a dobásokról, és egy „Items: 2 / 5” számláló.

**Hullám utáni képernyő**

- **Sorrend:**
  1. loot roll (közös),
  2. szintlépési kártyák (mindenki a sajátját, a saját negyedében),
  3. közös bolt + személyes panelek egyszerre,
  4. Ready.
- **Elrendezés:**
  - **Középen:** a **közös bolt** (goblin kereskedő standja) a játékosok színes kurzoraival,
    felül a reroll-szavazás pipái.
  - **A sarkokban:** 1–4 **személyes panel**, játékosonként egy.
  - LB/RB-vel lehet váltani a bolti kurzor és a saját panel között.
- **Személyes fülek:** **Trainer | Talents | Character**.
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
- **Tooltip:** pergamen / sötét keretes WoW-tooltip, felülről lefelé:
  - a ritkasághoz illő színű név, alatta „Looted”, slot, páncéltípus, a fegyvernél
    sebzés és sebesség,
  - fehér stat-sorok,
  - **zöld enchant-sorok** („Equip: …”, „Chance on hit: …”, „On kill: …”, „When struck: …”),
  - set-bónuszok (szürkén, ha nem aktív),
  - legalul az összehasonlítás a felvett itemmel (+zöld / −piros).
- **Indulás:** a „Ready” jelzés után indul a következő hullám, ha mindenki kész van
  (vagy 60 mp-es időkorlát után, beállításokban kikapcsolható).

---

## 13. Grafikai irány

- **Stílus:** WoW-szerű stilizált fantasy.
  - **A hősök hagymák WoW-páncélban** – a Brotato krumplijainak megfelelője.
  - Telített színek, kézzel festett hatású textúrák.
  - Enyhe toon-shading, rim light, vékony körvonal.
- **Technika:**
  - Godot 4, **3D low-poly** modellek.
  - Kb. 55–60°-os felülnézeti kamera (keskeny FOV vagy ortografikus).
  - A kamera a csapat középpontját követi, és dinamikusan zoomol, hogy mindenki látszódjon.
    Amíg van elesett játékos, a Spirit Healert is képen tartja (1. fejezet).
  - **Közös képernyő, osztás nélkül:** a kamera egy határig zoomol ki. Utána a képernyő széle
    láthatatlan falként megállítja azt a játékost, aki tovább szaladna. Így senki nem
    tűnhet el a képből.
- **Assetek (első kör, licencek letöltéskor ellenőrizendők):**
  - **KayKit** csomagok (Kay Lousberg, CC0): Skeletons, Dungeon Remastered, és a fegyver- /
    kellékmodellek az Adventurers csomagból (a hősök saját hagyma-modellek).
  - **Quaternius** (CC0): szörnyek és fantasy kellékek.
  - Ikonok: **game-icons.net** (CC BY 3.0 – feltüntetéssel), WoW-szerű keretbe és színezésbe
    rakva.
  - Hangok: Kenney (CC0), freesound.org (licenc szerint).
  - Betűtípus: *Cinzel* vagy hasonló, szabadon használható fantasy font.
- **A hagyma-hősök kinézete:**
  - **Alap modell:**
    - egyetlen saját low-poly hagymatest (gömbölyű, csúcsos hajtással a tetején, rétegzett
      héj-textúrával),
    - nagy kifejező szemek,
    - **lebegő kezek és apró lábak**, mint a Brotatóban.
  - **Héjszín kasztonként:**
    - Warrior: vöröshagyma,
    - Mage: lilahagyma,
    - Paladin: aranysárga hagyma,
    - Rogue: újhagyma (zöld szárral),
    - Warlock: fekete / mogyoróhagyma.
  - **Látható felszerelés:** a **Head**, **Shoulders**, **Chest** (mellvért / köpeny),
    **Main Hand** és **Off Hand** cseréje a modellen is látszik.
    - **Méret:** a vállvértek WoW-osan túlméretezettek.
    - **Ritkaság-effekt:** az Epic és a Legendary cuccok halványan izzanak.
  - **Kaszt-kezdőszettek (kinézet):**
    - Warrior: szarvas sisak és hatalmas vállvért,
    - Mage: csúcsos varázslósüveg és köpeny,
    - Paladin: aranyozott lemezvért és tabard,
    - Rogue: csuklya és maszk,
    - Warlock: szarvas csuklya és lila lángok.
  - **Sebződés vizuálisan:** alacsony HP-n a hagyma „hámlik”: héjrétegek repednek le róla.
    Elesésnél egy meghámozott, könnyező hagymaszellem lesz belőle.
  - **Készítés:** a hagymatest és a páncélelemek **saját modellek** (egyszerű low-poly, Blenderben
    vagy akár Godot primitívekből). A páncélokat csatlakozási pontokra (fej, váll, törzs, kezek)
    illesztjük, így a felszerelés modulárisan cserélhető.
- **Ellenségek:** maradnak a klasszikus fantasy szörnyek (csontvázak, ghoulok, trollok, démonok).
  A hagyma-hősök és a „komoly” szörnyek közti kontraszt a humor forrása.
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
- `EnchantData`: típus (Equip / Chance on hit / On kill / When struck), PPM vagy esély,
  belső cooldown, rangonkénti értékek, megengedett slotok, iskola.
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
| `LootSystem` | Item-generálás, ritkaság (bolt- és loot-tábla), drop-esélyek, lootzsákok |
| `LootRoll` | Need / Greed / Pass dobások, kiértékelés, backpackbe tétel / eladás |
| `ProcSystem` | Találat- / ölés- / sebződés-események, PPM-esélyek, belső cooldownok, proc-hatások |
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

**Mentés:**
- beállítások;
- **automatikus mentés minden hullám végén** (a teljes menet állapota: hullám, kassza,
  XP, játékosok felszerelése, abilityk, talentek), így egy 25 hullámos menet félbehagyható és
  folytatható;
- a fő profil meta-progressziója (17. fejezet).

---

## 16. Mérföldkövek

| # | Mérföldkő | Tartalom |
|---|---|---|
| M0 | Váz | Godot projekt, 1–4 kontroller csatlakozása, mozgó placeholder karakterek, kamera |
| M1 | Harc magja | Auto-attack MH/OH fegyverrel, 3 ellenségtípus, gold/XP felszedés, hullám-időzítő |
| M2 | Felszerelés és loot | Item-generálás (alaptípusok, utótagok, **enchantmentek és procok**, egzotikus statok), ritkaság, bolt, backpack, karakterpanel, tooltip, **item-drop és Need / Greed / Pass dobás** |
| M3 | Kasztok | 5 kaszt, erőforrások, 2-2 alap képesség, Mastery |
| M4 | Abilityk | Szintlépés (ability- és stat-kártyák), ability-slotok, auto-cast, Trainer és rangok |
| M5 | Mélység | Talentfák (5 kaszt × 3 fa), fegyverkovácsolás, setek, elitek, Loot Goblin, közös kassza |
| M6 | Tartalom | Mind a 7 ellenség, 2 boss + elit-hullám, Artifactok, **teljes item-tartalom (5.8)**, Enchanting, 25 hullám balansza (Normal) |
| M7 | Csiszolás | Grafikai réteg (assetek, shaderek, VFX), hangok, menük, beállítások |
| M8 | Új kasztok | **Hunter** és **Shaman** (3.7): kasztok, petek / totemek, ability-készletek, talentfák, tier setek, Artifactok; új fegyvertípusok: Crossbow, Polearm, Fist Weapon |
| M9 | Meta-progresszió (utolsó) | Fő profil, Class Level, glyphek, heirloomok, achievementek, transmog, Valor, The Onion Patch (menü) – 17. fejezet |

---

## 17. Meta-progresszió (utolsó mérföldkő, M9)

**Cél:** a megmaradó fejlődés főleg **új lehetőségeket** ad, nem nyers erőt. A Normal
nehézség 0 meta-fejlődéssel is végigjátszható és élvezetes marad. A nyers erő-bónusz
összesen **legfeljebb kb. +10%**.

### 17.1 Fő profil

- **Egyetlen fő profil (a játék mentése).** Minden meta-fejlődés ehhez tartozik:
  - kasztonként a Class Level,
  - glyphek, heirloomok,
  - achievementek, transmog, Valor.
- **Bárki, aki egy kaszttal játszik, a fő profil adott kaszthoz tartozó szintjét és
  feloldásait kapja.** Ha pl. a fő profilon a Warrior 12-es szintű, akkor a Warriort választó
  játékos (akár P1, akár P3) a 12-es Warrior minden feloldásával indul.
- **Class XP:** a menet végén minden kaszt, amivel játszottak, Class XP-t kap a fő profilon.
  Ha ketten játszottak ugyanazzal a kaszttal, az XP-jük összeadódik.
- **Későbbi opció:** több mentési hely (pl. 3 fő profil) a főmenüben.

### 17.2 Class Level (kasztonként 1–30)

- **Class XP** jár minden menet után. Forrásai:
  - túlélt hullámok,
  - ölések,
  - bossok,
  - győzelem;
  - a magasabb nehézség szorzót ad.
- **Szint-jutalmak (útvonal):**

  | Szint | Jutalom |
  |---|---|
  | 2, 4, 6, … | Új ability kerül a kaszt húzópaklijába (indulásra 4 van a 6-ból) |
  | 3, 10, 20 | Glyph-slot (17.3) |
  | 5 | Első Heirloom (17.4) |
  | 8, 16, 24 | A talentfák capstone-jai fokozatosan nyílnak meg |
  | 12 | Alternatív kezdőfegyver |
  | 15, 25, 30 | Kozmetika (tabard, kalapváltozat, fényhatás) |
  | 30 | Cím, pl. „*Onion, the Unbreakable*” |

- **Kis nyers erő** (összesen legfeljebb kb. +10%, főleg kényelem): +1 backpack-hely,
  +20 kezdő gold, +1 ingyen bolti reroll menetenként, +2% fő stat.

### 17.3 Glyphek

- **Választás:** menet előtt, a lobbyban legfeljebb **3 glyph** választható (a slotok Class
  Levellel nyílnak).
- **Mit tudnak:** a kaszt **képességeit módosítják**, oldalirányú választások. Például:
  - *Glyph of Whirlwind*: behúzza az ellenségeket.
  - *Glyph of Blink*: jégcsíkot hagy.
  - *Glyph of the Imp*: Felhunter jön az Imp helyett.
- **Mennyiség:** kasztonként kb. 8 glyph, Class Levellel és achievementekkel nyílnak.

### 17.4 Heirloomok

- **Menetenként 1 heirloom-slot:** egy megmaradó itemmel lehet indulni.
- **Skálázás:** a hullámmal nő, de gyengébb az Artifactnál; a kényelmes kezdést szolgálja.
- **Szerzés és fejlesztés:** Class Level mérföldkövekből és achievementekből jönnek, és
  **Valorért** fejleszthetők.

### 17.5 Fiók-szintű fejlődés

- **Achievementek:** pontokkal és címekkel. Például:
  - „Win without anyone going down”,
  - „Need-roll a Legendary”,
  - „Kill 3 Loot Goblins in one run”.
- **Feloldások achievementekből:**
  - új kasztok (**Hunter**, **Shaman**),
  - új Legendaryk a loot-készletbe,
  - nehézségi szintek kasztonként (Normal megnyerése → Heroic, Heroic → Mythic).
- **Transmog-gyűjtemény:**
  - minden valaha felvett item kinézete elmentődik,
  - a lobbyban kozmetikailag ezekbe lehet öltöztetni a hagymát.

### 17.6 Valor és „The Onion Patch”

- **Valor:** menetenként kapott megmaradó pénz.
- **The Onion Patch:** hagymakert-hub, kasztonként egy trainer-NPC-vel. Itt Valorért
  heirloom-fejlesztés, glyphek és kozmetika vehető.
- **Megvalósítás:** **először menü**, később bejárható kis kert.

### 17.7 Amire a fejlesztés közben már most figyelünk

Az M9 előtti rendszerek úgy épülnek, hogy a meta-progresszió később átírás nélkül
ráépíthető legyen (részletek: `docs/ARCHITECTURE.md`):
- stabil tartalom-azonosítók,
- feloldás-ellenőrzés a tartalom-készletekben,
- menet-statisztika események,
- verziózott mentés,
- profilhoz köthető beállítások.

---

## 18. Nyitott kérdések

1. A 14 hiányzó talentfa részletes kidolgozása most, vagy a fejlesztés közben (M5)?

### Lezárt döntések

| Kérdés | Döntés |
|---|---|
| Karakterek kinézete | Hagymák WoW-páncélban |
| Gold | Egyetlen közös pénztárca, bárki költhet belőle |
| Szintlépés | 5 kártya, ability és stat keverve, goldért rerollolható |
| Cím | SmartOnion |
| Nyelv | Angol |
| Kamera | Közös képernyő; korlátos kizoomolás, a képernyő széle falként megállítja a játékosokat |
| Felélesztés | Spirit Healer a pálya közepén: 1 mp a körében = 100% HP; egy társ 5 mp alatt is feléleszt (30% HP), cast barral és animációval; a szellem normál sebességgel mozog |
| Gyógyulás | Minden hullám elején teljes HP |
| Hullámok közti időkorlát | 60 mp, beállításokban kikapcsolható |
| Gombfeliratok | A kontroller típusa szerint (Xbox / PlayStation / Nintendo) |
| Mentés | Automatikus, minden hullám végén |
| Meta-progresszió | Egy fő profil (a kaszt szintjét bárki megkapja, aki azzal a kaszttal játszik), Class Level, glyphek, heirloomok, achievementek, transmog, Valor + The Onion Patch (17. fejezet); nyers erő legfeljebb +10%; az utolsó mérföldkő (M9), de a rendszerek már most erre készülnek |
| Zene | Egyelőre nincs |
| Célzás | Csak automatikus (fegyverek és képességek); nincs kézi célzás |
| Paladin Word of Glory | Azonnal feléleszti a 8 m-en belüli elesett társat (40% HP) |
| Fegyver-jártasság | Szigorú, WoW-szerű: minden kaszt csak a saját fegyvertípusait használhatja (3. fejezet), nincs „büntetéssel bármit” opció |
| Páncél-jártasság | Szigorú, WoW-szerű: a saját páncéltípus és az annál könnyebbek (5.3) |
| Kaszt-specifikus itemek | Vannak („Classes: X”), a kaszt képességeit módosítják (5.5) |
| Bolt | Közös bolt, saját kurzorokkal; reroll csak akkor, ha minden játékos megszavazta |
| Hullámhossz | A 10. hullám felett +10 mp hullámonként (25. hullám = 210 mp) |
