class_name LevelUpDeck
extends RefCounted
## Level-up cards (GDD 6.1): after a wave every hero picks 1 of 5 cards per level gained.
## Cards come mixed from one deck: new abilities from the class + general pool
## (Db.ability_pool), free rank-ups of known abilities (core ones included), and stat cards
## (StatCards). About half are ability cards; every hand has at least one ability card (when
## any exists) and one stat card. When the slots of an ability's kind are full, new abilities
## of that kind come less often and rank-ups more often: a card that would need a replacement
## keeps only [constant FULL_SLOTS_MIN_SHARE] of its weight and the rest goes to stat cards,
## while rank-ups keep their chance ([method ability_share], [method pick_weights]).
## Reroll: all 5 cards for [method reroll_price] gold from the shared wallet.
## Randomness: RunState.rng.

const HAND_SIZE := 5
## Chance of each card to be an ability card while every ability card is usable as it is.
const ABILITY_SHARE := 0.5
## Share of a replacement-only card's weight (a new ability whose kind has no free slot) that
## still counts towards the ability cards; the rest goes to stat cards (all slots full, every
## ability at Rank V: 0.5 × 0.2 = 10 % per card, plus the one-ability-card guarantee).
const FULL_SLOTS_MIN_SHARE := 0.2
## New-ability weight when every slot of its kind is taken (picking it means replacing).
const FULL_SLOTS_NEW_WEIGHT := 0.3
## Rank-up weight (per known ability) – higher once the learned slots are full.
const RANK_UP_WEIGHT := 0.8
const RANK_UP_WEIGHT_FULL := 1.6
## Reroll: wave + 2 gold, +2 for every further reroll in the same round.
const REROLL_BASE := 2
const REROLL_STEP := 2


static func reroll_price(wave: int, rerolls_done: int) -> int:
	return maxi(1, wave) + REROLL_BASE + REROLL_STEP * maxi(0, rerolls_done)


## A hand of [param count] cards for [param player].
static func draw(player: Player, rng: RandomNumberGenerator, count: int = HAND_SIZE) -> Array[LevelCard]:
	var hand: Array[LevelCard] = []
	var candidates := ability_candidates(player)
	var share := ability_share(player, candidates)
	var picks := pick_weights(player, candidates)
	var used: Dictionary[StringName, bool] = {}
	var abilities := 0
	var stat_cards := 0
	for i in count:
		var left := count - i
		var want_ability := rng.randf() < share
		# Guarantees: one ability card (if any is possible) and one stat card per hand.
		if abilities == 0 and left == 1 and stat_cards > 0:
			want_ability = true
		elif stat_cards == 0 and left == 1 and abilities > 0:
			want_ability = false
		var card: LevelCard = null
		if want_ability:
			card = _pick_ability(picks, used, rng)
		if card == null:
			card = _stat_card(player, rng)
			stat_cards += 1
		else:
			used[card.ability.id] = true
			abilities += 1
		hand.append(card)
	return hand


## Weighted ability cards for [param player]: [card, weight] pairs, deterministic order
## (slotted abilities first, then the pool in Db order).
static func ability_candidates(player: Player) -> Array:
	var out: Array = []
	var runner := player.abilities if player != null else null
	if runner == null:
		return out
	var full_kinds := {}
	for kind in [AbilityData.Kind.ACTIVE, AbilityData.Kind.AUTO]:
		full_kinds[kind] = runner.free_slot(kind) < 0
	var any_full: bool = full_kinds[AbilityData.Kind.ACTIVE] and full_kinds[AbilityData.Kind.AUTO]
	for a in runner.slots:
		if a != null and runner.can_rank_up(a.id):
			var w := RANK_UP_WEIGHT_FULL if (a.is_learned_kind() and full_kinds.get(a.kind, false)) or any_full else RANK_UP_WEIGHT
			out.append([LevelCard.rank_up(a), w])
	var class_id := player.class_data.id if player.class_data != null else &""
	for a in Db.ability_pool(class_id):
		if runner.knows(a.id):
			continue
		var w := a.card_weight * (FULL_SLOTS_NEW_WEIGHT if full_kinds.get(a.kind, false) else 1.0)
		if w > 0.0:
			out.append([LevelCard.new_ability(a), w])
	return out


## Chance of each card in a hand to be an ability card (GDD 6.1): [constant ABILITY_SHARE] x
## (usable + [constant FULL_SLOTS_MIN_SHARE] x replacement-only weight) / total weight of the
## [param candidates]. Usable: rank-ups and new abilities whose kind has a free slot;
## replacement-only: new abilities whose kind is full. Picked from [method pick_weights], each
## usable card keeps its ABILITY_SHARE x weight / total chance per card (rank-ups do not lose
## out to full slots); what the replacement-only cards lose goes to stat cards. A fresh hero:
## 0.5; all slots full at Rank V: 0.1.
static func ability_share(player: Player, candidates: Array) -> float:
	var total := 0.0
	var counted := 0.0
	for c: Array in candidates:
		var w := float(c[1])
		total += w
		counted += w * (FULL_SLOTS_MIN_SHARE if _needs_replacement(player, c[0] as LevelCard) else 1.0)
	if total <= 0.0:
		return ABILITY_SHARE
	return ABILITY_SHARE * counted / total


## The [param candidates] as [card, weight] pairs to pick the ability cards of a hand from:
## replacement-only cards (a new ability whose kind has no free slot) weigh
## [constant FULL_SLOTS_MIN_SHARE] of their candidate weight, the rest their full weight.
## Same order; the card objects are shared with [param candidates].
static func pick_weights(player: Player, candidates: Array) -> Array:
	var out: Array = []
	for c: Array in candidates:
		var card := c[0] as LevelCard
		out.append([card, float(c[1]) * (FULL_SLOTS_MIN_SHARE if _needs_replacement(player, card) else 1.0)])
	return out


## A new-ability card whose kind has no free slot for [param player] (picking it means
## replacing a learned ability).
static func _needs_replacement(player: Player, card: LevelCard) -> bool:
	if card.kind != LevelCard.Kind.NEW_ABILITY:
		return false
	var runner := player.abilities if player != null else null
	return runner != null and runner.free_slot(card.ability.kind) < 0


## Applies [param card] to [param player]. A new ability with its slots full needs
## [param replace_index] (a slot of the same kind); its refund goes to the shared wallet.
## Returns {"ok": bool, "needs_replace": bool, "needs_spec": bool, "refund": int}.
static func apply(player: Player, card: LevelCard, replace_index: int = -1) -> Dictionary:
	var result := {"ok": false, "needs_replace": false, "needs_spec": false, "refund": 0}
	if player == null or card == null:
		return result
	var runner := player.abilities
	match card.kind:
		LevelCard.Kind.STAT:
			player.add_card_stats(card.stats)
			result["ok"] = true
		LevelCard.Kind.RANK_UP:
			result["ok"] = runner != null and runner.rank_up(card.ability.id)
			result["needs_spec"] = result["ok"] and runner.needs_spec(card.ability.id)
		LevelCard.Kind.NEW_ABILITY:
			if runner == null:
				return result
			if runner.knows(card.ability.id):
				# Learned meanwhile (two levels in one break): a free rank instead.
				result["ok"] = runner.rank_up(card.ability.id)
				result["needs_spec"] = result["ok"] and runner.needs_spec(card.ability.id)
				return result
			var free := runner.free_slot(card.ability.kind)
			if free < 0 and replace_index < 0:
				result["needs_replace"] = true
				return result
			var refund := 0
			if free < 0:
				refund = AbilityRanks.replace_refund(runner.rank_of(runner.slots[replace_index].id), RunState.wave) \
						if replace_index >= 0 and replace_index < runner.slots.size() and runner.slots[replace_index] != null else 0
			var slot := runner.learn(card.ability, -1 if free >= 0 else replace_index)
			result["ok"] = slot >= 0
			if result["ok"] and refund > 0:
				RunState.add_gold(refund)
				result["refund"] = refund
	return result


## Bot choice (smoke / demo): a new ability while a slot of its kind is free, else a
## rank-up of the highest-ranked ability that can still rise, else the rarest stat card.
static func bot_pick(player: Player, hand: Array[LevelCard]) -> int:
	var runner := player.abilities if player != null else null
	var best := -1
	var best_score := -INF
	for i in hand.size():
		var c := hand[i]
		var score := 0.0
		match c.kind:
			LevelCard.Kind.NEW_ABILITY:
				score = 100.0 if runner != null and runner.free_slot(c.ability.kind) >= 0 else -1.0
			LevelCard.Kind.RANK_UP:
				score = 50.0 + (runner.rank_of(c.ability.id) if runner != null else 0)
			LevelCard.Kind.STAT:
				score = 20.0 + 10.0 * c.rarity + c.stats.size()
		if score > best_score:
			best_score = score
			best = i
	return best


static func _pick_ability(candidates: Array, used: Dictionary[StringName, bool], rng: RandomNumberGenerator) -> LevelCard:
	var total := 0.0
	for c: Array in candidates:
		if not used.has((c[0] as LevelCard).ability.id):
			total += float(c[1])
	if total <= 0.0:
		return null
	var r := rng.randf() * total
	for c: Array in candidates:
		var card := c[0] as LevelCard
		if used.has(card.ability.id):
			continue
		r -= float(c[1])
		if r < 0.0:
			# A fresh card per hand (the candidate objects are shared within one draw).
			return LevelCard.rank_up(card.ability) if card.kind == LevelCard.Kind.RANK_UP else LevelCard.new_ability(card.ability)
	return null


static func _stat_card(player: Player, rng: RandomNumberGenerator) -> LevelCard:
	var rarity := StatCards.roll_rarity(rng)
	return LevelCard.stat(rarity, StatCards.roll_stats(rng, rarity, player.class_data if player != null else null))
