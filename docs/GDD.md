# SmartOnion – Game Design Document

> Felülnézetes, hullámalapú arena survivor (Brotato-szerű) World of Warcraft-hangulatú
> fantasy stílusban, 1–4 fős helyi co-oppal. A hősök **hagymák WoW-páncélban**.
>
> Státusz: **M0–M6b kész** (a 16. fejezet szerint), egyetlen kivétellel: a **végleges 25
> hullámos balansz** az M6b utolsó lépése, és még hátravan. Az M6b (módok, környezetek,
> események, szentélyek, Dungeon-portál, tartalom-csomagok) megvalósult; ahol a kód
> pontosít a tervhez képest, a 16.1 „pontosítások” blokkjai és az érintett fejezetek ezt
> rögzítik. Az M7a (hang, menük, beállítások, IP-tisztítás) kész, az M7b (grafika) folyamatban van, a későbbi mérföldkövek még tervezés. Ez a dokumentum a fejlesztés
> alapja; minden szám kiinduló érték, a balanszolás során változni fog (az M6b maga nem
> hangolt: a végleges balansz egyszer, a legvégén készül, lásd 9. és 16. fejezet).

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
| Aktív képességek | **Igen**, kasztonként saját erőforrással (Rage, Mana, Energy, Resolve, Pact Shard) |
| Menet hossza | **25 hullám** (Normal mód); az **Endless** módban a 25. hullám után folytatható (M6b, lásd 16.1) |
| Módok (M6b) | **Normal** vagy **Endless**, opcionálisan **Hardcore** (nincs Grave Tender); a lobbyban választható, módonként helyi ranglista (16.1) |
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
Főmenü → Csatlakozás (Press A to join) → Kasztválasztás + módválasztás (Normal / Endless, Hardcore)
  → Aréna sorsolása („Rolling the arena…”, 12. fejezet)
  → [ Hullám (harc; esetleg egy esemény) → Loot roll (Need / Greed / Pass)
      → (Szentély, 5% eséllyel) → Szintlépés (ability / stat)
      → (Dungeon-portál a 6., 9., 12., 15. hullám után)
      → Bolt + Trainer + Talents + Karakterpanel → Ready ] × 25   (Endless: a 25. után tovább)
  → Győzelem / Vereség képernyő (összegzés, Damage Meter, díjak, run kártya, ranglista)
```

- **Egy menet = 25 hullám** (Normal mód). Az **Endless** mód a 25. hullám után is folytatódik
  (lásd lent és 16.1); a menet hossza ezentúl a módból jön, nem egy beégetett 25-ös szám.
- Hullámhossz:
  - **1–10. hullám:** `20 + 5 × (hullám − 1)` másodperc, legfeljebb 60 mp (a 9–10. hullám 60 mp).
  - **A 10. hullám felett hullámonként +10 mp:** 11. = 70 mp, 15. = 110 mp, 20. = 160 mp,
    25. = 210 mp.
  - **Endless módban a 26. hullámtól** a hullámhossz **legfeljebb 210 mp** (a 25. hullám
    hossza a plafon).
  - Egy teljes menet így kb. **42 perc** harc (a két boss-hullámot a képlet szerinti hosszal
    számolva; valójában a boss legyőzése dönt), plusz a hullámok közötti idő.
- **Különleges hullámok** (részletek: 8. fejezet):
  - **10.** – boss-hullám: Lich Commander Morvain (mini-raid boss),
  - **20.** – elit-hullám (minden ellenség elit-affixet kap, de csak ×1,5 HP-val),
  - **25.** – végső boss: Vor'thalax, the Burning Tyrant; Normal módban a halála a menet
    győzelme, **Endless módban** nem ér véget a menet: „*Endless begins!*” szalag, és jön a
    26. hullám.
  - **Endless, 26. hullám fölött:** minden 5. hullám boss-hullám a 30.-tól, váltakozva
    Morvain (30., 40., …) és Vor'thalax (35., 45., …); a 20. hullám elit-szabálya a 33., 43.,
    53. … hullámon ismétlődik.
  - **Az Endless szabályai a hullámszám függvényei** (M6b, megvalósítva): a boss
    `(hullám − 30) / 5` párossága szerint Morvain vagy Vor'thalax, HP-ja és sebzése a szokásos
    hullám-növekedést követi. A boss-hullámokon és az elit-szabályú hullámokon **nincs
    esemény**; a **Dungeon-portál** az Endlessben is csak a 6., 9., 12., 15. hullám után nyílik
    (a 26.-tól nincs); a **szentélyek** és az **események** a 25. hullám után is ugyanúgy
    működnek.

  A boss-hullámon a fenti hullámhossz nem érvényes: a hullám **a boss halálával ér véget**
  (nincs időkorlát, de 90 mp után Enrage). Közben a normál ellenségek a szokásos spawn-ráta
  50%-ával tovább érkeznek.
- Hullám közben a karakterek **automatikusan támadnak** a fegyvereikkel a legközelebbi
  ellenségre; a játékos **mozog** és **képességeket** használ.
- **Hullám közbeni esemény** (M6b): a 4. hullámtól, 30% eséllyel egy hullámban legfeljebb egy
  esemény jön – őrzött láda, megvédendő totem vagy Goblin karaván (16.1).
- A hullám végén a földön maradt gold és XP automatikusan begyűjtődik.
- Hullám után: **loot roll** a hullámban szerzett itemekre (közös képernyőn) →
  (M6b: 5% eséllyel **szentély**) → szintlépés-választások (ability vagy stat) →
  (M6b: a 6., 9., 12., 15. hullám után **Dungeon-portál**) → bolt / trainer / talents /
  karakterpanel → minden játékos „Ready” → következő hullám.
- **Aréna-környezet** (M6b): a menet elején 5 környezet egyike sorsolódik ki, és a menet
  végéig megmarad (13. fejezet és 16.1).

### Elesés és halál (co-op)

- 0 HP-nál a játékos **elesik** (szellem-alak, **normál sebességgel** mozoghat, nem támad;
  az ellenségek nem foglalkoznak vele).
- **Grave Tender:** a pálya közepén egy lebegő, áttetsző, szárnyas szellemalak (arany
  glória, a földön világító rúnakör jelöli a hatósugarát, kb. 1,6 m). **Csak akkor látszik,
  ha van elesett játékos:**
  - Amíg mindenki él, nincs ott.
  - Amint valaki elesik, felvillanva előtűnik és felemelkedik.
  - Ha mindenki újra él, elhalványul.

  **Folyamatosan futó
  10 mp-es számlálója** van: a hullám elején indul, és minden lejáratkor (10 mp-enként) a
  körében álló összes szellem **100% HP-val** feléled (fényoszlop az égből, „*Resurrected!*”
  felirat, 1 mp sebezhetetlenség). Az elesett játékos odasétál, és a következő pulzusig vár.
  - **Wilted:** a Grave Tender felélesztése után a játékos **15 mp-es**
    debuffot kap; ez alatt a Grave Tender nem tudja újra feléleszteni (a társak és a Word of
    Glory igen). Hullámkezdéskor megszűnik.
  - A körben várakozó szellem feje fölött a „Resurrecting” cast bar a következő pulzusig
    hátralévő időt mutatja, halványkék szellemszínben; a Grave Tender fölött is lebeg a
    számláló, amíg van szellem.
  - Ha a szellem kilép a körből, nem éled fel a pulzusnál. Egy pulzus az összes körben álló
    szellemet feléleszti.
  - Élő játékosra nincs hatása. Csak hullám közben számít (hullámkezdéskor amúgy is
    mindenki feléled).
  - Amíg látszik (van elesett játékos), izzik és lüktet, fényoszlop jelöli, és a kamera
    mindig képen tartja, így a szellem biztosan látja és eléri. A számláló láthatatlanul is
    fut tovább.
  - A játékos keretén (unit frame) a „DOWNED” felirat alatt a „*Go to the Grave Tender (7 s)*”,
    a körben a „*Grave Tender: 7 s*”, betegség alatt a „*Wilted: 12 s*” felirat
    jelenik meg.
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
  - **Grave Tender-rel együtt:** ha a társ és a Grave Tender egyszerre éleszt, a cast bar a
    befejezéshez közelebbit mutatja, és amelyik előbb végez, az éleszt fel.
- **Szellem-lassítás:** amíg egy játékos elesett (szellem), a felélesztési körében (1,8 m a
  szellem körül – ahol a társ a felélesztést csatornázza) álló ellenségek **33%-kal
  lassabban** mozognak, így a felélesztő nem marad védtelen. A kör a szellemmel együtt mozog
  (a Grave Tender-hez sétálva is lassít).
  - Minden ellenségre hat, a **Coin Gremlin-re is** (rá is hat a crowd control); a feldühödött
    (Enraged) elitre nem – az minden lassításra immunis.
  - **Nem adódik össze:** több szellem átfedő köre is 33%, és más lassításokkal sem
    halmozódik – mindig az erősebb érvényes, és egyik sem írja felül a másikat.
  - A kör elhagyása, a szellem felélesztése vagy elsétálása után egy pillanaton belül
    (0,1 mp) megszűnik.
  - A lassított ellenség „lassítottnak” számít a talentek feltételeinél (pl. Frost: több
    sebzés lassított célpontra).
  - **Jelzés:** amíg a kör lassít valakit, a felélesztési kör halvány kékes szellemszínbe
    vált, és a belseje lassan lüktet.
- Ha a hullám végéig nem élesztik fel, a következő hullám elején **50% HP-val** visszatér.
- Ha **mindenki** elesik egyszerre → a menet véget ér.
- Egyjátékos módban az elesés = halál (mint a Brotatóban).
- **Hardcore mód** (M6b, a lobbyban kapcsolható; részletek: 16.1):
  - **Nincs Grave Tender:** az aréna nem hozza létre, így csak a társak tudnak feléleszteni
    (5 mp-es csatornázás, Call of Valor).
  - Az elesett hős keretén a „Go to the Grave Tender …” helyett a „*Only a teammate can
    revive you*” felirat áll. Ugyanez a felirat áll a **Dungeonban** is, ahol szintén nincs
    Grave Tender (a Wilted felirata előbbre való; a normál tisztáson marad a
    „Go to the Grave Tender”).
  - Aki a hullám végéig nem kap segítséget, a **következő hullám elején** így is visszatér
    (50% HP-val), mint Normalban.
  - A **HARDCORE jelvény** a lobbyban (a fejlécben), a HUD-on (a hullám-tábla első sora) és
    a végképernyőn (a felirat alatti sor) látszik (12. fejezet).
  - **Szóló Hardcore = szóló Normal:** egyedül az első elesés amúgy is a menet vége.

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
| **Area Size** | +% AoE-méret (robbanások, Sacred Circle, Hailstorm …) |
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
| Jártasság | Minden közelharci fegyver (az M6b-től a Two-Hand Sword és a Two-Hand Mace is), Shield, kétkezes fegyverek, **Dual Wield** |
| Alap | +5 Max HP, +2 Armor, **−5% Speed** |
| Erőforrás | **Rage** (0–100): +4 / kiosztott találat, +10 / elszenvedett találat, −3 / mp ha nincs találat |
| Képesség 1 | **Whirlwind** – 40 Rage: körkörös csapás, 150% fegyversebzés a környező ellenségekre |
| Képesség 2 | **Charge** – 8 mp CD: rohamozás mozgásirányba, a beérkezéskor 1 mp kábítás |
| Mastery | **Cornered Fury** – minél kevesebb a HP, annál több sebzés (pontonként +0,5% minden hiányzó 10% HP után) |

### 3.2 Mage
| | |
|---|---|
| Szerep | Távolsági varázsló, AoE |
| Páncél | Cloth |
| Kezdőfegyver | Wand |
| Jártasság | Wand, Staff, One-Hand Sword, Dagger, Off-hand Tome, Off-hand Orb (M6b) |
| Alap | **−3 Max HP**, **−2 Armor**, +3 Intellect |
| Erőforrás | **Mana** (100 + 2 × Int), +10 / mp (Haste-tel nő) |
| Képesség 1 | **Hailstorm** – 50 Mana: jégeső a legsűrűbb ellenségcsoportra, 3 mp, lassít |
| Képesség 2 | **Blink** – 6 mp CD: rövid teleport mozgásirányba |
| Mastery | **Ignite** – a kritikus találat égést okoz (a krit sebzés pontonként +1%-a 3 mp alatt). Ha a krit megölte a célt, a legközelebbi élő ellenség kezd égni a tetemtől 2,5 m-en belül (ha nincs ilyen, elvész) |

### 3.3 Paladin
| | |
|---|---|
| Szerep | Tank / támogató – **co-op erősség** |
| Páncél | Plate |
| Kezdőfegyver | Mace + Shield |
| Jártasság | Sword, Mace, kétkezes Sword / Mace (Two-Hand Sword, Two-Hand Mace – M6b), Shield, Off-hand Tome |
| Alap | +3 Max HP, +3 Armor, **−10% sebzés** |
| Erőforrás | **Resolve** (0–3 pip): +1 minden 5. fegyvertalálat után |
| Képesség 1 | **Sacred Circle** – 10 mp CD: megszentelt föld a lába alatt, 4 mp-ig sebez |
| Képesség 2 | **Call of Valor** – 3 Resolve: gyógyítja magát és a 8 m-en belüli legsebesültebb társat. **Ha 8 m-en belül van elesett társ, azonnal feléleszti** (40% HP-val, a gyógyítás helyett) – az egyetlen azonnali felélesztés a játékban. Kivétel: ha a Grave Tender 1 mp-en belül úgyis feléleszti, inkább gyógyít |
| Mastery | **Aura of Fealty** – a közelben lévő társak HP-regenerációt és Armort kapnak (pontonként) |

### 3.4 Rogue
| | |
|---|---|
| Szerep | Gyors, kritikus sebzés, kitérés |
| Páncél | Leather |
| Kezdőfegyver | 2 × Dagger |
| Jártasság | Dagger, One-Hand Sword, Mace, Bow, Gun, **Dual Wield** |
| Alap | +10% Crit, +10% Dodge, **−3 Max HP**, **−1 Armor** |
| Erőforrás | **Energy** (0–100), +15 / mp; **Combo Points** (0–5): +1 minden kritikus találatnál |
| Képesség 1 | **Knife Bloom** – 35 Energy: 10 tőr minden irányba (egyenként 110% fegyversebzés, mindegyik átüt egy ellenségen); minden elhasznált Combo Point +20% sebzés |
| Képesség 2 | **Melt Away** – 15 mp CD: 2 mp láthatatlanság, az ellenség elveszti a célt, a Rogue visszanyeri a max HP-ja 30%-át, a következő találat garantált krit |
| Mastery | **Lethal Venom** – a krit mérget tesz az ellenségre (pontonkénti DoT). Ha a krit megölte a célt, a méreg a tetemtől 2,5 m-en belüli legközelebbi élő ellenségre kerül (ha nincs ilyen, elvész) |

### 3.5 Warlock
| | |
|---|---|
| Szerep | DoT és pet (idéző) |
| Páncél | Cloth |
| Kezdőfegyver | Staff |
| Jártasság | Wand, Staff, Dagger, One-Hand Sword, Off-hand Tome, Off-hand Orb (M6b) |
| Alap | Állandó **Imp** pet (Intellect-tel skálázódó tűzlövedékek), **−2 Armor**, **−5% Speed** |
| Erőforrás | **Pact Shard** (0–5): +1 minden 12. ölés után |
| Képesség 1 | **Ember Rain** – 1 Pact Shard: tűzeső a legsűrűbb csoportra, 4 mp |
| Képesség 2 | **Vital Siphon** – 8 mp CD: 2 mp-es csatornázás a legközelebbi ellenségre, a sebzést gyógyításként kapja vissza |
| Mastery | **Ember Pact** – +% DoT- és pet-sebzés pontonként |

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

**M8-as nevek – átnevezendők:** a Hunter és a Shaman tervezett nevei (ez a fejezet, a 7. fejezet M8-as sorai és a 9. fejezet) WoW-ból származnak. Az M7a IP-tisztításban ezeket szándékosan nem neveztük át; az M8 építésekor a következő javaslatok szerint kell cserélni:

- Hunter fák: Beast Mastery / Marksmanship / Survival → **Packlord** / **Sharpshot** / **Wildcraft**.
- Shaman fák: Elemental / Enhancement / Restoration → **Stormweaving** / **Warspirit** / **Wellspring**.
- Hunter képességek és Mastery: Multi-Shot, Disengage, Master of Beasts, Aimed Shot, Rapid Fire → **Arrow Fan**, **Backstep**, **Beastbond**, **Long Shot**, **Quick Draw**; a Volley, Explosive Trap, Kill Command és Feign Death javasolt nevei: Blast Snare, Hunt Signal, Play Dead (a megfeleltetést M8-ban kell véglegesíteni).
- Shaman erőforrás és képességek: Maelstrom → **Surge**; Totemic Call → **Totem Rite**; Elemental Overload → **Storm Echo**; Chain Lightning → **Forking Bolt**; Lava Lash → **Magma Lash**; Healing Rain → **Soothing Downpour**; Thunderstorm → **Stormburst**; Feral Spirit → **Spirit Pack**; Ancestral Spirit → **Elder Spirits**.
- Capstone-ok (7. fejezet): Bestial Wrath → **Pack Frenzy**; Trueshot Aura → **Steady Aura**; Wildfire Bombs → **Firebug Bombs**; Elemental Mastery → **Elemental Surge**; Stormstrike → **Gale Strike**; Spirit Link Totem → **Bond Totem**.
- Hunter erőforrás: Focus → **Fervor**.

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

## 4. Fegyverek (13 db: az MVP 10 + az M6b 3)

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

**M6b: három új fegyver** (kész; a Crossbow, a Polearm és a Fist Weapon az M8-cal jön, 3.7):

| Fegyver | Típus | Skálázás | Sebesség / Range | Jellemző | Ki használhatja |
|---|---|---|---|---|---|
| **Two-Hand Sword** | 2H közelharci | 140% Str | 1,2 mp, 2,7 m, 125°-os ív | alapsebzés 10; a One-Hand Sword kétkezes párja: lassabb, nagyobb hatótáv | Warrior, Paladin |
| **Two-Hand Mace** | 2H közelharci | 120% Str + 60% Int | 1,6 mp, 2,4 m, 120°-os ív | alapsebzés 13; 15% esély 0,5 mp kábításra, erős hátralökés | Paladin, Warrior |
| **Orb** | Off Hand | – | – | nincs támadása; +4 Spell Power, +1 Intellect (a Tome-mal azonos költségvetés: 5 pont) | Mage, Warlock |

- Mindhárom a többi fegyverrel azonos szabályok szerint kap ritkaságot, és kovácsolható (4.1).
- Mindegyiknek van **saját Forge Legendary hatása** (fegyvertípusonként egy, 4.1) és egy
  **procedurális megjelenése** (primitívekből: nagy kardpenge arany kereszttel; hosszú nyelű
  buzogány kőfejjel és vas pántokkal; arany talpú-ágú foglalat izzó gömbbel; saját
  ikon-sziluettek és markolat-pózok; a végleges modellek az M7b-ben).
- A két kétkezes fegyver **saját fegyvertípus-azonosítót** kap (`two_hand_sword`,
  `two_hand_mace`), nem a `sword` / `mace`-t: így a Mage, a Warlock és a Rogue (akiknél a
  `sword` / `mace` már jártasság) nem kapja meg őket. A Warrior és a Paladin jártasságlistája
  bővül; az Orb a Mage és a Warlock jártassága.
- Az **Orb** a Tome útját járja (Off Hand, nincs automatikus támadás, nem fegyver-iskola): kétkezes
  fegyver mellé nem vehető fel (a hős nem maradhat támadó fegyver nélkül). A **Warlock a Staff-fal
  (kétkezes) indul**, ezért az Orb (és a Tearglass) csak egykezes főkéz (wand, dagger, sword) mellett
  vehető fel; a Staff mellett elutasítja („would disarm”), ahogy a Tome-nál. A Mage kezdő fegyvere a
  wand, neki nincs ilyen korlátja. A generátor az Orbot a Warlocknak is kínálja.
- A sebzés- és skálázási számok kiinduló értékek, a Two-Hand Axe és a One-Hand Sword / Mace közé
  állítva; az M6b nem hangol (9. fejezet).

### 4.1 Fegyverkovácsolás (Brotato-szerű egyesítés)

**Szabály:** **2 azonos alapfegyver, azonos ritkaságban → 1 fegyver eggyel magasabb
ritkaságban.** Azonos alapfegyver = ugyanaz a fegyvertípus (pl. Dagger, Two-Hand Axe).

> Példa: 2 × Uncommon Dagger → 1 × Rare Dagger.

**Mi kovácsolható:**
- A **generált** fegyverek Commontól Epicig, a kezdőfegyverek is (Common, nem kézzel tervezett).
- **Nem kovácsolható:** kézzel tervezett (unique) fegyver, mert a kézzel tervezett hatása
  elveszne vagy megduplázódna; Legendary, mert az a csúcs; Artifact, mert az hullámonként
  magától fejlődik (5.5).

**Hol lehet kovácsolni:**
- **Karakterpanel / backpack:** a fegyvert kiválasztva (A) megjelenő műveletmenüben
  (Equip / **Forge** / Sell / Disenchant / Trade / Cancel) minden fegyvernél ott a „Forge”.
  - Mellette látszik az eredmény ritkasága („→ Rare”).
  - Ha nincs párja, szürke, és kiírja az okát: „No other Common Dagger”, „Hand-made weapons
    cannot be forged”, „Legendary is the highest rarity”.
  - Sikeres kovácsolás után üzenet jelenik meg a ritkaság színében: „Forged [Rare Dagger]!”.
- **Boltban, automatikusan:** ha a vásárló backpackje tele van, és az ajánlatnak van párja
  nála, a vásárlás egyből kovácsol (mint a Brotatóban).
  - A megvett fegyver be sem kerül a backpackbe.
  - A bolti napló: „P1 bought and forged [Rare Dagger] – 62 g”.
  - Szabad hellyel a fegyver a backpackbe kerül, mint eddig. Tele backpacknél a „Backpack
    full” helyett a vásárlás kovácsol.
- **Bolti jelzés:** az ajánlati kártyán kis üllő-pip jelenik meg minden olyan játékos
  színében, akinek van hozzá párja – akkor is, ha a backpackje még nincs tele.

**A pár és az eredmény helye** (determinisztikus):
- A pár sorrendje: először a backpack (a legelső megfelelő), utána a Main Hand, végül az Off
  Hand; a fegyver soha nem önmaga párja.
- Ha bármelyik fél fel volt szerelve, az eredmény a helyére kerül (ha mindkettő, akkor a Main
  Handbe), különben a backpack végére. Ugyanaz a típus ugyanakkora kéz, így a hős soha nem
  marad fegyver nélkül.

**Az eredmény:** egy friss, eggyel magasabb ritkaságú fegyver ugyanabból az alapfegyverből.
- Szintje a két fél és az aktuális hullám közül a legmagasabb.
- **Új véletlen bónusz statokat és enchantokat kap** a ritkaságának megfelelően.
- **„Looted”** marad, ha bármelyik fele lootból jött (10.1).

**Költség:** **ingyenes** (a boltban csak a vételárat kell kifizetni).

**Ritkaság-szorzók (alapsebzés):**

| Ritkaság | Alapsebzés | Bónusz |
|---|---|---|
| Common | ×1,0 | – |
| Uncommon | ×1,3 | +1 véletlen stat |
| Rare | ×1,7 | +2 stat |
| Epic | ×2,2 | +2 stat és **+10% támadási sebesség** (M6b; a szabály lent) |
| Legendary | ×3,0 | +3 stat és a fegyvertípus **egyedi Legendary hatása** – kézzel tervezett hatás, fegyvertípusonként egy (13 van: a 10 mellé az M6b három új fegyvere – Two-Hand Sword, Two-Hand Mace, Orb – hozott 3-at; pl. Dagger: minden 4. találat mérgező pengét dob, a találat 100%-a Nature sebzésként + méreg) |

**Az Epic fegyver +10% támadási sebessége (M6b, megvalósítva):**
- Az **Epic támadó fegyver** +10% támadási sebességet kap (a cooldown ÷ 1,1). A passzív off-hand
  (Shield, Tome, Orb) nem, mert nincs támadása.
- **Csak az Epic sor** kapja: a Legendary és az Artifact sora nem tartalmazza, és a generált
  Legendary sem örökli az Epic bónuszt (a ×3,0 sebzés ennél erősebb). A kovácsolt Epic és a
  kézzel tervezett Epic fegyver (pl. Frostfang) is megkapja, mert ugyanazon a
  ritkaság-skálázáson megy át. Hogy egy Legendary így lassabban üt, mint az Epic, amelyből
  kovácsolták, a végső balansz nyitott kérdése (9. fejezet).
- A bónusz a Haste-tel **szorzódik** (nem additív), és valódi sebességnövekedés: a fegyverhez
  normált Attack Power / Spell Power és a PPM-esélyek az eredeti cooldownt használják, mint a
  Haste-nél (az Epic fegyver így kicsit több procot ad percenként).
- A tooltip a hatásos sebességet mutatja („Speed 0.82” a 0,9 helyett), a DPS-t ehhez számolja, és
  egy zöld „+10% Attack Speed” sor jelzi. Az érték ritkaságonként egy táblában van, így később egy
  sor átírásával más ritkaság is kaphat bónuszt.

**Az új fegyverek Forge Legendary hatásai (M6b, megvalósítva):**

| Fegyver | Legendary | Hatás |
|---|---|---|
| Two-Hand Sword | **Thistlebrand** | minden 4. találat szögesdárda-félholdat vet: a találat 150%-a fizikai sebzés a célpontra, 40%-os lassítással 3 mp-ig |
| Two-Hand Mace | **Boulderbloom** | minden 4. találat a földre csap: a találat 70%-a mindenkinek 4 méteren belül (a viselő körül), 50%-os lassítással 3 mp-ig |
| Orb | **Tearglass** | minden 3. varázslat (a `spell` címkéjű képességek) után az orb szétpattan: 45 Arcane sebzés (+ Spell Power) mindenkinek 3,5 méteren belül, 30%-os lassítással 2 mp-ig |

A Tearglass az első Forge Legendary, amelyik **varázslat-triggert** (`on_cast`) használ: az Orbnak
nincs találata, ezért fix sebzése van, nem a találat százaléka. „Varázslat” = a `spell`
címkéjű képesség (a Mage és a Warlock varázslatai, pl. Fireball, Umbral Bolt, Vital Siphon; a Blink,
a Frozen Layer, a Fear és a pet-idézések nem). Két Epic Orb / Two-Hand Sword / Two-Hand Mace kovácsolása ezeket adja, mint a
többi fegyvernél.

**Korlátok:**
- Legendary fölé nem lehet kovácsolni; a kovácsolt Legendary-t sem lehet tovább kovácsolni.
- **Artifact** fegyver nem kovácsolható (az hullámonként magától fejlődik, lásd 5.5).
- A kovácsolt Legendary neve a fegyvertípus Legendary-neve; nem lehet WoW-tárgy neve
  (14. fejezet).

**Botok:** a hullámok közt kovácsolják a párjaikat.
- Két backpackbeli fegyvert, vagy egy felszerelt és egy backpackbeli fegyvert; az utóbbinál
  az eredmény a felszerelt helyére kerül.
- Két felszerelt fegyvert (Dual Wield) soha, mert nem tudható előre, hogy jobb lesz-e.
- A bolti automatikus kovácsolást nem használják: vásárlás előtt eladnak, így a backpackjük
  sosem telik meg.

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

**M6b:** az utótagok száma 25 (5.8); a fenti példák a 12 alap-utótagot mutatják. A 7 új utótag
(a meglévő stat-azonosítókkal és a meglévő súlyozással; kész):

| Utótag | Statok (arány) | Súly | Slotok |
|---|---|---|---|
| of the Ox | Stamina 0,6 · Armor 0,4 | 1,0 | a 8 páncélslot |
| of the Lynx | Agility 0,6 · Crit Damage 0,4 | 1,0 | páncél + fegyver |
| of the Raven | Intellect 0,6 · Cooldown Reduction 0,4 | 0,8 | páncél + fegyver |
| of Thorns | Thorns 0,6 · Parry 0,4 | 0,8 | bármely |
| of Mending | Spirit 0,6 · Resource Regen 0,4 | 0,8 | bármely |
| of the Hunter | Slayer 0,6 · Executioner 0,4 | 0,7 | bármely |
| of the Magpie | Gold Find 0,6 · Pickup Range 0,4 | 0,7 | bármely |

- Az elsődleges statot (Str / Agi / Int / Stamina) adó utótagok nem kerülnek nyakra vagy gyűrűre
  (a teszt ellenőrzi).
- Az **of Mending** a Resource Regen mellé **Spiritet** (60%) ad, nem Healing Done-t: a Healing
  Done-t csak a Paladin gyógyítása olvassa, a másik négy kasztnál az utótag 60%-a holt stat lett
  volna; a Spirit minden kasztnál HP-t regenerál.

**Anyag-fokozatok (alaptípusok):** minden páncéltípusnak 3 fokozata van. A magasabb
fokozat a későbbi hullámokban jelenik meg, és +10% / +20% stat-keretet ad.

| Páncéltípus | I. (1–8. hullám) | II. (9–16. hullám) | III. (17. hullámtól) |
|---|---|---|---|
| Cloth | Linen | Silk | Moonweave |
| Leather | Rugged | Thick | Shadowhide |
| Mail | Chain | Scaled | Stormforged |
| Plate | Iron | Steel | Runed |

**M6b – a fokozatok külön alaptípusok (kész):**
- A mai alaptípusok (slotonként és páncéltípusonként egy, összesen 32) az **I. fokozatot**
  adják; az M6b hozzáadta a **II.** és a **III.** fokozatot (+64): slotonként és
  páncéltípusonként 3 alaptípus, összesen **96 páncél-alaptípus**.
- A II. fokozat a **9.**, a III. a **17. hullámtól** érhető el (az alaptípus `min_wave`
  adata; a GDD korábban `ItemBaseData.min_wave`-nek hívta, a kódban az osztály `ItemBase`).
- **Generálás:** a generátor **először az eddigi módon páncéltípust választ** (egy súlyozott
  húzás; a saját kaszt páncéltípusa ×4), **utána** a típus elérhető fokozatai közül a
  hullámon elérhető **legmagasabbat 70%-ban**, egy **alacsonyabbat 30%-ban** (egyenletesen)
  választja. Egy fokozatú típusnál (és az ékszernél, ami nem fokozatos) nincs plusz húzás, így a
  9. hullám alatt, és a korábbi seedekkel generált itemek nem változnak.
- A fokozat **csak az alaptípus nevét és kinézetét** adja (pl. „Runed Plate Carapace”, „Steel
  Cuirass”). A statköltségvetés, az implicit Armor és az anyagnév továbbra is a **hullám**
  anyag-fokozatát követi, nem az alaptípusét; a magasabb fokozatú alaptípus erősebbé tétele
  balansz-változtatás lenne, ezért nem történt meg (9. fejezet).
- Az alaptípus neve csak a darab nevét adja (az anyagszó a hullámtól függ, így nincs az
  alaptípus nevében); a nevek egyediek, kivéve az öt eredeti I. fokozatú főnevet, amelyen két
  páncéltípus osztozik (Gloves, Belt, Boots, Bracers, Leggings: a generált név az anyagszóval
  különbözteti meg őket).
- A II. / III. fokozat alaptípusai (az I. fokozatúak a meglévő 32):

| Slot | Cloth | Leather | Mail | Plate |
|---|---|---|---|---|
| Head | Hood / Veil | Headguard / Mask | Bascinet / Great Helm | Sallet / Warhelm |
| Shoulders | Pelerine / Cape | Epaulets / Spikeguard | Shoulderguards / Mantlet | Shoulderplates / Warplates |
| Chest | Vestments / Raiment | Jerkin / Brigandine | Haubergeon / Byrnie | Cuirass / Plate Carapace |
| Wrist | Wristwraps / Bindings | Armlets / Wristguards | Manchettes / Brassards | Armguards / Wristplates |
| Hands | Mitts / Handwraps | Grips / Handguards | Fingerguards / Knuckleguards | Warfists / Clawgauntlets |
| Waist | Cord / Cincture | Waistband / Cinch | Clasp / Waistguard | Tassets / Waistplate |
| Legs | Trousers / Breeches | Chaps / Legwraps | Chausses / Cuisses | Greaves / Kneecops |
| Feet | Sandals / Treads | Moccasins / Stalkers | Sollerets / Footguards | Warboots / Stompers |

- **Ékszer:** 20 alaptípus (10 Neck, 10 Ring), nem fokozatos (a `min_wave` 1), nincs páncéltípusuk
  és nincs modell-darabjuk. Neck: Amulet, Choker, Necklace, Pendant + az új **Torque, Locket,
  Collar, Medallion, Talisman, Lavalier**. Ring: Band, Loop, Ring, Signet + az új **Seal, Hoop,
  Crest, Bezel, Keeper, Thumb Ring**.

**Teljes névminta:** `[Enchant-előtag] [Anyag] [Alaptípus] [of the Utótag]`

> Példa: *Blazing Runed Plate Helm of the Bear* (Epic, Looted)
> - +8 Strength, +9 Stamina, +4 Armor, +3% Haste
> - *Chance on hit: Hurls a fiery ball that causes 38 Fire damage.*
> - *Equip: Increases your chance to strike twice by 3%.*

### 5.5 Kézzel tervezett itemek (MVP)

#### Trinketek (30 db: az eredeti 10 + az M6b 20, mind kézzel tervezett, proc- vagy aktiválós hatással)

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

**M6b: 20 új trinket (kész, összesen 30).** Mind kézzel tervezett, minden forrásból (shop, loot,
elite, goblin, boss) az 1. hullámtól kapható, a hatásuk a meglévő proc-szókincsből áll (5.7). A
statjuk a ritkaságnak megfelelő trinket-keret (Uncommon ≈ 5, Rare ≈ 8, Epic ≈ 11 pont).

| Név | Ritkaság | Statok | Hatás |
|---|---|---|---|
| Bottled Thundercloud | Rare | nature_damage 6, haste 2 | Találatkor láncvillám 3 ellenség között, 13 Nature sebzés egyenként |
| Wasp-Nest Charm | Uncommon | crit 3, haste 2 | Találatkor darázsraj: 16 Nature sebzés 4 mp alatt, 3× halmozódik |
| Jar of Leeches | Uncommon | leech 1, stamina 2 | Találatkor 7 Shadow sebzést szív el a célpontból, és ugyanennyit gyógyít neked |
| Bell of Stillness | Rare | stamina 4, versatility 2 | Találatkor a harang kongat: 1,5 mp kábítás |
| Warbeat Drum | Epic | haste 4, mastery 4, stamina 3 | Találatkor +4% Haste 6 mp-ig, 5× halmozódik |
| Carrion Talon | Rare | stamina 4, spirit 2 | Öléskor 12% eséllyel a Max HP 6%-át gyógyítja |
| Bone Chime | Rare | physical_damage 6, crit 2 | Öléskor 10% eséllyel a csontok szétrobbannak: 16 Physical sebzés 2,5 m-en belül és 40% lassítás 2 mp-ig |
| Soul Lantern | Rare | spirit 3, stamina 3 | Öléskor 12% eséllyel a Max HP 8%-át elnyelő pajzs 6 mp-ig |
| Notched Tally Stick | Uncommon | crit 3, haste 2 | Minden ölés +1% Damage 8 mp-ig, 8× halmozódik |
| Porcupine Quill | Uncommon | thorns 3, armor 1 | Ha eltalálnak, 20% eséllyel 8 Physical sebzés a támadónak és 30% lassítás 2 mp-ig |
| Beetle Carapace | Rare | armor 2, stamina 3 | Ha eltalálnak, 15% eséllyel +8 Armor 5 mp-ig |
| Basilisk Eye | Epic | dodge 3, stamina 4, versatility 2 | Ha eltalálnak, 10% eséllyel a támadó 2 mp-ig kábult |
| Ashfall Feather | Epic | stamina 6, spirit 3 | 30% HP alatt a Max HP 25%-át gyógyítja (hullámonként 1×) |
| Alarm Whistle | Rare | speed 5, dodge 2 | 35% HP alatt hangrobbanás: 25 sebzés 4 m-en belül és 1,5 mp kábítás (hullámonként 1×) |
| Smoke Pouch | Uncommon | dodge 2, speed 2 | 40% HP alatt +20% Speed és +15% Dodge 4 mp-ig (20 mp ICD) |
| Mote Lantern | Rare | holy_damage 6, spell_power 2 | 6 mp-enként 22 Holy sebzés a legközelebbi ellenségnek |
| Singing Bowl | Rare | stamina 4, resource_regen 3 | 15 mp-enként a Max HP 8%-át elnyelő pajzs 8 mp-ig |
| Prospector's Pebble | Uncommon | gold_find 10 | 15 mp-enként 2 gold |
| Wayward Compass | Epic | arcane_damage 8, spell_power 3 | 9 mp-enként 30 Arcane sebzés a körülötted lévő, 3 m-en belüli ellenségeknek |
| Votive Candle | Rare | holy_damage 5, spirit 2 | Találatkor 12 Holy sebzés a célpontnak, és 5 HP gyógyítás a legsérültebb társnak |

Eloszlás: 6 Uncommon + 10 Rare + 4 Epic az újak között (az összes 30: 9 / 15 / 6). Trigger szerint:
6 találatkor (on hit), 4 öléskor, 3 amikor eltalálják, 3 alacsony HP-nál, 4 időzített (periodic).
Új blokk vagy trigger nincs. A *periodic* és az *alacsony HP-s* területi hatások (Wayward Compass,
Alarm Whistle) mindig a viselő körül hatnak, mert ott nincs találati célpont. A Notched Tally Stick
**néma** (minden ölésnél halmozódik, ezért nem lebeg felirat a hős fölött).

#### Legendary itemek (25 db: az eredeti 8 + az M6b 17)

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

**M6b: 17 új Legendary (kész, összesen 25).** Loot-forrásokból (loot, elite, goblin, boss), a
10. hullámtól; **kasztkorlát nélkül** (a Legendary nem kaszthoz kötött), de kaszt-hangulatúak: a
statjuk a kaszt fő statját adja, a hatásuk a kaszt stílusához illik. A viselhetőséget a páncéltípus
adja (mint a meglévő nyolcnál): a ruha (Cloth) mindenkié, a bőr (Leather) a Rogue-é és a lemezeseké,
a lemez (Plate) csak a Warrioré és a Paladiné. Mind az 5 addig Legendary nélküli slottípus (Neck,
Chest, Wrist, Legs, Trinket) kapott egyet, így a 12 slottípus mindegyikéhez van Legendary. A
nyaklánc és a gyűrű nem ad fő statot (5.4). A fegyvertípusonkénti Forge Legendary hatások (4.1)
ettől külön készletet adnak.

| Név | Slot | Páncél | Kaszt-hangulat | Viselheti | Hatás |
|---|---|---|---|---|---|
| Greathelm of the Gilded Oath | Head | Plate | Paladin | Warrior, Paladin | 8 mp-enként a legsérültebb társ Max HP-jának 12%-át gyógyítja |
| Pauldrons of the Radiant Bulwark | Shoulders | Plate | Paladin | Warrior, Paladin | Ha eltalálnak, 20% eséllyel a Max HP 15%-át elnyelő pajzs 5 mp-ig (8 mp ICD) |
| Sabatons of the Long March | Feet | Plate | Paladin | Warrior, Paladin | 6 mp-enként 18 Holy sebzés a 3 m-en belüli ellenségeknek és 40% lassítás 2 mp-ig |
| Breastplate of Unbroken Anger | Chest | Plate | Warrior | Warrior, Paladin | Ha eltalálnak, 40% eséllyel +4% Damage 8 mp-ig, 6× halmozódik |
| Girdle of the Last Roar | Waist | Plate | Warrior | Warrior, Paladin | 40% HP alatt +25% Damage és +10 Armor 8 mp-ig (hullámonként 1×) |
| Tearjerker | Main Hand (Two-Hand Axe) | - | Warrior | Warrior | Találatkor 36 Physical sebzés 4 mp alatt (3× halmozódik); a vérző ellenség halálakor a sebek a 3 m-en belüli ellenségekre terjednek |
| Hood of the Quiet Knife | Head | Leather | Rogue | Rogue, Warrior, Paladin | Öléskor 15% eséllyel +20% Crit és +15% Speed 5 mp-ig |
| Bracers of the Hidden Blade | Wrist | Leather | Rogue | Rogue, Warrior, Paladin | Találatkor rejtett penge: a célpont a találat 120%-ának megfelelő Physical sebzést kapja (hit_pct: a találattal skálázódik) |
| Breeches of the Light Fingers | Legs | Leather | Rogue | Rogue, Warrior, Paladin | Öléskor 6% eséllyel 3 gold |
| Vial of Distilled Adrenaline | Trinket | - | Rogue | all | 25 mp-enként +35% Haste és +15% Damage 8 mp-ig |
| Amulet of Unspent Wishes | Neck | - | Mage | all | 6 mp-enként arkán varázsnyilak ugranak 4 ellenség között, 20 Arcane sebzés egyenként |
| Leggings of the Brimming Well | Legs | Cloth | Mage | all | Találatkor +2 Spell Power és +3% Arcane Damage 6 mp-ig, 5× halmozódik |
| Staff of the Deep Winter | Main Hand (Staff) | - | Mage | Mage, Warlock | Találatkor 24 Frost sebzés és 1,5 mp kábítás (befagyasztás) |
| Gloves of the Patient Rot | Hands | Cloth | Warlock | all | 6 mp-enként a legközelebbi ellenségbe rothadás: 40 Shadow sebzés 5 mp alatt; a gazdája halálakor a 3 m-en belüli ellenségekre terjed |
| Robe of the Hollow Pact | Chest | Cloth | Warlock | all | Ha eltalálnak, 20% eséllyel 24 Shadow sebzést szív el a támadóból, és ugyanennyit gyógyít neked |
| Ring of the Mischievous Imp | Ring | - | Warlock | all | Minden 4. ölésnél az imp tűzgolyói 3 ellenség között ugrálnak, 20 Fire sebzés egyenként |
| Grimoire of Seeded Doom | Off Hand (Tome) | - | Warlock | Mage, Paladin, Warlock | Találatkor 26 Shadow sebzés a célpontnak és a 3 m-en belülieknek, és 20 DoT 4 mp alatt |

Kaszt-lefedettség (hangulat szerint az új 17-ből): Warrior 3, Paladin 3, Rogue 4, Mage 3,
Warlock 4. Minden kaszt legalább 8-at viselhet az új 17-ből és legalább 12-t az összes 25-ből, és
mindegyik megtalálja a fő statját legalább 3 viselhető újon (teszt).

#### Névvel ellátott Rare / Epic itemek (40 db: az eredeti 10 + az M6b 30)

Kézzel tervezett, kasztkorlát nélküli Rare / Epic itemek egyedi névvel és egy-egy hatással. Mindegyik
egy meglévő proc-blokkot használ (nincs új trigger). Forrás: mind az öt (shop, loot, elit, goblin,
boss), az 1. hullámtól. Az eredeti 10 (M2): Bramblethorn Bracers, Emberglow Wand, Frostfang,
Galestride Boots, Grimtusk Cleaver, Helm of the Iron Vigil, Mossweave Leggings, Pendant of the
Starless Night, Signet of the Dawnwatch, Sunforged Breastplate. Az M6b 30 új darabja:

| Név | Ritkaság | Slot / páncél | Statok | Hatás |
|---|---|---|---|---|
| Circlet of Ninefold Skin | Rare | Head / Cloth | +6 Intellect, +4 Stamina | 15 mp-enként +3 gyógyítás (magadnak) |
| Tunic of the Quiet Bulb | Rare | Chest / Leather | +5 Agility, +5 Stamina | Ölésnél 8% eséllyel +20% Haste 3 mp-ig |
| Bracers of the Shallot Fold | Rare | Wrist / Cloth | +3 Intellect, +3 Spirit | Ütésnél 20% eséllyel 3 sebzés-pajzs 3 mp-ig |
| Garlic Clove Pendant | Rare | Neck | +4 Stamina, +3 Spirit | Találatnál 2,5 ppm: 10 Frost sebzés |
| Ring of the Chive Coil | Rare | Ring | +4 Crit, +3 Haste | Találatnál 2 ppm: 1 extra ütés |
| Quickstep Boots | Rare | Feet / Leather | +5 Agility, +5 Speed | 12 mp-enként +15% Speed 3 mp-ig |
| Leggings of the Scaled Skin | Rare | Legs / Mail | +5 Strength, +4 Stamina | Ütéskor 8%: 6 Holy sebzés 2 m-en belül (kör) |
| Shardbound Gauntlets | Rare | Hands / Mail | +5 Haste, +3 Strength | Találatnál 3 ppm: 9 Arcane sebzés |
| Cellar Sash | Rare | Waist / Cloth | +5 Intellect, +3 Spirit | Ölésnél 6%: +2 arany |
| Shoulderpads of Shallow Roots | Rare | Shoulders / Leather | +4 Agility, +4 Stamina | Találatnál 3 ppm: 25% lassítás 2 mp-ig |
| Splinterwand | Rare | Fegyver (wand) | +5 Intellect, +3 Crit | Találatnál 3 ppm: 8 Arcane sebzés, ugrik 2 célpontra |
| Ring of the Ember Bulb | Rare | Ring | +4 Versatility, +3 Stamina | Ölésnél 6%: 10 Fire sebzés 2 m-en belül |
| Cuffs of the Last Breath | Rare | Wrist / Cloth | +3 Spirit, +2 Versatility | 30% HP alatt (hullámonként 1×): 6 sebzés-pajzs 4 mp-ig |
| Helm of the Brittle Crown | Rare | Head / Mail | +4 Strength, +5 Stamina | 14 mp-enként +3 gyógyítás a legsérültebb szövetségesnek |
| Breastplate of the Crisp Shell | Rare | Chest / Mail | +5 Strength, +6 Stamina | Ütéskor 15%: 5 Fire visszasebzés |
| Visor of the Sunward Watch | Epic | Head / Plate | +8 Strength, +8 Stamina | Ütéskor 12%: 8 Holy visszasebzés |
| Ringmail of the Second Skin | Epic | Chest / Mail | +7 Strength, +7 Stamina, +2 Crit | Ütéskor 9%: 12 Physical sebzés 2,5 m-en belül (kör) |
| Silken Leggings of the Veil | Epic | Legs / Cloth | +8 Intellect, +6 Spirit | 8 mp-enként +4 gyógyítás a legsérültebb szövetségesnek |
| Treads of the Nimble Clove | Epic | Feet / Leather | +6 Agility, +4 Crit, +3 Haste | Találatnál 2,5 ppm: extra ütés |
| Gauntlets of the Cloven Crust | Epic | Hands / Plate | +5 Strength, +6 Stamina, +3 Versatility | Találatnál 2,5 ppm: 12 Holy sebzés + 4 gyógyítás a legsérültebb szövetségesnek |
| Girdle of the Unyielding Layer | Epic | Waist / Plate | +6 Strength, +7 Stamina | 35% HP alatt (hullámonként 1×): 10 sebzés-pajzs 4 mp-ig |
| Spaulders of the Hollow Shell | Epic | Shoulders / Mail | +6 Strength, +5 Haste | Ölésnél 15%: +12% Crit 4 mp-ig |
| Halo of the Pearled Onion | Epic | Head / Cloth | +7 Intellect, +4 Spirit, +2 Versatility | Találatnál 3 ppm: 16 Arcane sebzés |
| Signet of the Festering Wound | Epic | Ring | +5 Crit, +4 Leech | Találatnál 4 ppm: 8 Shadow sebzés 4 mp alatt, max. 2 halmozódás |
| Amulet of the Thousand Skins | Epic | Neck | +6 Stamina, +4 Haste | Ütéskor 15%: 4 sebzés-pajzs 4 mp-ig |
| Wrap of the Blighted Peel | Epic | Wrist / Leather | +5 Agility, +3 Crit | Ölésnél 10%: 12 Nature sebzés 2,5 m-en belül (kör) |
| Scallion Edge | Epic | Fegyver (sword) | +5 Strength, +3 Crit | Találatnál 3 ppm: 14 Physical sebzés a cél körül 2,5 m-en belül |
| Shallot Shiv | Epic | Fegyver (dagger) | +6 Agility, +3 Crit | Ölésnél 10%: 3 gyógyítás magadnak |
| Robe of the Lantern Heart | Epic | Chest / Cloth | +8 Intellect, +4 Spirit, +2 Haste | 15 mp-enként +20% Haste 4 mp-ig |
| Leathers of the Rooted Dance | Epic | Legs / Leather | +7 Agility, +5 Stamina | Találatnál 3 ppm: 8 Nature sebzés, szívás (gyógyulsz is) |

A Black Market ezeket nem árulja (tier-set darab vagy generált max-roll Epic, 16.1); a Shrine of
Fortune és a dungeon-jutalom Epic itemei viszont kaphatnak ilyet is (a generátor kézzel tervezett
Epic-sorsolása).

#### Tier setek (kasztonként 1, Epic ritkaság, 5 darab: Head, Shoulders, Chest, Hands, Legs)

| Kaszt | Set | 2 darab | 4 darab |
|---|---|---|---|
| Warrior | Ragebound Plate | +10% Rage-termelés | A Whirlwind 30%-ban ingyenes |
| Mage | Regalia of the Arcane | +10% Haste | A Blink után 3 mp-ig +30% sebzés (legfeljebb 6 mp-enként) |
| Paladin | Dawnforged Plate | +3 Armor | A Call of Valor minden hőst gyógyít 8 m-en belül, és a gyógyítás a Max HP további 10%-át adja vissza |
| Rogue | Shadowstitch Garb | +5% Crit | A Melt Away után 4 mp-ig +50% krit sebzés |
| Warlock | Hexfire Raiment | +10% pet-sebzés | Az Ember Rain 20%-ban nem fogyaszt Pact Shard-ot |
| Hunter (M8) | Wildrunner's Garb | +10% pet-sebzés | A Multi-Shot +2 nyilat lő |
| Shaman (M8) | Totemkeeper's Mail | +30% totem-időtartam | A Chain Lightning +2 célpontot ér |

> **M6b-ből M8-ra tolva:** a **kaszt-független tier setek** (5.8) – ezek a set-rendszer
> módosítását igénylik (a rendszer ma kasztonként egy setet feltételez), ezért az M8-cal
> jönnek, nem az M6b-vel. Az M6b-ben a tier setek kasztonként egy-egy marad.

- **Nevek:** a Paladin, a Rogue és a Warlock setje új nevet kapott (korábban Lightforged
  Plate, Shadowcraft Garb, Felheart Raiment), mert azok WoW-setek, illetve -kifejezések
  nevei (14. fejezet).
- **Dawnforged Plate 4 darab:** a „minden hőst gyógyít” rész ugyanaz, mint a Call of Valor
  V. rangú „Chorus of Dawn” specializációja, ezért a bónusz +10 százalékpontot is ad a
  gyógyítás Max HP-arányos részéhez (25% → 35%, × a rang ereje). Így a Chorus of Dawn-t
  választó Paladinnak is ér valamit a 4 darab.
- **A darabok:**
  - Epic ritkaságúak, kaszthoz kötöttek („Classes: X”), a kaszt páncéltípusában.
  - Kézzel tervezett statjuk van: elsődleges stat + Stamina + egy másodlagos, az Epic
    keretében.
  - A 6. hullámtól jelennek meg.
- **Honnan jönnek:**
  - Egy Epic dobás a boltban **5%**, lootból (normál drop, elit, Coin Gremlin, boss) **15%**
    eséllyel set-darab lesz – lootban 3× gyakoribb (5.2).
  - Boltban az első Epic-hullámtól (9.) kaphatók.
  - A darab mindig a csapat egyik kasztjának szól.
  - Az adott set darabjai közül egyenlő eséllyel jön egy; duplikátum lehetséges (azt
    Greedelni lehet).
- **Bónuszok:** halmozódnak (4 darab = a 2- és a 4-darabos bónusz együtt); 5-darabos bónusz
  nincs.
- **Tooltip:**
  - A set neve és az állás: „(n/5)”, a dobóablakban „(5 pieces)”.
  - Az öt darab: a saját panelen és a boltban röviden, a slotjuk nevével egy sorban
    („Head  Shoulders  Chest  Hands  Legs”, a felvettek világosan), flavor szöveg nélkül –
    így a sarokpanelben is olvasható; a dobóablakban a darabok teljes nevével.
  - A „(2) Set: …” / „(4) Set: …” sor zöld, ha aktív, egyébként szürke.
- **Botok:**
  - A 2-es vagy 4-es küszöböt elérő darab fejlesztésnek számít, hacsak a statjai 30%-nál
    többel nem rosszabbak.
  - A botok a hátizsákba is előre néznek: ha ugyanannak a setnek más darabjai (más slotra,
    ahol nincs setdarab, és legfeljebb 30%-kal gyengébbek annál, amit leváltanának) a
    hátizsákban várnak, ezekből annyit számítanak viseltnek, amennyi a következő küszöbhöz
    (2 vagy 4 darab) még hiányzik – a legjobbakat. Így a 3. darab is fejlesztés, ha a 4. már
    megvan, a 4. darab akkor is, ha egy 5. is vár mellette, és a botok egy piacon elérik a
    4 darabos bónuszt.
  - Egy sima tárgy, amely egy így elérhető 4 darabos bónuszból venné ki a 3. darabot,
    rosszabbnak számít (hacsak nem több mint 30%-kal jobb); egy viselt 4 darabos bónuszt sem
    bontanak meg azért, mert a leváltott darab a hátizsákban vár. Teljes (5 darabos) setből
    egy darabot odaadhatnak egy jobb sima tárgyért, egy másodikat már nem.
  - Addig ismétlik a felszerelést a hátizsákból, amíg már semmit sem vesznek fel (legfeljebb
    a hátizsák méretének megfelelő körben), így ami egy későbbi csere után lett fejlesztés, az
    ugyanazon a piacon felkerül.

#### Artifact fegyverek (kasztonként 1)

Az Artifact **ritka, véletlen loot** – senki nem kapja meg automatikusan. Ha leesik, az
a menet legnagyobb pillanata. (M6a: az öt jelenlegi kasztnak; a Hunter és a Shaman Artifactja
az M8-cal jön.)

**Honnan eshet (a 10. hullámtól)**

Az Artifact-dobás **ölésenként** történik, a normál loot-dobás után, és csak a 10. hullámtól.

| Forrás | Esély |
|---|---|
| Boss (10. és 25. hullám) | 15% – **bossonként egyszer** (nem a boss-loot itemenként), plusz pech-védelem |
| Coin Gremlin | 5% |
| Elit | 2% |
| Normál ellenség | **0,05% ÷ játékosszám** (a „jackpot”): 1 fő 0,05%, 2 fő 0,025%, 3 fő 0,0167%, 4 fő 0,0125% |

- **Egy ölés = egy dobás.** Egy elit ölése két hívást csinál (elit, majd normál loot), egy boss
  ölése hősönként egyet: csak az első számít. A dobás forrása a kill legmagasabb forrása:
  **boss > Coin Gremlin > elit > normál ellenség**, akkor is, ha a hívás alacsonyabbat mond. A
  boss halála így mindig egyetlen dobás (a gyilkos Fortune-jével), nem hősönként egy.
- **Fortune:** a gyilkos Fortune-ja minden esélyt szoroz: × (1 + Fortune%) (pl. Fortune 100
  megduplázza); az esély legfeljebb 100%.
- **Miért osztjuk a normál esélyt a játékosszámmal:** a hullámonkénti ölések száma a
  csapattal nő (spawn-szorzó `1 + 0,6 × (n − 1)`, 9. fejezet), a bossok, a goblinok és az
  elitek száma alig. Osztás nélkül egy 4 fős csapat menetenként átlag 7,1 találatot kapott
  volna (a szóló hős 2,9-et), és a menetek ≈ 84%-ában mind az öt kaszté leesett. Az osztással a
  normál ölésekből várt találat a csapatmérettől alig függ.
- **Pech-védelem:** csak egy ténylegesen lefutott, de mellément **boss-dobás** növeli (+5
  százalékpont a következő boss-esélyhez; egy boss egyetlen lépés); bármelyik Artifact-drop
  nullázza. A többi forrást nem érinti.
- **Várható Artifact egy teljes (25 hullámos) menetben** (Fortune 0, számított érték; a
  40. szintű bot-futások – 1 fő 5, 4 fő 4 Artifact – összhangban vannak vele; egy-egy futás
  nem bizonyíték, a 2 fős futás pedig a 20. hullámon vereséggel ért véget):

  | Játékosok | Normál ölés (10–25. hullám) | Várt találat: normál / elit / boss / goblin | Összesen | Várt Artifact (max. 5) | Osztás nélkül |
  |---|---|---|---|---|---|
  | 1 | ≈ 4 220 | 2,11 / 0,39 / 0,32 / 0,05 | 2,9 | 2,8 | 2,9 → 2,8 |
  | 2 | ≈ 6 760 | 1,69 / 0,53 / 0,32 / 0,05 | 2,6 | 2,5 | 4,3 → 3,8 |
  | 4 | ≈ 11 830 | 1,48 / 0,81 / 0,32 / 0,05 | 2,7 | 2,6 | 7,1 → 4,7 |

  Mind az öt Artifact leesésének esélye 1 / 2 / 4 játékosnál ≈ 16% / 12% / 13% (osztás nélkül
  16% / 43% / 84%). A számítás: a 10–25. hullám ölései (a két boss, az elitek és a goblinok
  nélkül; a 20. hullám „lite” elitjei normál dobást adnak), az elitek `EliteAffixes.
  expected_count` szerint, a boss 15% (a 25. hullámon + pech ≈ 0,32 találat), a goblin ≈ 1 ölés
  menetenként; a várt Artifact a Poisson-eloszlású találat és az 5-ös kasztlimit minimuma.
- Debug: `--artifact-chance=X` minden dobás esélyét X-re állítja (osztás és Fortune nélkül; a
  10. hullám és a kasztszabály marad); 0 = soha.

**Melyik kaszté:**
- 80% eséllyel a csapatban lévő, még Artifact nélküli kasztok egyikéé (ha már nincs ilyen:
  bármely még szabad kaszté), 20% eséllyel bármely még szabad kaszté.
- Egy menetben kasztonként legfeljebb **1 Artifact** eshet: az a kaszt, amelyiké már leesett,
  kimarad a sorsolásból; ha mindegyiké leesett, nincs több Artifact-drop (és sorsolás sem).

**A dobás:** a leesett Artifact aranyszínű lootzsákban esik (9 m-es fénynyaláb, „Artifact!”
felirat), nem számít a normál drop hullámlimitjébe, és a szokásos **Need / Greed / Pass**
dobásra megy (10.1).
- **Need:** csak a megfelelő kasztú játékos nyomhat rá Needet; a többieknek csak Greed vagy Pass
  választható. Teli backpackkel a Need nem megy („Backpack full”): helyet kell csinálni, vagy
  Greedet választani.
- **Greed:** nem az eladási árat, hanem az adott hullám **Epic árának 5-szörösét** adja a közös
  kasszába (pl. a 10. hullámon 775 gold). Így akkor is nagy jutalom, ha senki nem tudja
  használni.

**Az item:**
- **Ritkasága Artifact:** nem adható el (a Sell sor szürke, „Artifact”), nem kovácsolható
  („Artifacts grow on their own”), nem Disenchantolható (a „mindenki Pass” után sem lesz belőle
  Dust), és az Enchanter sem módosítja (5.7): a két fix enchantja marad. Átadható (Trade).
- **Statok:** kézzel tervezettek (a hullám anyagszintjével és a loot-bónusszal skálázva),
  2 fix enchant (III. rang), a fegyver alapsebzése a Legendary szorzóval (×3). Nincs „Looted”
  +6 Item Level, és a tooltipben nincs eladási ár.
- **Item Level:** a leesés hullámán `10 + 3 × hullám + 25` (5.6.1), így akkor is értelmes,
  ha későn esik le.
- **Fejlődés:** minden hullám végén, amíg a hősnél van (felszerelve vagy a backpackben is),
  **+3 Item Level** és az **alapsebzés (a felvételkori) 4%-a** hozzáadódik – lineárisan, nem
  kamatosan: n hullámvég után `alapsebzés × (1 + 0,04 × n)`.
- **Slot:** Main Hand fegyver; a kétkezes változatok mindkét slotot foglalják.
  - **Kivétel – *Fangs of the Shadow*:** egy **pár**, egy Main Hand és egy Off Hand tőr, egyetlen
    backpack-helyen. Felvételkor mindkét kéz betelik (a kiszorított két tőr a backpackbe
    megy); bármelyik tőr kiszorítása (vagy másik fegyver felvétele) az egész párt kiveszi, és
    **egyetlen** backpack-itemként jön vissza. A pár egy fegyvernek számít az „utolsó fegyver”
    védelemnél (nem Unequip-olható, csak lecserélhető), és **egyetlen Artifactnak** számít (a
    kasztonkénti limitnél, a növekedésnél és a tulajdonságoknál is).
- **Két különleges tulajdonság:** az elsőt a felvétel után **3**, a másodikat **6 hullámvéggel**
  kapja meg; **csak felszerelve aktívak** (a backpackben lévő Artifact csak nő). Addig a
  tooltip kiírja, mikor nyílik meg („Awakens in N waves”).
- **Ha az abilityt nem tanulta meg:** az a tulajdonság, amelyhez a hős még nem tanulta meg a
  szükséges abilityt, szürkén látszik, a hiányzó ability nevével („(needs Whirlwind)”). Az M6a
  mind a 10 tulajdonsága alap-abilityre épül, ezért a szürke állapot ma csak egy másik kaszt
  nézőjének tooltipjében látszik.
- **Tooltip:** arany cím + szöveg (ébren), halvány cím + „Awakens in N waves” (alszik), szürke
  cím + „(needs X)” (hiányzó ability). Az Artifact mindig upgrade a botoknak, és sima felszerelés
  sosem váltja le.

| Kaszt | Artifact | 1. tulajdonság (3 hullámvég után) | 2. tulajdonság (6 hullámvég után) |
|---|---|---|---|
| Warrior | *Earthsplitter* (2H Axe) | A Whirlwind elindulásakor a hős lábánál **földrengés-zóna** keletkezik (a Whirlwind alapsugara, 3 mp, 0,5 mp-es tickek, tickenként a fegyversebzés 30%-a) | A Charge becsapódása **lökéshullámmal** végződik: a 3 m-en belüli ellenségeket 1 mp-re elkábítja (az Area Size növeli a sugarat) |
| Mage | *Staff of the Frostwyrm* (Staff) | Minden 4. Hailstorm (a hős számlálója, a hullámokon át megy) **dupla sugarú** | A lassított vagy fagyott ellenség, amit megölsz, **jégszilánkokra** robban: a 3 m-en belüli ellenségek 40%-kal lassulnak 2 mp-re |
| Paladin | *Dawnbreaker* (Mace) | A Sacred Circle **gyógyítja a benne álló hősöket** (a Paladint is): 0,5 mp-enként a Max HP 1%-át (= 2%/mp) | A Call of Valor a gyógyított / feltámasztott hőst a Max HP-ja 15%-ának megfelelő **pajzzsal** is védi (nem halmozódik 15% fölé) |
| Rogue | *Fangs of the Shadow* (tőr-pár: Main Hand + Off Hand) | Minden 5. krit támadás **ingyen Knife Bloom**-t lő (támadásonként csak az első találat számít; Combo Pointot használ el, Energiát nem) | A Melt Away után a következő **3 találat krit** |
| Warlock | *Skull of the Damned* (Staff) | Állandó **második pet**: egy Gloomguard (a Summon Gloomguard paramétereivel, Shared Pain pajzs nélkül; a hullám első tickjén jön, a hullám végén és a hős elestekor elmegy), ami magára vonja az ellenségeket | A petek **+25% sebzést** okoznak, és sebzésük 10%-át a Warlock gyógyulásként kapja |
| Hunter (M8) | *Galestrike Longbow* (Bow) | Minden 4. lövés nyílzáporrá hasad | az M8-cal készül |
| Shaman (M8) | *Fist of the Ancestors* (Mace) | A Chain Lightning egy villám-totemet idéz | az M8-cal készül |

**Botok:** a bot Needeli a saját kasztja Artifactját, felveszi, sosem adja el; ha a backpackje
tele van, a loot-dobás előtt eladja az első nem-upgrade itemét (ha minden upgrade, Greedel).
Artifact-fegyverrel az Enchantert a páncéljára használja (5.7).

#### Kaszt-specifikus itemek

A WoW-hoz hasonlóan vannak **csak egy kaszt által használható** itemek. A tooltipben külön
sor jelzi: „*Classes: Mage*”.

- **Mit tudnak:** az erejük nem a statokban van, hanem abban, hogy a kaszt saját
  képességeit **módosítják**, pl. hosszabb időtartam, extra célpont vagy új mellékhatás.
- **Honnan:** lootból és a boltból. A közös bolt a csapat kasztjaihoz illőket kínálja
  (10. fejezet).
- **Need:** csak az adott kaszt nyomhat rá.
- **Ritkaság:** Rare-től felfelé léteznek. A tier set darabok is ilyenek.

**Az eredeti 10 (kasztonként 2; az MVP terve kasztonként 4 volt, a többi az M6b-ben készült el)**

| Kaszt | Item | Slot | Hatás |
|---|---|---|---|
| Warrior | Gauntlets of the Whirling Blade | Hands | A Whirlwind +1 mp-ig tart, és közben lassít |
| Warrior | Vanguard's Greaves | Feet | A Charge után 3 mp-ig +20% sebzés |
| Mage | Rimeweave Cowl | Head | A Hailstorm területe +30% |
| Mage | Band of the Blinking Star | Ring | A Blink 2 töltettel használható |
| Paladin | Hymnal of Devotion | Off Hand (Tome) | A Call of Valor 1 Resolve-rel olcsóbb |
| Paladin | Sabatons of the Dawn | Feet | A Sacred Circle követi a Paladint |
| Rogue | Shadowstalker Wraps | Wrist | A Melt Away 5 mp-mel rövidebb cooldownú |
| Rogue | Blade of the Thousand Cuts | Main Hand (Dagger) | A Knife Bloom +4 tőrt dob |
| Warlock | Grimoire of the Imp Lord | Off Hand (Tome) | Az Imp +50% sebzés, és tűzlövedéke 2 célpontot ér |
| Warlock | Soulbinder's Sash | Waist | Minden 8. ölés ad Pact Shard-ot (12 helyett) |

A többi 30 az M6b-ben készült el, ugyanígy (lent).

**M6b: kasztonként 8, összesen 40 kaszt-specifikus item (kész**; az M6a-ban 10 volt, tehát +30).
Mind „*Equip:*” sorral módosítja a kaszt egyik képességét (ability mod), Rare-től felfelé (5.8).
A kasztonkénti 6 új darab:

| Név | Kaszt | Ritkaság / slot | Statok | Módosítás |
|---|---|---|---|---|
| Warhelm of the Standing Shout | Warrior | Epic / Head (Plate) | +7 Strength, +8 Stamina | Battle Roar +5 m sugár |
| Shoulderguards of the Stubborn Wall | Warrior | Rare / Shoulders (Plate) | +5 Strength, +4 Stamina | Stalwart Guard +2 mp |
| Breastplate of Thunderous Echo | Warrior | Epic / Chest (Plate) | +8 Strength, +8 Stamina | Ground Slam +1 visszhang |
| Wristguards of the Sundering Edge | Warrior | Rare / Wrist (Plate) | +3 Strength, +3 Crit | Execute küszöb +10% |
| Legplates of the Bold Leap | Warrior | Rare / Legs (Plate) | +6 Stamina, +3 Strength | Soaring Slam bénítása 1 mp-cel hosszabb |
| Reaping Greataxe | Warrior | Epic / Fegyver (two-hand axe) | +8 Strength, +4 Crit | Steel Cyclone −5 mp cooldown |
| Long Coal Staff | Mage | Epic / Fegyver (staff) | +6 Intellect, +8 Fire Damage | Fireball égése a találat 15%-ával több sebzést okoz |
| Shoulderwrap of the Glacial Ring | Mage | Rare / Shoulders (Cloth) | +4 Intellect, +4 Stamina | Rime Burst fagyasztás +0,5 mp |
| Robe of the Tidewoven Veil | Mage | Epic / Chest (Cloth) | +8 Intellect, +5 Stamina | Frozen Layer teljes pajzsa (alap + Intelligencia + Spell Power) +25% |
| Leggings of the Falling Star | Mage | Epic / Legs (Cloth) | +7 Intellect, +5 Stamina | Meteor bénítása 0,5 mp-cel hosszabb |
| Cuffs of the Blazing Heart | Mage | Rare / Wrist (Cloth) | +3 Intellect, +3 Haste | Magma Bolt égése a találat 10%-ával több sebzést okoz |
| Gloves of the Quiet Missile | Mage | Rare / Hands (Cloth) | +5 Intellect, +2 Spirit | Arcane Darts +1 lövedék |
| Helm of the Holy Hour | Paladin | Epic / Head (Plate) | +7 Strength, +8 Stamina | Ricochet Shield +1 célpont |
| Pauldrons of the Second Oath | Paladin | Rare / Shoulders (Plate) | +4 Strength, +4 Stamina | Boon of Crowns +4 mp |
| Cuirass of the Vigilant Dawn | Paladin | Epic / Chest (Plate) | +8 Strength, +9 Stamina | Gilded Halo −8 mp cooldown |
| Vambrace of the Oathstone | Paladin | Rare / Wrist (Plate) | +3 Strength, +2 Versatility | Smiting Hammer +0,5 mp stun |
| Girdle of Lasting Grace | Paladin | Epic / Waist (Plate) | +6 Strength, +6 Stamina, +3 Crit | Mending Touch újratöltése 10 mp-cel rövidebb |
| Legplates of the Endless Storm | Paladin | Rare / Legs (Plate) | +5 Strength, +6 Stamina | Radiant Whirl +1 hullám |
| Hood of Quick Blades | Rogue | Epic / Head (Leather) | +7 Agility, +6 Stamina | Cleaving Blades +1 célpont |
| Pauldrons of the Pale Smoke | Rogue | Rare / Shoulders (Leather) | +4 Agility, +4 Crit | Poison Bomb lassítása további +20% |
| Jerkin of the Last Breath | Rogue | Epic / Chest (Leather) | +8 Agility, +7 Stamina | Narrow Escape +5% Max HP gyógyulás |
| Gloves of the Quick Thrust | Rogue | Rare / Hands (Leather) | +5 Agility, +3 Haste | Cutthroat Rush −3 mp cooldown |
| Belt of Shifting Shadows | Rogue | Rare / Waist (Leather) | +4 Agility, +4 Stamina | Duskstep buff +1 mp |
| Leathers of the Unseen Throw | Rogue | Epic / Legs (Leather) | +7 Agility, +4 Crit | Throwing Stars +1 shuriken, +3 m hatótáv |
| Hood of Burning Summons | Warlock | Epic / Head (Cloth) | +7 Intellect, +6 Stamina | Summon Cinder Brute −10 mp cooldown |
| Mantle of Lingering Curses | Warlock | Rare / Shoulders (Cloth) | +5 Intellect, +3 Spirit | Corruption +2 mp |
| Robe of the Hollow Star | Warlock | Epic / Chest (Cloth) | +8 Intellect, +8 Stamina | Umbral Bolt +1 átütés |
| Bracers of the Siphoning Thread | Warlock | Rare / Wrist (Cloth) | +3 Intellect, +3 Crit | Vital Siphon gyógyítás +20% |
| Leggings of Dread Steps | Warlock | Rare / Legs (Cloth) | +6 Intellect, +5 Stamina | Fear +1 m sugár |
| Slippers of the Seeded Path | Warlock | Rare / Feet (Cloth) | +5 Intellect, +3 Haste | Blight Seed +1 ugrás |

**Az „Equip:” sor kiszürkülése.** Ha a hős még nem tanulta meg a képességet, az item Equip sora
szürkén, „(needs <képesség>)” jelzéssel látszik a tooltipben (mint az Artifact-tulajdonságoknál); az
item attól még felvehető, a módosítás akkor lép életbe, amikor a hős megtanulja a képességet.

**Forrás és súly.** A trinketek és a névvel ellátott itemek mind az öt forrásból (shop, loot, elite,
goblin, boss) az 1. hullámtól jönnek; a Legendaryk a loot-forrásokból (loot, elite, goblin, boss) a
10. hullámtól. A kaszt-specifikus itemek a saját kasztjuk dobásában ×3 súlyt kapnak, mint a
meglévők.

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
  | Artifact | +25, és felvétel után minden hullám végén +3 (lásd 5.5) |

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

**Rangok:** minden enchantnak I–V. rangja van. Az **induló rang** az item hullámszintje
szerint I–III. (I: 1–8., II: 9–16., III: 17. hullámtól; a lootolt itemeké eggyel magasabb, de
legfeljebb III.; ez a kézzel tervezett itemekre is igaz), a IV. és az V. rangot csak az
**Empower** adja (lásd lent). A rang növeli az értékét vagy a proc sebzését: I ×1, II ×1,5,
III ×2, IV ×2,5, V ×3 (az egész értékű statok, pl. „+1 Pierce”, lefelé kerekítve).

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
| Warfever | Chance on hit | 6 mp-ig +20% Haste | 1 PPM |
| Crusading | Chance on hit | 10 mp-ig +5 fő stat és 2 HP gyógyítás | 1 PPM |
| Thundering | Chance on hit | Kis AoE lökéshullám, 1 mp kábítás | 2 PPM, 5 mp ICD |
| Hallowed | Chance on hit | Holy villanás: sebez, és a legsérültebb társat gyógyítja (co-op) | 2 PPM |
| Duskflame | Chance on hit | Árnylövedék, ami ölésnél DoT-ot terjeszt | 3 PPM |
| Soulreaping | On kill | 10% eséllyel +1 kaszt-erőforrás | 10% |
| Detonating | On kill | 8% eséllyel a hulla felrobban (AoE) | 8% |
| Greedy | On kill | 5% eséllyel +1 gold | 5% |
| Frozen Ward | When struck | 10% eséllyel Rime Burst körülötted | 10%, 8 mp ICD |
| Reprisal | When struck | 6 Holy sebzés a támadónak | 100%, 0,5 mp ICD |

A rang szorzója a gold-procnál (Greedy) a gold tört részét átviszi a következő procra, így a
II. rang procjonként átlagban 1,5 goldot ad.

**M6b – 50 enchant (kész):** a készlet 26 új enchanttal bővült (összesen 50: 16 Equip, 18
Chance on hit, 8 On kill, 8 When struck), saját nevekkel, a meglévő proc- és bónusz-szókincsen
belül (új trigger-fajta nem kellett). A rangok (I–V: ×1 … ×3), a PPM-szabályok és az Enchanter
(lent) változatlanok. A fix számú értékek (sugár, időtartam, célpontszám) **nem skálázódnak** a
ranggal; a gyógyítás / pajzs a **Max HP százaléka** (a rang a százalékot szorozza), így a teljes
futamon át értelmes. Az új nevek nem utalhatnak Blizzard-márkákra (14. fejezet).

| Előtag | Típus | Slotok | Min. ritkaság | Hatás (I. rang) | Esély / PPM |
|---|---|---|---|---|---|
| Scorching | Equip | Head, Neck, Shoulders, Chest, Hands, Ring, Trinket, Weapon | Uncommon | +10% Fire Damage | - |
| Glacial | Equip | Head, Neck, Shoulders, Chest, Hands, Ring, Trinket, Weapon | Uncommon | +10% Frost Damage | - |
| Sweeping | Equip | Head, Shoulders, Chest, Waist, Ring, Trinket | Uncommon | +8% Area Size | - |
| Quickened | Equip | Head, Neck, Wrist, Waist, Feet, Ring, Trinket | Uncommon | +5% Cooldown Reduction | - |
| Gilded | Equip | Neck, Wrist, Waist, Feet, Ring, Trinket | Uncommon | +10% Gold Find | - |
| Spiked | Equip | Shoulders, Chest, Wrist, Waist, Legs, Feet | Uncommon | +3 Thorns (a közelharci támadó 3 sebzést kap vissza) | - |
| Riposting | Equip | Wrist, Hands, Waist, Ring, Trinket, Weapon | Uncommon | +4% Parry | - |
| Studious | Equip | Head, Neck, Wrist, Ring, Trinket | Uncommon | +10% XP Gain | - |
| Rupturing | Chance on hit | Weapon, Ring, Trinket | Rare | A célpont szétreped: 12 Arcane sebzés neki és a 2 m-en belüli ellenségeknek | 2,5 PPM, 2 mp ICD |
| Warding | Chance on hit | Weapon, Ring, Trinket | Rare | Védőburok: a Max HP 4%-át nyeli el 5 mp-ig | 2 PPM, 6 mp ICD |
| Soothing | Chance on hit | Weapon, Ring, Trinket | Rare | A legsérültebb társat gyógyítja (a Max HP-jának 3%-a); egyedül magadat | 3 PPM, 3 mp ICD |
| Concussive | Chance on hit | Weapon, Ring, Trinket | Rare | 1 mp kábítás a célponton | 2 PPM, 5 mp ICD |
| Rimebound | Chance on hit | Weapon, Ring, Trinket | Rare | Fagyrobbanás a célpont körül: 8 Frost sebzés, 40% lassítás 2 mp-ig, 2,5 m | 2,5 PPM, 3 mp ICD |
| Smoldering | Chance on hit | Weapon, Ring, Trinket | Rare | Felgyújtja a célpontot: 14 Fire sebzés 4 mp alatt, 2× halmozódik | 4 PPM, 0,5 mp ICD |
| Frenzied | Chance on hit | Weapon, Ring, Trinket | Rare | +12% Damage 6 mp-ig | 1 PPM, 8 mp ICD |
| Feasting | On kill | bármelyik slot | Rare | A Max HP 3%-ának visszaállítása | 10%, 1 mp ICD |
| Rousing | On kill | bármelyik slot | Rare | +12% Haste 4 mp-ig | 8%, 3 mp ICD |
| Arcing | On kill | bármelyik slot | Rare | A hullától villám ugrik 3 ellenség között, 12 Nature sebzés egyenként | 8%, 1 mp ICD |
| Gravewarded | On kill | bármelyik slot | Rare | Védőburok: a Max HP 5%-át nyeli el 5 mp-ig | 8%, 4 mp ICD |
| Wailing | On kill | bármelyik slot | Rare | A hulla sikolt: 10 Shadow sebzés a 3 m-en belüliekre és 1 mp kábítás | 6%, 3 mp ICD |
| Barbed | When struck | Head, Shoulders, Chest, Weapon | Rare | A támadó 5 Nature sebzést kap, és még 8-at 3 mp alatt (tövisek) | 40%, 1,5 mp ICD |
| Rallying | When struck | Head, Shoulders, Chest, Weapon | Rare | A Max HP 4%-ának visszaállítása | 12%, 6 mp ICD |
| Fortifying | When struck | Head, Shoulders, Chest, Weapon | Rare | +4 Armor 5 mp-ig | 15%, 8 mp ICD |
| Bulwarking | When struck | Head, Shoulders, Chest, Weapon | Rare | Védőburok: a Max HP 6%-át nyeli el 4 mp-ig | 10%, 8 mp ICD |
| Emberhide | When struck | Head, Shoulders, Chest, Weapon | Rare | Lángcsóva körülötted: 8 Fire sebzés a 2,5 m-en belüli ellenségeknek | 10%, 5 mp ICD |
| Clinging | When struck | Head, Shoulders, Chest, Weapon | Rare | A támadó 40%-os lassítást kap 3 mp-re | 20%, 4 mp ICD |

- A *Chance on hit* enchantok a fegyver / gyűrű / trinket slotokra, a *When struck* enchantok a
  Head / Shoulders / Chest / Shield slotokra kerülhetnek (a fenti slot-táblázat szerint), az *On
  kill* enchantok bármelyikre; az Uncommon itemek csak Equip enchantot kaphatnak. Az Equip és az
  On kill enchantok a legtöbb slotra illenek, ezért a generált itemeken ők vannak többségben.
- A *Scorching* (+Fire) és a *Glacial* (+Frost) iskola-enchant minden kasztnál sorsolódik, a
  Warrior / Rogue / Paladin számára holt stat; ez a végső balansz kérdése (9. fejezet).
- Egy unique vagy enchant a lebegő szövegét (alapból az item neve / az enchant előtagja) a
  paramétereiben egy `"label"` kulccsal felülírhatja, az üres `""` = nincs szöveg. Az M6b-ben egyetlen
  item használja: a Notched Tally Stick (minden ölésnél halmozódik, ezért néma).
- Az **Enchanter** a 26 új enchantot is sorsolja (a Reroll és az Imbue készlete az összes enchant,
  amit a slot és a ritkaság enged); az Artifactot továbbra sem módosítja.

**Enchanting – Glimmer Dust és az Enchanter (M6a):**

Az **Glimmer Dust** a csapat **második közös pénzneme**: a gold mellett a kassza-táblán látszik
(10. fejezet), és bárki költheti.

- **Honnan jön a Dust:**
  - **Disenchant:** a Character fül item-menüjében (a Sell mellett) a **backpackben** lévő item
    Dustra bontható. Felszerelt itemet előbb le kell venni (Unequip). A hős utolsó fegyverét
    ugyanúgy nem lehet Disenchantolni, mint eladni („Last weapon”, „You need a weapon”). Az
    **Artifactnál** a menüpont nincs is ott.
  - **Automatikus Disenchant:** ha egy loot-dobás itemére **mindenki Passt** nyom, az item
    magától Dust lesz (10.1) – az Artifact kivételével.
  - Az eladás továbbra is csak gold (a vételár 35%-a), abból nem lesz Dust.

  | Ritkaság | Dust |
  |---|---|
  | Common | 1 |
  | Uncommon | 2 |
  | Rare | 4 |
  | Epic | 8 |
  | Legendary | 16 |

- **Az Enchanter fül** (a 4. személyes fül; a címkéje a csapat Dustját mutatja: „Enchanter
  (12)”, a szám előtt a Dust rajzolt csillag-ikonjával): kiválasztod az itemet (előbb a
  felszereltek, utána a backpack), majd egy műveletet:
  - **Reroll:** az item egy enchantját újrasorsolja – új véletlen enchant, ami a slotra illik
    (a generátor szabályai: slot, fajta, minimális ritkaság, lövedékes fegyver), **ugyanazon a
    rangon** (a IV. és az V. is marad). A sorsolás **súlyozott, mint a generátornál**: az
    Attack Power / Spell Power enchant a hős kasztjához igazodik (a Mage inkább Spell Powert
    kap). **Nem lehet olyan, amilyen az itemen már van** – a lecserélt enchant sem –, tehát a
    Reroll mindig változtat.
  - **Empower:** egy enchant rangját +1-gyel emeli, **V. rangig**. A IV. és az V. rangot csak
    ez adja.
  - **Imbue:** az Uncommon vagy magasabb ritkaságú item, amelyen kevesebb enchant van, mint
    amennyit a ritkasága megenged, kap egy új enchantot az item **induló rangján** (I–III, az
    item hullámszintje és a „Looted” jelző szerint, mint a generáltaknál). Hány enchant fér
    az itemre: **Common 0, Uncommon 1, Rare 1, Epic 2, Legendary 2** (Artifact 0). Common
    itemre Imbue nincs („Common items hold no enchants”).
  - Az **Artifact nem módosítható** (Reroll / Empower / Imbue elutasítva; a két fix enchantja
    marad): az Enchanter fülön halványan szerepel, enchant-sorok nélkül, „Artifacts cannot be
    changed” felirattal.
- **Ár** (mindhárom művelet goldot **és** Dustot kér):
  - **gold** = az item bolti árának **25%-a** az **aktuális hullámon** (nem az item
    hullámán) × 2^használat, kerekítve, legalább 1,
  - **Dust** = a ritkaság Dust-értéke × 2^használat.
  - A használatok száma **itemenként** számít, és a Reroll, az Empower és az Imbue is egy
    használat (az elutasított művelet nem számít): ugyanazon az itemen minden újabb művelet
    kétszer annyiba kerül, mint az előző. Így ez a fő, felső korlát nélküli sink (16.1).
  - Példa: egy Epic item a 15. hullámon (bolti ár kb. 191 gold): az 1. művelet kb. 48 gold és
    8 Dust, a 2. kb. 96 gold és 16 Dust, a 3. kb. 191 gold és 32 Dust.
  - A művelet mindkét pénztárcát ellenőrzi, mielőtt bármelyikből levonna; a gold-ár a költésnaplóban
    a Dust-költséggel együtt jelenik meg („Empower Blazing (8 Dust)”).
- **Nyomva tartás:** a szabály (10. fejezet) a **gold-részre** vonatkozik, a Dust külön
  készletből megy. Ha a gold-ár a kassza több mint 50%-a, az A (Empower / Imbue) vagy az X
  (Reroll) gombot 1 mp-ig nyomva kell tartani. Elengedés, mozgás vagy B megszakítja; ha közben
  a kassza vagy a Dust úgy változik, hogy a művelet már nem fizethető, a nyomva tartás magától
  elmarad.
- **Botok:** a 12. hullám utáni piactól a legjobb **támadó fegyverükre** költenek az
  Enchanteren, a vásárlási kör **előtt**.
  - **Keret:** a Trainer tartaléka fölötti gold **30%-a**, a botok között egyenlően elosztva
    (amit egy bot nem tud elkölteni, az a következő botnál marad; az utolsó bot a megmaradt
    egészet kapja), legfeljebb 2 művelet / bot / kör. A maradék gold az offereknek, a
    Trainernek és a rerollnak jut (a bot-piac sorrendje: 16.1).
  - **Sorrend:** **Reroll** egy olyan enchantra, amit a kasztja nem tud használni (Attack Power
    egy varázsló kasztnál és fordítva) → **Imbue**, ha van szabad hely → **Empower** a
    legalacsonyabb rangú enchantra.
  - **Artifact-fegyver:** az Artifact nem enchantolható, ezért az Artifactot viselő bot a
    legjobb viselt, nem-Artifact **Epic+ páncél- / ékszerdarabját vagy nem támadó off-handjét**
    enchantolja (magasabb ritkaság, aztán Item Level, aztán az alacsonyabb slot) – azt is csak,
    ha van még mit tenni rajta. A Fangs of the Shadow párosa két Artifactnak számít, így a
    Rogue bot is a páncéljára vált. A normál fegyverrel rendelkező bot a fegyverét választja.
  - **Dust-szerzés:** mivel a botok sosem Passolnak (a loot-dobáson Need / Greed), a Dustot úgy
    szerzik, hogy a **felesleges backpack-itemeket** (amik nekik nem fejlesztések; a legkisebb
    Dustú előbb) Disenchantolják, de csak annyit, amennyi a következő művelethez kell.

### 5.8 Tartalomcél – „sok item”

Az **M6b** adta a teljes item-tartalmat, két kivétellel, amelyek az **M8-ra tolódtak**: a
Crossbow, a Polearm és a Fist Weapon, valamint a kaszt-független tier setek.

| Kategória | Állapot (M6a) | Állapot (**M6b, kész**) | M8 után |
|---|---|---|---|
| Fegyver-alaptípus | 10 | **13** (+ Two-Hand Sword, Two-Hand Mace, Orb) | 16 (+ Crossbow, Polearm, Fist Weapon) |
| Páncél-alaptípus (slot × páncéltípus × anyagfokozat) | 32 (csak az I. fokozat) | **96** (3 fokozat × 32) | 96 |
| Ékszer-alaptípus (Neck, Ring) | 8 (4 + 4) | **20** (10 Neck, 10 Ring) | 20 |
| Stat-utótag („of the Bear” …) | 18 | **25** | 25 |
| Enchantment | 24 | **50** (16 Equip, 18 Chance on hit, 8 On kill, 8 When struck) | 50 |
| Kézzel tervezett, névvel ellátott Rare/Epic itemek | 10 | **40** | 40 |
| Kaszt-specifikus itemek | 10 (kasztonként 2) | **40** (kasztonként 8) | 60+ (kasztonként 8+, az új kasztokkal) |
| Trinket | 10 | **30** | 30 |
| Legendary | 8 | **25** (mind a 12 slottípushoz van) | 25 |
| Forge Legendary hatás (fegyvertípusonként egy, 4.1) | 10 | **13** (Thistlebrand, Boulderbloom, Tearglass) | 16 |
| Tier set | 5 (kasztonként 1) | 5 (kasztonként 1; változatlan) | kasztonként 1 + 5 kaszt-független |
| Kézzel tervezett összesen (`Db.uniques`) | 63 | **160** (63 + 20 trinket + 17 Legendary + 30 névvel ellátott + 30 kaszt-specifikus; ebből 25 tier-set darab) | – |
| Artifact | 5 | 5 (változatlan) | kasztonként 1 (+ Hunter, Shaman) |
| Epic fegyver +10% támadási sebesség (4.1) | – | kész | – |
| Alaptípus-fokozat (`min_wave`) és a 70% / 30% fokozat-választás (5.4) | – | kész | – |

**Az M6b tartalom-csomagjai (megvalósítva)**

- **Fegyverek:** három új fegyvertípus – **Two-Hand Sword** (Warrior, Paladin), **Two-Hand
  Mace** (Paladin, Warrior) és **Orb** (Off Hand a Mage-nek és a Warlocknak: varázserő-jellegű
  statok, nincs automatikus támadás) –, mindegyikhez saját Forge Legendary hatás
  (fegyvertípusonként egy) és procedurális megjelenés (4. fejezet). A Crossbow, a Polearm és a
  Fist Weapon az M8-cal jön. Az **Epic** fegyverek **+10% támadási sebességet** kapnak (4.1).
- **Páncél:** a két újabb anyag-fokozat minden slotra és páncéltípusra: a II. a 9., a III. a 17.
  hullámtól (az alaptípus `min_wave` adata); a generátor az elérhető legmagasabb fokozatot
  70%-ban, egy alacsonyabbat 30%-ban választja (5.4). Az eredmény **96** alaptípus; a fokozat csak
  a nevet és a kinézetet adja, a statokat nem.
- **Ékszer és utótag:** 20 ékszer-alaptípus (10 Neck, 10 Ring) és 25 stat-utótag.
- **Enchantok:** 50 (+26), saját nevekkel, a meglévő proc- és bónusz-szókincsen belül; új
  trigger-fajta csak akkor, ha elkerülhetetlen (5.7).
- **Kézzel tervezett itemek:**
  - névvel ellátott Rare / Epic: 40 (+30);
  - kaszt-specifikus: kasztonként 8 = 40 (+30), „*Equip:*” sorral módosítják a kaszt
    képességeit (5.5);
  - trinket: 30 (+20);
  - Legendary: 25 (+17), kézzel tervezett procokkal.
- **Kaszt-független tier setek:** az **M8-ra tolódtak**, mert a set-rendszer módosítását
  igénylik (5.5); az M6b-ben a setek kasztonként egy-egy maradnak.
- **Nevek:** az új itemek és enchantok nevei nem Blizzard-nevek; mindet ellenőrizzük a 14.
  fejezet listája szerint, és minden megjelenített név egyedi (a teszt őrzi).
- **Hol jelennek meg az új itemek:** a generált tartalom (fokozatos alaptípusok, ékszerek, utótagok,
  enchantok, fegyverek) a boltban, lootban, a Black Marketben, a Shrine of Fortune és a
  dungeon-jutalom Epic itemein is feltűnik; a kézzel tervezett Epic itemek a Black Market kivételével
  mindegyiken (16.1). Az Artifactok változatlanok, sosem sorsolódnak ki.
- A csomagok számai kiinduló értékek: az M6b nem hangol, a végleges balansz a legvégén
  készül (9. fejezet).

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
    kivétel: Summon Cinder Brute (1 Pact Shard).
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
| Warrior | Ground Slam | Auto | Körkörös csapás, 2 mp lassítás |
| Warrior | Soaring Slam | Active | Ugrás a célpontra, AoE becsapódás |
| Warrior | Execute | Active | Hatalmas csapás; 20% HP alatti ellenséget azonnal megöl (bossra: dupla sebzés) |
| Warrior | Battle Roar | Auto | 6 mp-re +10% sebzés neked és a közeli társaknak |
| Warrior | Stalwart Guard | Active | 4 mp-ig −50% elszenvedett sebzés |
| Warrior | Steel Cyclone | Auto | 3 mp-es forgás, közben nem lehet lassítani |
| Mage | Fireball | Auto | Tűzgolyó a legközelebbi ellenségre, égést okoz |
| Mage | Rime Burst | Auto | Ha ellenség ér hozzád: fagyasztás a környezetben |
| Mage | Arcane Darts | Auto | 5 kis lövedék véletlen célpontokra |
| Mage | Frozen Layer | Auto | Elnyelő pajzs, amíg el nem fogy |
| Mage | Magma Bolt | Active | 1 mp felkészülés, óriási tűzgolyó |
| Mage | Meteor | Active | Meteor a legsűrűbb csoportra, égő földet hagy |
| Paladin | Smiting Hammer | Auto | Kalapácsdobás, 1,5 mp kábítás |
| Paladin | Ricochet Shield | Auto | Pattogó pajzs, 3 célpont |
| Paladin | Radiant Whirl | Auto | Körkörös szent csapás, a közeli társakat gyógyítja |
| Paladin | Boon of Crowns | Auto | Minden társ +5% minden statot kap 10 mp-re |
| Paladin | Gilded Halo | Active | 3 mp sebezhetetlenség |
| Paladin | Mending Touch | Active | Teljesen gyógyítja a legkevesebb HP-jú társat (hosszú CD); elesett társat nem éleszt fel (azonnal csak a Call of Valor éleszt) |
| Rogue | Throwing Stars | Auto | 3 shuriken legyezőben |
| Rogue | Cleaving Blades | Auto | 5 mp-ig a találatok egy második célpontot is érnek |
| Rogue | Poison Bomb | Auto | Méregfelhő a földön |
| Rogue | Narrow Escape | Auto (passzív) | Halálos találat helyett 1 HP, 60 mp-enként |
| Rogue | Duskstep | Active | Teleport a célpont mögé, a következő találat krit |
| Rogue | Cutthroat Rush | Active | 2 mp-ig ugrálás az ellenségek között |
| Warlock | Corruption | Auto | DoT, ami az ellenség halálakor átterjed |
| Warlock | Umbral Bolt | Auto | Erős árnylövedék |
| Warlock | Blight Seed | Auto | Mag egy ellenségbe; a halálakor AoE robbanás |
| Warlock | Summon Gloomguard | Auto (pet) | Második pet, magára vonja az ellenségeket |
| Warlock | Fear | Active | Az ellenségek 2 mp-ig menekülnek a közeledből |
| Warlock | Summon Cinder Brute | Active | 8 mp-re démon idézése (hosszú CD, 1 Pact Shard) |
| Általános | Bandage | Active | 3 mp alatt 30% HP gyógyítás |
| Általános | Sprint | Active | 3 mp-ig +50% Speed |
| Általános | Engineer's Bomb | Auto | Robbanó bomba dobása |
| Általános | Crowd Stomp | Auto | Kis AoE kábítás |
| Általános | Phantom Wolf | Auto (pet) | Szellemfarkas társ |
| Általános | Savage Haste | Active | 6 mp-ig +20% Haste |

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

- **A 10. szinttől minden szintlépés +1 talentpontot ad**, a kártyaválasztás mellé
  (`team level − 9`).
- **Minden hős a teljes pontszámot kapja** – a pontok hősönként járnak, nem közösek.
- A pontok **a hullámok között**, a bolti fázisban, a **Talents** fülön költhetők el. Nem
  kötelező azonnal elkölteni. A hullám közben szerzett pont a következő boltnál költhető.
- A szintlépési kártyáknak nincs közük a talentpontokhoz.
- A 10. szint előtt a fül csak ennyit mutat: „Talent points from level 10 (level 7)”.
- **Várható pontszám egy menet alatt:** kb. 15–20 (a menet végére a 25.–30. szint körül).
- **XP-skálázás co-opban:** az XP-igény a játékosszámmal nő (`× (1 + 0,6 × (játékosok − 1))`),
  hogy a szintlépés üteme 1–4 játékossal hasonló legyen.

### 7.2 A fák felépítése

Minden kasztnak **3 fája** van (a WoW-os specializációk szerint):

| Kaszt | Fa 1 | Fa 2 | Fa 3 |
|---|---|---|---|
| Warrior | Warblade | Berserker | Ironwall |
| Mage | Starlore | Pyrelore | Rimelore |
| Paladin | Radiance | Vigil | Verdict |
| Rogue | Toxins | Bladework | Gloaming |
| Warlock | Hexcraft | Pactcraft | Cinderfall |
| Hunter (M8) | Beast Mastery | Marksmanship | Survival |
| Shaman (M8) | Elemental | Enhancement | Restoration |

Egy fa **5 szintből (tier)** áll:

| Tier | Feltétel (pont a fa alacsonyabb tierjeiben) | Tartalom |
|---|---|---|
| 1 | 0 | 2 talent, egyenként max 3 pont |
| 2 | 3 | 2 talent, egyenként max 3 pont |
| 3 | 6 | 1 talent (max 2 pont) + 1 **képesség-módosító** (1 pont) |
| 4 | 9 | 2 talent, egyenként max 3 pont |
| 5 | 12 | **Capstone** (1 pont) – nagy, buildet meghatározó hatás |

- A tier feltétele a **fa alacsonyabb tierjeibe** tett pontok száma (WoW-szabály). Ezért a
  capstone már **13 ponttal** elérhető: 12 pont az 1–4. tierben, és a 13. maga a capstone.
- Egy fa teljes kitöltése **22 pont**, tehát egy menetben **egy fát lehet majdnem
  végigvinni**, vagy két fa között el lehet osztani a pontokat (hibrid build), ahogy a
  klasszikus WoW-ban. Két capstone-hoz 26 pont kellene, ez egy menetben nem jön össze.
- **Előfeltétel** (nyíl a fában): ugyanannak a fának egy alacsonyabb tierbeli talentje, amit
  **maxra** kell vinni. Fánként 1–2 nyíl van.
- **Képesség-módosító:** egyetlen abilityt változtat meg.
  - A legtöbb a kaszt mindig meglévő (Core) abilityjére hat.
  - Ha a módosított ability még nincs megtanulva, a pont akkor is elkölthető, és a
    megtanuláskor hat. A tooltip kiírja: „You haven't learned X”.
- Egyik fa sem épül egyetlen tanult (véletlenszerűen kapott) abilityre: minden fa a kaszt Core
  abilityjeivel, erőforrásával, Masteryjével és fegyvereivel is működik.
- A talentek **azonnal** hatnak, már a boltban: a Character fül, a Trainer és a tooltipek az
  új számokat mutatják.
- A talent- és set-sebzésbónuszok összeadódnak, utána szorzódnak a Masteryvel és az ideiglenes
  buffokkal.

### 7.3 Visszavétel, reset és botok

- **Visszavétel (X):** az utolsó hullám kezdete óta elköltött pontok egyenként visszavehetők –
  a fül bezárása és újranyitása után is, a teljes hullámközi szünetben. A hullám indulásakor a
  pontok véglegesek.
  - Nem vehető vissza a pont, ha egy előfeltétel függ tőle: „X depends on it”.
  - Akkor sem, ha egy magasabb tier pontjai a feltétel alá esnének: „X needs those points”.
- **Reset Talents** (a fül alján, árral: „Reset Talents – 40 g”): minden pont visszajár, a
  függőben lévők is.
  - **Ár:** hősönként számolva az első reset 20 gold, utána minden reset az előző ár duplája
    (20, 40, 80 …; a WoW-os respec-díj mintájára). Az ár nem csökken vissza.
  - A közös kasszából fizetünk, és a kassza melletti költésnaplóban is látszik (10. fejezet).
  - **Megerősítés:** az A egy figyelmeztetést nyit („Press A again to reset (40 g)”), és 2 mp-en
    belül újra meg kell nyomni.
  - Ha az ár a kassza több mint 50%-a, az A-t 1 mp-ig nyomva kell tartani (mint a boltban és a
    Trainernél).
- **Kezelés:**
  - **A** = pont elköltése, **X** = visszavétel, **Y** = a következő rang előnézete,
    **LT / RT** = fülváltás.
  - A **B** csak a nyitott megerősítést / nyomva tartást szakítja meg, így a B továbbra is
    visszavonja a ready-t.
  - A fül címkéje mutatja a szabad pontokat: „Talents (2)”.
- **Botok:** a hős slot-sorszáma választ fát (1. játékos az 1. fa, 2. a 2. … 4. megint az 1.).
  - Sorrend: a capstone, ha felvehető; különben a módosító; különben az első felvehető talent
    tier és oszlop szerint.
  - Elhalasztják, ami náluk nem hatna, és csak akkor veszik fel, ha már semmi más nem
    vehető: a talentet, amelynek minden hatásához más fegyver kellene (pl. pajzs), és a
    módosítót, amelynek az abilityjét nem tanulták meg.
  - A fa betelte után a következő fába költenek; soha nem resetelnek, és véletlen nélkül
    döntenek.

### 7.4 A talentfák (5 kaszt × 3 fa)

**Jelölések:**
- A számok **pontonként** értendők (3 pont = háromszoros hatás); a módosító és a capstone
  1 pontos, ezek a végleges számok.
- *Dőlt* név = képesség-módosító; **félkövér** = capstone; „előfeltétel: X 3/3” = nyíl a fában.
- Egy tieren belül az első sor a bal, a második a jobb oszlop.
- A talentnevek angolok (a UI-ban is), a klasszikus WoW talentneveket az M7a IP-tisztításban saját nevekre cseréltük; Blizzard-márka
  nincs köztük.

#### Warrior – Warblade fa

Kétkezes csapások, vérző sebek és kivégzések. A Ruinous Strike minden 5. támadást
megerősít, és a Vampiric elitek gyógyulását is letöri.

| Tier | Talent | Pont | Hatás / pont |
|---|---|---|---|
| 1 | Deflection | 3 | +2% Dodge |
| 1 | Rage Reserve | 3 | +5 Rage minden hullám elején és +3% Rage-termelés |
| 2 | Improved Charge | 3 | A Charge kábítása +0,3 mp, a cooldownja −0,5 mp |
| 2 | Gashing Blows | 3 | A kritikus fegyvertalálat 3 mp-es vérzést okoz (a találat sebzésének 10%-a) |
| 3 | Two-Hander Prowess | 2 | +5% sebzés kétkezes fegyverrel |
| 3 | *Sweeping Blows* (módosító – Whirlwind) | 1 | A Whirlwind után 5 mp-ig a fegyvertámadások 25% eséllyel azonnal még egyszer lecsapnak |
| 4 | Impale (előfeltétel: Gashing Blows 3/3) | 3 | +10% kritikus sebzés |
| 4 | Culling Instinct | 3 | Fegyvertalálatkor 3% esély, hogy az Execute cooldownja azonnal lejár |
| 5 | **Ruinous Strike** (capstone) | 1 | Minden 5. fegyvertámadás egy extra, 150%-os fegyversebzésű csapást is mér, és 8 mp-re Ruinous Wound-ot hagy: a célpont 50%-kal kevesebbet gyógyul, és 10%-kal több sebzést kap tőled (az Execute-ot is beleértve) |

#### Warrior – Berserker fa

Két fegyver, kritikus találatok, Rage és öldöklés: a kritek Rage-et adnak, a Rage
Whirlwindet, az ölések Carnage-et. A kevés HP keményebb ütést jelent (Cornered Fury).

| Tier | Talent | Pont | Hatás / pont |
|---|---|---|---|
| 1 | Cruelty | 3 | +2% Crit |
| 1 | Furious Spark | 3 | A kritikus fegyvertalálat +3 Rage-et termel |
| 2 | Improved Whirlwind | 3 | A Whirlwind költsége −2 Rage, az ereje +5% |
| 2 | Savoured Kills | 3 | Öléskor a Max HP 1%-át visszagyógyítod (legfeljebb 1,5 mp-enként egyszer) |
| 3 | Twin-Blade Prowess | 2 | +5% sebzés két fegyverrel (Dual Wield) |
| 3 | *Reaping Spin* (módosító – Whirlwind) | 1 | A Whirlwind minden eltalált ellenségért 3 Rage-et visszaad (pörgésenként legfeljebb 12-t, és legfeljebb annyit, amennyibe a pörgés került): nagy csapatban szinte ingyen pörögsz |
| 4 | Rising Tempo (előfeltétel: Cruelty 3/3) | 3 | Kritikus találat után 3 mp-ig +6% Haste |
| 4 | Desperate Might | 3 | +4 Mastery (Cornered Fury: minél kevesebb a HP-d, annál nagyobb a sebzésed) |
| 5 | **Carnage** (capstone) | 1 | Ölésenként +2% sebzés 5 mp-ig (legfeljebb 10 halmozás = +20%, minden ölés frissíti); a 8 m-en belüli társak a bónusz felét kapják |

#### Warrior – Ironwall fa

Pajzs, páncél és taunt: a fal, ami mögött a társak állnak. A pajzsos talenteknek van
pajzs nélküli szomszédja, így karddal vagy kétkezessel is elérhető a capstone.

| Tier | Talent | Pont | Hatás / pont |
|---|---|---|---|
| 1 | Toughness | 3 | +2 Armor |
| 1 | Shield Prowess | 3 | Pajzzsal: +3% Block esély és +10% Block Value |
| 2 | Payback | 3 | +2% Parry; blokk vagy kitérés (Dodge) után 15% esély azonnali visszavágásra a fegyvereddel |
| 2 | Defiance | 3 | Elszenvedett találatonként +2 Rage, és harcon kívül a Rage 1-gyel lassabban fogy másodpercenként |
| 3 | Vitality | 2 | +4 Stamina és +1 Strength |
| 3 | *Challenging Charge* (módosító – Charge) | 1 | A Charge által elkábított ellenségek a kábítás után még 4 mp-ig rád fókuszálnak (taunt); ellenségenként a Max HP 3%-ának megfelelő elnyelő pajzsot kapsz 5 mp-re (legfeljebb 15%) |
| 4 | Shieldcraft (előfeltétel: Shield Prowess 3/3) | 3 | Pajzzsal −4% elszenvedett sebzés |
| 4 | Whirl and Slam | 3 | A Whirlwind és a Ground Slam ereje +5%; a Whirlwind 1,5 mp-re 10%-kal lassítja az eltalált ellenségeket |
| 5 | **Unbreakable** (capstone; korábban Last Stand) | 1 | Hullámonként 1×: a halálos találat helyett talpon maradsz – 10 mp-re +30% Max HP (ennyit azonnal gyógyulsz is) és 1 mp sebezhetetlenség; a 8 m-en belüli társak ugyanígy +15% Max HP-t kapnak |

#### Mage – Starlore fa

A wand Arcane lövedékei, a Blink, a Haste / cooldownok és a mély Mana-készlet. A capstone a
nyers erő: minden sebzés +25%, cserébe drágább Hailstorm – amit a fa Mana-talentjei fizetnek
meg.

| Tier | Talent | Pont | Hatás / pont |
|---|---|---|---|
| 1 | Arcane Focus | 3 | +3% Arcane sebzés (a wand lövedékei, Arcane Darts, a Blink robbanásai) |
| 1 | Arcane Meditation | 3 | +10% Mana-regeneráció |
| 2 | Improved Blink | 3 | A Blink −5% CD, és 1 m-rel messzebre visz |
| 2 | Thrifty Casting (előfeltétel: Arcane Meditation 3/3) | 3 | 8% esély, hogy a Mana-varázslat (Hailstorm) nem kerül Manába |
| 3 | Arcane Mind | 2 | +3 Intellect (+6 max Mana) |
| 3 | *Phantom Double* (módosító – Blink) | 1 | A Blink 3 mp-re tükörképet hagy az indulási helyén: a 4 m-en belüli ellenségek őt üldözik, eltűnésekor Arcane robbanás (2,5 m); legfeljebb 6 mp-enként |
| 4 | Arcane Flows (előfeltétel: Improved Blink 3/3) | 3 | +4% Cooldown Reduction |
| 4 | Arcane Celerity | 3 | +4% Haste |
| 5 | **Overchannel** (capstone) | 1 | Minden sebzés +25%, de a Mana-költségek +30% |

#### Mage – Pyrelore fa

Kritikus találatok, Ignite és terjedő lángok; a Staff (Fire iskolájú fegyver) természetes
párja. A fa a kaszt Masteryjére (Ignite) épül, így tanult abilityk nélkül is működik.

| Tier | Talent | Pont | Hatás / pont |
|---|---|---|---|
| 1 | Fiery Precision | 3 | +2% Crit |
| 1 | Fire Power | 3 | +3% Fire sebzés (Ignite, égések, tűzvarázslatok, Staff) |
| 2 | Empowered Fire (előfeltétel: Fiery Precision 3/3) | 3 | +3 Mastery (erősebb Ignite) |
| 2 | Incineration | 3 | +5% DoT-sebzés (Ignite, égések) |
| 3 | Reckless Flame | 2 | +3% sebzés, de +2% elszenvedett sebzés |
| 3 | *Ticking Ember* (módosító – Fireball) | 1 | A Fireball égése élő bomba: ha lejár vagy a célpont meghal, felrobban – a Fireball sebzésének 40%-a 2,5 m-en belül |
| 4 | Burnout (előfeltétel: Empowered Fire 3/3) | 3 | +10% krit sebzés |
| 4 | Finishing Flame | 3 | +5% sebzés a 35% HP alatti ellenségekre |
| 5 | **Chain Ignition** (capstone) | 1 | Ha egy fegyvertámadás (első találata) kritikus, lángba borítja a környéket: a célpont és a 2,5 m-en belüli legközelebbi ellenségek (összesen legfeljebb 4) 3 mp alatt a krit sebzés 20%-át kapják égésként (ugyanazt az ellenséget legfeljebb 1 mp-enként) |

#### Mage – Rimelore fa

Hailstorm, fagyasztás, lassítás és jégpáncél. A fa a Hailstorm-ból (RT, mindig megvan) maga
állítja elő a fagyasztást, így a Frost Spike Rime Burst nélkül is működik; a társak
kábításait is kihasználja.

| Tier | Talent | Pont | Hatás / pont |
|---|---|---|---|
| 1 | Piercing Ice | 3 | +3% Frost sebzés |
| 1 | Rime Plating | 3 | +2 Armor, és a Frozen Layer +8%-kal többet nyel el |
| 2 | Improved Hailstorm | 3 | A Hailstorm sugara +3%, lassítása +10% |
| 2 | Numbing Cold | 3 | +3% sebzés a lassított ellenségekre |
| 3 | Boreal Winds | 2 | +2% Frost sebzés és −2% elszenvedett sebzés |
| 3 | *Glacial Finale* (módosító – Hailstorm) | 1 | Amikor a Hailstorm véget ér, a benne maradt ellenségek 1,5 mp-re megfagynak |
| 4 | Snap Freeze (előfeltétel: Improved Hailstorm 3/3) | 3 | A Hailstorm minden ütésénél 4% esély ellenségenként, hogy 1 mp-re megfagy |
| 4 | Frozen Marrow (előfeltétel: Numbing Cold 3/3) | 3 | +4% sebzés a fagyott és kábított ellenségekre |
| 5 | **Frost Spike** (capstone) | 1 | A fagyott ellenségeket minden találatod kritként éri: a fegyvertalálat garantált krit, a varázslatok, égések és petek (amik nem kritelhetnek) dupla sebzést okoznak (+ Critical Damage bónusz) |

#### Paladin – Radiance fa

A co-op gyógyító: több és nagyobb Call of Valor, akkor is jövő Resolve, ha nem ütsz,
szélesebb és védelmet adó aura, a sebesült társ lába elé hajított Sacred Circle. A támadás
gyenge, a hibrid Retributionnel ez javítható.

| Tier | Talent | Pont | Hatás / pont |
|---|---|---|---|
| 1 | Healing Light | 3 | A Paladin-képességeid gyógyítása +4% |
| 1 | Aura Reach | 3 | +1 Mastery, és az Aura of Fealty hatótávja +1 m |
| 2 | Boundless Valor | 3 | 8% esély, hogy a Call of Valor nem költ Resolve-t |
| 2 | Steadfast Prayer | 3 | 4 mp-enként 8% esély +1 Resolve-re (akkor is, ha nem ütsz) |
| 3 | Generous Valor | 2 | A Call of Valor gyógyítása +8%, és +1 sebesült társat gyógyít |
| 3 | *Gifted Circle* (módosító – Sacred Circle) | 1 | A Sacred Circle-t a 10 m-en belüli legsebesültebb (80% HP alatti) hős lába elé hajítod (ha nincs ilyen, a saját lábad elé), és a benne álló hősök 0,5 mp-enként a Max HP-juk 1%-át gyógyulják |
| 4 | Warding Presence (előfeltétel: Aura Reach 3/3) | 3 | Az Aura of Fealty-on belüli hősök (te is) −2% sebzést kapnak |
| 4 | Sunlit Might | 3 | +5% Holy sebzés |
| 5 | **Radiant Pulse** (capstone) | 1 | 4 mp-enként magától: ha 8 m-en belül van 90% HP alatti hős (te is), a legsebesültebbet gyógyítja (1 + a Max HP-ja 6%-a + 0,5 × Spell Power), különben a legközelebbi ellenségre 100%-os fegyversebzésű Holy csapást mér (+0,8 × Spell Power); a Haste és a Cooldown Reduction rövidíti |

#### Paladin – Vigil fa

A tank: blokk, páncél és Stamina, blokkolásból jövő Resolve, és a Sacred Circle mint
tauntoló föld, amiben állsz. A támadás abból jön, hogy eltalálnak (Swift Rebuke, Gleaming Shield).

| Tier | Talent | Pont | Hatás / pont |
|---|---|---|---|
| 1 | Redoubt | 3 | Pajzzsal: +3% Block esély és +10% Block Value |
| 1 | Stoicism | 3 | +2 Stamina és +1 Armor |
| 2 | Lasting Circle | 3 | A Sacred Circle +0,5 mp-ig tart |
| 2 | Shielded by Faith | 3 | Blokkoláskor 10% esély +1 Resolve-re (legfeljebb 2 mp-enként) |
| 3 | Dauntless Rally | 2 | Ha a HP-d 35% alá esik: a Max HP 8%-át visszagyógyulod, és 8 mp-re +4 Armort kapsz (legfeljebb 20 mp-enként) |
| 3 | *Provoking Light* (módosító – Sacred Circle) | 1 | A Sacred Circle-ben álló ellenségek rád fókuszálnak (taunt, tickenként 1 mp-re frissül), és amíg a saját Sacred Circle-ben állsz, −10% sebzést kapsz |
| 4 | Vigilant Shield (előfeltétel: Redoubt 3/3) | 3 | Pajzzsal −3% elszenvedett sebzés és +10% Block Value |
| 4 | Swift Rebuke | 3 | Ha eltalálnak, 5% esély egy azonnali extra fegyvertámadásra |
| 5 | **Gleaming Shield** (capstone) | 1 | Pajzzsal +20% Block; minden blokkolt találat a támadóra 60%-os fegyversebzésű Holy csapást mér (+0,5 × Spell Power), és a 8 m-en belüli legsebesültebb társadra a Max HP-ja 2%-ának megfelelő elnyelő pajzsot tesz 4 mp-re (legfeljebb 8%-ig halmozódik) |

A Block esélye legfeljebb 50%, és egy blokk legfeljebb a találat 85%-át nyeli el (Block
Value-tól függetlenül).

#### Paladin – Verdict fa

A csapásmérő: Strength és kritek, Resolve a kritekből, Holy tűz, gyakoribb Sacred Circle,
Resolve-befejező (Divine Verdict), a csapat sebzését emelő aura, és a Sunbrand
gyógyító szent csapásai. Teljesen ellensúlyozza a kaszt −10% sebzését.

| Tier | Talent | Pont | Hatás / pont |
|---|---|---|---|
| 1 | Divine Strength | 3 | +2 Strength |
| 1 | Conviction | 3 | +2% Crit |
| 2 | Rhythm of Battle | 3 | Kritikus fegyvertalálatkor 20% esély +1 Resolve-re (legfeljebb mp-enként egyszer) |
| 2 | Sacred Cadence | 3 | +4% Holy sebzés, és a Sacred Circle cooldownja −0,5 mp |
| 3 | Vengeance (előfeltétel: Conviction 3/3) | 2 | Kritikus találat után 8 mp-ig +1% sebzés, legfeljebb 2-szer halmozódik |
| 3 | *Divine Verdict* (módosító – Call of Valor) | 1 | Ha a hatótávon belül senki sincs 80% HP alatt és nincs felélesztendő társ, a Call of Valor gyógyítás helyett ítéletet mond: a 4 m-en belüli legközelebbi ellenségre (elitre / bossra elsőként) 300%-os fegyversebzésű Holy csapás (+1,5 × Spell Power) |
| 4 | Sanctified Fervor | 3 | Te és az Aura of Fealty-on belüli társak +2% sebzést kaptok |
| 4 | Branding Strikes | 3 | A kritikus fegyvertalálat sebzésének 10%-át 4 mp alatt Holy tűzként is elszenvedi a célpont |
| 5 | **Sunbrand** (capstone) | 1 | Fegyvertámadásonként 15% esély egy extra Holy csapásra: a találat sebzésének 70%-a a célpontra és legfeljebb 2 további, tőle 3 m-en belüli ellenségre; minden ilyen csapás a 8 m-en belüli legsebesültebb hőst (téged is) a Max HP-ja 2%-ával gyógyítja |

#### Rogue – Toxins fa

Mérgek, Combo Pointok és halálos Knife Bloom. A kritikus találat Combo Pointot és Deadly
Poisont ad, a Knife Bloom befejezőként elkölti őket (az Overdose a mérget is
„beváltja”); a capstone a hullám minden 3. legyezőjét garantált kritté teszi.

| Tier | Talent | Pont | Hatás / pont |
|---|---|---|---|
| 1 | Malice | 3 | +2% Crit |
| 1 | Improved Poisons | 3 | +3 Mastery (a Lethal Venom stackenként a krit sebzésének +3%-át okozza) |
| 2 | Fateful Cuts (előfeltétel: Malice 3/3) | 3 | A kritikus fegyvertalálat 15% eséllyel egy extra Combo Pointot ad |
| 2 | Finishing Flourish | 3 | A Knife Bloom Combo Pointonként +2% sebzést kap (az alap 20% mellé) |
| 3 | Lethality | 2 | +10% Critical Damage (tőrrel ×2,5 → ×2,6) |
| 3 | *Overdose* (módosító – Knife Bloom) | 1 | A Knife Bloom elfogyasztja az eltalált ellenségek Lethal Venom-ját: a hátralévő méregsebzés 150%-a azonnal, Nature sebzésként éri őket (ellenségenként dobásonként egyszer) |
| 4 | Toxic Harvest | 3 | Ha egy Lethal Venom-mal mérgezett ellenség meghal, +1 Energy-t kapsz |
| 4 | Venom Savant (előfeltétel: Improved Poisons 3/3) | 3 | A Lethal Venom +1 stackkel többször halmozható (5 → 8), és +4% Nature sebzés |
| 5 | **Steel Nerve** (capstone) | 1 | A hullámban minden 3. Knife Bloom dobás garantált krit +50% krit sebzéssel (tőrrel ×3,0); a tőrök 3 mp-re 30%-kal lelassítják az eltalált ellenségeket |

#### Rogue – Bladework fa

Két fegyver, Energy és közelharc a tömeg közepén: kitérés és visszavágás, gyorsabb és dupla
ütések. A Knife Bloom a többi penge cooldownját pörgeti, a capstone a tömegben felgyorsítja
az Energy-termelést, és a közeli társakat is gyorsítja.

| Tier | Talent | Pont | Hatás / pont |
|---|---|---|---|
| 1 | Quicksilver Reflexes | 3 | +2% Dodge |
| 1 | Battle Verve | 3 | +8% esély, hogy a fegyvertámadás 2 Energy-t adjon |
| 2 | Sly Counter (előfeltétel: Quicksilver Reflexes 3/3) | 3 | +1% Dodge; kitéréskor +25% esély azonnali visszavágásra a fegyvereddel |
| 2 | Aggression | 3 | +3% Physical sebzés |
| 3 | Ambidexterity | 2 | Két fegyverrel (Dual Wield) +5% Haste |
| 3 | *Hastening Blades* (módosító – Knife Bloom) | 1 | A Knife Bloom minden elköltött Combo Pointja 0,2 mp-cel csökkenti a többi Rogue-ability cooldownját (5 ponttal 1 mp: Melt Away, Cutthroat Rush, Cleaving Blades …) |
| 4 | Twin Strike | 3 | +4% Extra Attack (a fegyvertalálat azonnal még egyszer üt) |
| 4 | Blade Tactics | 3 | A Cleaving Blades és a Cutthroat Rush +6% erő és −6% cooldown |
| 5 | **Crowd Surge** (capstone) | 1 | Amíg legalább 3 ellenség van 5 m-en belül: +50% Energy-termelés, és a 8 m-en belüli társak +10% Haste-et kapnak |

#### Rogue – Gloaming fa

Melt Away, támadás az árnyékból és garantált kritek. A Melt Away Combo Pointot, Energy-t és
sebzést ad, a végén ingyen tőrlegyezőt dob; a capstone után 5 mp-ig minden fegyvertalálat
krit, és a közeli társak is kritesebbek.

| Tier | Talent | Pont | Hatás / pont |
|---|---|---|---|
| 1 | Forethought | 3 | A Melt Away +1 Combo Pointot és +1 garantált kritet ad |
| 1 | Veiling Dusk | 3 | +3% Avoidance |
| 2 | Veiled Aggression (előfeltétel: Forethought 3/3) | 3 | A Melt Away után 6 mp-ig +4% sebzés |
| 2 | Quiet Mind | 3 | A Melt Away 10 Energy-t ad |
| 3 | Callous Hide | 2 | −4% elszenvedett sebzés |
| 3 | *Unseen Blades* (módosító – Melt Away) | 1 | Amikor a Melt Away lejár, ingyen (Energy nélkül) dobsz egy Knife Bloom-ot az árnyékból; a Combo Pointokat a szokásos módon elkölti |
| 4 | Opportunist's Eye | 3 | A kritikus fegyvertalálat 8% eséllyel garantált kritté teszi a következő fegyvertalálatot |
| 4 | Quick Fingers | 3 | A Duskstep és a Narrow Escape +6% erő és −6% cooldown |
| 5 | **Dusk Waltz** (capstone) | 1 | A Melt Away után 5 mp-ig minden fegyvertalálatod krit (a Knife Bloom tőrei és a shurikenek is); a 8 m-en belüli társak ennyi időre +10% Critet kapnak; legfeljebb 12 mp-enként egyszer |

#### Warlock – Hexcraft fa

Átkok, életszívás és rettegés. Az **Anguish** átok minden fegyvertalálattal a célpontra kerül,
így a fa tanult DoT-abilityk nélkül is működik – a Corruption, a Blight Seed és a Fear
(Dread) mellett még jobban. A capstone az átkozott ellenségek halálát láncreakcióvá teszi.

| Tier | Talent | Pont | Hatás / pont |
|---|---|---|---|
| 1 | Hex of Anguish | 3 | A fegyvertalálat Anguish átkot tesz a célpontra: a találat sebzésének 5%-a Shadow sebzésként 6 mp alatt (az újabb találatok hozzáadódnak) |
| 1 | Improved Vital Siphon | 3 | A Vital Siphon +6% sebzés és gyógyítás, −4% CD |
| 2 | Umbral Affinity | 3 | +3% Shadow sebzés |
| 2 | Hex of Fatigue | 3 | Az átkaid (Anguish, Corruption, Blight Seed, Dread) alatt álló ellenségek 10%-kal lassabbak |
| 3 | Malediction | 2 | +6% DoT-sebzés |
| 3 | *Dark Harvest* (módosító – Vital Siphon) | 1 | A Vital Siphon a hatótávján belül minden átkozott ellenséget is szív (legfeljebb 6-ot): egy tick sebzésének 25%-át kapják, és ez is gyógyít |
| 4 | Spreading Anguish (előfeltétel: Hex of Anguish 3/3) | 3 | Ha egy Anguish alatt álló ellenség meghal, a megmaradt átok szétoszlik +1 közeli ellenségre (4 m-en belül, a hátralévő idővel; a sebzés összege nem nő) |
| 4 | Doomed Prey | 3 | +5% sebzés a 35% HP alatti ellenségekre |
| 5 | **Volatile Blight** (capstone) | 1 | Ha egy átkaid alatt álló ellenség meghal (bárki ölte meg), szétrobban: Shadow sebzés a 3 m-en belüli ellenségekre és 1 mp kábítás (ellenségenként legfeljebb 4 mp-enként) |

#### Warlock – Pactcraft fa

Démonok a Warlock oldalán: az állandó Imp, a Gloomguard és a Cinder Brute, Pact Shard-ok és
szívós lélek. Az állandó Imp miatt a fa tanult pet nélkül is működik; az Imp Brood módosító a
Ember Rain-t démonidézéssé teszi.

| Tier | Talent | Pont | Hatás / pont |
|---|---|---|---|
| 1 | Fiendish Vigor | 3 | +3 Stamina |
| 1 | Pampered Imp | 3 | Az Imp tűzlövedékei +5% sebzés |
| 2 | Pack Command | 3 | +3% pet-sebzés (Imp, Gloomguard, Cinder Brute, Phantom Wolf) |
| 2 | Shard Hunger | 3 | Egy Pact Shard-hoz 1-gyel kevesebb ölés kell (alapból 12) |
| 3 | Pact Ward | 2 | −3% elszenvedett sebzés |
| 3 | *Imp Brood* (módosító – Ember Rain) | 1 | Az Ember Rain 2 Wild Impet is megidéz 6 mp-re: úgy harcolnak, mint az Imp, a sebzése 50%-ával (egyszerre legfeljebb 4) |
| 4 | Pactmaster (előfeltétel: Pack Command 3/3) | 3 | +4 Mastery (Ember Pact: +8% DoT- és pet-sebzés) |
| 4 | Kindly Fiends | 3 | 5 mp-enként a legsebesültebb hős (akár te) a Max HP-ja 1,5%-át gyógyul |
| 5 | **Soul Tether** (capstone) | 1 | A rád eső sebzés 20%-át a démonjaid viselik (−20% elszenvedett sebzés); a petek +30% sebzés |

#### Warlock – Cinderfall fa

Tűz és árnyék, kritikus találatok és tűzeső. A Staff Fire iskolájú, így a fa a fegyvert, a
Ember Rain-t és az Imp tűzlövedékeit egyszerre erősíti; a Pact Shard-ok több tűzesőt adnak.
(A képességek nem kritelnek – a krit a fegyvertalálaté.)

| Tier | Talent | Pont | Hatás / pont |
|---|---|---|---|
| 1 | Devastation | 3 | +2% Crit |
| 1 | Stoked Flames | 3 | +3% Fire sebzés (Staff, Ember Rain, Imp, Cinder Brute) |
| 2 | Fire and Brimstone | 3 | Az Ember Rain +4% sebzés és +2% sugár |
| 2 | Aftermath | 3 | Az Ember Rain 10%-kal lassítja a benne álló ellenségeket |
| 3 | Bloody Tithe | 2 | A kritikus találat a sebzése 20%-át Shadow sebzésként kiszívja a célpontból, és ennyit gyógyít |
| 3 | *Parting Scorch* (módosító – Vital Siphon) | 1 | A végigcsatornázott Vital Siphon végén Parting Scorch: a célpont a csatornázás sebzésének 75%-át kapja egyszerre; ha 3 mp-en belül meghal, +1 Pact Shard (legfeljebb 10 mp-enként) |
| 4 | Ruin (előfeltétel: Devastation 3/3) | 3 | +10% krit sebzés |
| 4 | Pocketed Shards | 3 | +1 Pact Shard minden hullám elején |
| 5 | **Lingering Blaze** (capstone) | 1 | Az Ember Rain égő földet hagy: a kör még 3 mp-ig ég 40%-os sebzéssel, és 30%-kal lassít; a kritikus találataid 10% eséllyel +1 Pact Shard-ot adnak |

### 7.5 Capstone-ok (minden kaszt, minden fa)

| Kaszt | Fa | Capstone | Hatás |
|---|---|---|---|
| Warrior | Warblade | Ruinous Strike | Minden 5. fegyvertámadás extra 150%-os csapás, és 8 mp-re Ruinous Wound-ot hagy: −50% gyógyulás (a Vampiric eliteken is), +10% sebzés tőled; Execute-tal szinergiában |
| Warrior | Berserker | Carnage | Ölésenként +2% sebzés (max 20%), 5 mp-ig tart (minden ölés frissíti); a 8 m-en belüli társak a bónusz felét kapják |
| Warrior | Ironwall | Unbreakable (korábban Last Stand) | Halálos találat helyett talpon maradsz: +30% Max HP 10 mp-re (ennyit gyógyulsz is) és 1 mp sebezhetetlenség, hullámonként 1×; a 8 m-en belüli társak +15% Max HP-t kapnak |
| Mage | Starlore | Overchannel | A Mana-költségek +30%-kal nőnek, de minden sebzés +25% |
| Mage | Pyrelore | Chain Ignition | Ha egy fegyvertámadás kritikus, lángba borítja a célpont környékét: a célpont és a 2,5 m-en belüli legközelebbi ellenségek (összesen legfeljebb 4) 3 mp alatt a krit sebzés 20%-át kapják égésként (ugyanazt az ellenséget legfeljebb 1 mp-enként) |
| Mage | Rimelore | Frost Spike | A fagyott ellenségeket minden találatod kritként éri: a fegyvertalálat garantált krit, a varázslatok, égések és petek dupla sebzést okoznak (+ Critical Damage bónusz) |
| Paladin | Radiance | Radiant Pulse | Automatikus, 4 mp-enként (a Haste és a Cooldown Reduction rövidíti): a 8 m-en belüli legsebesültebb, 90% HP alatti hőst (téged is) a Max HP-ja 6%-ával gyógyítja, különben a legközelebbi ellenségre 100%-os fegyversebzésű Holy csapást mér |
| Paladin | Vigil | Gleaming Shield | Pajzzsal +20% Block; a blokkolt találat 60%-os fegyversebzésű Holy csapást mér a támadóra, és a 8 m-en belüli legsebesültebb társadra a Max HP-ja 2%-ának megfelelő pajzsot tesz (legfeljebb 8%) |
| Paladin | Verdict | Sunbrand | Fegyvertámadásonként 15% esély extra Holy csapásra (a találat 70%-a) a célpontra és legfeljebb 2 közeli ellenségre; minden csapás a legsebesültebb közeli hőst a Max HP-ja 2%-ával gyógyítja |
| Rogue | Toxins | Steel Nerve | A hullámban minden 3. Knife Bloom dobás garantált krit +50% krit sebzéssel; az eltalált ellenségek 3 mp-re 30%-kal lelassulnak |
| Rogue | Bladework | Crowd Surge | Amíg legalább 3 ellenség van 5 m-en belül, +50% Energy-termelés, és a 8 m-en belüli társak +10% Haste-et kapnak |
| Rogue | Gloaming | Dusk Waltz | A Melt Away után 5 mp-ig minden fegyvertalálat krit (a dobott tőrök és shurikenek is), a 8 m-en belüli társak +10% Critet kapnak; legfeljebb 12 mp-enként |
| Warlock | Hexcraft | Volatile Blight | Ha egy ellenség az átkaid (DoT-jaid) alatt hal meg – bárki ölte meg –, instabil árnyrobbanás sebzi a 3 m-en belüli ellenségeket, és 1 mp-re elkábítja őket (ellenségenként legfeljebb 4 mp-enként) |
| Warlock | Pactcraft | Soul Tether | A sebzés 20%-át a pet viseli el (−20% elszenvedett sebzés, a pet nem halhat meg); a pet +30% sebzés |
| Warlock | Cinderfall | Lingering Blaze | Az Ember Rain égő földet hagy: a kör még 3 mp-ig ég 40%-os sebzéssel, és 30%-kal lassít; a kritikus találataid (fegyvertalálat) 10% eséllyel +1 Pact Shard-ot adnak |
| Hunter | Beast Mastery | Bestial Wrath | 30 mp-enként 10 mp-ig a pet +50% sebzést kap és nem lehet lassítani |
| Hunter | Marksmanship | Trueshot Aura | A közeli társak +5% sebzést kapnak; az Aimed Shot cooldownja felére csökken |
| Hunter | Survival | Wildfire Bombs | Az Explosive Trap égő földet hagy, és 3 kisebb bombát szór szét |
| Shaman | Elemental | Elemental Mastery | 20 mp-enként a következő 3 varázslat garantált krit |
| Shaman | Enhancement | Stormstrike | Minden 5. fegyvertalálat dupla villámcsapást vált ki |
| Shaman | Restoration | Spirit Link Totem | Totem, ami kiegyenlíti a közeli társak HP-ját, és 20%-kal csökkenti a sebzésüket (co-op) |

**Értelmezések (a játék szabályai miatt):**
- **A képességek nem kritelnek** (csak a Rogue fegyvertalálatos abilityjei), ezért a kritre
  épülő capstone-ok a **fegyvertalálat** kritjére épülnek: Chain Ignition, Frost Spike, Lingering Blaze.
  - A Frost Spike a nem kritelő találatokat (varázslat, égés, pet) duplázza.
  - A Frost Spike a procokat nem duplázza, mert azok már a fegyvertalálat kritjéből jönnek.
- **Az ellenségek nem dispellelnek és nem varázsolnak:** a Volatile Blight a halálra
  reagál, a Silence helyett kábít.
- **Az ellenségek nem gyógyulnak**, kivéve a Vampiric eliteket: a Ruinous Strike −50%
  gyógyulása rajtuk hat, és a Ruinous Wound +10% sebzést is ad tőled.
- **„Találatonként” = támadásonként:** egy ívcsapás, robbanó vagy átlövő lövedék egy
  támadásnak számít (Ruinous Strike, Chain Ignition, Sunbrand). Az extra támadás külön
  támadás.
- **Co-op ráadások:** több capstone a társakat is segíti – Carnage, Unbreakable, Gleaming Shield,
  Sunbrand, a Steel Nerve lassítása, Crowd Surge, Dusk Waltz.
  - A társakra ható rész mindig kisebb a saját hatásnál.
  - Minden hős a saját kulcsán adja, így két azonos kasztú hős hatása szorzódik, mint két
    Battle Roar-é.
- **Mind a 15 capstone M5-ben kész** (a Hunter és a Shaman fái M8-ban jönnek).

### 7.6 Kapcsolat a többi rendszerrel

- A szintlépési **ability-kártyák** szélességet adnak: új eszközöket.
- A **Trainer-rangok** goldért erősítik az abilityket.
- A **talentfa** az irányt adja meg: a kaszt identitását és a buildet.
- Az ability-iskolák (tagek) miatt a talentek a tanult abilitykre is hatnak
  (pl. a Pyrelore fa erősíti a Fireball és a Meteor abilityt).

---

## 8. Ellenségek

A fajok WoW-hangulatúak, de saját nevűek.

| Név | Leírás | Viselkedés | Megjelenik |
|---|---|---|---|
| **Skeleton Grunt** | Csontváz kardos | Egyenesen a legközelebbi játékosra jön | 1. hullámtól |
| **Candlekin** | Kis gyertyás bányász-lény | Gyors, gyenge, rajban jön | 2. hullámtól |
| **Marsh Gurgler** | Hal-ember | 4–6-os csoportban, rövid nekirugaszkodás | 3. hullámtól |
| **Troll Hatchet-Hurler** | Troll | Távolról baltát dob, tartja a távolságot | 5. hullámtól |
| **Plague Ghoul** | Ghoul | Halálakor méregtócsát hagy | 7. hullámtól |
| **Cultist Acolyte** | Kultista | Gyógyítja / pajzsolja a többieket, elsődleges célpont | 9. hullámtól |
| **Flesh Golem** | Varrott óriás | Lassú, sok HP, időnként maga felé húz | 12. hullámtól |

**A három új ellenség (M6a) – kiinduló értékek**

A számok a hullám- és co-op-növekedés előtti alapértékek (9. fejezet); a balanszolás során
változnak. Az érintéses sebzés az ellenség alap-sebzése, a gold és az XP a normál (nem elit)
jutalom.

| | Plague Ghoul | Cultist Acolyte | Flesh Golem |
|---|---|---|---|
| Megjelenik | 7. hullámtól | 9. hullámtól | 12. hullámtól |
| Viselkedés | üldöző (Chase) | támogató (Support) | brute |
| Alap HP | 7 | 6 | 40 |
| Érintéses sebzés | 2 | 1 | 4 |
| Sebesség (m/s) | 2,1 | 2,3 | 1,5 |
| Spawn-súly | 0,6 | 0,35 | 0,25 |
| Csoportméret | 2–3 | 1 | 1 |
| Gold / XP | 1 / 2 | 2 / 3 | 4 / 5 |

A Flesh Golem érintéses sebzése (és vele a horog, ami 1× ennyi) az M6a kiinduló értéke, nem
hangolt szám: a bot-futásokban a spawnolt ellenségek kis részéből a hősök kapott sebzésének
nagy részét adja, ezért a végső balansz nyitott kérdése (9. fejezet, „Nyitott kérdések M6b-re”).

- **Plague Ghoul** (sugár 0,5 m): úgy üldöz, mint a Skeleton Grunt.
  - Halálakor **méregtócsát** hagy ott, ahol meghalt (ha a hullám vége tünteti el, nem
    keletkezik): 1,6 m sugarú, 3 mp-ig áll, **0,5 mp-enként** sebez – az első tick 0,5 mp-cel a
    halál után esik, így a mellette álló hős még kiléphet. Tickenként a Ghoul akkori (a hullám
    szerint skálázott) érintéses sebzésének felét okozza, a csapatméret-szorzóval és az
    elit-affix sebzésszorzójával együtt.
  - **Csak a hősöket** bántja (az ellenségeket nem), az élő hősöket, akiknek a **középpontja** a
    körben van. AoE-sebzésnek számít: az Armor, az Avoidance, a Dodge és a Block érvényes rá;
    nincs forrása, ezért a Thorns / Reprisal nem sül el.
  - Zöld korong világos peremmel és buborékokkal; figyelmeztető jel nincs.
  - Egyszerre legfeljebb **12 tócsa** él; a 13.-nál a legrégebbi (kor szerint, döntetlennél a
    korábban létrejött) eltűnik. A hullám vége minden tócsát eltávolít.
  - A botok a tócsát **veszélyzónának** tekintik, és kikerülik (lásd „Bossok”, veszélyzónák).
- **Cultist Acolyte:** új, **támogató** viselkedés.
  - **Távolság:** a legközelebbi látható hőstől 6 m alatt **hátrál** (a falak mentén, falnak nem
    megy; sarokban a fal mentén fut), 9 m fölött **közelít** (a csorda felé, ha az közelebb van a
    hőshöz nála, különben a hős felé); a 6–9 m-es sávban a **csorda** (a 10 m-en belüli többi
    ellenség közepe) felé sodródik, ha az nincs 6 m-en belül a hőstől. Így a többi ellenség
    közelében marad.
  - **Csatornázás:** 4 mp-enként (induláskor 2–4 mp késleltetéssel, csoportonként szétszórva)
    **0,6 mp-es** csatornázást végez; közben **áll**, lila sugár köti össze a célponttal.
  - **Célpont:** a 7 m-en belüli **legkisebb HP-arányú**, sebesült ellenség: a Max HP-ja
    **25%-át** gyógyítja (a gyógyuláscsökkentés hat rá). Ha nincs sebesült, a hatótávon belüli
    **legnagyobb Max HP-jú** ellenségre, akinek a pajzsa még 20% alatt van, a Max HP-ja
    **20%-ának** megfelelő pajzsot tesz. Más ellenségeket segít (más Acolyte-ot is), saját magát
    és a Coin Gremlin-t nem.
  - **A pajzs nem halmozódik, csak frissül:** a nagyobb pajzs megmarad, a kisebb 20%-ra frissül;
    a bossokon sem megy 20% fölé. Az Acolyte pajzsa elfogyva **nem nő vissza** (csak a
    Shielding elit affix regenerál). Nem elit ellenségen lila buborék, az eliten a névtáblán
    látszik.
  - **A bosst sosem gyógyítja** (az mindig a legsebesültebb lenne, és minden Acolyte rajta
    tartaná); a boss melletti sebesült add-ot továbbra is gyógyítja.
  - **Megszakítás:** a kábítás, a hátralökés (bármilyen, a találat sebzése nem), a fear és a
    taunt. Megszakítás után a következő csatornázás a cooldown **felénél** jön. Ha a cél meghal
    vagy 7 + 1,5 m-nél messzebb kerül, a csatornázás 0,5 mp szünettel véget ér; ha nincs élő
    hős, szintén.
  - **Elsődleges célpont:** a botok 14 m-en belül az Acolyte felé mennek (ha egészségesek és
    kevesebb mint 4 ellenség van körülöttük), és a fegyverük a lőtávon belüli Acolyte-ot
    választja a legközelebbi helyett. Az emberi játékos fegyvere továbbra is a legközelebbit
    veszi célba.
- **Flesh Golem** (sugár 0,9 m, ×1,6 méret): új, **brute** viselkedés – lassú, sok HP.
  - Hátralökés-ellenállás 80%, kábítás-ellenállás 50%.
  - **Horog:** 6 mp-enként (induláskor 3–6 mp), ha egy **látható** (nem Melt Away-olt) hős 4–9 m-re
    van, a golem megáll, és **0,8 mp-es piros sávot** (1,2 m széles, 9,5 m hosszú) húz; a célzás
    a hőst követi a telegraph első 60%-ában, az utolsó **40%-ban zárolva** van. A kijelzőn a sáv
    kitöltődik (visszaszámlálás).
  - **Találat:** lejártakor a **vonalban még álló legközelebbi hőst** (a közepe a sávon belül)
    találja: **1× érintéses sebzés** (lövedék típusú, az Avoidance érvényes), majd **3 m-es húzás**
    a golem felé (0,22 mp alatt; a falak és a képernyőszél megállítják; nem húz a golem testéig:
    a golem sugara + a hős sugara + 0,1 m marad). A hős mögött állót nem viszi el.
  - A **Dodge** egyetlen dobással (mint bármelyik támadás) kikerüli a sebzést ÉS a húzást; a
    sérthetetlen hős (Gilded Halo, Charge, i-frame) immunis. Aki a zárolás után kilép a
    sávból, kikerüli; a cooldown ilyenkor is elmegy.
  - **Megszakítás:** a kábítás (50% ellenállás: a felezett idő), a fear és a taunt. A hátralökés
    nem szakítja meg (80% ellenállás). Megszakítás után a cooldown fele. Ha az egyetlen látható
    hős Melt Away-ol a telegraph alatt, a golem eldobja a hurkot (cooldown fele); ha van másik
    látható hős, a telegraph fut tovább, de a láncot a Melt Away-olt hős már nem találja.
  - **Botok:** a hős-botok a hurkok **60%-át** kikerülik (a bot saját RNG-jével, **golemenként és
    hurkonként** egyszer döntenek), a többit elszenvedik – mint egy ember, aki nem figyelt.

**Elitek**

- **Mikor:** az 5. hullámtól, véletlenszerűen.
  - Hullámonkénti várható szám: `(0,4 + 0,06 × (hullám − 5)) × (1 + 0,35 × (játékosok − 1))`.
    A tört rész az esély még egy elitre.
  - Egy játékossal az 5. hullámban 0,4, a 15.-ben 1,0, a 25.-ben 1,6; 4 játékossal ennek
    2,05-szöröse.
  - A 20. hullám elit-hullám (lásd lent), a 10. és a 25. boss-hullám (lásd „Bossok”).
- **Melyik ellenség:** a hullám 15–70%-a közé sorsolt időpontok után a következő csoport első
  tagja lesz elit (bármilyen típus); egy időpont egy elitet ad. Az elitek beleszámítanak a
  pályán lévő ellenségek számába.
- **Erő:** 3× HP, ×1,3 méret, és **1 véletlen affix**:
  - **Shielding:** érkezéskor és utána 8 mp-enként (ha az előző elfogyott) a Max HP-ja 30%-ának
    megfelelő elnyelő pajzs, kék buborék; a sebzés először a pajzsot viszi („Absorb”).
  - **Enraged:** 50% HP alatt egyszer: +50% sebzés, +30% sebesség, nem lassítható (a kábítás,
    a fagyasztás és a fear működik), vörös árnyalat.
  - **Frenzied:** +25% sebesség; a támadások, a nekirugaszkodás és az érintéses sebzés
    cooldownja ×0,6.
  - **Vampiric:** minden találata (közelharc vagy lövedék), ami hőst ér, a Max HP-ja 10%-ával
    gyógyítja. A gyógyuláscsökkentés (Ruinous Strike) hat rá.
- **Kinézet:** ezüst, sárkányszárnyas névtábla a feje fölött („<Affix> <név>” ezüstben), alatta
  vékony HP-csík és a pajzs szegmense. Az ellenségeknek nincs portréjuk, ezért nincs
  portrékeret.
- **Jutalom:**
  - 10 gold (a normál gold helyett) és ×5 XP.
  - **Garantált Rare+ item** (a gyilkos Fortune-jével), amit a hullám végén **Need / Greed /
    Pass** dobással osztunk el (lásd 10.1). Ez nem számít bele a normál drop hullámlimitjébe.
  - A normál dropesély is megmarad.
  - A hullám végén eltűnő (meg nem ölt) elit nem ad semmit.
- **Kivégzés:** az Execute az eliteket is azonnal megöli a küszöb alatt; a Slayer stat hat
  rájuk.
- **20. hullám – elit-hullám** (M6a): a hullám minden ellensége kap egy véletlen elit-affixet.
  - Az **affix hatása** ugyanaz, mint az eliteknél (Shielding, Enraged, Frenzied, Vampiric),
    de az ellenség csak **×1,5 HP-t** kap (nem ×3-at), és a **jutalma normál** (nincs
    elit-gold, ×5 XP és garantált item).
  - A **megjelenése kompakt** („lite”): csak az affix-drágakő a fej fölött, a Shielding-buborék
    és az Enraged árnyalat; nincs névtábla, HP-sáv és szárny, és nincs méretnövelés (a ×1,3 az
    igazi eliteké). Nem számít elitnek: a Slayer és az Execute elit-prioritása nem hat rájuk.
  - Az igazi elitek (3× HP, elit-jutalom) várható száma ezen a hullámon a **kétszeres**.
  - Nincs boss, és Coin Gremlin sem jön (lásd lent).
  - **Endless módban** (M6b) ez a szabály a **33., 43., 53. …** hullámon ismétlődik (16.1).
  - A botoknak a 20. hullám kiugró nyomást jelent (az elit-affixes golemek és Axethrowerek);
    hogy mennyire legyen kemény, a végső balansz nyitott kérdése (9. fejezet, „Nyitott
    kérdések M6b-re”).

**Coin Gremlin** (ritka, különleges ellenség)

- **Megjelenés:**
  - A 3. hullámtól, a 10., 20. és 25. hullám kivételével (boss- és elit-hullám), hullámonként
    legfeljebb 1.
  - Esély: **15% + 0,5 százalékpont** a csapat legmagasabb Fortune-jű élő hősének minden
    Fortune-pontjáért, legfeljebb 50%.
  - Időpont: a hullám 3. másodperce és a hullám 35%-a között jön, és csak akkor, ha utána még
    legalább 18 mp hátravan.
- **Bejelentés:** arany felirat: „*A Coin Gremlin appeared!*” (a csilingelő hang az M7a hangrendszerrel szól). A feje fölött arany „Coin Gremlin” felirat.
- **Kamera:** a kamera a Coin Gremlin-t is keretezi, amíg él és meg nem szökött (a portál
  nyitása alatt is, mert addig még megölhető): kizoomol érte (legfeljebb a maximális
  távolságig). A hősök mindig elsőbbséget kapnak: ha keskeny képernyőn nem fér ki velük
  együtt, a kép csak felé dől, és a goblin sosem korlátozza, hova léphet egy hős. A
  „Coin Gremlin” felirat sosem lóg ki a képből: a képernyő szélén a szél mentén csúszik, így a
  goblin irányát is mutatja.
- **Viselkedés:**
  - **Nem támad, menekül** a játékosoktól (a közelebbiektől erősebben), kerüli a falakat, és
    0,6–1,2 mp-enként véletlenül irányt vált. Érintéssel nem sebez.
  - 30 alap HP a szokásos hullám- és co-op-növekedéssel (≈ 7,5 Skeleton Gruntnyi).
  - 4,4 m/s: gyors, de lassabb a hősöknél (5 m/s), így utol lehet érni.
  - **Működik rajta:** kábítás, fagyasztás, lassítás, hátralökés.
  - **Nem működik:** taunt, fear.
- **Szökés:** 15 mp után megáll, és 1,2 mp alatt portált nyit – közben még megölhető –, majd
  eltűnik: „*The Coin Gremlin escaped!*” (szürke).
- **Találatkor:** minden találatnál 1 goldérme szóródik belőle, legalább 0,15 mp-enként,
  goblinonként legfeljebb 30.
- **Ha megölik:**
  - 30× a hullám átlagos ellenség-goldja, kb. 8 kupacban,
  - 25× a hullám átlagos ellenség-XP-je,
  - garantált item (Rare+, 25% eséllyel Epic+), Need / Greed / Pass dobással (lásd 10.1); nem
    számít a normál drop limitbe.
- **Elit vagy nem:** a Slayer szempontjából elitnek számít, de elit-jutalmat (10 gold, ×5 XP,
  elit-drop) nem kap. Az Execute normál ellenségként kezeli.
- **Botok:** ha nincs más ellenség a közelükben és van elég HP-juk, üldözik.
- **Ritka változat (később):** *Golden Goblin* – 1% eséllyel, csak goldot dob, de
  nagyon sokat.
- **Co-op:** a csapatnak össze kell hangolnia, hogy körbezárják (pl. Rime Burst,
  Smiting Hammer, Charge, Hailstorm lassítása).

**Esemény-ellenségek és -célpontok** (M6b)

A hullám közbeni események (16.1) szereplői. A számok kiinduló értékek (nincs hangolás); a
„grunt HP” a Skeleton Grunt HP-ja az adott hullámon (a szokásos hullám-növekedéssel, 9.
fejezet).

- **Guarded Chest – őrök:** 4 őr a láda körül, az adott hullámon jogosult ellenségtípusok
  közül, **×2 HP**-val és **affix nélkül**. Az őrök a láda körül egy 2,8 m sugarú körön
  **posztjukon állnak**, és nem indulnak a hősök után, amíg egy hős 9 m-en belülre nem ér
  valamelyikükhöz, vagy valamelyikük sebzést nem kap (pl. távoli lövés); ekkor az egész
  csoport egyszerre támad.
- **Defend the Totem – totem:** szövetséges célpont. HP-ja **30 × grunt HP** a csapatméret
  szerinti HP-szorzóval (9. fejezet); a „grunt HP” amennyi egy Skeleton Grunt HP-ja
  ténylegesen. A **8 m-en belüli** ellenségeket a totem magához csalogatja, azok a hősök
  helyett rá támadnak, és a szokásos érintés-sebzésükkel (az elit szorzójával, 1 mp-es
  újratöltéssel) harapják; az elkábított vagy megfélemlített nem harap. Nem csalogat bosszt,
  Coin Gremlin-t és kordét, és azt sem, akit egy hős vagy pet éppen magára vett. A
  **teljesített** totem a hullám végéig áll, de már nem csalogat és nem sebződik.
- **Goblin Caravan – kordé:** HP-ja **40 × grunt HP** (a csapatszorzóval); egyenes sávban
  megy az aréna két rövid oldala között (a faltól 1,8 m-re indul és ér célba), ~25 mp alatt;
  nem sebez, nem kábítható, nem lökhető, a taunt és a megfélemlítés nem hat rá, lassítható
  (Rime Burst, Hailstorm). 3 őr kíséri, amíg egy hős a közelükbe nem ér vagy a kordét el nem
  találják. Ha a hullámból kevesebb idő marad 27 mp-nél, az átkelés rövidül (a hullám vége
  előtt 2 mp-cel ér át, legalább 15 mp alatt). Megölve gold-özönt és egy Rare itemet dob
  (10.1); a túloldalon elszökik („*The caravan got away*”).
- **Futó szentély és környezeti veszély:** mivel az őrök és a kordé szokásos ellenségek, a
  **futó szentélyek** (HP / sebzés / sebesség) őket is erősítik, a környezeti veszélyek pedig
  sebzik / lassítják őket; a totem saját HP-szabályú, a szentély nem hat rá. A fix
  esemény-jutalmakat a szentély nem szorozza.
- **Kamera és botok:** a kamera az esemény célpontját is képen tartja. A botok az őrökkel
  normálisan harcolnak, kinyitják a ládát, a totem 6 m-es körzetében maradnak, és a kordét
  üldözik, ha nincs ellenség a közelben (a pontos viselkedés: 16.1, „Hullám közbeni
  események – pontosítások”).
- **Dungeon Warden:** lásd a Bossok alatt.

**Bossok** (M6a)

Boss-hullám a **10.** és a **25.** hullám (M6b: Endless módban a 30.-tól minden 5. hullám is,
lásd a „Győzelem” pontot és a 16.1-et). A számok kiinduló értékek, a balanszolás során
változnak. Közös szabályok:

- **A boss az időzítő helyett:** a hullám a **boss halálával ér véget** (nincs időkorlát). A
  pályán maradt ellenségek ilyenkor eltűnnek, a földön lévő gold, XP és loot a szokásos módon
  begyűjtődik, mint egy normál hullám végén. A piac fejléce a boss-hullám előtt ezért nem ír
  másodpercet: „Next up: Wave 10 of 25 – Boss wave! (ends when the boss falls)” (ugyanígy a
  25. hullámra); a többi hullám fejléce változatlan („Next up: Wave 4 of 25  ·  60 seconds”, az
  elit 20. hullámé „… seconds  –  Elite wave!”).
- **Érkezés:** a boss-hullám elején a pályán egy 2,6 m sugarú piros rúna jelenik meg a
  hősöktől legalább 10 m-re (lehetőleg a képernyőn), és **2 mp múlva** megérkezik a boss. A
  HUD-on ekkor a neve piros szalagként jelenik meg; a boss-keret (teli HP-sáv) a hullám 1.
  másodpercétől a helyén van.
- **Add-ok:** a normál spawn a szokásos ráta **50%-ával** folytatódik. Boss-hullámon **nincs
  elit és nincs Coin Gremlin** (a boss az elit).
- **A boss nem mozdítható és nem irányítható:** hátralökésre immunis, a kábítás időtartama
  ×0,25, a lassítások fele erősséggel hatnak (a szellem-lassítás is), a taunt és a fear nem hat
  rá. Az Execute nem ölheti meg azonnal (dupla sebzést kap), a Phantom Double nem csalja el.
- **Kamera:** az élő bosst a kamera is keretezi (a Coin Gremlin-hez hasonlóan „puha” pont; a
  hősök mindig elsőbbséget kapnak), a magas alakja is belefér a HUD alá.
- **Enrage 90 mp-nél** (a boss megérkezésétől számítva): a boss sebzése ×1,5, sebessége +30%.
  Ezután minden további 30 mp-enként a sebzés-szorzó +0,25-tel nő (×1,75, ×2,0 …). A boss
  **minden támadása** (érintés és mezők) ezt a szorzót használja.
- **2. fázis** 50% HP-nál: a boss cooldownjai rövidülnek; a futó cooldownok megtartják az
  előrehaladásukat az új (rövidebb) intervallumon.
- **HUD:** a hullám-időzítő helyén **boss-keret** áll: név, HP-sáv, két fázis-pip és „ENRAGED”
  felirat (12. fejezet). Az „ENRAGED” pulzáló, világos piros; a sora **mindig le van foglalva**
  (nyugodt bossnál átlátszó), így a keret nem ugrik meg, amikor a boss dühöngeni kezd.
- **Boss HP:** `alap HP × az adott hullám szokásos ellenség-HP-szorzója × (1 + k × (játékosok −
  1))`, ahol a co-op szorzó a boss saját szorzója (9. fejezet), nem a normál +20% játékosonként:
  **k = 0,75** mindkét bossnál (×1 / ×1,75 / ×2,5 / ×3,25 1–4 játékosnál). A `k` bossonként
  állítható adat; hogy a csapat sebzése gyorsabban nő-e a létszámnál (itemek, Artifactok,
  fókusz), a végső balansz kérdése (9. fejezet).
- **Boss sebzés:** `alap érintéses sebzés × az adott hullám szokásos sebzés-szorzója × a
  csapatlétszám-sebzésszorzó` (9. fejezet). Az alábbi „N× érintéses” az így kapott érintéses
  sebzés N-szerese.
- **Jutalom:** 50 gold és XP (Morvain 30, Vor'thalax 60); **játékosonként 1** Epic+ item (20%
  eséllyel Legendary, 10.1), mind a boss halálának helye körül egy körben; a Need / Greed /
  Pass dobás a hullám végén. A gyilkos itemje az első; **egyetlen Artifact-dobás** jár a bossért
  (a gyilkos Fortune-jével, 5.5), nem hősönként egy. A boss-item nem számít a normál drop
  hullámlimitjébe. A legyőzött bossok száma a Damage Meter „Bosses” statjába is bekerül: a
  boss halálos ütését adó hős kapja (12. fejezet), a boss HP-ja (túlütés nélkül) pedig a hősök
  sebzésébe.
- **Győzelem:** Vor'thalax halála a 25. hullámon: „Victory!” szalag, 1,6 mp, majd a győzelmi
  képernyő. A másik boss-hullám végén a szalag „<Boss neve> defeated!”.
  - **Endless módban** (M6b) Vor'thalax halála nem zárja le a menetet: „*Endless begins!*”
    szalag, és jön a 26. hullám.
  - Endlessben a **30. hullámtól minden 5. hullám** boss-hullám: **Morvain** a 30., 40., …,
    **Vor'thalax** a 35., 45., … hullámon, ugyanazokkal a képességekkel és szabályokkal,
    a szokásos hullám-skálázással. A menet itt csak vereséggel ér véget.
- **Veszélyzónák és a botok:** a boss köreit, kúpját, mezőit, meteorjait és a Plague Ghoul
  tócsáját a botok veszélyzónának tekintik: a sugarán + 0,9 m-en belül kifelé tolják magukat
  (a közepéből a pálya közepe felé; ártalmatlan vagy lejárt zóna nem tol). A Meteor körébe a
  bot-csapat beáll (a sebzés megoszlik), a magányos hős kilép belőle (4× kap 8× helyett). A
  hullám vége minden ellenség-veszélyzónát eltüntet.
  - **M6b:** az aréna-környezetek veszélyei (Grasping Hands, lápfoltok, lávakürtők, Falling
    Icicles; 16.1) is ellenség-veszélyzónák: a botok kikerülik őket, és a hullám vége
    eltünteti őket.
- **Fejlesztői biztosíték (csak `--smoke`):** ha egy boss a saját enrage-e után 120 mp-pel még
  él (tehát 210 mp-nél), meghal („SMOKE boss timeout” sor), hogy a futás mindig véget érjen.
  Egy lezárt smoke-futás tehát nem bizonyítja, hogy a boss legyőzhető.

**10. hullám – Lich Commander Morvain** (alap HP 450, érintéses sebzés 3)

- **Kinézet:** nagy csontváz-mágus, jeges korona, bot.
- **Frost Circles** – 7 mp-enként minden élő hős alatt egy 2,2 m sugarú jégkör jelenik meg; 1,2
  mp figyelmeztetés után lecsap: 2× érintéses sebzés és 2 mp-re 40% lassítás (a hős
  mozgássebessége csökken, időzített buff; a hullám végén megszűnik). „Ne állj benne.”
- **Call the Fallen** – 12 mp-enként 4 Skeleton Gruntot idéz (a 2. fázisban +2, vagyis 6-ot).
- **Frost Breath** – 9 mp-enként 60°-os, 7 m hosszú kúp a legközelebbi hős felé; 1 mp
  figyelmeztetés, 3× érintéses sebzés. „Szóródjatok szét.”
- **2. fázis** 50% HP-nál: minden cooldown ×0,7 (gyakoribb támadások).

**20. hullám – Elit-hullám:** nincs boss, de minden ellenség elit-affixet kap, és az igazi
elitek is kétszer annyian jönnek (lásd „Elitek”).

**25. hullám – Vor'thalax, the Burning Tyrant** (démon, végső boss; alap HP 450, érintéses
sebzés 4)

- **Kinézet:** szarvas démon, izzó tűzfény.
- **Fire Fields** – 8 mp-enként 2 égő folt (2 m sugarú) jelenik meg a hősök pozícióján; 1 mp
  figyelmeztetés után 8 mp-ig áll, és másodpercenként 1× érintéses sebzést okoz. Az első tick
  a gyulladás pillanatában esik (a jelzés alatt ki lehet lépni), utána másodpercenként (8 mp =
  8 tick). Ha több a folt, mint a hős, a többlet a hős mellé (2,6 m-re) kerül.
- **Meteor** – 14 mp-enként egy véletlen hős alatt 3 m sugarú jelölt kör jelenik meg; 3 mp
  figyelmeztetés után csapódik be. A teljes sebzés **8× érintéses**, ami **egyenlően oszlik el**
  a körben állók között: minél többen állnak bent, annál kisebb a rájuk jutó rész (co-op
  mechanika). Ha senki nem áll a körben, minden élő hős 4× érintéses sebzést kap.
- **Imp Swarm** – 20 mp-enként 6 Candlekin („imp”) érkezik.
- **2. fázis** 50% HP-nál: a Fire Fields 3 foltot hoz, a Meteor 10 mp-enként jön.
- **Győzelem:** Vor'thalax halála a 25. hullámon a menet győzelme – nem az időzítő lejárta.
- **Alap HP 450:** a korábbi 1200-as alap HP elírás volt: a természetes (nem szintre állított)
  botok 210 mp alatt a HP-nak csak a 33–62%-át vitték le vele (38–67% maradt). Az érintéses
  sebzés 4, a HP a létszámmal ugyanúgy nő, mint Morvainé (k = 0,75).
- **A harc hossza nyitott kérdés:** a kill-idő létszámtól és kasztoktól erősen függ (a csapat
  sebzése gyorsabban nő a létszámnál, mint a boss HP-ja, és a bot-csapat DPS-e a bossra
  kasztonként nagyon eltér), és a boss minden területi támadása és érintése a késői
  hullámok sebzés-szorzójával érkezik. A végső balansz az M6b-é (9. fejezet).

**Dungeon Warden** (mini-boss, M6b – a Dungeon 4. terme, 16.1)

- **Adat:** `BossData`, **alap HP 120**; a HP a boss-szabályokat követi (a „Boss HP” pont: az
  adott hullám szokásos ellenség-HP-szorzója, a létszám szerinti boss-szorzó), a kitisztított
  hullám szerint skálázva.
- **Képességei** a boss-veszélyekből újrahasznosítottak: **Frost Circles** és **Call the Fallen**
  (Morvain, lásd fent).
- **Enrage 60 mp-nél** (a boss-hullámok 90 mp-es Enrage-e helyett).
- A Warden legyőzése zárja a dungeont (siker és jutalom: 16.1, 10.1).
- A számok kiinduló értékek, az M6b-ben nincs hangolás.

---

## 9. Hullámok és skálázás

- **25 hullám** (Normal mód); a hullámhossz az 1. fejezet képlete szerint (a 10. hullám felett +10 mp hullámonként).
  A két boss-hullámot (10., 25.) a boss halála zárja, nem az időzítő (8. fejezet, „Bossok”).
  - **Endless módban** (M6b) a 26. hullámtól a hullámhossz legfeljebb 210 mp, az ellenségek
    növekedési képletei (alább) változatlanul folytatódnak; a 30.-tól minden 5. hullám
    boss-hullám, a 33., 43., … hullám elit-hullám (1. fejezet, 16.1).

- **Ellenség HP és sebzés:** hullámonként nő. A h. hullámon (n = h − 1):
  - HP-szorzó: `(1 + 0,12 × n) × 1,22^n`;
  - sebzés-szorzó: `(1 + 0,15 × n) × 1,10^n`.

  Az összeadódó növekedést (+12% HP, +15% sebzés hullámonként) egy hullámonként kamatozó
  szorzó egészíti ki (+22% HP, +10% sebzés), mert a hősök ereje (itemek, rangok, kártyák,
  M5-től talentek, setek, kovácsolás) is kamatozva nő. Közelítő értékek (HP / sebzés):

  | Hullám | HP | Sebzés |
  |---|---|---|
  | 5. | ×3,3 | ×2,3 |
  | 10. | ×12 | ×5,5 |
  | 15. | ×43 | ×12 |
  | 20. | ×143 | ×24 |
  | 25. | ×459 | ×45 |

  A sebzést ezen felül a csapatlétszám-szorzó is szorozza (lásd lent). Ez az M5 utáni
  ideiglenes hangolás (talentekkel, setekkel, elitekkel, Coin Gremlin-nel); a végleges egyensúly
  az M6b-ben jön. Korábban (M4) +8% volt a kamatozó sebzés, még korábban +12% HP és +8% sebzés,
  kamatozás nélkül.
- **Spawn:** a spawnpontok a pálya szélén és véletlen belső pontokon vannak, 1 mp-es
  figyelmeztető jellel (piros rúna a földön), mint a Brotatóban.
- **Co-op skálázás:** minden további játékos után
  - +60% ellenségszám,
  - +20% ellenség-HP,
  - a boss HP-ja ×(1 + k × (játékosok − 1)) – ez a boss saját szorzója, a normál +20%
    helyett (mindkét bossnál k = 0,75: ×1 / ×1,75 / ×2,5 / ×3,25; az alap boss-HP-t és a
    sebzést a 8. fejezet adja),
  - az Artifact normál ölésből eső esélye osztva a játékosszámmal (5.5), mert az ölések
    száma a csapattal nő.
- **Spawn-ráta:** `(0,9 + 0,08 × (h − 1))` ellenség / mp egy játékosra, co-opban szorozva az
  ellenségszám-szorzóval. Egy 4 fős teljes menet kb. 15 000 ellenség. Mivel minden ellenség
  goldot és XP-t ad, a szám lassan nő; a késői nehézséget a HP- és sebzés-skálázás adja.
- **Ellenség-sebzés csapatlétszám szerint:** az ellenségek érintéses és lövedéksebzését a
  csapatlétszám is szorozza: 1 / 2 / 3 / 4 játékosnál ×0,45 / ×0,6 / ×0,75 / ×0,95 (kb. ×1,3
  minden további játékossal).
  - **Miért:** kisebb csapatban kevesebben tudják felsegíteni az elesett hőst (egyedül az első
    elesés már vereség), és egy hősre több ellenség jut (a +60% ellenségszám kevesebb, mint egy
    újabb fejadag).
  - A teljes csapat ×0,95-öt kap: M5 után (talentek, setek) ×0,9-cel 8 próbából egyik sem
    esett el, és a késői hullámok nyomása több seeden gyenge volt; ×1,0-val 5 próbából kettő
    már a 17–18. hullámon elesett.
  - Az ellenség HP-ja, száma és a gazdaság nem változik.
  - Ideiglenes hangolás M5 után; a végleges egyensúly az M6b-ben jön.
  - **M5 mérés (botok, 25 hullám):** 4 fő: 8 seedből 7 végigért, 1 csapat a 20. hullámon
    esett el, az első elesések a 5–22. hullámon, a 20–25. hullámon erős a nyomás. 2 fő: 6
    próbából 5 végigért, 1 a 23. hullámon esett el. 1 fő: 13 próbából 6 végigért, a többi a
    8–24. hullámon halt meg.
- **Nehézség az M6a után:** az M6a tartalma (a három új ellenség, a 20. hullám elit-hulláma,
  Morvain és Vor'thalax) a játékot az M5-nél **nehezebbé tette**. Ezt szándékosan nem
  hangoltuk újra: a hullám- és sebzés-görbe, a csapatlétszám-szorzó és az új ellenségek,
  bossok kiinduló számai változatlanok. A végleges 25 hullámos balansz **egyszer, az M6b
  végén** készül (16. fejezet), az összes M6b-s tartalommal (item-csomagok, módok, események)
  együtt, hogy ne kétszer kelljen hangolni.
  - **Az M6b nem hangolt:** egyik csomagja sem (módok, környezeti veszélyek, események,
    szentélyek, Dungeon, item-tartalom) módosította a hullám- és sebzés-görbét, a
    csapatlétszám-szorzót vagy a meglévő tartalom számait; ahol egy csomag új értéket írt elő
    (pl. az Epic fegyverek +10% támadási sebessége, 4.1), azt a megfelelő fejezet rögzíti. Az
    új elemek számai (16.1, 8. fejezet) kiinduló értékek; a végső balansz mindet **egyszer, a
    legvégén** hangolja, a lenti nyitott pontokkal együtt.
  - **A régebbi mérések nem összehasonlíthatók az M6b-s fejjel.** A kód változásai önmagukban
    semlegesek a seedelt futásra (a tartalom nélküli másolat pontosan a régi számokat adja), de az
    új utótagok, enchantok és fegyverek a súlyozott sorsolásokba kerültek, ami a generált itemeket
    (és a botok vásárlását) eltolja; az alapértelmezett menet ráadásul már **sorsolja a
    környezetét** (a `--seed=5` az Ice Cave-et játssza). Példa, `godot --headless --fixed-fps 60
    --path . -- --smoke --waves=6 --seed=5`: az M6a fejen 587 gyilkolás (Forest Ruin, még sorsolás
    nélkül), az M6b funkciók után 603 (Ice Cave), a tartalom-csomagok után 607 (gold 215, 1 kovácsolt
    fegyver). A régi számokat csak az új adatfájlok nélkül lehet újra előállítani; a végső
    balansz-mátrixot ezért az M6b-s fejen újra kell futtatni.
  - **Nyitott kérdések M6b-re** (az ismert nyomáspontok; számszerű célok és mérések a
    végső balanszban készülnek):
    - **Flesh Golem sebzése:** az érintéses sebzése (4) és a horog (1×) a bot-futásokban a
      kapott sebzés nagy részét adja a 12. hullámtól, a spawnolt ellenségek kis részéből.
    - **A 20. hullám (elit-hullám):** minden ellenség elit-affixet kap (golemek
      Shielding / Vampiric affixszel, Enraged / Frenzied Axethrowerek); a három természetes
      bot-futás közül kettő (a 4 fős és a szóló) ezen a hullámon halt meg.
    - **Vor'thalax kill-ideje létszám szerint:** a boss HP-ja ×(1 + 0,75 (játékosok − 1)),
      de a csapat sebzése gyorsabban nő a létszámnál (itemek, Artifactok, fókusz), ezért a
      harc hossza létszámonként erősen eltér (egy-egy természetes bot-futáson: 4 fő ≈ 2
      perc, 3 fő ≈ 2,5 perc a vereség határán, a szóló bot ≈ 3,3 perc sok felélesztéssel). A
      `k`, az alap HP és a boss sebzése a hangolható kar; a hős-HP és az ellenség-sebzés viszonya is ide tartozik (a 25. hullámon az
      ellenség-sebzés ×45, a hősök HP-ja ennél lassabban nő: egy boss-támadás vagy a golem
      horga a törékeny hőst – Mage, Rogue – egy lövéssel ölheti; egy hős-HP-növekedési tag
      szintenként vagy Item Level-enként a lehetséges megoldás).
    - **Szóló és duó túlélés:** egyedül az első elesés vereség, a duó pedig nem tud
      éleszteni, ha mindkét hős elesik (a természetes futásokban a duó a 14. hullámon,
      a szóló hős a 20. hullámon halt meg); a csapatlétszám-sebzésszorzóhoz (fent) ezért
      a végső balansz nyúlhat.
    - **Artifact-kínálat:** a normál ölés esélye osztva a játékosszámmal (5.5), a várt szám
      számított érték; a 4 és 2 fős futásokat az összefésült fejen még nem mértük le, és az
      Artifactokat viselő bot Enchanter-szabálya (5.7) is a késői erőt módosítja (kevesebb
      Artifact kevesebb késői fegyversebzést jelent).
    - **A késői kassza:** az **M6a** goldsinkjei (Enchanter, fogyóeszközök, Black Market;
      16.1) célozták; hogy elég jól elviszik-e a goldot, a végső balanszban dől el.
    - **Az M6b új rendszereinek kiinduló számai:** az eseményeké (HP-szorzók, jutalmak, a 30%-os
      esély), a szentélyeké (hatások, az 5%-os esély), a környezeti veszélyeké (sebzés, gyakoriság), a
      Dungeoné (terem-ráták, a parázstartó HP-ja, a Warden, a jutalom, a bukás ára), az Endless
      (26+ hullám, Hardcore) nehézsége: mind kiinduló érték, és a végső balansz egyszerre hangolja a
      többivel. A botok a 16 hullámos smoke-futásokban szinte minden eseményt teljesítettek és a
      Dungeonokat megnyerték, a fejlesztői szintre állított Endless Hardcore futás viszont tömeges
      elesést mutatott (a hősök kezdő felszerelésben), amiből balansz-következtetés nem vonható le.
    - **Az M6b tartalom-áttekintéseiből gyűlt tételek** (az item-tartalom a számokat nem
      hangolta):
      - **Pajzsok halmozódása:** a különböző procokból érkező pajzsok korlát nélkül, összeadódva
        halmozódnak; az M6b a pajzsforrások számát 1-ről 8-ra növelte (Warding, Bulwarking,
        Gravewarded, Soul Lantern, Singing Bowl, …), ezért hős-szintű összes-plafon (pl. a Max HP
        50%-a) mérlegelendő.
      - **Iskola-torzítás:** a Scorching (+Fire) és a Glacial (+Frost) Equip-enchant minden
        kasztra sorsolódik, a Warrior / Rogue / Paladin számára holt stat; egy kaszt-iskola
        torzítás a `power_enchant_weight`-ben (a generátor Attack Power / Spell Power súlyozása
        mintájára) megoldhatja.
      - **Epic-only támadási sebesség:** a +10% csak az Epic sort illeti (4.1), így egy Legendary
        lassabban üt, mint az Epic, amelyből kovácsolták (a kardnál az Epic ütési ideje 0,82 mp, a
        Legendaryé 0,90 mp). A DPS-próbában (minden elsődleges stat 40) a Legendary sima
        támadásának DPS-e a tőrnél (104,0 az Epic 107,4-e ellen), a varázspálcánál (86,7 / 89,5), a
        Staffnál (78,0 / 80,5), az íjnál (76,7 / 77,5), a kardnál (64,4 / 65,0) és a buzogánynál
        (62,7 / 63,4) az Epicével egyenlő vagy alatta van, a pisztolynál, a baltánál és a két új
        kétkezesnél kb. +0,3%: a Legendary így csak a hatását, +3 statját és 2 enchantját éri.
        Döntés: marad az Epic-only (és a 4.1 kimondja), vagy Epic+ (`[0, 0, 0, 10, 10, 10]`,
        egysoros átírás).
      - **Ritkaság-inverzió:** az Epic Girdle of the Unyielding Layer (35% HP alatt 10 elnyelés 4
        mp-ig) erősebb a Legendary Bulwark of the Last Stand-nél (25% HP alatt 8 elnyelés 3 mp-ig);
        a Rare Cuffs of the Last Breath is közel áll a Legendaryhoz.
      - **Orb:** a statjai (+4 Spell Power, +1 Intellect) kiinduló értékek; a botok az item_score-ban
        a Spell Powert 1,0-val számolják, így egy Mage bot a Tome-ot (2 Int + 3 Crit) az Orbnál
        többre tartja. A Warlock a kétkezes Staff-fal indul, ezért az Orb (és a Tearglass) csak
        egykezes főkéz mellett vehető fel, a generátor mégis kínálja neki.
      - **Gold-bevétel:** a gold-find trinketek (Prospector's Pebble: 2 gold / 15 mp, kb. +10
        gold hullámonként) és a Breeches of the Light Fingers (6% × 3 gold ölésenként + Gold Find
        20, kb. +10% egy ölés goldjából) a késői kasszához adnak; a goldsinkek (16.1) mellett kell
        mérni.
      - **Nem hangolt tartalom:** az új utótagok (súlyok, arányok), a hand-made procok lapos
        számai (kivéve a Bracers of the Hidden Blade `hit_pct`-jét és a Max HP-arányos
        gyógyítást / pajzsot), a kétkezes fegyverek számai és a magasabb fokozatú páncél-alaptípusok
        (csak név és kinézet) kiinduló értékek; a késői hullámokban a lapos sebzésű procok
        tervezetten gyengék.
    - **Módszertan:** egy smoke „végigért” nem bizonyítja, hogy a boss legyőzhető (a
      smoke-biztosíték 210 mp-nél megöli): a mátrix olvasásakor a „TIMEOUT” sorokat külön kell
      számolni. Egy adat-módosítás is átrendezi az RNG-t, ezért az egyes seedek párjai
      zajosak, a következtetések az összesítésre épülnek.

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
  - **M6b – esemény, Dungeon, szentély:** a Guarded Chest (10×), a Goblin Caravan (40×) és a
    sikeres Dungeon (20×) a **hullám átlagos ellenség-goldjának** többszörösét adja (16.1,
    10.1); a **Shrine of Greed** +30%-ot ad a felszedett goldra, a **Shrine of Fortune** és
    a **Shrine of the Gambler** közvetlenül a kasszát változtatja (−25%, illetve ×1,5 / ×0,5);
    a Dungeon bukása a kassza 50%-át viszi el.
- **Ellenségenkénti gold:** 1 alap, elit 10, boss 50, Coin Gremlin lásd 8. fejezet.

**Koordinációs eszközök (hogy a közös kassza ne okozzon káoszt)**

- **Kívánságjelzés (Ping):** a játékos a jobb kar benyomásával (R3, billentyűzeten Tab)
  megjelölhet egy bolti ajánlatot vagy egy **Trainer-rangot**.
  - A bolti ping a játékos színével az ajánlaton látszik, és rerollnál megmarad.
  - A Trainer-ping a Trainer-soron látszik.
  - Mindkettő megjelenik a kassza melletti táblán: „*Wants: P2 [Rare Dagger] 62 g · P4 Fireball
    Rank III 45 g*”.
  - A megvásárlás vagy egy új kör törli a jelzést.
- **Vásárlás megerősítése:** ha a költés a kassza **több mint 50%-át** elvinné, 1 mp-ig nyomva
  kell tartani az „A” gombot. Ez véletlen nagy költés ellen véd.
  - Érvényes a bolti vásárlásra, a Trainer-rangra, az Enchanter-műveletre és a **Reset
    Talents**-re.
  - A Reset Talents-nél ehhez még egy megerősítő A is kell.
  - Rerollnál nincs nyomva tartás: a bolti reroll közös szavazás, a szintlépési reroll pedig
    kicsi összeg.
- **Kassza-tábla (Purse board):** a képernyő tetején, a kassza mellett. A gold **jobb oldalán**
  itt látszik a csapat **Glimmer Dust** készlete is (5.7): ibolya csillag-ikon és a szám (0-nál
  az ikon halvány; 1000 fölött rövidítve: „1.2k”, „12k”, „1.2M”, lefelé kerekítve). Ha a gold és
  a Dust együtt nem fér a pénztárca-oszlopba (pl. ötjegyű gold és háromjegyű Dust), a két szám
  betűmérete lépésenként kisebb lesz, az oszlop nem nő. Három része van:
  - **Ready-pipek:** minden játékosnak egy rombusz a színében, kitöltve, ha kész.
  - **Költésnapló** (csak ez a kör, a legújabb elöl, legfeljebb két sor, utána „+N more”): ki,
    mit, mennyiért. Pl. „*P1 [Rare Dagger] 62 · P2 Fireball Rank III 45 · Team Stall reroll
    12*”.
    - Minden költés benne van: bolti vásárlás, automatikus kovácsolás, bolti reroll
      („Team”), Trainer-rang, szintlépési reroll, talent-reset, valamint M6a-tól a
      fogyóeszköz (sima név), a Black Market (az item neve szögletes zárójelben, mint a bolti
      itemeké) és az Enchanter-művelet (a gold mellett a Dust-költség is a feliratban:
      „*P1 Empower Blazing (8 Dust) 48*”).
    - Az eladás és a Greed bevétele nem.
  - **Kívánságsor:** a bolti és a Trainer-pingek összesítve. Ha a költésnapló csak egy sort
    foglal, a kívánságsor a felszabadult második sort is használja.
  - A bolt saját visszajelző sora (a pult alján) is megmarad.
- **Ready-állapot:** a kassza mellett, a pipeken látszik, ki van már kész; a lenti ready-chipek
  (a visszaszámlálással) megmaradnak. A ready-t a B megszünteti, ha valaki még vásárolni akar.
- **Talentpont-jelzés:** a ready-chipen kis „★N” jelzi, ha a hősnek N szabad talentpontja
  van.
- **Egyidejű vásárlás:** ha két játékos ugyanabban a képkockában költene, és már csak az
  egyiknek jut fedezet, a kisebb sorszámú játékos nyer (P1 → P4). A gombnyomások sorrendje egy
  képkockán belül nem mérhető. A másik „*Not enough gold*” üzenetet kap, a naplóban egy
  bejegyzés lesz.

**XP**

- **Közös XP-sáv:** az egész csapat egyszerre lép szintet, mindenki kap választást.
- **M6b:** a sikeres **Defend the Totem** a hullám átlagos ellenség-XP-jének 25-szörösét adja,
  a **Shrine of Learning** +50% XP-t 3 hullámig (16.1).

**Item-loot:** lásd **10.1** (Need / Greed / Pass).

**Gold felhasználása (mind a közös kasszából):** item vásárlás (bolt), **ability rangemelés
(Trainer, 6.3)**, szintlépési reroll, bolti reroll, talent-reset; M6a-tól az Enchanter, a
fogyóeszközök és a Black Market is (16.1, „Goldsinkek”).

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
| Coin Gremlin | garantált 1 | Rare+, 25% eséllyel Epic+ |
| Boss (10. és 25. hullám) | **játékosonként 1** | Epic+, 20% eséllyel Legendary |
| Artifact (ritka) | lásd 5.5: boss 15% (bossonként egyszer), goblin 5%, elit 2%, normál 0,05% ÷ játékosszám – a 10. hullámtól | Artifact |
| Guarded Chest (M6b esemény) | a láda kinyitásakor 1 (+ 10× átlagos ellenség-gold) | Rare+ |
| Goblin Caravan (M6b esemény) | a kordé megölésekor 1 (+ 40× átlagos ellenség-gold) | Rare |
| Dungeon (M6b), sikeres | **játékosonként 1** (+ 50% eséllyel 1 extra tier set-darab a csapat egy kasztjának; + 20× átlagos ellenség-gold) | Epic |
| Shrine of Fortune (M6b) | **játékosonként 1**, azonnal, ingyen (16.1) | Epic |

Az események itemei a hullám végi Need / Greed / Pass dobásra mennek, mint minden drop; a
Guarded Chest itemje **a normál drop hullámlimitjén kívül** esik (Artifact-dobás nélkül). Az
esemény-itemek is lootzsákként esnek le, és ha senki sem veszi fel, a hullám vége a csapat közös
lootjába teszi (mint minden zsákot). A Dungeon itemeinek dobása a dungeon **után**, még a piac
előtt történik. A Dungeon ellenségei **nem** adnak goldot, XP-t, itemet, Artifactot (a Dungeonnak
saját jutalma van), de az ölések a sebzésmérőbe és a menet-statisztikába beleszámítanak.

**A földön**

- Az item **lootzsákként** esik le, a ritkaság színében világító fénynyalábbal
  (fehér, zöld, kék, lila, narancs; az Artifacté arany), így messziről is látszik, ha valami
  jó esett.
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

   - **A B-gomb felirata** követi az aktuális itemet: csapatban „Pass (all pass: 8 Dust)” –
     utalás, hogy ha mindenki passzol, az item Dust lesz (Artifactnál sima „Pass”); szólóban
     „Disenchant (8 Dust)” (Artifactnál „Leave”).
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
     eladási áron megy, ami jobb a normál 35%-nál, így a Greed is valódi jutalom. (Kivétel
     az Artifact: az az adott hullám Epic árának 5-szörösét adja, lásd 5.5.)
   - **Mindenki Passt nyom:** az item automatikusan **Disenchantolódik**: *Glimmer Dust* lesz
     belőle a csapat közös készletébe (ritkaságtól függően 1 / 2 / 4 / 8 / 16, lásd 5.7). Az
     Artifact kivétel: azt nem lehet Disenchantolni. A kovácsoláshoz nem kell anyag (4.1).
5. **Eredmény:** WoW-stílusú üzenetsor, pl.:
   „*P2 rolls 87 (Need) for [Stormcaller]*” → „*P2 wins [Stormcaller]*”. Ha mindenki Passolt:
   „*Everyone passed on [X] – disenchanted into 8 Dust*” (szólóban „*Disenchanted [X] into 8
   Dust*”); az Artifactnál (nem Disenchantolható) a régi szöveg marad („Left … behind” /
   „Everyone passed on …”).

**Különleges esetek**

- **Egy játékos:** nincs dobás, csak Take (A) / Sell (X) / Disenchant (B; Artifactnál Leave).
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

**Lobbyban** (M6b): Y = mód léptetése (Normal ↔ Endless), X = Hardcore ki / be – bármelyik
játékos megteheti. **Szentély-szavazáskor:** A = Accept, B = Decline.

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
(Hailstorm, Ember Rain), a mozgásos képességek (Charge, Blink) pedig **mozgásirányba**
indulnak.

---

## 12. Felület (UI)

**Csatlakozási képernyő**

- 4 hely; „Press A to join”; kasztválasztás karakter-előnézettel.
- **Módválasztás** (M6b): **bármelyik csatlakozott játékos** az **Y**-nal (billentyűzeten C)
  léptet a módok között (Normal ↔ Endless), és az **X**-szel (R) kapcsolja a **Hardcore**-t.
  A választás a fejléc **jobb szélén** áll a cím sorában („*Mode: Endless · Hardcore*”,
  mellette Hardcore-nál a HARDCORE jelvény), alatta a két gomb felirata; amíg senki nem
  csatlakozott, halványan. A fejléc magassága nem nő. Visszaszámlálás közben a módváltás a váltó
  játékost „nem kész”-re állítja, ezzel megszakítja a visszaszámlálást. A választás a következő
  menetekre is megmarad (16.1).
- **Sorsoló képernyő** („*Rolling the arena…*”, M6b): az indítás (a visszaszámlálás) után, a
  menet előtt:
  - a környezet-kártyák **vízszintes sora** (a lista 7 ismétlésben; festett kép, név,
    veszély-név, leírás) ease-out módon ~3,5 mp alatt lassul, és a kisorsolt kártyán áll meg,
    amely aranykeretet kap;
  - **1 mp szünet**, a cím „*The arena: <név>*”, alatta a veszély szabálya **legfeljebb két
    sorban**; ezután indul a menet;
  - **bármelyik játékos A / START gombja átugorja** (az első 0,6 mp-ben nem);
  - a képernyő a **futás magjához tartozó** környezetet mutatja (a környezetet a futásmagból
    számolt külön véletlenszám-generátor első húzása adja), így a kártya és a futás környezete
    szükségképpen egyezik;
  - smoke-futásban, demóban, `--view` futásban és tesztben kimarad; a `--env=<id>` az eredményt
    (a kártyát is) kényszeríti.

**Harci HUD**

- **Unit frame-ek** a 4 sarokban, WoW-stílusban:
  - portré, zöld HP-sáv,
  - erőforrás-sáv kaszt-színnel (Rage piros, Mana kék, Energy sárga, Resolve arany pipek, Pact Shard lila pipek),
  - ability-sáv: 2 alap + 2 tanult aktív + 4 auto-cast ikon, cooldown-animációval és
    rang-jelzéssel (I–V),
  - az aktív fogyóeszközök (16.1) kis ikonjai.
- **A hősök feje fölött:** névtábla („P1” + gyémánt a játékos színében) és alatta egy kis
  életerő-csík. A csík fix képernyőméretű, és a tömegen át is látszik.
  - Színe a HP szerint változik: zöld → sárga (50%) → piros.
  - Az elnyelő pajzs halványkék szakaszként látszik a HP után. Ha túlnyúlik, a csík végére
    rajzolódik.
  - Szellemként a csík eltűnik; ilyenkor a cast bar és a Grave Tender jelzései adnak
    információt.
- **Felül középen:** hullám száma, visszaszámláló, csapat-kassza. Boss-hullámon a
  visszaszámláló helyén a **boss-keret** áll: a boss neve, HP-sávja, fázis-pipek és
  „ENRAGED” felirat (8. fejezet).
- **Alul:** közös XP-sáv (WoW-lila).
- **Lebegő számok:** sebzés, krit (nagyobb, sárga), gyógyítás (zöld).
- **M6b kiegészítések:**
  - **HARDCORE jelvény** a HUD-n, ha a menet Hardcore módú: a felső tábla első sora (normál
    menetben nincs rá hely lefoglalva).
  - **Szentély-ikonok:** az aktív szentély-hatásokat (16.1) kis ikonok mutatják az arany alatt
    (Greed: érmék, Haste: villám, Learning: könyv, Blood: csepp, Fortune: lóhere, Gambler:
    kocka; 40 px), a hátralévő hullámok számával egy kerek jelvényen. A hullám-szalag a címe
    alatt soronként kiírja a futó szentélyeket („*Shrine of Greed: +30% gold, enemies +20%
    damage · 2 waves left*”).
  - **Esemény-szalag és névcédula:** a hullám közbeni esemény indulását szalag jelzi, és a kamera
    az esemény célpontját is képen tartja (16.1). Az esemény célpontján fix méretű **névcédula**
    áll (ládán „*Guarded Chest / N guards left*”, majd „*Stand here to open*”; totemen „*Totem /
    Hold 14 s*” + HP-sáv; kordén „*Goblin Caravan*” + HP-sáv). A cédula mindig a képernyőn és a
    HUD alatt / mellett marad: a kép szélén vagy sarokban a szabad terület széle mentén csúszik, és
    az objektum felé mutat.
  - **Dungeon:** a dungeonban a HUD hullámsora „*Dungeon – Room 2/4*”, alatta a terem
    feladata („*Kill enemies 12 / 25*”, „*Survive*”, „*Defend the brazier (80%)*”); az időzített
    termekben az időzítő helyén a terem visszaszámlálója áll, a Warden termében a boss-keret
    (16.1).

**Loot roll képernyő (közös)**

- **Elrendezés:** a hullám után a közös képernyő közepén egy nagy, WoW-szerű dobó-ablak
  jelenik meg: item-ikon, név a ritkaság színében, tooltip és visszaszámláló sáv.
- **Játékos-chipek:** alul 1–4 chip a játékosok színével. Mindegyiken látszik az upgrade-nyíl,
  a döntés állapota (pipa), majd a végén a dobás eredménye (kocka, érme vagy Pass ikon és a szám).
- **Jobb oldal:** üzenetsor a dobásokról, és egy „Items: 2 / 5” számláló.
- **Az item-keret** (és a tooltipje) a játékos-chipek felett marad, és nem takarja a „Loot
  Roll” címet, amennyire az látszik. A hétköznapi itemek (egyedi itemek, set-darabok, a 25.
  hullám véletlen dropjai) tooltipje ezért mindig **1,0-s léptékben** látszik: ha magas, a
  hely először a **cím-blokkból** jön, lépésenként (teljes cím alcímmel → egy kompakt, kisebb
  betűs sor alcím nélkül → nincs cím), és minden lépésnél a tooltip előbb **szélesebb** lesz
  (360 → 480 → 600 → 720 px, kevesebb töréssort ad; a keret vele nő). Csak ha a legszélesebb
  tooltip sem fér el cím nélkül, kicsinyedik (legfeljebb 0,5-ig; kisebb ablakon ez
  előfordulhat). Minden item újra a teljes cím-blokkal indul.
  - Az Artifact tooltipje (két tulajdonság-blokk) a legmagasabb: cím nélkül látszik, 1920×1080-on
    négy játékosnál mind az öt ≈ 0,99–1,0-s léptékben (a legalacsonyabb a Skull of the Damned,
    0,99). A törzsszöveg 20 px × lépték; a tesztelt alsó határ 0,85 (≈ 17 px).
  - Egy kétsoros Greed-eredménysor helye (48 px) mindig le van foglalva, így az eredménysor
    nem csúszik a chipek alá.
- Az Artifacton nincs zöld „Looted” felirat (nincs Looted +6 Item Level), a loot roll tooltipje
  (nincs néző hős) a teljes szöveget mutatja.

**Hullám utáni képernyő**

- **Sorrend:**
  1. loot roll (közös),
  2. (M6b) **szentély** – 5% eséllyel, közös kártya, szavazással,
  3. szintlépési kártyák (mindenki a sajátját, a saját negyedében),
  4. (M6b) **Dungeon-portál** – a 6., 9., 12. és 15. hullám után, csapatszavazással; belépés
     esetén a dungeon, utána a jutalom-dobás,
  5. közös bolt + személyes panelek egyszerre,
  6. Ready.
- **Szentély-kártya** (M6b): a szentély neve, az áldása és az átka; minden játékos szavaz:
  **Accept (A)** vagy **Decline (B)**. Csak az egyhangú elfogadás lép életbe; egy elutasítás
  vagy a **15 mp-es** időkorlát lejárta elutasítás (16.1).
- **Portál-szavazás** (M6b): „*A dungeon portal has opened!*” felirat és csapatszavazás; ha
  mindenki elfogadta, a csapat belép, egy elutasítás vagy a **20 mp-es** időkorlát kihagyja
  (16.1).
- **Fejléc:** a következő hullám sora: „Next up: Wave 4 of 25  ·  60 seconds”; a boss-hullám
  előtt másodperc nélkül („Next up: Wave 10 of 25 – Boss wave! (ends when the boss falls)”, 8.
  fejezet), az elit 20. hullám előtt „… seconds  –  Elite wave!” (piros).
- **Elrendezés:**
  - **Középen:** a **közös bolt** (goblin kereskedő standja) a játékosok színes kurzoraival,
    felül a reroll-szavazás pipái.
    - Az item-ajánlatok alatt áll a **fogyóeszköz-sor** (4 kompakt kártya), mellette jobbra, a
      15. hullámtól a **Black Market** arany keretes, széles kártyája (16.1).
    - A pult mérete 4 játékosnál sem nő: az item-kártya kisebb (124×176 px a korábbi 124×212
      helyett), így az 5×2-es item-rács, a fogyóeszköz-sor és a Black Market átfedés nélkül
      elfér az 1920×1080-as vásznon (az 1280×720-as ablak ugyanazt a vásznat kicsinyítve
      mutatja). A fogyóeszköz-sor 96 px magas és 652 px széles (az 5 oszlopos rács
      szélessége): Black Markettel 4 × 105 px és a 200 px széles Black Market kártya, nélküle
      4 × 157 px.
    - A Black Market kártyán a lakat nem takarja a nevet, a ping-címkék („P2 wants”) nem takarják
      az ikont: az ikontól jobbra, a név alatt jönnek, és ha a teljes sor nem fér ki, a rövid
      „P2” szöveget kapják.
    - A fogyóeszköz-kártya: ikon, ár (piros, ha nincs rá fedezet), név (kék: főzet, narancs:
      étel). Nincs játékosjelölő a kártyán: ki mit vett, azt a költésnapló mutatja, a hullám
      alatt pedig a hős unit frame-jén a kis ikonok.
    - **Kurzor:** a pozíciók egyetlen listában vannak: az item-ajánlatok, utánuk a
      fogyóeszközök, a legvégén a Black Market. Fel / le a rács és a sor között megy (a
      képernyőn x-ben legközelebbi kártyára), balra / jobbra a soron belül.
  - **A sarkokban:** 1–4 **személyes panel**, játékosonként egy.
  - LB/RB-vel lehet váltani a bolti kurzor és a saját panel között.
- **Személyes fülek:** **Trainer | Talents | Character | Enchanter** (az Enchanter a 4. fül).
- **Trainer fül:** a megtanult abilityk listája, a jelenlegi rang, a következő rang
  hatása, ára és egy „Train” gomb. A Rank V-nél a 2 specializáció közül lehet választani.
- **Talents fül:** WoW-szerű elrendezés – a 3 fa egymás mellett, tierenként sorokban.
  - Kontrollerrel rácsban lehet lépkedni; „A” = pont elköltése, „X” = az utolsó hullám óta
    elköltött pont visszavétele, „Y” = a következő rang előnézete (lásd 7.3).
  - Felül a szabad pontok száma, alul a „Reset Talents” gomb és az ára.
- **Enchanter fül** (M6a): a címkéje a csapat Dustját mutatja: „Enchanter (12)” – a Dustot a
  szám előtt egy rajzolt csillag-ikon jelzi (az UI-font nem tartalmazza a „✦” karaktert).
  - **Items:** bal oldalon az itemek **ikon-rácsban** (5 oszlop; fent a felszereltek –
    slot-sorrendben –, alatta a backpack); az ikon alatt apró pöttyök: egy tele pötty
    enchantonként, üres karika a szabad helyért. Ami az Enchantertől nem kaphat semmit (Common,
    Artifact, mindenre tiltott), halvány.
  - **Részletek:** jobb oldalon az item neve, fajtája (ritkaság, slot, Item Level, Equipped /
    Backpack), az enchantjai (rang I–V + név + zöld szöveg az adott rangon) és a következő
    művelet ára (gold + Dust, pirosan, ha nincs rá fedezet; a sor jobb szélén „Used 2x” /
    „Unused”). Az ár az item minden használatával duplázódik, a költésre a szokásos nyomva
    tartás vonatkozik (5.7, 10. fejezet).
  - **Irányítás:** nyilak az itemek közt; **A** vagy a rács jobb széléről a **jobbra** belép az
    enchantokba; ott fel / le választ, **A = Empower** (az Imbue soron **Imbue**), **X =
    Reroll**, **B** vagy **balra** vissza az itemekhez. A kiválasztott soron a zöld / piros
    előnézet megmutatja, mit ad az Empower (a következő rang szövegével) és mit a Reroll, vagy
    miért nem megy („Already Rank V”). A B az itemek között nem „felhasznált”, így a piac a
    Ready-t továbbra is vissza tudja venni.
- **Kovácsolás:** a Character fülön a fegyvert kiválasztva (A) egy műveletmenü jelenik meg:
  Equip / Forge / Sell / Disenchant / Trade / Cancel. A Forge csak akkor aktív, ha van azonos
  párja; különben szürke, és kiírja az okát (lásd 4.1). A **Disenchant** a Sell mellett áll, és
  Glimmer Dust-ot ad („+8 Dust”; 5.7), az utolsó fegyvernél szürke („Last weapon”); az Artifactnál
  nincs. A boltban üllő-pip jelzi a kovácsolható ajánlatot annak a játékosnak a színében,
  akinek van hozzá párja.
- **Character fül:** WoW-szerű karakterpanel – bal oldalon a páncélslotok, jobb oldalon az
  ékszerek és trinketek, alul a fegyverek, középen a karakter 3D modellje, alatta a statlista.
- **Backpack:** 10 hely a panel alján.
- **Tooltip:** pergamen / sötét keretes WoW-tooltip, felülről lefelé:
  - a ritkasághoz illő színű név, alatta „Looted” (az Artifactnak nincs), slot, páncéltípus, a
    fegyvernél sebzés és sebesség,
  - fehér stat-sorok,
  - **zöld enchant-sorok** („Equip: …”, „Chance on hit: …”, „On kill: …”, „When struck: …”),
  - set-bónuszok (szürkén, ha nem aktív),
  - Artifactnál a két különleges tulajdonság: a még zárt tulajdonság alatt „Awakens in N
    waves”, a nem tanult abilityhez kötött szürkén „(needs X)” (5.5),
  - legalul az összehasonlítás a felvett itemmel (+zöld / −piros).

  Az **Artifact tooltipje kompakt**, ha egy hőshöz kötött (játékos-panel, bolt): a tulajdonságok
  rövid szöveggel (legfeljebb 72 karakter), nincs flavor szöveg, nincs „Scales with” sor, nincs
  „Classes:” sor a saját kasztnál, a sorok szorosabban állnak, és az összehasonlítás
  eltéréseit egy törő sor mutatja. A sarokpanelekben így az Artifact tooltipje olvasható
  léptékben marad (≥ 0,85, négy sarokban, 1920×1080-on).
- **Indulás:** a „Ready” jelzés után indul a következő hullám, ha mindenki kész van
  (vagy 60 mp-es időkorlát után, beállításokban kikapcsolható).

**Győzelem / Vereség képernyő** (M6a)

A menet végén (Győzelem: Vor'thalax halála a 25. hullámon; Vereség: mindenki elesett) a képernyő
két oldalból áll, amik között váltani lehet. A képernyő mindig a Summaryn nyílik meg.

- **Oldalváltás:** bármelyik játékos **LB / RB** gombja (billentyűzeten **Q / E**) vagy a
  **bal / jobb** irány lapoz a Summary és a Damage Meter között; a végeken nincs körbefordulás.
  A botok és a megnyitáskor még nyomva tartott kar / gomb nem lapoz. Az **X** (billentyűzeten
  **R**) a Run kártyát menti, az **A / START** kilép – mindhárom a megnyitás utáni 1 másodperces
  késleltetés után működik. A prompt sor a billentyűzetes gombokat is mutatja: „LB RB / Q E / ◀ ▶
  Page”, „Save card” (X / R), „Back to Lobby” (A / Enter).
- **Panel mérete:** a Summary és a Damage Meter **ugyanolyan magas** panelben ül (a magasabbik
  oldal szabja meg, 7 díjnál a Damage Meter két díjsorával), így lapozáskor sem a cím, sem a
  panel nem mozdul; a rövidebb oldal (Summary) **függőlegesen középre** kerül.
- **Summary:** az eddigi összegzés (eredmény, elért hullám, loot-statisztika – 10.1) a négy
  csempe mellé ötödikként a **menet idejével** kiegészítve (a hullámidők összege, `m:ss`, egy
  óra felett `h:mm:ss`; a hullám utáni loot roll, a piac és a szünetek nem számítanak). A hős-tábla
  (hős, kaszt, ölések, sebzés) változatlan.
- **Damage Meter:** WoW-szerű sávok, 4 × 2 rács, statonként egy panel, benne hősönként egy sáv a
  kaszt színében (az onion bőrszíne, úgy korrigálva, hogy a szöveg olvasható maradjon; a bal
  szélén a játékos színe). A legtöbbet elérő van felül (döntetlennél a kisebb sorszámú), a sáv
  hossza az adott stat legjobb értékéhez viszonyított arány; a 0 érték üres, halvány sáv. A panel
  fejléce a csapat összegét mutatja (több hősnél). Az értékek 10 000-től „12.3k”, egymilliótól
  „1.25M” alakúak (a „999 960” nem „1000.0k”, hanem „1.00M”), a számlálók mindig egész számok.
  A „legtöbb” díjakhoz és a halvány sávhoz a **kijelzett**, egészre kerekített érték számít: a
  0,4 gyógyítás „0”-t mutat, ezért nem kap Most Healing díjat. Az oldalak:
  - **Damage** – kiosztott sebzés (az Execute-tal együtt; a túlütés nem számít),
  - **Healing** – a ténylegesen megkapott HP (a max HP-n túli rész nem), a gyógyítónak írva; a
    regeneráció, a Leech, a Life on Kill és a saját gyógyítás önmagára számít,
  - **Absorbed** – a játékos által rakott pajzsok (pajzs-procok, Call of Valor, Mending Touch,
    Gleaming Shield, Frozen Layer, Charge-pajzs, a Dawnbreaker pajzsa …) által a pajzs
    **tulajdonosának** írt elnyelt sebzés – bárkin –, valamint a saját blokk megmentette rész
    (a blokk nélküli és a blokkolt találat különbsége, a mitigáció után); a le nem járt, el nem
    használt pajzs nem számít,
  - **Taken** – a ténylegesen levont HP (a mitigáció és a pajzsok után, a túlütés nélkül); a
    kitért, hárított és a sérthetetlenség alatti ütés nem számít,
  - **Revives** – a csapattárs-csatornázás befejezésekor **minden** ott álló felélesztő kap egyet;
    a Call of Valor felélesztése a varázslót illeti; a hullámkezdéskori feléledés, a Spirit
    Healer és a smoke „mindenki feláll” nem számít,
  - **Downs** – elesések; **Kills** – ölések; **Bosses** – a boss halálos ütését adó játékos.
- **Awards** (csak co-opban, legalább 2 hősnél): a díjat az kapja, aki az adott statban a
  legjobb; döntetlennél a kisebb sorszámú játékos. A „legtöbb” díjakhoz **0-nál nagyobb** érték
  kell (ha senki sem gyógyított, nincs Most Healing). Egy hős több díjat is kaphat. A díjak a
  Damage Meter oldal alján, díjanként egy csempén látszanak (a díj neve, alatta a nyertes).

  | Díj | Ki kapja |
  |---|---|
  | **Most Damage** | a legtöbb kiosztott sebzés |
  | **Most Healing** | a legtöbb gyógyítás |
  | **Most Absorbed** | a legtöbb elnyelt sebzés |
  | **Guardian Angel** | a legtöbb felélesztés |
  | **Floor Inspector** | a legtöbb elesés |
  | **Exterminator** | a legtöbb ölés |
  | **Untouchable** | a legkevesebb elszenvedett sebzés a menet végén **élő** hősök között (ha mindenki elesett, nincs ilyen díj; ha a legkevesebb mindenkinél 0, a kisebb sorszámú kapja) |

- **Legjobb item** (a kártyához): a hős viselt és hátizsákban lévő itemei közül a legmagasabb
  ritkaságú, azon belül a legnagyobb item level, azon belül a legdrágább; egyenlőségnél a viselt,
  illetve a korábbi. A menet végén rögzítjük (a hősök a képernyő elhagyásakor felszabadulnak).
- **Run kártya:** a végképernyőn a „**Save card**” felirat (X / R) egy **1200×630**-as képet
  renderel: fent a játék címe és a mód („Normal mode”; a mód a `RunState.difficulty`-ből jön),
  alatta a **VICTORY / DEFEAT** felirat, jobbra az elért hullámok („25 / 25 waves”; vereségnél
  „Fell on wave N”, ahol N a hullám, amelyen a csapat elbukott) és az idő; alatta hősönként
  (legfeljebb négy) egy kártya: portré (az elesett hősé szürke), `P1 Warrior`, a legjobb item
  (a ritkaság színével, item level), a hős első díja (`+N`, ha több is van) és a Damage /
  Healing sor. A kép PNG-ként a `user://cards/run_<yyyy-mm-dd_hh-mm-ss>.png` fájlba kerül (ha
  ugyanabban a másodpercben másodszor mentenek, `_2`, `_3` … toldalék kerül rá).
  - A képernyő egy sorban kiírja, hová mentett („Saved to …”): a hosszú útvonal elejét „…”-ra
    rövidíti mappahatáron (a fájlnév és az utolsó mappák maradnak, pl. „Saved to
    …/SmartOnion/cards/run_2026-10-14_15-20-11.png”), így a panel nem szélesedik; a teljes
    útvonal a naplóba kerül. Hiba esetén „The card could not be saved.”.
- **M6b kiegészítések a végképernyőn:**
  - **Három oldal:** Summary, Damage Meter és **Leaderboard** (LB / RB, Q / E).
  - **Mód-sor:** a felirat alatt (a felirattal egy szoros csoportban) mindig áll egy sor, amely
    a környezetet mutatja a környezet színében („*Arena: Cemetery*”); Endless vagy Hardcore
    menetnél ugyanebben a sorban előtte az „*Endless mode*” / „*Normal mode*” felirat és a HARDCORE
    jelvény is áll, így a legmagasabb (Endless + Hardcore) panel is elfér 1080 px magasan.
    A run kártya jobb felső sora „*Normal mode  ·  Cemetery*”.
  - **Best sor:** a Summary a hős-tábla alatt a „*Best: …*” sort mutatja („Best: Wave 31 ·
    18:22”; Normalnál „Best: Victory · 24:10” / „Best: Fell on wave 18 · 9:40”); új
    helyezésnél „  –  New best!” az első helyen, egyébként „  –  This run: #3”.
  - **Ranglista oldal:** a menet kategóriájának (pl. „Endless · Hardcore · 4 players”) 10 helyét
    listázza: #, Result („Wave 31” / „Victory” / „Fell on wave 18”), Time, Party (kasztnevek),
    Date; az üres helyek kötőjelesek, az új bejegyzés sora arany keretes, „This run”
    jelzéssel, alatta megjegyzés-sor („*New entry: place 5 of 10.*” / „*This run did not reach
    the top 10.*” / „*No runs recorded in this category yet.*” / „*The leaderboard is not
    recorded in this session.*” / „*Could not save the leaderboard.*” pirossal, 16.1).

**Főmenü, beállítások, Credits (M7a)**

- **Főmenü:** Play / Settings / Credits / Quit, a fókusz körbeér. A Settings és a Credits a címképernyő fölé nyíló oldal; bezáráskor a fókusz visszakerül a gombra. Mivel még nincs csatlakozott játékos, az oldalakat bármelyik játékos vezérelheti (billentyűzet vagy bármelyik kontroller).
- **Szünetmenü:** Resume, Settings, Quit to Menu (a „Continue without Pn” ajánlatok mellett). A Settings oldalt a szüneteltető játékos kezeli; amíg nyitva van, a játék szünetel, a START nem léptet tovább, a B pedig a szünetmenübe visz vissza (a záró B nem léptet tovább a játékba is).
- **Settings oldal:** fel / le lép a sorok között, bal / jobb egy értéket állít, az A vált, léptet, illetve a *Reset to Defaults* és a *Back* gombot nyomja meg, a B visszalép. Egérrel az egér alatti sor kiemelődik, a nyilak (vagy az érték bal / jobb fele) állítanak.

| Szakasz | Beállítás | Értékek | Alapérték |
|---|---|---|---|
| Audio | Master / Music / Effects / Interface volume | 0–100 %, 10 %-os lépés (0 % = némítás) | 100 / 70 / 80 / 80 |
| Video | Window Mode | Windowed / Borderless Fullscreen / Fullscreen | Windowed |
| Video | VSync | On / Off | On |
| Video | Max FPS | 30 / 60 / 120 / 144 / Unlimited | Unlimited |
| Gameplay | Screen Shake | Off / Low / Full | Full |
| Gameplay | Damage Numbers | On / Off | On |
| Gameplay | Show FPS | On / Off | Off |

- **Hatás:** a beállítások csak a látványt és a hardvert érintik; egyik sem változtat játékszámot, és nem használ `RunState.rng`-t. Alapértéken a játék úgy működik, mint M7a előtt. A Screen Shake a kamerarázkódás szorzója (0 / 0,5 / 1); a Damage Numbers Off esetén a sebzésszámok nem jelennek meg (a többi lebegő felirat, pl. a „Dodge”, marad); a Show FPS a jobb felső sarokban „<n> FPS” feliratot mutat.
- **Mentés:** `user://settings.cfg`; minden változtatás azonnal érvénybe lép és mentődik. Hiányzó vagy ismeretlen érték az alapértéket kapja, a tartományon kívüli érték a határra kerül / a lépésre igazodik; olvashatatlan fájl esetén alapértékek és figyelmeztetés, a következő változtatás felülírja. Automatikus futtatásban (smoke, demo, `--view`, `--screenshot`) a fájl nem olvasódik és nem íródik, az ablak, a VSync és a FPS-limit sem változik.
- **Credits oldal:** a `CREDITS.md` tartalma (a hang- és zenecsomagok forrásai és licencei), a végén a Godot Engine neve, weboldala és MIT-licence szövege. Görgetés kontrollerrel, nyilakkal vagy az egérgörgővel; a B visszalép.

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
    Amíg van elesett játékos, a Grave Tender-t is képen tartja (1. fejezet).
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
- **Arénák** (M6b): menetenként **5 környezet** egyike, a menet elején sorsolva (a „Rolling the
  arena…” animációval, 12. fejezet), a menet végéig megmaradva (16.1):
  - **Forest Ruin** (erdei rom – a mai aréna, veszély nélkül), **Cemetery** (temető),
    **Swamp** (mocsár), **Volcano** (vulkán), **Ice Cave** (jégbarlang).
  - Mindegyiknek saját **veszélye** van (Grasping Hands, lápfoltok, lávakürtők, Falling
    Icicles; a szabályokat a 16.1 táblázata adja).
  - **Megjelenés:** környezetenként saját paletta (ég, köd, ambient fény, nap, talajszínek,
    falszín) és saját kellékkészlet, primitívekből építve: sírkövek, száraz fák és kripta;
    nád, zavaros tavak és mangrove; bazalt és izzó repedések; jégkristályok, hó és oszlopok.
  - Az aréna **mérete** minden környezetben ugyanaz, a draw-call keret a mai marad (összevont
    meshek / MultiMesh).
  - Az M6b a **tartalmat** adja (paletta, kellékek, veszélyek, sorsolás); a végleges látvány
    (assetek, shaderek, VFX) az M7b-ben készül.
  - A **Dungeon** külön, kis arénája (24 × 14 m) a menet környezetének palettáját használja,
    környezeti veszély nélkül (16.1): a Volcano kürtői ott nem látszanak (a falak elvágnák
    őket, és nem működnének).
  - **Mérések (megvalósítva):** a kellékkészletek draw-call kerete a mai marad (13–14
    összevont mesh az erdő 15-je mellett, a csúcspontok száma legfeljebb az erdő 1,5-szerese);
    a játéktéren **0,55 m-nél magasabb semmi nem áll** (a teszt őrzi); a végleges látvány az
    M7b-ben készül.

**Hang (M7a)**

- **Hangok:** UI-hangok (mozgás, megerősítés, vissza, hiba, nyitás / zárás, kártyák, kocka, vásárlás, eladás, felszerelés); fegyverhangok (könnyű, nehéz és kétkezes csapás, íj- és puskalövés, varázslat iskolánként); harchangok (találat, kritikus találat, ellenség halála normál / elit / boss, hős sebzése és elesése, felélesztés, szintlépés, kitérés, kivédés, blokk); loot- és világhangok (arany, XP, tárgy-dobás, láda, portál, goblin, banner); hullámhangok (hullám indul / tiszta, boss megjelenése, boss-előjelzés).
- **Zene:** négy sáv (menü, harc, köztes pihenő, boss), átfedő váltással (crossfade). A zene az állapottal együtt változik: a menüben és a lobbyban a menü-sáv; a hullámokon a harc-sáv, a boss-hullámokon a boss-sáv; a dungeonban a harc-sáv, a Dungeon Warden életében a boss-sáv; a hullámszünetben az intermission-sáv; Game Over alatt a zene elhalkul. A győzelem és a vereség rövid stinger.
- **Hangerő:** négy csatorna (Master, Music, Effects, Interface), a Settings oldal állítja; 0 % némít.
- **Korlátok:** minden hangnak van egyidejű darabszám-korlátja és minimális időköze; ha nincs szabad csatorna, egy alacsonyabb prioritású hang helyét át lehet venni, különben a hang elmarad. Ismeretlen hangazonosító csendben nem szól.
- **Játékmenet:** a hangok nem befolyásolják a játékmenetet; saját véletlenszám-generátort használnak (nem a `RunState.rng`-t), így a smoke-futamok eredménye a hangok nélkül is ugyanaz.
- **Licenc:** minden hang és zene CC0 1.0 (Kenney-csomagok és OpenGameArt-zenék); a forrásokat a `CREDITS.md` sorolja fel.

---

## 14. Jogi megjegyzés (szellemi tulajdon)

- **M7a:** az IP-tisztítást elvégeztük: a játék és a dokumentáció az új neveket használja, a fenti régi neveket csak felsorolásként idézzük; az átnevezési táblázat a „Kiadás és IP (M7 / M9)” részben van („Átnevezések (M7a)”).
- **Szabadon használható:** a stílus, a kasztnevek (Warrior, Mage, …), az általános
  stat-nevek és a ritkaság-színek.
- **Nem használjuk:** Blizzard-tulajdonnevek (Azeroth, Murloc, Thunderfury, Ashbringer,
  Horde/Alliance stb.), logók, eredeti assetek, a Friz Quadrata font.
- A dokumentumban `*`-gal jelölt nevek munkanevek, publikálás előtt cserélendők.
- **M6b:** minden új item- és enchant-nevet (5.8) ennek a listának a szerint ellenőriztünk,
  mielőtt bekerült a játékba. Ellenőrizve, egyik sem Blizzard-név: Thistlebrand, Boulderbloom,
  Tearglass (Forge Legendary); Two-Hand Sword, Two-Hand Mace, Orb (fegyverek); az új alaptípus-nevek
  (a 64 páncél-alaptípus, pl. Cuirass, Plate Carapace, és a 12 új ékszer), a 7 új utótag, a 26 új
  enchant-előtag, a 20 új trinket, a 17 új Legendary, a 60 új névvel ellátott és kaszt-specifikus
  item. A tesztek ellenőrzik (item-, alaptípus-, utótag-, set-nevek, enchant-előtagok és
  -leírások tiltott-listája; minden megjelenített név egyedi). Névütközések, amiket a névadáskor
  kikerültünk: a „Mending” enchant-előtag „Rallying” lett (az „of Mending” utótag miatt), a
  „Thorned” „Spiked” (az „of Thorns” miatt), a fagy-bot „Staff of the Deep Winter” (a
  Boulderbloom miatt). A „Rallying Sprint” és a „Spiked Wall” képesség neve közös szót használ az
  előtagokkal (más névtér, nincs működési ütközés).

---

## 15. Technikai architektúra (terv, nem kód)

**Adatvezérelt felépítés:** Godot Custom Resource-ok (`.tres`) a tartalomhoz.

- `ClassData`: alapstatok, páncéltípus, jártasságok, erőforrás, alap képességek, ability-készlet.
- `WeaponData`, `ItemData` (alaptípus + kézzel tervezett itemek), `AffixData` (utótagok).
- `EnchantData`: típus (Equip / Chance on hit / On kill / When struck), PPM vagy esély,
  belső cooldown, rangonkénti értékek, megengedett slotok, iskola.
- `AbilityData`: típus (Active / Auto), iskola-tag, rangok, specializációk, kaszt-kötés.
- `TalentTreeData` / `TalentData`: tierek, pontlimitek, előfeltételek, hatások.
- `SetData`, `EnemyData`, `WaveData`, `BossData`, `ConsumableData`, `DifficultyData`.
- `EnvironmentData` (M6b): az aréna-környezetek (paletta, kellékkészlet, veszély; 16.1);
  `ShrineData` (M6b): a szentélyek (áldás, átok, időtartam; 16.1). Az alaptípus kódbeli osztálya
  `ItemBase` (a fenti `ItemData` alaptípus-fele; M6b: `min_wave`, 5.4).

**Fő rendszerek**

| Rendszer | Feladat |
|---|---|
| `PlayerManager` | Eszközök (kontroller / billentyűzet) játékoshoz rendelése, csatlakozás / kilépés |
| `RunState` | Hullámszám, közös kassza, közös XP, játékosállapotok; M6b-től a mód (Normal / Endless, a menet hossza ebből jön), a Hardcore, a környezet és az aktív szentély-hatások |
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
| `EventSpawner` / `EnvironmentHazards` / `Shrines` / `Dungeon` (M6b) | A hullám közbeni események, a környezeti veszélyek, a szentélyek és a Dungeon-portál (16.1); mind saját véletlenszám-generátort használ, a `RunState.rng`-hez nem nyúl |
| `Leaderboard` (M6b) | A helyi ranglista modellje és fájl-I/O-ja (`user://leaderboard.json`, 16.1) |
| `Inventory` / `Equipment` | Backpack, slotok, set-bónuszok, Armor Specialization |
| UI | Játékosonkénti panelek |

**Projektstruktúra (tervezett)**

```
/project.godot
/data/        classes/ abilities/ talents/ weapons/ items/ affixes/ sets/ enemies/ bosses/ consumables/ waves/ difficulties/ environments/
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
- a **helyi ranglista** (M6b): `user://leaderboard.json`, verziózott, kategóriánként (mód,
  Hardcore, játékosszám) top 10 (16.1);
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
| M5 | Mélység | Talentfák (5 kaszt × 3 fa), fegyverkovácsolás, setek, elitek, Coin Gremlin, közös kassza |
| M6 | Tartalom | Mind a 7 ellenség, 2 boss + elit-hullám, Artifactok, **teljes item-tartalom (5.8)**, Enchanting, módok (Endless, Hardcore, ranglista), környezetek, események, szentélyek, Dungeon-portál, 25 hullám balansza (Normal) – **két részben szállítjuk: M6a (kész) és M6b (a végleges balansz kivételével kész)**, lásd alább |
| M7 | Csiszolás | **M7a – kész:** hangok (UI, harc, zene), főmenü (Settings, Credits), beállítások, IP-tisztítás (az átnevezési tábla a „Kiadás és IP” részben). **M7b – folyamatban:** grafikai réteg (assetek, shaderek, VFX) |
| M8 | Új kasztok | **Hunter** és **Shaman** (3.7): kasztok, petek / totemek, ability-készletek, talentfák, tier setek, Artifactok; új fegyvertípusok: Crossbow, Polearm, Fist Weapon; az M6b-ből átcsúszott **kaszt-független tier setek** (set-rendszer módosítással, 5.8) |
| M9 | Meta-progresszió (utolsó) | Fő profil, Class Level, glyphek, heirloomok, achievementek, transmog, Valor, The Onion Patch (menü) – 17. fejezet |

**Az M6 két részben jön**

- **M6a** – a rendszerek (**kész**):
  - alapok: Glimmer Dust a közös kasszában, menet-statisztikák hősönként (sebzés, gyógyítás,
    elnyelés, kapott sebzés, felélesztés, elesés, ölés),
  - a három új ellenség: Plague Ghoul, Cultist Acolyte, Flesh Golem (8. fejezet),
  - a két boss: Lich Commander Morvain (10. hullám) és Vor'thalax (25. hullám; a halála a
    győzelem), plusz a 20. hullám elit-hulláma (8. fejezet),
  - az Artifactok az öt jelenlegi kasztnak (5.5),
  - az Enchanter és a Glimmer Dust (5.7),
  - a goldsinkek: a fogyóeszköz-sor és a Black Market (16.1),
  - a Damage Meter, a díjak és a run kártya (12. fejezet),
  - balansz-kör **nincs**: az új tartalom a játékot nehezebbé tette, a hangolás egyszer, az
    M6b végén készül (9. fejezet).
- **M6b** – a tartalom és a módok (**kész, a végleges balansz kivételével**; a részletek a
  16.1-ben és a hivatkozott fejezetekben):
  - játékmódok: **Endless** mód, **Hardcore** mód, módválasztás a lobbyban, helyi ranglista
    (16.1; 1., 8., 12. fejezet),
  - az **5 aréna-környezet** saját veszélyekkel és a „Rolling the arena…” sorsoló animáció
    (13. fejezet, 16.1); a végleges látvány az M7b-ben készül,
  - **hullám közbeni események** (Guarded Chest, Defend the Totem, Goblin Caravan; 8. fejezet,
    16.1) és **szentélyek** (16.1),
  - a **Dungeon-portál**: 4 termes dungeon és a Dungeon Warden mini-boss (8. fejezet, 16.1),
  - a **tartalom-csomagok** (5.8): fegyver-alaptípusok +3 (**Two-Hand Sword**, **Two-Hand
    Mace**, **Orb**; a Crossbow, a Polearm és a Fist Weapon az M8-cal jön), páncél- és
    ékszer-alaptípusok, utótagok, 50 enchant, névvel ellátott és kaszt-specifikus itemek,
    30 trinket, 25 legendary; a kaszt-független tier setek az **M8-ra tolódtak** (a
    set-rendszer módosítását igénylik),
  - **az M6b egyik csomagja sem hangolt számokat:** minden szám az itt rögzített kiinduló
    érték, a meglévő értékek változatlanok (9. fejezet). Mivel az új tartalom a súlyozott
    sorsolásokba (utótagok, enchantok, fegyverek) is bekerült, az M6b előtt mért seedelt
    baseline-ok (smoke, balansz) a mai fejjel **nem összehasonlíthatók** (9. fejezet),
  - **hátravan:** a végleges 25 hullámos balansz (Normal), **egyszer, a legvégén**, az összes
    M6b-s tartalommal együtt. A nyitott pontok (9. fejezet, „Nyitott kérdések M6b-re”): a Flesh
    Golem sebzése, a 20. hullám elit-hulláma, Vor'thalax kill-ideje létszám szerint, a szóló
    és duó hősök túlélése, az Artifact-kínálat (÷ játékosszám, 5.5), és az M6b tartalom-
    áttekintéseiből gyűlt tételek (pajzs-halmozódás, Epic-only támadási sebesség, ritkaság-
    inverziók, Orb, gold-find trinketek, iskola-torzítás; lásd 9. fejezet).

### 16.1 Jóváhagyott ötletek (backlog)

A playtest után elfogadott bővítések, a tervezett mérföldkővel (az M6 két része: **M6a** és
**M6b**, lásd fent). A részletek a megvalósításkor kerülnek a megfelelő fejezetbe; az **M6b**
elemei **megvalósultak** (alább a terv, majd a „pontosítások” blokkja arról, ahogy a kód
működik; a számok kiinduló értékek, az M6b nem hangolt).

| Ötlet | Mit jelent | Mérföldkő |
|---|---|---|
| **Szellem-lassítás** | Az elesett játékos felélesztési körében (ahol a társ felélesztést csatornáz) az ellenségek **33%-kal lassabbak**, így a felélesztő nem marad védtelen | **Kész (M5)** – 1. fejezet, „Elesés és halál” |
| **Sebzésmérő és díjak** | WoW-szerű damage meter a menet végén (sebzés, gyógyítás, elnyelt sebzés, kapott sebzés, felélesztések, elesések, ölések) és díjak: „Most Damage”, „Guardian Angel”, „Floor Inspector” stb. – részletek: 12. fejezet | **Kész (M6a)** |
| **Menet végi összefoglaló kártya** | Megosztható kép („Save card”): kasztok, elért hullám, idő, legjobb itemek, díjak – részletek: 12. fejezet | **Kész (M6a)** |
| **Véletlen környezet menetenként** | 5 féle aréna-környezet: erdei rom, temető, mocsár, vulkán, jégbarlang – saját veszélyekkel és saját palettával, kellékkészlettel; a menet elején egy „Rolling the arena…” sorsoló animáció (vízszintes kártyasor, mint egy skin-nyitás) sorsolja ki, és a menet végéig az marad | **Kész (M6b)** (a tartalom; a végleges látvány: M7b) |
| **Hullám közbeni események** | Őrzött kincsesláda (Guarded Chest), megvédendő totem (Defend the Totem), elfogandó „Goblin karaván” – véletlenszerűen, jutalommal | **Kész (M6b)** |
| **Szentélyek a hullámok között** | Kockázat / jutalom választás (pl. „+30% gold, de az ellenségek +20% sebzést okoznak 3 hullámig”); **csak 5% eséllyel** jelenik meg egy szünetben, és minden játékosnak el kell fogadnia | **Kész (M6b)** |
| **Végtelen mód (Endless)** | A 25. hullám után folytatható, egyre nehezebb hullámokkal, a 30. hullámtól 5 hullámonként bossal | **Kész (M6b)** |
| **Hardcore mód** | Nincs Grave Tender: csak a társak tudnak feléleszteni | **Kész (M6b)** |
| **Módválasztás és helyi ranglista** | A lobbyban választható mód (Normal / Endless) és Hardcore-kapcsoló; módonként, létszámonként helyi top 10 | **Kész (M6b)** |
| **Dungeon-portál** | Opcionális dungeon a 6., 9., 12. és 15. hullám után (részletek lent) | **Kész (M6b)** |
| **Item-tartalom csomagok** | 3 új fegyver (Two-Hand Sword, Two-Hand Mace, Orb), 96 páncél- és 20 ékszer-alaptípus (anyag-fokozatok), 25 utótag, 50 enchant, 40 névvel ellátott és 40 kaszt-specifikus item, 30 trinket, 25 Legendary (5.8) | **Kész (M6b)** |
| **Goldsinkek** | Enchanter, fogyóeszközök saját bolti sorral, Black Market a 15. hullámtól – hogy a késői gold is döntést jelentsen (részletek lent) | **Kész (M6a)** |
| **Végleges 25 hullámos balansz** | Egyetlen hangolási kör az M6b végén (az M6a nehezebbé tette a játékot, és a számok addig kiinduló értékek; **az M6b csomagjai sem hangolnak**); a nyitott pontok a 9. fejezetben | **M6b** (a legvégén) |
| **Remote Play Together** | A helyi co-op online is működjön (Steam) | A legvégén, M9 után |
| **Meta-progresszió bővítések** | Önkéntes nehezítések, heti kihívás, receptkönyv, hagymafajták, kezdőfegyver-választék, bestiárium, mini-petek, Paragon-szintek – részletek: 17.8 | A legeslegvégén, a Remote Play Together után |
| **IP-tisztítás (Blizzard)** | Minden WoW-ból / Blizzard-játékból átvett név lecserélése saját névre, hogy ne legyen IP-ütközés – részletek lent („Kiadás és IP”) | **Kész (M7a)**, a Steam-oldal előtt |
| **Steam-kiadás** | Early Access az M7 után, teljes kiadás az M8–M9 után – részletek lent („Kiadás és IP”) | M7 (Early Access), M9 (teljes) |

**Játékmódok: Endless és Hardcore (M6b)**

- **Módválasztás:** a lobbyban **bármelyik játékos** az **Y**-nal léptet a módok között
  (**Normal** ↔ **Endless**), és az **X**-szel kapcsolja a **Hardcore**-t; a két kapcsoló
  független. A lobby fejlécében mindig látszik az aktuális választás („*Mode: Endless ·
  Hardcore*”, 12. fejezet). Indítási kapcsolók: `--mode=normal|endless`, `--hardcore`.
- **A menet hossza a módból jön:** Normal 25 hullám, Endless korlátlan (a kódban
  `RunState.total_waves()`: 25, illetve 0 = korlátlan; az „utolsó hullám” Endlessben sosem
  igaz). Nincs több beégetett 25-ös szám.
- **Endless:**
  - **Indulás:** a 25. hullámon Vor'thalax halála **nem** zárja le a menetet: „*Endless
    begins!*” szalag, és jön a 26. hullám. (Normalban ez továbbra is a győzelem.)
  - **A 26. hullámtól:** a hullámhossz legfeljebb **210 mp**, az ellenségek növekedési
    képletei változatlanul folytatódnak (9. fejezet).
  - **Bossok:** a 30. hullámtól **minden 5. hullám** boss-hullám, váltakozva **Morvain** (30.,
    40., …) és **Vor'thalax** (35., 45., …), a szokásos hullám-skálázással (8. fejezet).
  - **Elit-hullám:** a 20. hullám szabálya a **33., 43., 53. …** hullámon ismétlődik.
  - A bolt és a piac a szokásos módon működik (a szentély és a Dungeon-portál szabályai lent).
  - A menet **csak vereséggel ér véget**; a ranglista az elért hullámot rögzíti.
- **Hardcore:**
  - **Nincs Grave Tender** (az aréna nem hozza létre): csak a társak tudnak feléleszteni.
  - Az elesett hős keretén a Grave Tender-hez irányító felirat helyett: „*Only a teammate can
    revive you*”.
  - Az elesett hősök a **következő hullám elején** így is visszatérnek (50% HP-val), mint
    Normalban.
  - **HARDCORE jelvény** a HUD-n, a lobbyban és a végképernyőn; **külön ranglista-kategória**.
  - **Szóló Hardcore = szóló Normal:** egyedül az első elesés amúgy is a menet vége.

**Helyi ranglista (M6b)**

- **Hol:** helyi fájl, `user://leaderboard.json`, verziózott formátummal.
- **Kategóriák:** minden (mód, Hardcore, játékosszám) hármasra külön **top 10**.
- **Egy bejegyzés:** az elért hullám (Endless) vagy a győzelem ideje (Normal), a kasztok, a
  dátum és hogy győzelem volt-e.
- **Mikor ír:** a menet végén. Smoke-futás, demó és teszt **nem ír**, hacsak egy teszt nem állít
  be ideiglenes útvonalat.
- **Végképernyő:** a „*Best: …*” sor és a menet kategóriájának táblája, az új bejegyzés
  kiemelve (12. fejezet).
- **Felépítés:** tiszta adatmodell és egy fájl-I/O segéd; ideiglenes útvonalon tesztelhető.

**Helyi ranglista – pontosítások (M6b, megvalósítva)**

- **A bejegyzés** `{wave, time, classes, date, victory}`: a `wave` a menetet lezáró hullám
  (győzelemnél az utolsó megnyert), a `time` a hullámokban töltött idő (**a Dungeon nélkül**: a
  menet órája csak hullám közben jár). Kategóriánként legfeljebb 10 bejegyzés.
- **Rangsor:** a későbbi hullám a jobb; azonos hullámon a **hosszabb** túlélési idő (győzelemnél a
  **rövidebb** idő). Az Endless menetek és a Normal vereségek hullám, majd hosszabb idő szerint
  rangsorolnak.
- **Feladás:** a normál menet feladása (Quit to Menu) nem kerül a listára. Endless menetnél a
  feladás (vagy az utolsó hős kiesése a kontroller kihúzása miatt) a folyamatban lévő hullámmal,
  vereségként felkerül (végképernyő nélkül), de csak ha a menetben legalább egy hullámot
  kitisztítottak: az első harcban feladott (vagy későbbi kezdőhullámról indított és kitisztított
  hullám nélkül feladott) menet nem eredmény.
- **Mikor érinti a fájlt:** teszt (alapból) nem olvas, nem ír. Smoke futás a `--leaderboard` nélkül
  sosem írja és nem is olvassa a játékos ranglistáját; a demó / `--view` / képernyőkép-futás mutatja,
  de nem írja. A `--leaderboard=<útvonal>` saját fájlt ad, amelyet **minden** futás ír.
- **Sérült fájl:** hiányzó fájl = üres lista; törött fájl `.corrupt` néven félreáll; újabb verziójú
  fájlt a játék nem ír felül (a lista üres és csak olvasható); az írás ideiglenes fájlon és
  átnevezéssel történik. Ha a bejegyzés felkerült, de a mentés nem sikerült, a Leaderboard oldal
  pirosan jelzi.

**Aréna-környezetek és a sorsoló animáció (M6b)**

- **Öt környezet** (`EnvironmentData` adat a `data/environments/` mappában), menetenként
  egy: a menet elején sorsolódik, és a menet végéig megmarad. Az aréna **mérete nem
  változik**. A tartalom az M6b-ben készült (paletta, kellékek, veszélyek), a végleges látvány
  az M7b-ben.

  | Környezet | Veszély | Szabály (kiinduló értékek) |
  |---|---|---|
  | **Forest Ruin** (erdei rom) | – | A mai aréna, nincs veszély |
  | **Cemetery** (temető) | **Grasping Hands** | ~9 mp-enként 2–3 jelzett kör (1,5 m sugarú) jelenik meg a hősök alatt; 1 mp figyelmeztetés után a kezek 1,2 mp-re **gyökerezik** a hőst, és a grunt-érintéses sebzés 0,5-szörösét okozzák |
  | **Swamp** (mocsár) | **Bog pools** | Menetenként 5, a helyükön álló lápfolt: bent a hősök mozgássebessége **−30%**, az ellenségeké **−15%** |
  | **Volcano** (vulkán) | **Lava vents** | 6 fix kürtő, mindegyik ~8 mp-enként kitör (1 mp figyelmeztetés, 2 m sugár); a grunt-érintéses sebzés 1,5-szeresét okozza a hősöknek **és az ellenségeknek** |
  | **Ice Cave** (jégbarlang) | **Falling Icicles** | ~7 mp-enként 3 jelzett kör (1,2 m sugarú) a hősök közelében; a grunt-érintéses sebzés 1-szerese és 30% lassítás 1,5 mp-re |

- **Veszélyek közös szabályai:**
  - A „grunt-érintéses sebzés” a Skeleton Grunt érintéses sebzése az adott hullámon: a hullám
    ellenség-sebzés növekedését és a csapatlétszám-sebzésszorzót is használja (9. fejezet).
  - **Boss-hullámon** a veszélyek **fele gyakorisággal** futnak.
  - Minden veszély ellenség-veszélyzónának számít: a botok kikerülik, és a hullám vége
    eltünteti (8. fejezet, „Veszélyzónák és a botok”).
- **Megjelenés:** környezetenként saját **paletta** (ég, köd, ambient fény, nap, talajszínek,
  falszín) és saját **kellékkészlet**, primitívekből építve:
  - Cemetery: sírkövek, száraz fák, kripta;
  - Swamp: nád, zavaros tavak, mangrove;
  - Volcano: bazalt, izzó repedések;
  - Ice Cave: jégkristályok, hó, oszlopok;
  - Forest Ruin: a mai kinézet.

  A draw-call keret a mai marad (összevont meshek / MultiMesh).
- **Sorsolás:** a menet futásmagjából számolt **külön véletlenszám-generátorral** történik.
- **Sorsoló animáció:** a lobbyban az indítás után a „*Rolling the arena…*” képernyő:
  - a környezet-kártyák **vízszintes sora** (ismétlődve) ~3,5 mp alatt lassul, és a
    kisorsolt kártyán áll meg;
  - 1 mp szünet, majd indul a menet;
  - smoke-futásban, demóban és tesztben kimarad.
- **Kijelzés:** a környezetet a run kártya és a végképernyő is mutatja (12. fejezet).
- Debug: `--env=<id>` a kisorsolt környezetet kényszeríti.

**Aréna-környezetek – pontosítások (M6b, megvalósítva)**

- **Sorsolás:** a menet környezete a futásmagból számolt külön generátor **első** húzása
  (súlyozva, `roll_weight`; a 0 súlyú sosem nyer); smoke-futásban is sorsolódik (a `--env`
  kényszeríti), így a CI a magokon át az összes környezetet lefedi (az `--smoke --seed=5` az
  Ice Cave-et játssza; `--env=forest_ruin` a régi arénát).
- **Grasping Hands:** az első kéz-kör ~4 mp-nél jelenik meg, utána 9 mpenként; a körök mindig
  **különböző hősök alatt** vannak (véletlen sorrendben); ha kevesebb a hős, mint a kör, a többlet
  1,6–2,8 m-re a hős mellett. Gyökerezés alatt a hős **támadhat és varázsolhat**, csak járni nem tud;
  a becsukódott kezek nem sebeznek újra, a botok sem kerülik őket.
- **Swamp:** a lápfolt 2,3 m sugarú; menetenként ugyanaz az 5 hely (az első hullámnál sorsolódnak: a
  középtől ≥ 4,5 m, faltól ≥ 3 m, egymástól ≥ 6 m); **boss-hullámon 3 folt** van; a lassítás a
  kilépés után még 0,35 mp-ig tart; a botok enyhén kerülik; nem sebez.
- **Volcano:** a 6 kürtő **fix helyen** áll (±12 / 0 m x, ±6 / ±8 m z körül) és az aréna-tisztáson
  mindig látszik; az első kitörések az első 8 mp-es ciklusra szétosztva indulnak; az ellenségek
  sebzése nem ad kill-krediteket, de a menet kill-számlálójába beleszámít.
- **Ice Cave:** a kör a hőstől 0,8–3,2 m-re jelenik meg, hősönként egy, körbejárva; az első jégcsap
  ~3 mp-nél esik; a lassítás külön hatás (`ice_chill`) a Morvain-féle fagyás mellett; a
  jégcsap-kör **sötétkék** (sötét körvonallal).
- **Olvashatóság:** minden veszély jelölőjének a **saját környezete talajától** legalább **2:1
  fényerő-kontrasztot** (WCAG) kell tartania a talaj minden tónusához képest; a teszt őrzi. A lápfolt
  a sötét ovális alakjáról olvasható (nem figyelmeztető kör).
- **Hatókör:** minden veszély a **hullám végén** eltűnik, és a rajtuk lévő hatás (lassítás,
  gyökerezés) véget ér. **Veszély csak futó hullámban van: a szünetben és a Dungeonban nincs.**
  Boss-hullámokon (az Endless 30., 35. … hullámán is) a veszélyek fele gyakorisággal működnek.

**Hullám közbeni események (M6b)**

- **Mikor:** a **4. hullámtól**; **soha** nem boss-hullámon, a 20. hullámon és az elit-szabályú
  hullámokon (Endlessben a 33., 43., 53. …); minden jogosult hullámon **30%** eséllyel, egy
  hullámban **legfeljebb egy**. Az esemény saját véletlenszám-generátorral sorsolódik, a hullám
  **20–40%-ánál** indul, szalag jelzi, és a kamera a célpontot is képen tartja.
- **Guarded Chest** (őrzött láda):
  - A láda körül **4 őr** áll: az adott hullámon jogosult ellenségtípusok, ×2 HP-val,
    affix nélkül.
  - Ha az őrök meghaltak, a ládánál **1,5 mp-ig** álló hős kinyitja.
  - **Jutalom:** egy **Rare+** item (a hullám végi Need / Greed / Pass dobásra megy, nem számít
    a normál drop hullámlimitjébe) + a hullám átlagos ellenség-goldjának **10-szerese**.
  - Ha nem nyitják ki, a hullám végén eltűnik.
- **Defend the Totem** (megvédendő totem):
  - Egy szövetséges totem; HP-ja a hullám Skeleton Gruntja HP-jának **30-szorosa** a csapatméret
    szerinti HP-szorzóval (9. fejezet). A **8 m-en belüli** ellenségek rá támadnak.
  - Ha **20 mp-ig** életben marad: minden hős **+15% sebzést** kap a hullám végéig, és a csapat
    a hullám átlagos ellenség-XP-jének **25-szörösét** kapja.
  - Ha elesik, nincs semmi jutalom.
- **Goblin Caravan** (Goblin karaván):
  - Egy kordé **3 őrrel**, ami ~25 mp alatt átkel az arénán a szélétől a széléig; a kordé
    HP-ja a hullám Skeleton Gruntja HP-jának **40-szerese**.
  - **Megölve:** a hullám átlagos ellenség-goldjának **40-szeresét** szórja szét, és egy
    **Rare** itemet ad.
  - A túloldalon elszökik: „*The caravan got away*”.
- **Botok:** az esemény őreivel a szokásos módon harcolnak, kinyitják a ládát, a totemet
  őrzik (6 m-en belül maradnak), és a kordét üldözik, ha nincs ellenség a közelben.
- **Jutalmak és ellenségek részletei:** 8. fejezet (esemény-ellenségek), 10.1 (loot).

**Hullám közbeni események – pontosítások (M6b, megvalósítva)**

- **Hely:** a láda legalább 10 m-re kerül a hősöktől (a falaktól annyira, hogy az őrök köre elférjen),
  a totem legalább 4 m-re; mindkettő lehetőleg a képernyőn, a HUD-on kívül. Az esemény fajtáját,
  kezdési idejét, az őrök típusát, a kordé oldalát és sávját az esemény saját generátora sorsolja (a
  menet-maggal reprodukálható); a láda és a totem pontos helye a hősök aktuális állásától is függ.
  Esemény csak a 4. hullámtól van, a boss- és elit-szabályú hullámokon soha.
- **Guarded Chest:** a nyitás előrehaladása nem nullázódik, ha a hős kilép a 2 m-es körzetből:
  ugyanolyan gyorsan csökken (a leütött hős nem számít). Az item lootzsák a láda előtt (a Need /
  Greed / Pass dobás a hullám végén); az arany érmékben hullik a láda körül.
- **Defend the Totem:** a +15% sebzés a hullám végéig tart (a hullám végén, illetve a következő
  hullám sorsolásakor lekerül); az XP-t a hősök felszedik, a fel nem szedettet a hullám vége a közös
  sávba írja.
- **Goblin Caravan:** a megölt kordé az aranyat érmékben szórja szét, az itemet (Rare, nem
  Artifact-dobás) lootzsákban; a „*The caravan got away*” szürke szalag, jutalom nélkül.
- **Szalagok (angolul):** *A guarded chest appeared!* / *The chest was opened!* · *Defend the
  totem!* / *The totem holds!  +15% damage* / *The totem fell* · *A goblin caravan is crossing!* /
  *The caravan was plundered!* / *The caravan got away*.
- **Botok:** a nyitható ládához teljes erővel mennek, és ráállva nem mozognak (csak veszély tolja el
  őket); a zárt láda táborához (7 m) is odamennek, ha nincs körülöttük ellenség és elég HP-juk
  van; a totemtől 5 m fölött visszahúzza őket (minél távolabb, annál erősebben; a 6 m-en kívüli bot
  a körülötte maradt ellenségek hátrálási tolásánál is erősebben; a totemre csalt ellenségek elől az
  5 m-en kívüli bot nem hátrál – ők a totemhez mennek, nem a botokhoz); a kordét 40 m-ről
  üldözik, ha 3 m-en belül nincs ellenség, és nem hátrálnak előle. Veszély, horog-kitérés és
  felélesztési futás a totem-őrzésnél előbbre való.
- **Debug:** `--event=<id>` a rövid neveket is érti (`chest`, `totem`, `caravan`); minden esemény
  naplósort ír (a Main naplóján át, csak smoke / demo / view futásban: `SMOKE EVENT …`).

**Szentélyek a szünetekben (M6b)**

- **Mikor:** minden szünetben **5%** eséllyel (a menet utolsó hulláma után nem), saját
  véletlenszám-generátorral. A szünet új fázisa a **SHRINE**, a loot roll és a szintlépés
  **között** (12. fejezet).
- **Szavazás:** egy kártya mutatja a szentély áldását és átkát; **minden játékos** szavaz:
  **Accept (A)** vagy **Decline (B)**. Csak akkor lép életbe, ha **mindenki elfogadta**; egy
  elutasítás vagy a **15 mp-es** időkorlát lejárta elutasítás.
- **Hatások** (a „3 hullámig” hatások a következő 3 hullámra szólnak):

  | Szentély | Áldás | Átok |
  |---|---|---|
  | **Shrine of Greed** | +30% felszedett gold (3 hullámig) | az ellenségek +20% sebzést okoznak |
  | **Shrine of Haste** | +15% Haste (3 hullámig) | az ellenségek +15% sebessége |
  | **Shrine of Learning** | +50% XP (3 hullámig) | az ellenségek +25% HP-ja |
  | **Shrine of Blood** | +20% sebzés (3 hullámig) | −20% Max HP |
  | **Shrine of Fortune** | minden hős kap egy **Epic** itemet, azonnal | a kassza **25%-át** azonnal elveszti |
  | **Shrine of the Gambler** | 50% eséllyel a kassza ×1,5 | különben a kassza ×0,5 (azonnal) |

- **HUD:** az aktív szentély-hatásokat kis ikonok mutatják, a hátralévő hullámok számával.
- **Botok:** a Greed, Haste, Learning és Blood szentélyt elfogadják, a Fortune-t és a Gamblert
  elutasítják.
- Debug: `--shrine-chance=X` felülírja az 5%-os esélyt.

**Szentélyek a szünetekben – pontosítások (M6b, megvalósítva)**

- **A hatások csak hullám közben élnek:** a gold- és XP-bónusz, az ellenségek erősödése, a hősök
  bónuszai a hullám elejétől a végéig érvényesek; a szünetben, a boltban és a **Dungeonban nem**, és a
  Dungeon **nem hullám**: nem számol le egyet sem a szentély hátralévő hullámaiból, de a szentély a
  Dungeon után a következő hullámban újra él. A „3 hullám” az elfogadás utáni következő 3 **hullám**;
  a HUD-jelvény a még lejátszandó hullámok száma (a futóval együtt).
- A szünet sorrendje: loot → **szentély** → szintlépés kártyák → **portál** (→ Dungeon → a Dungeon
  Epic-jeinek Need / Greed / Pass dobása) → piac. A szentély az **Endlessben** is 5% eséllyel jelenik
  meg minden szünetben (a 26. hullám után is); a normál menet utolsó hulláma után nincs szünet.
- **Egy már futó, időzített szentély nem jelenik meg újra** (a Fortune és a Gambler bármikor); több
  futó szentély hatása összeszorzódik.
- **Gold- és XP-bónusz:** a felszedett (és a hullám végén bankolt) goldra / XP-re vonatkozik; a töredék
  nem vész el. Fix jutalmakra (esemény, Greed-eladás, Gambler) nem hat. A **boss HP-ját** is növeli a
  Learning.
- **Fortune:** először a kassza 25%-a (lefelé kerekítve) elvész, aztán minden hős kap egy, az osztálya
  által használható **Epic** itemet; tele hátizsáknál az item azonnal eladódik (Greed-érték), **egy
  közös sorban** („*Backpacks full: 3 items sold for 201 gold*”). **Gambler:** 50%-os érme; nyerés: a
  kassza fele jön hozzá, vesztés: a fele elvész. A „*purse is empty*” csak 0 goldnál áll, kis
  kasszánál „*too small*”.
- **Szavazás:** A = Accept, B = Decline; az Accept visszavonható B-vel, a Decline végleges és azonnal
  elutasítja. 0,4 mp-ig a gombok nem számítanak. A kapcsolat nélküli kontroller botként szavaz. Emberi
  játékos mellett a botok legalább ~1 mp-et várnak. A döntés ~2,4 mp-ig látszik („Accepted by
  everyone” / „P2 declined – the shrine fades” / „Time ran out – the shrine fades”), csak botokkal
  azonnal megy tovább a szünet.
- A Haste hátránya „*Enemies move 15% faster*” (az előjel az irány; lassító szentélynél „slower”).
- A teszt-futtató az alap 5%-ot 0-ra állítja; a tesztek a `--shrine-chance` megfelelőjét használják.

**Kiadás és IP (M7 / M9)**

- **Állapot (M7a):** az IP-tisztítás kész – a játék, az adatok és a dokumentáció az új neveket használja (kivéve a tervezett M8-as neveket és a Blizzard-márkát), a tiltott nevekre a `tests/test_m7_ip_names.gd` teszt őrködik, az új nevek listáját pedig az alábbi „Átnevezések (M7a)” táblázat adja.
- **IP-tisztítás – cél:** a játékban (UI, adat, tooltip, GDD) ne maradjon olyan név, amely
  a Blizzard játékaiból (WoW, Diablo, Hearthstone, Overwatch) egy az egyben átvett tulajdonnév
  vagy jellegzetes kifejezés. A WoW-hangulat maradhat (onion-paródia, általános fantasy
  szavak), de a konkrét nevek nem.
- **Mit kell átnézni:**
  - **Ability-nevek**, amelyek egy az egyben WoW-varázslatok – pl. *Blizzard* (ez a cég neve
    is), *Vanish*, *Consecration*, *Word of Glory*, *Light of Dawn*, *Lay on Hands*,
    *Divine Shield*, *Hammer of Justice*, *Avenger's Shield*, *Blessing of Kings*,
    *Fan of Knives*, *Shadowstep*, *Killing Spree*, *Blade Flurry*, *Cheat Death*,
    *Bladestorm*, *Heroic Leap*, *Shield Wall*, *Battle Shout*, *Thunder Clap*,
    *Pyroblast*, *Arcane Missiles*, *Ice Barrier*, *Frost Nova*, *Seed of Corruption*,
    *Rain of Fire*, *Drain Life*, *Summon Infernal*, *Summon Voidwalker*, *Mortal Strike*.
  - **Talentfa- és spec-nevek** WoW-os kombinációban (Arms / Fury / Protection, Holy /
    Retribution, Assassination / Combat / Subtlety, Affliction / Demonology / Destruction),
    és a talentek, modifierek nevei.
  - **Rendszer- és szörnynevek:** *Loot Goblin* (a Diablo Treasure Goblinjára emlékeztet),
    *Spirit Healer*, *Voidwalker*, *Infernal*, *Imp*, a pet-nevek; itemek, setek, Artifactok,
    enchantok neveinek újraellenőrzése (14. fejezet tiltólistája).
  - Általános fantasy szavak maradhatnak (Warrior, Mage, Paladin, Rogue, Warlock, Hunter,
    Shaman, Fireball, Charge, Execute stb.), de a végső listát a tisztításkor egyenként döntjük el.
- **Hogyan:** egy átnevezési kör (adat-id-k maradhatnak belső azonosítónak, a megjelenő név
  változik), a tiltólista bővítése, és egy teszt, amely a megjelenő szövegekben (adatok,
  tooltip, UI) tiltott nevet keres. A GDD-t és a README-t is átírjuk.
- **Steam-kiadás – árazási terv** (a hasonló játékok alapján: Brotato, Vampire Survivors,
  Halls of Torment 4,99 USD; Soulstone Survivors, Deep Rock Galactic: Survivor ~9,99 USD):
  - **Early Access** az M7 (grafika, hang, menük, IP-tisztítás) után, **4,99 USD**, az
    5 meglévő kaszttal;
  - **teljes kiadás** az M8–M9 (Hunter, Shaman, meta-progresszió) után, **6,99–7,99 USD**;
  - indulási kedvezmény 10–20% (1–2 hét), a Steam regionális ártáblázatával (HU kb.
    1500–2000 Ft a 4,99-es árhoz);
  - számolni kell a Steam 30%-os részesedésével, az áfával és az egyszeri 100 USD-s
    Steam Direct díjjal.

**Átnevezések (M7a)**

| Kategória | Régi → új |
|---|---|
| **Képességek** (34) | Berserking → Savage Haste · War Stomp → Crowd Stomp · Spirit Wolf → Phantom Wolf · Arcane Missiles → Arcane Darts · Blizzard → Hailstorm · Frost Nova → Rime Burst · Ice Barrier → Frozen Layer · Pyroblast → Magma Bolt · Avenger's Shield → Ricochet Shield · Blessing of Kings → Boon of Crowns · Consecration → Sacred Circle · Divine Shield → Gilded Halo · Divine Storm → Radiant Whirl · Hammer of Justice → Smiting Hammer · Lay on Hands → Mending Touch · Word of Glory → Call of Valor · Blade Flurry → Cleaving Blades · Cheat Death → Narrow Escape · Fan of Knives → Knife Bloom · Killing Spree → Cutthroat Rush · Shadowstep → Duskstep · Shuriken Toss → Throwing Stars · Vanish → Melt Away · Drain Life → Vital Siphon · Rain of Fire → Ember Rain · Seed of Corruption → Blight Seed · Shadow Bolt → Umbral Bolt · Summon Infernal → Summon Cinder Brute · Summon Voidwalker → Summon Gloomguard · Battle Shout → Battle Roar · Bladestorm → Steel Cyclone · Heroic Leap → Soaring Slam · Shield Wall → Stalwart Guard · Thunder Clap → Ground Slam |
| **Rank V specializációk** (27) | Focused Missiles → Focused Darts · Arcane Barrage → Burst Darts · Ice Block → Glacial Cocoon · Pyroclasm → Piercing Blaze · Hot Streak → Quickfire · Blessing of Might → Boon of Vigor · Blessing of Sanctuary → Boon of Warding · Hallowed Ground → Healing Circle · Hands of Mercy → Touch of Many · Light of Dawn → Chorus of Dawn · Relentless Flurry → Relentless Blades · Adrenaline Surge → Racing Pulse · Deadly Fan → Deadly Bloom · Smoke Bomb → Smoke Pellet · Siphon Life → Leeching Curse · Abyssal Guardian → Burning Guardian · Consuming Shadows → Smothering Dark · Commanding Shout → Commanding Roar · Intimidating Shout → Dread Roar · Ravager → Whirling Axe · Warbringer → Battering Ram · Sweeping Strikes → Reaping Arc · Spiked Wall → Spiked Guard · Booming Voice → Raging Echo · Spirit Link → Pack Bond · Aftershock (Thunder Clap) → Echoing Slam · Soul Siphon (Drain Life) → Threefold Drain |
| **Talentfák** (15) | Arms → Warblade · Fury → Berserker · Protection (Warrior) → Ironwall · Arcane → Starlore · Fire → Pyrelore · Frost → Rimelore · Holy → Radiance · Protection (Paladin) → Vigil · Retribution → Verdict · Assassination → Toxins · Combat → Bladework · Subtlety → Gloaming · Affliction → Hexcraft · Demonology → Pactcraft · Destruction → Cinderfall |
| **Talentek – Warrior** (16) | Tactical Mastery → Rage Reserve · Deep Wounds → Gashing Blows · Two-Handed Specialization → Two-Hander Prowess · Sudden Death → Culling Instinct · Mortal Strike → Ruinous Strike · Unbridled Wrath → Furious Spark · Blood Craze → Savoured Kills · Dual Wield Specialization → Twin-Blade Prowess · Meat Cleaver → Reaping Spin · Flurry → Rising Tempo · Death Wish → Desperate Might · Rampage → Carnage · Shield Specialization → Shield Prowess · Revenge → Payback · Shield Mastery → Shieldcraft · Blood and Thunder → Whirl and Slam |
| **Talentek – Mage** (16) | Arcane Concentration → Thrifty Casting · Mirror Image → Phantom Double · Arcane Power → Overchannel · Critical Mass → Fiery Precision · Playing with Fire → Reckless Flame · Living Bomb → Ticking Ember · Molten Fury → Finishing Flame · Combustion → Chain Ignition · Ice Armor → Rime Plating · Improved Blizzard → Improved Hailstorm · Winter's Chill → Numbing Cold · Arctic Winds → Boreal Winds · Deep Freeze → Glacial Finale · Flash Freeze → Snap Freeze · Chilled to the Bone → Frozen Marrow · Ice Lance → Frost Spike |
| **Talentek – Paladin** (20) | Aura Mastery → Aura Reach · Eternal Glory → Boundless Valor · Unyielding Faith → Steadfast Prayer · Light's Grace → Generous Valor · Light's Hammer → Gifted Circle · Divine Guardian → Warding Presence · Purifying Power → Sunlit Might · Holy Shock → Radiant Pulse · Consecrated Ground → Lasting Circle · Guarded by the Light → Shielded by Faith · Ardent Defender → Dauntless Rally · Righteous Fury → Provoking Light · Shield of the Templar → Vigilant Shield · Reckoning → Swift Rebuke · Holy Shield → Gleaming Shield · Art of War → Rhythm of Battle · Sanctity of Battle → Sacred Cadence · Sanctified Retribution → Sanctified Fervor · Righteous Vengeance → Branding Strikes · Seal of Command → Sunbrand |
| **Talentek – Rogue** (20) | Seal Fate → Fateful Cuts · Coup de Grace → Finishing Flourish · Envenom → Overdose · Venomous Wounds → Toxic Harvest · Master Poisoner → Venom Savant · Cold Blood → Steel Nerve · Lightning Reflexes → Quicksilver Reflexes · Combat Potency → Battle Verve · Unfair Advantage → Sly Counter · Restless Blades → Hastening Blades · Hack and Slash → Twin Strike · Adrenaline Rush → Crowd Surge · Premeditation → Forethought · Enveloping Shadows → Veiling Dusk · Master of Subtlety → Veiled Aggression · Shadow Focus → Quiet Mind · Deadened Nerves → Callous Hide · Find Weakness → Opportunist's Eye · Sleight of Hand → Quick Fingers · Shadow Dance → Dusk Waltz |
| **Talentek – Warlock** (21) | Curse of Agony → Hex of Anguish · Improved Drain Life → Improved Vital Siphon · Shadow Mastery → Umbral Affinity · Curse of Exhaustion → Hex of Fatigue · Writhe in Agony → Spreading Anguish · Death's Embrace → Doomed Prey · Unstable Affliction → Volatile Blight · Demonic Embrace → Fiendish Vigor · Improved Imp → Pampered Imp · Unholy Power → Pack Command · Soul Harvest → Shard Hunger · Demonic Aegis → Pact Ward · Wild Imps → Imp Brood · Master Demonologist → Pactmaster · Fel Synergy → Kindly Fiends · Soul Link → Soul Tether · Emberstorm → Stoked Flames · Soul Leech → Bloody Tithe · Shadowburn → Parting Scorch · Burning Embers → Pocketed Shards · Conflagrate → Lingering Blaze |
| **Szövegbeli nevek** | Mortal Wound → Ruinous Wound · Agony (főnév) → Anguish |
| **Mesterségek, erőforrások, petek** | Aura of Devotion → Aura of Fealty · Deadly Poison → Lethal Venom · Demonic Pact → Ember Pact · Battle Fury → Cornered Fury · Holy Power → Resolve · Soul Shards → Pact Shards · Soul Shard → Pact Shard · Voidwalker → Gloomguard · Torment → Menace · Infernal → Cinder Brute · Arcane Dust → Glimmer Dust |
| **Ellenfelek és rendszerek** | Loot Goblin → Coin Gremlin · Troll Axethrower → Troll Hatchet-Hurler · Raise Dead (boss-képesség) → Call the Fallen · Spirit Healer → Grave Tender · Resurrection Sickness → Wilted |
| **Itemek, setek, enchantok** | Frostweave Cowl → Rimeweave Cowl · Warbringer's Greaves → Vanguard's Greaves · Libram of Devotion → Hymnal of Devotion · Battlegear of Fury (set) → Ragebound Plate · Felfire Raiment (set) → Hexfire Raiment · Bloodlust (enchant-előtag) → Warfever · Shadowflame (enchant-előtag) → Duskflame · Retribution (enchant-előtag) → Reprisal |

**Megtartott nevek (döntések)**

- Általános szavak: Need / Greed / Pass, Disenchant, Trainer, Enchanter, Skeleton Grunt.
- Imp: a szó megmarad (Imp, Imp Swarm, Grimoire of the Imp Lord, Ring of the Mischievous Imp); a talentek: *Wild Imps* → **Imp Brood**, *Improved Imp* → **Pampered Imp**, a talentszövegekben marad az „Imp” / „Imps”; a Wild Imp teremtmények neve marad.
- Goblin-téma (Goblin's Goods, Goblin Caravan, Goblin Coin Purse) és az állat-utótagok (Bear, Eagle …).
- Gyenge megtartások: Whirlwind, Corruption, Ignite, Artifact, Stormcaller, Frostfang, Dawnbreaker; a *Divine Verdict* talent; a *Shockwave* (Warrior spec és artifact-tulajdonság); az *Aftershock* (a War Stomp saját tulajdonsága); a Skull of the Damned „Soul Siphon” tulajdonsága; a boss-képességek (Frost Circles, Frost Breath, Fire Fields).
- A *Blizzard* csak cégnévként szerepel (ebben a dokumentumban a Blizzard-márkára utaló szövegek maradnak).
- Eltérés a jóváhagyott tábláztól: a tűz-fa neve **Pyrelore** (az Emberlore szöveg a Talents fülön nem fért el); az Arcane Dust → **Glimmer Dust** (a „Dust” rövid címke maradhat); a Holy Power → **Resolve**; a Soul Shard(s) → **Pact Shard(s)**.

**Dungeon-portál (M6b)**

- **Mikor:** fix időpontban, a **6., 9., 12. és 15. hullám után** (Normalban, Endlessben és
  Hardcore módban is): a szünetben, a szintlépés **után** és a piac **előtt** (PORTAL fázis)
  a „*A dungeon portal has opened!*” felirat jelenik meg.
- **Opcionális, csapatszavazással:** mindenki szavaz (Accept / Decline). Ha **mindenki**
  elfogadta, a csapat belép; egy elutasítás vagy a **20 mp-es** időkorlát lejárta kihagyja, és a
  menet a piaccal folytatódik.
- **Belül:** külön, kis aréna (**24 × 14 m**, a menet környezetének palettájával, környezeti
  veszély nélkül); **4 terem** egymás után, mindegyik rövid, forgatókönyves harc a menet
  jogosult ellenségeivel, a kitisztított hullám szerint skálázva. A harcrendszer és az
  aréna-technika ugyanaz, mint a menetben.

  | # | Terem | Feladat |
  |---|---|---|
  | 1 | **Clear** | 25 ellenség megölése |
  | 2 | **Survive** | 25 mp sűrű spawn túlélése |
  | 3 | **Defend** | egy parázstartó (brazier) életben tartása 20 mp-ig |
  | 4 | **Warden** | mini-boss: a **Dungeon Warden** (8. fejezet) |

  A termek között **3 mp-es** „*Room cleared*” szünet van, ami a hősök Max HP-jának **30%-át**
  gyógyítja.
- **Szabályok:** nincs Grave Tender, a társak élesztenek; ha **mindenki** elesik, a dungeon
  bukás. A piac időzítője a dungeon alatt **áll**.
- **Siker:** minden hős kap egy **garantált Epic** itemet (a dungeon után Need / Greed / Pass
  dobás), **50% eséllyel** egy extra tier set-darabot a csapat egyik kasztjának, és a
  kitisztított hullám átlagos ellenség-goldjának **20-szorosát** kapja a csapat (10.1).
- **Bukás:** a közös kassza **50%-át** elveszíti a csapat, és visszatér a piacra (mindenki
  feléled, mint egy hullám elején).
- **Akárhogy is végződik, a piac következik.**
- **HUD:** „*Dungeon – Room 2/4 · <feladat>*” és a terem-feladat állása; a sebzésmérő és a
  menet-statisztikák a dungeon sebzését is számolják.
- **Botok:** a 6. és a 9. hullám után belépnek; a 12. és a 15. után csak akkor, ha az előző
  hullámban senki sem esett el.
- **Szerepek:** a kasztok úgy működnek, mint a menetben; külön tank / healer / DPS
  hangsúly nincs.
- **Később (M10, ha az M6b-s változat bevált):** külön Dungeon mód a főmenüből, egymásba
  nyíló termekkel és több bosszal.
- Debug: `--dungeon=1` a következő hullám után portált nyit.

**Dungeon-portál – pontosítások (M6b, megvalósítva)**

- **Mikor:** a 6., 9., 12., 15. hullám után (Normal, Endless, Hardcore; az Endless 26.-tól már nem),
  vagy `--dungeon=1` esetén a következő hullám után egyszer. **Szavazás:** A (Accept) / B (Decline),
  20 mp; mindenkinek igent kell mondania. A bot a 6. és 9. hullám után, valamint `--dungeon` esetén
  igent szavaz, a 12. és 15. után csak akkor, ha az adott hullámban senki sem esett el. A
  lecsatlakoztatott kontrollerű játékos tartózkodik; aki kilép, magával viszi a szavazatát; ha nincs
  szavazó, a portál kimarad. A szavazó-jelvények kerete semleges (arany), amíg nem szavazott; zöld =
  Accept, piros = Decline.
- **Belépés / kilépés:** a hősök mintha hullám kezdődne: teljes HP, az elesettek 50%-kal térnek
  vissza; a Dungeon után szintén (az elesettek 50%-kal), a hullámvégi hatások lejárnak. Az
  Artifactok **nem** nőnek a Dungeonnal. A piac időzítője csak a piac nyitásakor indul. A Dungeon ideje
  **nem számít bele** a menet idejébe (run time, így a ranglista idejébe sem).
- **Ellenségek / termek:** a kitisztított hullám jogosult ellenségei; 1 Clear (25 ölés; max. 12
  egyszerre; 1,5× ráta), 2 Survive (25 mp; max. 30; 2,5×), 3 Defend (a parázstartó 20 mp-ig; max. 24;
  2×), 4 Warden. A parázstartó HP-ja **30 Skeleton Grunt** HP-ja az adott hullámon (a csapat
  HP-szorzójával); a 9 m-en belüli ellenségek ráközelítenek, és másodpercenként mindegyik a saját
  érintéses sebzését viszi le róla; ha elfogy, a Dungeon **bukás**. A termek között 3 mp szünet, ami
  minden élő hős Max HP-jának 30%-át gyógyítja; az elesettek lent maradnak (nincs Grave Tender),
  csapattárs éleszti őket („*Only a teammate can revive you*”).
- **Dungeon Warden:** alap HP 120, érintés 3, sebesség 1,9, Frost Circles (7 mp) + Call the Fallen (12 mp, 4
  Skeleton Grunt, a 2. fázisban 6), 2. fázis 50%-nál (×0,7 cooldown), Enrage **60 mp**; nem ad
  boss-itemet és -goldot (a smoke-biztosíték 60 mp-pel az enrage után megöli).
- **Siker:** hősönként 1 garantált Epic (a hős kasztja használhatja), 50% eséllyel egy extra tier
  set-darab (lehetőleg olyan, ami még hiányzik), és 20 × a hullám átlagos ellenség-goldja; a
  Need / Greed / Pass dobás a Dungeon után van, a piac előtt. **Bukás:** mindenki elesett vagy a
  parázstartó megsemmisült; a kassza fele (lefelé kerekítve) elvész (a vásárlás-statisztikában nem
  szerepel), mindenki feléled.
- **Környezet a Dungeonban:** a szoba a menet környezetének palettájában készül, **környezeti veszély
  nélkül**; a Grave Tender a Dungeon alatt nincs (Hardcore-ban a tisztáson sincs).

**Goldsinkek (M6a)**

- **Miért:** az M5-ös mérésekben a késői kassza gyakran 2000 gold fölött van, egyedül már a
  19–21. hullámtól gyűlik a gold, mert a késői hullámokban nincs mire érdemes költeni. A cél
  nem adó, hanem döntés: a felesleges gold kis, de valódi erővé váljon.
- **Enchanter** (az 5.7 „Enchanting” pontjának kibontása; a részletes szabályok és az árak ott
  vannak):
  - A Character fül item-menüjében a **Disenchant** (a Sell mellett) *Glimmer Dust-ot* ad
    (Common 1 … Legendary 16); a loot-dobáson mindenki által Passolt item is magától Dust
    lesz. Az Artifact nem Disenchantolható.
  - Az **Enchanter** fülön (a 4. személyes fül, a címkéjén a Dust: „Enchanter (12)”) Dustért
    és goldért egy item enchantja **újrasorsolható** (Reroll), **rangja emelhető** (Empower,
    V. rangig), vagy az enchant-hiányos item új enchantot kap (Imbue).
  - Az ár (gold: a bolti ár 25%-a; Dust: a ritkaság értéke) itemenként minden használattal
    **duplázódik**, így ez a fő, felső korlát nélküli sink: mindig van mire költeni, de
    csökkenő hozammal.
- **Fogyóeszközök** (Flask / Elixir / étel):
  - A boltban **saját, +1 sorban** jelennek meg, az item-ajánlatok alatt: **4 kompakt kártya**,
    a készletből véletlenszerűen húzva, mind **különböző**. A bolt item-kínálata nem csökken.
  - **A sor a bolt saját oldalsó RNG-jéből húz** (a futás magjából és egy sóból számolt külön
    generátor), ezért az **item-ajánlatok ugyanazok maradnak**, mint a fogyóeszközök nélkül: egy
    magolt futás item-kínálata nem változik. A sor a körrel és **minden bolti rerollal**
    újrahúzódik; ha minden item-ajánlat zárolt vagy pingelt, a sor akkor sem indít rerollt
    egyedül, de ha a reroll lefut, a sor is cserélődik.
  - **Korlátlan készlet:** minden hős a *saját* fogyóeszközét veszi, a vevő kapja. Nincs lock és
    nincs ping a kártyákon (nincs mit visszatartani). Az A itt is a tartós nyomás szabályát
    követi (ár > a kassza fele → 1 mp tartás).
  - **Függő szabály:** hősönként legfeljebb 1 főzet (Flask / Elixir) és 1 étel várhat a
    következő hullámra; egy újabb (azonos fajtájú) a függőben lévőt lecseréli (visszatérítés
    nincs). A tooltip piros „Replaces: …” sora és a bolt visszajelző sora is megmondja, mit
    szorít ki.
  - A hatás a **következő hullám elején** lép életbe, és a hullám végén megszűnik (a boltban
    sosem látszik lejárt hatás). A hős unit frame-jén kis ikonok mutatják az aktív
    fogyóeszközöket.
  - **Ár:** alapár × a bolti árszorzó (`1 + 0,08 × (hullám − 1)`, 10. fejezet), egész goldra
    kerekítve, legalább 1; a „hullám” a bolt hulláma (a kiürített hullám).
  - Kiinduló készlet (a számok a balanszolás során változnak):

    | Név | Fajta | Hatás | Alapár |
    |---|---|---|---|
    | *Flask of Fury* | Főzet | +15% sebzés | 14 g |
    | *Elixir of Ironskin* | Főzet | +30% Armor | 12 g |
    | *Elixir of Swiftness* | Főzet | +10% Haste, +10% mozgási sebesség | 12 g |
    | *Elixir of Fortune* | Főzet | +25 Fortune | 10 g |
    | *Hearty Onion Stew* | Étel | +15% Max HP, +5 HP-regeneráció (Spirit) | 10 g |
    | *Spiced Onion Rings* | Étel | +5% Crit | 10 g |
    | *Smoked Boar Ribs* | Étel | −8% elszenvedett sebzés | 12 g |

  - **A százalékos hatások:** a „+30% Armor” és a „+15% Max HP” a hős aktuális értékének
    százaléka, **a hullám elején számolva** (0,1-re kerekítve; a Max HP Staminaként érkezik). A
    százalék alapja legalább 0: negatív Armor-ral (az itemek tervezett negatív statjai, pl. a
    Mage Armor −2) az Elixir of Ironskin nem ront, csak nem segít – egy százalékos
    fogyóeszköz csak segíthet.
  - **Hearty Onion Stew:** a hozzáadott Max HP-t azonnal feltölti, de nem gyógyítja teljesen a
    hőst, és nem számít gyógyításnak a statisztikában. Aki a hullám elején 50%-kal feltámad,
    50% régi Max HP-val + az új résszel indul (a feltámadás ára az étellel nem szűnik meg); az
    élő hősök az új teljes Max HP-n indulnak.
  - Minden körben visszatérő, kis költés, egyedül és co-opban is.
- **Black Market** (a 15. hullámtól):
  - Egy drága **extra ajánlat** a boltban, saját helyen – arany keretes, széles kártya (ikon,
    név, ár, a „ki tudja használni” pipák) a fogyóeszköz-sor jobb oldalán –, nem vesz el egy
    item-ajánlatot sem.
  - Tartalma: **40% eséllyel** egy **maximális statdobású Epic**, egyébként garantált tier
    set-darab a csapat egyik kasztjának. A bolt Legendaryt továbbra sem árul (10).
    - A **max-roll Epic** a generátor loot-költségvetésével készül (+25% stat, egy enchant-rankkal
      több, +6 Item Level, „Looted” jelzés), 2 enchanttal, a csapat egy kasztjára (nem kézzel
      készített és nem set-darab).
    - A **set-darab** olyan, amilyet a bolt is árulna az adott hullámon (Item Level 68 a 15.
      hullámon, nem 74): **nem „looted”**, a loot-költségvetés csak a max-roll Epicé. A csapat
      kasztjai közül a hiányzó darabot választja (a kaszt hősei közül valamelyik sem viseli és
      nem hordja a hátizsákban; a hiányzók közül egyenletesen húz, ha nincs hiányzó, bármelyik
      elérhető darab jön). Ha a csapatnak nincs elérhető set-darabja (a 6. hullám előtt, vagy
      set nélküli kaszt), max-roll Epic lesz.
  - Ára az adott hullám Epic árának **3-szorosa** (a 15. hullámon 573 gold), így egyszerre
    nagy összeget visz el. Az item saját értéke (eladás / Greed) a szokásos Epic ár.
  - Zárolható (lock), pingelhető és rerollozható, mint a többi ajánlat: a lock átviszi a
    következő körre, a ping kihagyja a rerollból, a reroll újrahúzza; **egyedül a Black Market
    is elég ahhoz, hogy a reroll lefusson**. A Black Market ugyanabból az oldalsó RNG-ből húz,
    mint a fogyóeszköz-sor.
- **Botok:**
  - A 6. hullám utáni piactól minden bot a saját hősének venne 1 főzetet és 1 ételt, ha a
    vásárlás után a közös kasszában a botok tartaléka megmarad. A választás nem függ a bottól
    (korlátlan a készlet), ezért **minden bot ugyanazt a legjobb főzetet és ugyanazt a legjobb
    ételt veszi** (főzet: Fury > Ironskin > Swiftness > Fortune; étel: Stew > Ribs > Rings); csak
    a kassza szab határt, hányan tudnak fizetni.
  - A Black Marketet az a bot veszi meg, akinek a legtöbbet javít (ha egyáltalán fejlesztés), ha
    utána a tartalék **kétszerese** marad; azonnal felveszi. A bot-reroll után újra megnézik, mert
    a reroll a Black Marketet is újrahúzza.
  - Az Enchanterre a 12. hullám utáni piactól költenek (5.7).
  - **A bot-piac sorrendje:** felszerelés / kovácsolás → enchant → vásárlás → Black Market →
    fogyóeszközök → Trainer → talentek → reroll.
- **Repair rendszer: nem lesz.**
  - Adó, nem döntés.
  - Egyedül (ahol a legtöbb gold gyűlik) az első elesés vereség, így ott szinte nem hatna.
  - A bajban lévő csapatot büntetné tovább (több elesés → nagyobb számla → gyengébb csapat).

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

### 17.8 Bővítések a legeslegvégére

Elfogadott ötletek, amelyek **minden más után** (M9 és a Remote Play Together után) jönnek.
Ugyanaz az elv, mint a 17. fejezetben: új lehetőségek, nem nyers erő.

- **Önkéntes nehezítések (Heat-szerű):** menet előtt a csapat apró nehezítéseket választhat
  (pl. „+20% ellenség-sebesség”, „nincs Grave Tender”, „1 bolti ajánlattal kevesebb”);
  mindegyik több Valort és Class XP-t ad. Finomabb skála, mint a Heroic / Mythic.
- **Heti kihívás:** fix seed, fix környezet, 1–2 előre megadott nehezítés, saját ranglista és
  plusz Valor; később online is (Remote Play Together).
- **Receptkönyv (Cooking / Alchemy):** a menetekben ritka receptek esnek, amelyek véglegesen
  bővítik a bolti fogyóeszköz-sor kínálatát (több választék, nem erősebb hős).
- **Hagymafajták:** az Onion Patch kertjében a menetekből hozott magok „nőnek”, és új
  megjelenést nyitnak (Shallot, Red Onion, Leek, Spring Onion …) – csak kozmetika.
- **Kezdőfegyver-választék:** Class Level mérföldkövek új indulófegyvereket nyitnak
  kasztonként (pl. Warrior kétkezes karddal, Mage Orbbal) – új játékstílus, nem erő.
- **Bestiárium (Onion Almanac):** ellenségenkénti ölésszám, rövid leírás, mérföldkövekért
  címek és keretek; a bossok és az események is bekerülnek.
- **Mini-petek:** nem harcoló kis kísérők, gyűjthetők a Coin Gremlin-től, bossoktól és
  dungeonokból – kozmetika.
- **Paragon-szintek:** a 30-as Class Level fölött végtelen szintek, csak kozmetikai
  jutalommal (keretek, portré-díszek).

---

## 18. Nyitott kérdések

Tervezési kérdés jelenleg nincs nyitva. Az M6b-re átvitt **hangolási** kérdések (a Flesh Golem
sebzése, a 20. hullám, Vor'thalax kill-ideje létszám szerint, a duók és a szóló hősök
túlélése, az Artifact-kínálat, a hős-HP és az ellenség-sebzés viszonya a késői hullámokon) és az
M6b tartalom-áttekintéseiből gyűlt tételek (a pajzsok halmozódása, a Scorching / Glacial
iskola-torzítása, az Epic-only támadási sebesség és a Legendary, a ritkaság-inverziók, az Orb
statjai és a Mage bot Tome-választása, a gold-find trinketek, az új rendszerek kiinduló számai) a
9. fejezetben vannak („Nyitott kérdések M6b-re”); az ütemezésük a 16. fejezet **M6b**
listájában található: ezeket az M6b végleges balansza kezeli, egyszer, a legvégén. A késői
kasszát az M6a goldsinkjei célozták (16.1).

### Lezárt döntések

| Kérdés | Döntés |
|---|---|
| Karakterek kinézete | Hagymák WoW-páncélban |
| Gold | Egyetlen közös pénztárca, bárki költhet belőle |
| Szintlépés | 5 kártya, ability és stat keverve, goldért rerollolható |
| Cím | SmartOnion |
| Nyelv | Angol |
| Kamera | Közös képernyő; korlátos kizoomolás, a képernyő széle falként megállítja a játékosokat |
| Felélesztés | Grave Tender a pálya közepén: folyamatos 10 mp-es számláló, minden pulzus a körében álló szellemeket 100% HP-val feléleszti, utána 15 mp Wilted (addig a Healer nem éleszt újra); egy társ 5 mp alatt is feléleszt (30% HP), cast barral és animációval; a szellem normál sebességgel mozog; a szellem 1,8 m-es körében az ellenségek 33%-kal lassabbak (nem halmozódik) |
| Gyógyulás | Minden hullám elején teljes HP |
| Hullámok közti időkorlát | 60 mp, beállításokban kikapcsolható |
| Gombfeliratok | A kontroller típusa szerint (Xbox / PlayStation / Nintendo) |
| Mentés | Automatikus, minden hullám végén |
| Meta-progresszió | Egy fő profil (a kaszt szintjét bárki megkapja, aki azzal a kaszttal játszik), Class Level, glyphek, heirloomok, achievementek, transmog, Valor + The Onion Patch (17. fejezet); nyers erő legfeljebb +10%; az utolsó mérföldkő (M9), de a rendszerek már most erre készülnek |
| Zene | Egyelőre nincs |
| Célzás | Csak automatikus (fegyverek és képességek); nincs kézi célzás |
| Paladin Call of Valor | Azonnal feléleszti a 8 m-en belüli elesett társat (40% HP), kivéve, ha a Grave Tender 1 mp-en belül úgyis feléleszti |
| Talentfák | Mind a 15 fa kidolgozva (7.4), az M5-ben; a capstone-értelmezések a 7.5 alatt |
| Fegyver-jártasság | Szigorú, WoW-szerű: minden kaszt csak a saját fegyvertípusait használhatja (3. fejezet), nincs „büntetéssel bármit” opció |
| Páncél-jártasság | Szigorú, WoW-szerű: a saját páncéltípus és az annál könnyebbek (5.3) |
| Kaszt-specifikus itemek | Vannak („Classes: X”), a kaszt képességeit módosítják (5.5) |
| Bolt | Közös bolt, saját kurzorokkal; reroll csak akkor, ha minden játékos megszavazta |
| Hullámhossz | A 10. hullám felett +10 mp hullámonként (25. hullám = 210 mp); a boss-hullámot (10., 25.) a boss halála zárja |
| M6 felosztása | M6a (rendszerek: ellenségek, bossok, Artifactok, Enchanter, goldsinkek, Damage Meter) és M6b (módok, környezetek, események, Dungeon-portál, tartalom-csomagok, végleges balansz) – 16. fejezet |
| Glimmer Dust | A csapat második közös pénzneme; Disenchantból és a mindenki által Passolt itemekből jön, az Enchanter költi (5.7) |
| Győzelem | A 25. hullámon Vor'thalax halála (nem az időzítő lejárta) – 8. fejezet |
| Artifact-kínálat | A normál ölés esélye (0,05%) osztva a játékosszámmal, így a várt Artifact-szám 1 / 2 / 4 játékosnál ≈ 2,8 / 2,5 / 2,6 menetenként (5.5) |
| Vor'thalax | Alap HP 450 (az 1200 elírás volt), érintéses sebzés 4, a boss HP-ja ×(1 + 0,75 × (játékosok − 1)) mint Morvainé; a Flesh Golem érintéses sebzése 4 – a végső balansz az M6b végén, egyszer (8., 9. fejezet) |
| Módok (M6b) | **Normal** (25 hullám) vagy **Endless** (a 25. hullám után folytatódik, a 30.-tól 5 hullámonként boss; csak vereséggel ér véget), opcionális **Hardcore** (nincs Grave Tender); a lobbyban választható (Y / X); módonként és létszámonként helyi top 10 ranglista (1., 12., 16.1) |
| Környezetek (M6b) | 5 környezet (Forest Ruin, Cemetery, Swamp, Volcano, Ice Cave), menetenként egy, a „Rolling the arena…” animáció sorsolja; saját veszélyek, az aréna mérete nem változik; a végleges látvány az M7b-ben (13., 16.1) |
| Események és szentélyek (M6b) | Hullám közbeni esemény a 4. hullámtól, 30% eséllyel, hullámonként legfeljebb egy (Guarded Chest, Defend the Totem, Goblin Caravan); szentély a szünetekben 5% eséllyel, csak egyhangú elfogadással (8., 10.1, 16.1) |
| Dungeon-portál (M6b) | A 6., 9., 12. és 15. hullám után, csapatszavazással; 4 terem (Clear, Survive, Defend, Warden); siker: hősönként 1 garantált Epic, bukás: a kassza 50%-a elvész, a piac mindkét esetben következik (8., 16.1) |
| M6b tartalom | +3 fegyver (Two-Hand Sword, Two-Hand Mace, Orb), a Crossbow, a Polearm és a Fist Weapon az M8-cal; a kaszt-független tier setek az **M8-ra tolva** (set-rendszer módosítás kell) – 5.8; **megvalósítva**: 13 fegyver, 96 páncél- és 20 ékszer-alaptípus, 25 utótag, 50 enchant, 160 kézzel tervezett item |
| M6b megvalósítás | Kész (a végleges balansz kivételével): az 1–13., 16.1 és 5.8 fejezet írja le, ahogy a kód működik; az Epic fegyverek +10% támadási sebességet kapnak (4.1), a környezet alapból sorsolódik (smoke-ban is) |
| M6b hangolás | **Nincs.** Egyik M6b-csomag sem hangolt; a végleges 25 hullámos balansz egyszer, a legvégén készül (9. fejezet) |
