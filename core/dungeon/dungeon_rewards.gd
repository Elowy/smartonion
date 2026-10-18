class_name DungeonRewards
extends RefCounted
## What a dungeon pays out (GDD 16.1 "Dungeon-portál", 10.1), the pure part of the DUNGEON package –
## [Dungeon] runs the rooms, Main hands the result to this file and then to the Intermission.
##
## - Success ([method grant_success]): every hero with a hero in play gets one guaranteed Epic
##   (usable by its class, a loot-quality item: Source.LOOT, +25% stats) that goes to the team loot,
##   i.e. to the Need / Greed / Pass roll after the dungeon; with [constant SET_PIECE_CHANCE] one
##   extra tier-set piece of a class in the team (a piece somebody's set is still missing is
##   preferred, [method BlackMarket.set_piece_candidates]) joins them; and the team's purse gets
##   [constant GOLD_MULT] x the wave's average enemy gold ([method gold_for], the Loot Goblin's
##   average, LootGoblin.average_gold).
## - Failure ([method apply_failure]): the purse loses [constant FAIL_PURSE_SHARE] of its gold. The
##   loss is a line of the round's spend log (kind &"dungeon") so the purse board shows it, but it is
##   not counted in RunState.gold_spent (that number is for purchases).
## Every draw comes from the rng the caller passes (RunState.dungeon_rng): per hero in slot order the
## generator's own draws, then the extra-piece chance (randf), then – on a hit – the piece pick.

## Multiple of the wave's average enemy gold a cleared dungeon pays (GDD 10.1).
const GOLD_MULT := 20
## Chance of the extra tier-set piece (GDD 16.1).
const SET_PIECE_CHANCE := 0.5
## Share of the purse a failed dungeon takes (GDD 16.1).
const FAIL_PURSE_SHARE := 0.5
## The spend-log kind of the failure's loss.
const FAIL_KIND := &"dungeon"


## Gold a dungeon cleared at [param wave] pays: GOLD_MULT x the wave's average enemy gold.
static func gold_for(wave: int) -> int:
	return roundi(GOLD_MULT * LootGoblin.average_gold(maxi(1, wave)))


## The guaranteed Epic of [param slot]'s hero at [param wave]: usable by its class (the team's classes
## are passed on, so a tier-set roll is for a class that plays), a loot-quality item. Null only when
## the generator has nothing to make.
static func epic_for(slot: PlayerSlot, wave: int, team: Array[ClassData], rng: RandomNumberGenerator) -> ItemInstance:
	var options := {&"rarity": Items.Rarity.EPIC, &"team_classes": team}
	if slot != null and slot.class_data != null:
		options[&"usable_by"] = slot.class_data
		options[&"class_data"] = slot.class_data
	return _finish(ItemGenerator.generate(ItemGenerator.Source.LOOT, maxi(1, wave), rng, options), wave)


## The extra tier-set piece for the team of [param slots] at [param wave], or null: the chance
## (SET_PIECE_CHANCE, one randf) misses, or no class of the team has a piece at the wave. A missing
## piece is preferred ([method BlackMarket.set_piece_candidates]); one randi_range picks among several.
static func bonus_set_piece(wave: int, slots: Array[PlayerSlot], rng: RandomNumberGenerator) -> ItemInstance:
	if rng.randf() >= SET_PIECE_CHANCE:
		return null
	var all := BlackMarket.set_piece_candidates(maxi(1, wave), slots)
	if all.is_empty():
		return null
	var pool: Array[Dictionary] = []
	for c in all:
		if c["missing"]:
			pool.append(c)
	if pool.is_empty():
		pool = all
	var pick := pool[0] if pool.size() == 1 else pool[rng.randi_range(0, pool.size() - 1)]
	return _finish(ItemGenerator.from_unique(pick["data"], maxi(1, wave), true, rng, pick["class"]), wave)


## Pays a cleared dungeon: the Epics (one per slot with a hero, slot order) and the extra piece go to
## RunState.team_loot, the gold to the purse. Returns {"items": Array[ItemInstance] (the Epics),
## "extra": ItemInstance or null, "gold": int}.
static func grant_success(wave: int, slots: Array[PlayerSlot], rng: RandomNumberGenerator) -> Dictionary:
	var heroes: Array[PlayerSlot] = []
	for s in slots:
		if s != null and is_instance_valid(s.player):
			heroes.append(s)
	heroes.sort_custom(func(a: PlayerSlot, b: PlayerSlot) -> bool: return a.index < b.index)
	var team: Array[ClassData] = []
	for s in heroes:
		if s.class_data != null and s.class_data not in team:
			team.append(s.class_data)
	var items: Array[ItemInstance] = []
	for s in heroes:
		var item := epic_for(s, wave, team, rng)
		if item != null:
			items.append(item)
			RunState.add_team_loot(item)
	var extra := bonus_set_piece(wave, heroes, rng)
	if extra != null:
		RunState.add_team_loot(extra)
	var gold := gold_for(wave)
	RunState.add_gold(gold)
	return {"items": items, "extra": extra, "gold": gold}


## Gold a failed dungeon would take from the purse now: FAIL_PURSE_SHARE of it, rounded down.
static func failure_loss(gold: int = -1) -> int:
	var purse := RunState.gold if gold < 0 else gold
	return floori(float(purse) * FAIL_PURSE_SHARE)


## Takes the failure's share out of the purse (the spend log shows "Dungeon failed"). Returns the
## gold lost (0 with an empty purse).
static func apply_failure() -> int:
	var amount := failure_loss()
	if amount <= 0:
		return 0
	RunState.gold -= amount
	var entry := {"slot": -1, "kind": FAIL_KIND, "label": "Dungeon failed", "amount": amount, "wave": RunState.wave}
	RunState.spend_log.append(entry)
	RunState.gold_changed.emit(RunState.gold, -amount)
	RunState.spent.emit(entry)
	return amount


## A looted item as the loot drops make them: the loot flag and the Epic price.
static func _finish(item: ItemInstance, wave: int) -> ItemInstance:
	if item == null:
		return null
	item.looted = true
	if item.buy_price <= 0:
		item.buy_price = ItemGenerator.price_for(item.rarity, maxi(1, wave))
	return item
