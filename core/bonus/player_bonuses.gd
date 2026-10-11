class_name PlayerBonuses
extends RefCounted
## The bonus-effect engine of one hero (M5, architecture §2.1): [code]player.bonuses[/code].
## Turns bonus-vocabulary entries (BonusVocabulary, talent_vocabulary.md) into game state. Each
## source replaces its whole entry list:
##   player.bonuses.set_effects(PlayerBonuses.SOURCE_TALENTS, player.talents.effects())
##   player.bonuses.set_effects(PlayerBonuses.SOURCE_SETS, SetBonuses.effects_for(player.equipment))
## Player calls the hooks below (hits, kills, damage taken, casts, avoided hits, wave start /
## end, ticks, teardown) and asks the queries on its hot paths (ability_mods_for, damage_mult,
## damage_taken_mult, crit_forced).
##
## Every [method set_effects] rebuilds everything derived from ALL sources (so a set bonus that
## changes the weapons, or a learned ability, re-evaluates the talent conditions too):
##   stats         summed per source into the StatBlock source named like it (&"talents",
##                 &"set_bonus"; "primary" = the class's primary stat), then
##                 Player.refresh_armor_spec() (Armor Specialization counts them).
##   ability       merged mods per ability id (BonusVocabulary.matches_id – pseudo ids too):
##                 [method ability_mods_for], which Player.ability_mods merges after the item mods.
##   damage        additive % on outgoing damage (1 + Σ pct / 100) with the filters source /
##                 school / target (+ target_pct) / self_below_pct / self_above_pct:
##                 [method damage_mult] (Player.outgoing_damage_mult).
##   damage_taken  additive % on incoming damage, max(0.1, 1 + Σ pct / 100), optional
##                 kind_filter: [method damage_taken_mult] (Player.take_damage).
##   resource      "<field>_add" amounts summed per resource id ("primary" = the class's first
##                 resource) and handed to ClassResource.set_bonus (every resource of the hero
##                 gets its sum – {} when none – on each rebuild).
##   proc          the rank-resolved "proc" dicts per source, handed to
##                 ProcSystem.set_extra_procs(source, defs) – each def gets the entry's "label"
##                 (unless the proc names one; "" silences it) and "id" (the talent / set bonus
##                 id) – followed by procs.refresh() when a source's defs changed.
##   script        one TalentEffect instance per entry ([method scripts]); diffed by
##                 source + id + index + rank + str(params): an unchanged script keeps its
##                 instance (and its wave state), a removed one gets teardown() before new ones
##                 are set up. Hooks run in source order (talents, set bonuses, others).
## Amounts are rank-scaled by BonusVocabulary.resolve (talent_vocabulary §2). An entry's
## "requires" ({"weapon": ...} / {"knows": <ability id>}) is checked on every rebuild: the
## Player's set_effects call in apply_equipment rebuilds after every equipment change, and the
## engine rebuilds itself on AbilityRunner.slots_changed when a "knows" condition flips.
## After a rebuild the ability params are invalidated and [signal changed] fires once.
##
## The hot paths (damage_mult, damage_taken_mult, crit_forced and the per-hit hooks) walk
## pre-built arrays: no allocation, no tree scan, no RNG. The engine itself never draws from
## RunState.rng; scripts and procs that roll chances do.

## The entries changed (and everything derived from them was rebuilt). Player invalidates the
## ability params on it; kits that cache derived numbers re-read them.
signal changed

const SOURCE_TALENTS := &"talents"
const SOURCE_SETS := &"set_bonus"
## Rebuild / hook order of the known sources; other sources follow in the order they were set.
const SOURCE_ORDER: Array[StringName] = [SOURCE_TALENTS, SOURCE_SETS]
## Floor of the damage_taken entries' multiplier (talent_vocabulary §3.4).
const MIN_DAMAGE_TAKEN_MULT := 0.1


## One conditional "damage" entry, pre-parsed for the hot path.
class DamageRule:
	var pct := 0.0
	## Empty = every source / school.
	var sources: Array[StringName] = []
	var schools: Array[StringName] = []
	## &"" or a BonusVocabulary.TARGET_CONDITIONS id.
	var target := &""
	var target_pct := 0.0
	## Hero HP % bounds (< 0 = no bound).
	var self_below := -1.0
	var self_above := -1.0

	func is_unconditional() -> bool:
		return sources.is_empty() and schools.is_empty() and target == &"" \
				and self_below < 0.0 and self_above < 0.0

	func applies(p: Player, hit_target: Node3D, school: StringName, source: StringName) -> bool:
		if not sources.is_empty() and source not in sources:
			return false
		if not schools.is_empty() and school not in schools:
			return false
		if self_below >= 0.0 or self_above >= 0.0:
			var m := p.max_hp()
			var hp_pct := p.hp / m * 100.0 if m > 0.0 else 0.0
			if self_below >= 0.0 and not hp_pct < self_below:
				return false
			if self_above >= 0.0 and not hp_pct > self_above:
				return false
		if target != &"":
			return PlayerBonuses.target_condition_met(hit_target, target, target_pct)
		return true


var player: Player

## Source -> its entries (as given; "rank" / "id" / "label" set by the source).
var _effects: Dictionary[StringName, Array] = {}

# --- Derived state (rebuilt from every source by _rebuild) ---
## Active, rank-resolved "ability" entries ({"match", "mods"}), in source order.
var _ability_entries: Array[Dictionary] = []
## ability id -> merged mods (read-only); cleared on rebuild.
var _mods_cache: Dictionary[StringName, Dictionary] = {}
## Σ pct of the unconditional damage entries; the conditional ones as rules.
var _damage_flat_pct := 0.0
var _damage_rules: Array[DamageRule] = []
## Σ pct of the damage_taken entries without / with a kind_filter.
var _taken_all_pct := 0.0
var _taken_by_kind: Dictionary[StringName, float] = {}
## Source -> the proc defs last handed to ProcSystem.set_extra_procs.
var _proc_defs: Dictionary[StringName, Array] = {}
## Live scripts in hook order, and the same instances by diff key.
var _scripts: Array[TalentEffect] = []
var _script_by_key: Dictionary[String, TalentEffect] = {}
## Every "knows" condition of the entries -> whether it held at the last rebuild.
var _knows_state: Dictionary[StringName, bool] = {}


static func create(p_player: Player) -> PlayerBonuses:
	var b := PlayerBonuses.new()
	b.player = p_player
	if p_player != null and p_player.abilities != null:
		p_player.abilities.slots_changed.connect(b._on_slots_changed)
	return b


## Replaces every entry of [param source] with [param entries] and rebuilds.
func set_effects(source: StringName, entries: Array[Dictionary]) -> void:
	_effects[source] = entries.duplicate(true)
	_rebuild()


## The entries [param source] last set (a copy; empty when none).
func effects_of(source: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var list: Array = _effects.get(source, [])
	for e: Dictionary in list:
		out.append(e.duplicate(true))
	return out


## Talent / set ability mods for [param ability_id] (merged like item mods – numbers summed,
## anything else replaces – and applied after them by Player.ability_mods). [param ability_id]
## may be a BonusVocabulary.PSEUDO_IDS id (kits read warlock_imp, paladin_aura … here).
## Cached per id until the next rebuild; the result is read-only.
func ability_mods_for(ability_id: StringName) -> Dictionary:
	var cached: Variant = _mods_cache.get(ability_id)
	if cached != null:
		return cached
	var out := {}
	if not _ability_entries.is_empty():
		var owner_class := _class_id()
		for e in _ability_entries:
			if BonusVocabulary.matches_id(e["match"], ability_id, owner_class):
				_merge_mods(out, e["mods"])
	out.make_read_only()
	_mods_cache[ability_id] = out
	return out


## Outgoing damage multiplier of the "damage" entries (1 + Σ pct / 100 of the matching ones)
## times the scripts' (Player.outgoing_damage_mult). [param source]: &"weapon", &"ability",
## &"dot", &"pet", &"proc"; [param target] may be null (target conditions then fail).
func damage_mult(target: Node3D, school: StringName, source: StringName) -> float:
	var pct := _damage_flat_pct
	for rule in _damage_rules:
		if rule.applies(player, target, school, source):
			pct += rule.pct
	var m := 1.0 + pct / 100.0
	for s in _scripts:
		m *= s.damage_mult(target, school, source)
	return maxf(0.0, m)


## Incoming damage multiplier of the "damage_taken" entries – max(0.1, 1 + Σ pct / 100) of the
## unfiltered ones and those whose kind_filter is [param kind] – times the scripts'
## (Player.take_damage). [param attacker] may be null.
func damage_taken_mult(kind: StringName, attacker: Node3D) -> float:
	var pct := _taken_all_pct
	if not _taken_by_kind.is_empty():
		pct += float(_taken_by_kind.get(kind, 0.0))
	var m := maxf(MIN_DAMAGE_TAKEN_MULT, 1.0 + pct / 100.0)
	for s in _scripts:
		m *= s.damage_taken_mult(kind, attacker)
	return maxf(0.0, m)


## True when a script forces the next weapon crit on [param target] (may be null: thrown
## knives roll at throw time).
func crit_forced(target: Node3D) -> bool:
	for s in _scripts:
		if s.crit_forced(target):
			return true
	return false


## The live TalentEffect instances (talents and set bonuses), in hook order (a copy).
func scripts() -> Array[TalentEffect]:
	return _scripts.duplicate()


## The live script of talent / set bonus [param source_id] (null when none).
func script_for(source_id: StringName) -> TalentEffect:
	for s in _scripts:
		if s.source_id == source_id:
			return s
	return null


## True when [param req] (an entry's "requires", or null / {} for none) holds for this hero.
func requires_met(req: Variant) -> bool:
	return PlayerBonuses.requirement_met(player, req)


# --- Hooks (Player) ----------------------------------------------------------------------------

## Every weapon hit: [param damage] = the base amount (architecture §2.1), [param first] = the
## attack's ProcGate hit.
func on_hit(target: Node3D, damage: float, is_crit: bool, first: bool) -> void:
	for s in _scripts:
		s.on_hit(target, damage, is_crit, first)


func on_kill(enemy: Node3D) -> void:
	for s in _scripts:
		s.on_kill(enemy)


func on_damage_taken(amount: float, attacker: Node3D) -> void:
	for s in _scripts:
		s.on_damage_taken(amount, attacker)


func on_cast(slot_index: int, ability: AbilityData) -> void:
	for s in _scripts:
		s.on_cast(slot_index, ability)


## &"dodge" / &"parry" / &"block".
func on_avoided(kind: StringName, attacker: Node3D) -> void:
	for s in _scripts:
		s.on_avoided(kind, attacker)


func begin_wave() -> void:
	for s in _scripts:
		s.begin_wave()


func end_wave() -> void:
	for s in _scripts:
		s.end_wave()


func tick(delta: float) -> void:
	for s in _scripts:
		s.tick(delta)


## The hero is leaving: every script tears down (a later rebuild would set them up again).
func teardown() -> void:
	var old := _scripts
	_scripts = []
	_script_by_key.clear()
	for s in old:
		s.teardown()


# --- Conditions (static: TalentBot asks them too) -----------------------------------------------

## True when [param req] ({"weapon": <WEAPON_REQUIREMENTS>} and / or {"knows": <ability id>};
## null or {} = no condition) holds for [param p] right now. Unknown keys never hold.
static func requirement_met(p: Player, req: Variant) -> bool:
	if typeof(req) != TYPE_DICTIONARY or (req as Dictionary).is_empty():
		return true
	if p == null:
		return false
	for key: Variant in req:
		var v := _name(req[key])
		match String(key):
			"weapon":
				if not weapon_requirement_met(p, v):
					return false
			"knows":
				if p.abilities == null or not p.abilities.knows(v):
					return false
			_:
				return false
	return true


## The weapon conditions of talent_vocabulary §2, on the equipped weapons (Player.main_hand /
## off_hand): two_handed / one_handed (main hand), dual_wield (two attacking weapons), shield
## (a shield in the off hand), melee (main hand MELEE_ARC), ranged (main hand PROJECTILE, not
## magic), magic (main hand of a spell school: wand, staff).
static func weapon_requirement_met(p: Player, req: StringName) -> bool:
	if p == null:
		return false
	var main := p.main_hand
	var off := p.off_hand
	match req:
		&"two_handed":
			return main != null and main.is_two_handed()
		&"one_handed":
			return main != null and main.hand == WeaponData.Hand.ONE_HAND
		&"dual_wield":
			return main != null and off != null and main.attacks() and off.attacks()
		&"shield":
			return off != null and off.weapon_type == &"shield"
		&"melee":
			return main != null and main.attack_kind == WeaponData.AttackKind.MELEE_ARC
		&"ranged":
			return main != null and main.attack_kind == WeaponData.AttackKind.PROJECTILE and not main.is_magic()
		&"magic":
			return main != null and main.is_magic()
	return false


## A "damage" entry's "target" condition on [param target] (an Enemy; anything else fails):
## elite (elites, the Loot Goblin, bosses), boss, stunned (a freeze is a stun), slowed, feared,
## below_pct / above_pct (target HP % vs [param target_pct], strict).
static func target_condition_met(target: Node3D, condition: StringName, target_pct: float) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var e := target as Enemy
	if e == null:
		return false
	match condition:
		&"elite":
			return e.is_elite() or e.is_boss()
		&"boss":
			return e.is_boss()
		&"stunned":
			return e.is_stunned()
		&"slowed":
			return e.is_slowed()
		&"feared":
			return e.is_feared()
		&"below_pct":
			return e.max_hp > 0.0 and e.hp / e.max_hp * 100.0 < target_pct
		&"above_pct":
			return e.max_hp > 0.0 and e.hp / e.max_hp * 100.0 > target_pct
	return false


# --- Rebuild -----------------------------------------------------------------------------------

func _rebuild() -> void:
	var stats_by_source: Dictionary[StringName, Dictionary] = {}
	var defs_by_source: Dictionary[StringName, Array] = {}
	var resource_sums: Dictionary[StringName, Dictionary] = {}
	## [key, entry (resolved), source] of every active script entry, in hook order.
	var wanted: Array[Array] = []
	_ability_entries = []
	_mods_cache.clear()
	_damage_flat_pct = 0.0
	_damage_rules = []
	_taken_all_pct = 0.0
	_taken_by_kind.clear()
	_knows_state.clear()
	for source in _ordered_sources():
		var stats := {}
		var defs: Array[Dictionary] = []
		## Script entries seen per id in this source (the diff key's index).
		var script_index: Dictionary[String, int] = {}
		for raw: Dictionary in _effects[source]:
			var kind := _name(raw.get("kind"))
			var index := 0
			if kind == &"script":
				var sid := str(raw.get("id", ""))
				index = int(script_index.get(sid, 0))
				script_index[sid] = index + 1
			_note_knows(raw.get("requires"))
			if not requires_met(raw.get("requires")):
				continue
			var rank := maxi(1, int(raw.get("rank", 1)))
			var e := BonusVocabulary.resolve(raw, rank)
			match kind:
				&"stats":
					_add_stats(stats, e.get("stats"))
				&"ability":
					if typeof(e.get("match")) == TYPE_DICTIONARY and typeof(e.get("mods")) == TYPE_DICTIONARY:
						_ability_entries.append({"match": e["match"], "mods": e["mods"]})
				&"damage":
					_add_damage(e)
				&"damage_taken":
					_add_damage_taken(e)
				&"resource":
					_add_resource(resource_sums, e)
				&"proc":
					var def := _proc_def(e)
					if not def.is_empty():
						defs.append(def)
				&"script":
					var key := "%s|%s|%d|%d|%s" % [source, str(raw.get("id", "")), index, rank, str(raw.get("params", {}))]
					wanted.append([key, e, source])
				_:
					push_warning("PlayerBonuses: unknown entry kind '%s' (%s)" % [kind, str(raw.get("id", ""))])
		stats_by_source[source] = stats
		defs_by_source[source] = defs
	_apply_stats(stats_by_source)
	_apply_resources(resource_sums)
	_apply_procs(defs_by_source)
	_apply_scripts(wanted)
	if player != null and player.abilities != null:
		player.abilities.invalidate_params()
	changed.emit()


func _ordered_sources() -> Array[StringName]:
	var out: Array[StringName] = []
	for s in SOURCE_ORDER:
		if _effects.has(s):
			out.append(s)
	for s in _effects:
		if s not in out:
			out.append(s)
	return out


## Remembers a "knows" condition so slots_changed only rebuilds when one of them flips.
func _note_knows(req: Variant) -> void:
	if typeof(req) != TYPE_DICTIONARY or not (req as Dictionary).has("knows"):
		return
	var id := _name(req["knows"])
	_knows_state[id] = player != null and player.abilities != null and player.abilities.knows(id)


func _add_stats(into: Dictionary, stats: Variant) -> void:
	if typeof(stats) != TYPE_DICTIONARY:
		return
	for key: Variant in stats:
		var v: Variant = stats[key]
		if typeof(v) not in [TYPE_INT, TYPE_FLOAT]:
			continue
		var stat := _name(key)
		if stat == &"primary":
			if player == null or player.class_data == null:
				continue
			stat = player.class_data.primary_stat
		into[stat] = float(into.get(stat, 0.0)) + float(v)


func _add_damage(e: Dictionary) -> void:
	var r := DamageRule.new()
	r.pct = float(e.get("pct", 0.0))
	r.sources = _names(e.get("source"))
	r.schools = _names(e.get("school"))
	r.target = _name(e.get("target", ""))
	r.target_pct = float(e.get("target_pct", 0.0))
	r.self_below = float(e["self_below_pct"]) if e.has("self_below_pct") else -1.0
	r.self_above = float(e["self_above_pct"]) if e.has("self_above_pct") else -1.0
	if r.is_unconditional():
		_damage_flat_pct += r.pct
	else:
		_damage_rules.append(r)


func _add_damage_taken(e: Dictionary) -> void:
	var pct := float(e.get("pct", 0.0))
	if e.has("kind_filter"):
		var k := _name(e["kind_filter"])
		_taken_by_kind[k] = float(_taken_by_kind.get(k, 0.0)) + pct
	else:
		_taken_all_pct += pct


func _add_resource(sums: Dictionary[StringName, Dictionary], e: Dictionary) -> void:
	var id := _name(e.get("resource", ""))
	if id == &"primary":
		if player == null or player.abilities == null or player.abilities.resource_order.is_empty():
			return
		id = player.abilities.resource_order[0]
	var sum: Dictionary = sums.get(id, {})
	for key: Variant in e:
		var k := String(key)
		var v: Variant = e[key]
		if not k.ends_with("_add") or typeof(v) not in [TYPE_INT, TYPE_FLOAT]:
			continue
		sum[k] = float(sum.get(k, 0.0)) + float(v)
	sums[id] = sum


## The ProcSystem params dict of a resolved "proc" entry ({} when it has none): the entry's
## label and id ride along unless the proc dict sets them.
static func _proc_def(e: Dictionary) -> Dictionary:
	var p: Variant = e.get("proc")
	if typeof(p) != TYPE_DICTIONARY:
		return {}
	var def: Dictionary = (p as Dictionary).duplicate(true)
	if not def.has("label") and e.has("label"):
		def["label"] = str(e["label"])
	if not def.has("id") and e.has("id"):
		def["id"] = str(e["id"])
	return def


func _apply_stats(stats_by_source: Dictionary[StringName, Dictionary]) -> void:
	if player == null or player.stats == null:
		return
	var touched := false
	for source in stats_by_source:
		var stats := stats_by_source[source]
		if stats.is_empty():
			if player.stats.has_source(source):
				player.stats.remove_source(source)
				touched = true
			continue
		if not player.stats.has_source(source) or player.stats.get_source(source) != _as_stat_dict(stats):
			player.stats.set_source(source, stats)
			touched = true
	if touched:
		player.refresh_armor_spec()


func _apply_resources(sums: Dictionary[StringName, Dictionary]) -> void:
	if player == null or player.abilities == null:
		return
	for id in player.abilities.resources:
		player.abilities.resources[id].set_bonus(sums.get(id, {}))


## Hands changed sources to ProcSystem. The trailing refresh() is here because the P0
## set_extra_procs only stores; once it rebuilds on its own (T-CORE-B), drop the refresh()
## here so ProcSystem is its single owner (otherwise each proc change rebuilds twice).
func _apply_procs(defs_by_source: Dictionary[StringName, Array]) -> void:
	if player == null or player.procs == null:
		return
	var dirty := false
	for source in defs_by_source:
		var defs: Array = defs_by_source[source]
		if defs == _proc_defs.get(source, []):
			continue
		var typed: Array[Dictionary] = []
		typed.assign(defs)
		player.procs.set_extra_procs(source, typed)
		_proc_defs[source] = defs.duplicate(true)
		dirty = true
	if dirty:
		player.procs.refresh()


## Keeps unchanged scripts, tears the removed ones down, then sets the new ones up (so a new
## rank of a script never loses the stat source / guard key its old rank shared with it).
func _apply_scripts(wanted: Array[Array]) -> void:
	var old_by_key := _script_by_key
	var kept: Dictionary[String, bool] = {}
	for w in wanted:
		if old_by_key.has(w[0]):
			kept[w[0]] = true
	for key in old_by_key:
		if not kept.has(key):
			old_by_key[key].teardown()
	var next: Array[TalentEffect] = []
	var next_by_key: Dictionary[String, TalentEffect] = {}
	for w in wanted:
		var key: String = w[0]
		if next_by_key.has(key):
			continue
		var inst: TalentEffect = old_by_key.get(key) if kept.has(key) else _make_script(w[1])
		if inst == null:
			continue
		next.append(inst)
		next_by_key[key] = inst
	_scripts = next
	_script_by_key = next_by_key


## A set-up TalentEffect for the resolved script entry [param e] (null + error when the path
## does not give one).
func _make_script(e: Dictionary) -> TalentEffect:
	var path := str(e.get("script", ""))
	var script := load(path) as Script if ResourceLoader.exists(path) else null
	if script == null or not script.can_instantiate():
		push_error("PlayerBonuses: cannot load talent script '%s' (%s)" % [path, str(e.get("id", ""))])
		return null
	var inst := script.new() as TalentEffect
	if inst == null:
		push_error("PlayerBonuses: '%s' does not extend TalentEffect" % path)
		return null
	inst.source_id = StringName(str(e.get("id", "")))
	var params: Variant = e.get("params", {})
	var rank := maxi(1, int(e.get("rank", 1)))
	inst.setup(player, rank, (params as Dictionary).duplicate(true) if typeof(params) == TYPE_DICTIONARY else {})
	return inst


func _on_slots_changed() -> void:
	if _knows_state.is_empty() or player == null or player.abilities == null:
		return
	for id in _knows_state:
		if player.abilities.knows(id) != _knows_state[id]:
			_rebuild()
			return


func _class_id() -> StringName:
	return player.class_data.id if player != null and player.class_data != null else &""


# --- Helpers -----------------------------------------------------------------------------------

## Adds [param mods] into [param out] like Player._merge_mods: numbers on a numeric key are
## summed, anything else replaces.
static func _merge_mods(out: Dictionary, mods: Dictionary) -> void:
	for key: Variant in mods:
		var k := String(key)
		var v: Variant = mods[key]
		if typeof(v) in [TYPE_INT, TYPE_FLOAT] and out.has(k) and typeof(out[k]) in [TYPE_INT, TYPE_FLOAT]:
			out[k] = float(out[k]) + float(v)
		else:
			out[k] = v


## [param stats] as StatBlock stores a source (StringName -> float), for comparisons.
static func _as_stat_dict(stats: Dictionary) -> Dictionary:
	var out: Dictionary[StringName, float] = {}
	for key: Variant in stats:
		out[StringName(key)] = float(stats[key])
	return out


static func _name(v: Variant) -> StringName:
	if typeof(v) in [TYPE_STRING, TYPE_STRING_NAME]:
		return StringName(v)
	return &""


## A name or an array of names as StringNames ([] for none).
static func _names(v: Variant) -> Array[StringName]:
	var out: Array[StringName] = []
	if typeof(v) == TYPE_ARRAY:
		for x: Variant in v:
			var n := _name(x)
			if n != &"":
				out.append(n)
	else:
		var n := _name(v)
		if n != &"":
			out.append(n)
	return out
