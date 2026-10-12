class_name TalentState
extends RefCounted
## One hero's talents (GDD 7, M5): [code]player.talents[/code]. Every hero gets the team's full
## talent point count (RunState.talent_points_earned(): one per team level from level 10) and
## spends it in the market on the Talents tab; the level-up cards are unrelated (GDD 7.1).
##
## Rules (talent_vocabulary.md §1.1):
## - Tier gates: a talent of tier t needs TIER_POINTS[t - 1] points in the LOWER tiers of its
##   own tree (0 / 3 / 6 / 9 / 12 – the capstone is reachable with 13 points).
## - Prerequisite (TalentData.prerequisite): another talent of the same tree at its max rank.
## - Undo (X): only points added since the last wave start ([member pending]) can be taken back,
##   and only while no taken talent depends on them (a prerequisite it needs, or the points a
##   higher tier's gate counts). [method commit] (Player.begin_wave) makes them permanent.
## - Reset: refunds every point (pending ones included) for RESET_BASE_PRICE x 2^resets gold
##   from the shared wallet, per hero ([method try_reset]).
## [signal changed] fires on add / remove / reset / from_dict – the Player then rebuilds its
## bonus entries (PlayerBonuses.set_effects(&"talents", effects())). commit() changes no effect,
## so it emits nothing.
##
## Block reasons are UI texts (the Talents tab shows them); add: unknown → level → max rank →
## gate → prerequisite → free points; remove: pending → dependent prerequisite → gate break.

signal changed

## Points a tier's gate needs in the lower tiers of the same tree (index = tier - 1).
const TIER_POINTS: Array[int] = [0, 3, 6, 9, 12]
const RESET_BASE_PRICE := 20
## Wallet log kind of a reset (RunState.try_spend_for).
const RESET_SPEND_KIND := &"talent_reset"
const RESET_SPEND_LABEL := "Reset Talents"

var class_id: StringName
## Talent id -> rank (committed + pending); talents at rank 0 are absent.
var ranks: Dictionary[StringName, int] = {}
## Talent id -> points added since the last wave start (X undoes these).
var pending: Dictionary[StringName, int] = {}
## Resets this hero bought this run (the price doubles each time).
var resets := 0

var _trees: Array[TalentTreeData] = []
var _talents: Dictionary[StringName, TalentData] = {}
var _tree_of: Dictionary[StringName, TalentTreeData] = {}


## The talents of [param p_class_id]: [param p_trees] (fixtures), or Db's trees of that class
## when empty.
static func create(p_class_id: StringName, p_trees: Array[TalentTreeData] = []) -> TalentState:
	var s := TalentState.new()
	s.class_id = p_class_id
	s._set_trees(p_trees if not p_trees.is_empty() else Db.talent_trees_for(p_class_id))
	return s


# --- Queries ---------------------------------------------------------------------------------

## The class's trees in tab order (TalentTreeData.index, then id). Do not modify.
func trees() -> Array[TalentTreeData]:
	return _trees


## The tree that holds [param talent_id] (null when unknown).
func tree_of(talent_id: StringName) -> TalentTreeData:
	return _tree_of.get(talent_id)


## The talent [param talent_id] of this class (null when unknown).
func talent(talent_id: StringName) -> TalentData:
	return _talents.get(talent_id)


## Talent points the team level has given every hero (RunState.talent_points_earned()).
func points_earned() -> int:
	return RunState.talent_points_earned()


func points_spent() -> int:
	var n := 0
	for id in ranks:
		n += ranks[id]
	return n


func points_free() -> int:
	return maxi(0, points_earned() - points_spent())


func rank_of(talent_id: StringName) -> int:
	return ranks.get(talent_id, 0)


## Points spent in tree [param tree_id].
func tree_points(tree_id: StringName) -> int:
	for tree in _trees:
		if tree.id == tree_id:
			return _points_in(tree, 99)
	return 0


## Points spent in the tiers of [param tree] below [param tier] (what tier [param tier]'s gate
## counts).
func points_below_tier(tree: TalentTreeData, tier: int) -> int:
	return _points_in(tree, tier) if tree != null else 0


## Points the gate of [param tier] needs (TIER_POINTS).
static func gate_points(tier: int) -> int:
	return TIER_POINTS[clampi(tier, 1, TIER_POINTS.size()) - 1]


# --- Adding / removing points --------------------------------------------------------------------

## Why a point cannot go into [param talent_id] right now ("" = it can).
func add_block_reason(talent_id: StringName) -> String:
	var t := talent(talent_id)
	if t == null:
		return "Unknown talent"
	if RunState.level < RunState.TALENT_START_LEVEL:
		return "Talent points from level %d" % RunState.TALENT_START_LEVEL
	if rank_of(talent_id) >= t.max_rank:
		return "Max rank"
	var tree := tree_of(talent_id)
	var gate := gate_points(t.tier)
	if points_below_tier(tree, t.tier) < gate:
		return "Needs %d points in %s" % [gate, tree.display_name]
	if t.prerequisite != &"":
		var pre := talent(t.prerequisite)
		if pre != null and rank_of(pre.id) < pre.max_rank:
			return "Requires %s" % pre.display_name
	if points_free() <= 0:
		return "No talent points"
	return ""


func can_add(talent_id: StringName) -> bool:
	return add_block_reason(talent_id) == ""


## Puts one point into [param talent_id] (a pending point until the next wave starts).
func add(talent_id: StringName) -> bool:
	if not can_add(talent_id):
		return false
	ranks[talent_id] = rank_of(talent_id) + 1
	pending[talent_id] = int(pending.get(talent_id, 0)) + 1
	changed.emit()
	return true


## Why a point cannot be taken back from [param talent_id] ("" = it can).
func remove_block_reason(talent_id: StringName) -> String:
	var t := talent(talent_id)
	if t == null:
		return "Unknown talent"
	if int(pending.get(talent_id, 0)) <= 0:
		return "Only points spent since the last wave can be taken back"
	var tree := tree_of(talent_id)
	for u in tree.talents:
		if u != null and u.prerequisite == talent_id and rank_of(u.id) > 0:
			return "%s depends on it" % u.display_name
	for u in tree.talents:
		if u == null or u.tier <= t.tier or rank_of(u.id) <= 0:
			continue
		if points_below_tier(tree, u.tier) - 1 < gate_points(u.tier):
			return "%s needs those points" % u.display_name
	return ""


func can_remove(talent_id: StringName) -> bool:
	return remove_block_reason(talent_id) == ""


## Takes one pending point back from [param talent_id] (X).
func remove(talent_id: StringName) -> bool:
	if not can_remove(talent_id):
		return false
	_take(ranks, talent_id)
	_take(pending, talent_id)
	changed.emit()
	return true


## Wave start (Player.begin_wave): the pending points become permanent. The effects do not
## change, so nothing is emitted (no engine rebuild).
func commit() -> void:
	pending.clear()


# --- Reset -----------------------------------------------------------------------------------

## Gold for the next reset: RESET_BASE_PRICE x 2^resets (20, 40, 80 ...).
func reset_price() -> int:
	return RESET_BASE_PRICE * (1 << clampi(resets, 0, 24))


## Why a reset is refused ("" = allowed): "Nothing to reset" / "Not enough gold (40 g)".
func reset_block_reason() -> String:
	if points_spent() <= 0:
		return "Nothing to reset"
	var price := reset_price()
	if not RunState.can_afford(price):
		return "Not enough gold (%d g)" % price
	return ""


## Refunds every point (pending ones too) for [method reset_price] gold from the shared wallet,
## logged for slot [param slot_index] (RunState.try_spend_for). Returns false when refused.
func try_reset(slot_index: int) -> bool:
	if reset_block_reason() != "":
		return false
	if not RunState.try_spend_for(reset_price(), slot_index, RESET_SPEND_KIND, RESET_SPEND_LABEL):
		return false
	ranks.clear()
	pending.clear()
	resets += 1
	RunState.talent_resets += 1
	changed.emit()
	return true


# --- Effects and saving ----------------------------------------------------------------------

## Every effect entry of every talent with a rank, in tree / talent order: deep copies with
## "rank", "id" (the talent id) and "label" (its name) added – what PlayerBonuses takes for
## the source &"talents".
func effects() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for tree in _trees:
		for t in tree.talents:
			if t == null:
				continue
			var r := rank_of(t.id)
			if r <= 0:
				continue
			for e in t.effects:
				var entry: Dictionary = e.duplicate(true)
				entry["rank"] = r
				entry["id"] = String(t.id)
				entry["label"] = t.display_name
				out.append(entry)
	return out


## {"version": 1, "ranks": {"<talent id>": rank, ...}, "resets": n} (future autosave).
func to_dict() -> Dictionary:
	var r := {}
	for id in ranks:
		r[String(id)] = ranks[id]
	return {"version": 1, "ranks": r, "resets": resets}


## Restores [method to_dict] data: known talents only, ranks clamped to their max, nothing
## pending.
func from_dict(d: Dictionary) -> void:
	if int(d.get("version", 0)) != 1:
		push_warning("TalentState.from_dict: unknown version %s" % str(d.get("version")))
		return
	ranks.clear()
	pending.clear()
	var r: Variant = d.get("ranks", {})
	if typeof(r) == TYPE_DICTIONARY:
		for key: Variant in r:
			var t := talent(StringName(str(key)))
			var v: Variant = r[key]
			if t != null and typeof(v) in [TYPE_INT, TYPE_FLOAT] and int(v) > 0:
				ranks[t.id] = mini(int(v), t.max_rank)
	resets = maxi(0, int(d.get("resets", 0)))
	changed.emit()


# --- Internals -------------------------------------------------------------------------------

func _set_trees(p_trees: Array[TalentTreeData]) -> void:
	_trees.clear()
	_talents.clear()
	_tree_of.clear()
	for tree in p_trees:
		if tree != null:
			_trees.append(tree)
	_trees.sort_custom(func(a: TalentTreeData, b: TalentTreeData) -> bool:
		return a.index < b.index if a.index != b.index else String(a.id) < String(b.id))
	for tree in _trees:
		for t in tree.talents:
			if t != null and not _talents.has(t.id):
				_talents[t.id] = t
				_tree_of[t.id] = tree


## Points of [param tree] in tiers below [param tier].
func _points_in(tree: TalentTreeData, tier: int) -> int:
	var n := 0
	for t in tree.talents:
		if t != null and t.tier < tier:
			n += rank_of(t.id)
	return n


static func _take(d: Dictionary[StringName, int], id: StringName) -> void:
	var left := int(d.get(id, 0)) - 1
	if left > 0:
		d[id] = left
	else:
		d.erase(id)
