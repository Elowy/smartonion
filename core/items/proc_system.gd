class_name ProcSystem
extends Node
## Runs a player's enchantments and unique item effects (GDD 5.7). Child node "Procs" of its
## Player; [method refresh] rebuilds the list from the equipped items on equipment.changed.
##
## Every effect is one of a small set of reusable building blocks, configured by a params
## Dictionary (shared vocabulary for EnchantData.effect / .params and
## ItemInstance.unique_effect / .unique_params):
##
## Trigger keys: "trigger": "on_hit" | "on_kill" | "when_struck" | "low_hp" | "periodic" |
## "equip" (uniques; enchants take it from EnchantData.kind), "ppm" (on_hit: chance per hit =
## ppm x weapon cooldown / 60), "chance" (% – on_kill / when_struck / low_hp / periodic, or
## on_hit without ppm; default 100), "icd" (internal cooldown, s), "threshold" (low_hp: HP
## PERCENT 0..100, not a 0..1 ratio – 25 fires when HP drops below 25% of Max HP; default 30;
## re-arms once HP is back at or above it), "interval" (periodic, s, default 5), "per_wave"
## (max fires per wave, 0 = unlimited; cheat_death defaults to 1 – e.g. Bulwark of the Last
## Stand: low_hp shield with per_wave 1). Cooldowns and per-wave counts reset at wave start.
##
## Blocks (effect id {params}):
##   bolt {damage, school}            – the hit target (else the nearest enemy)
##   chain {damage, targets, school}  – jumps to the nearest new enemy within CHAIN_RANGE
##   dot {damage (total), duration, stacks, school} – a re-proc adds a stack (up to stacks)
##                                      and refreshes the duration; ticks every DOT_TICK
##   nova {damage, radius, school, at: "self"|"target", slow (opt %), stun (opt s)}
##   explode {damage, radius, school} – at the target / the corpse (on_kill)
##   extra_attack {count}             – instant extra attacks of the hitting weapon
##   buff {stats: Dictionary, duration} – temporary stats (stat ids or "primary" = the class's
##                                      primary stat; numeric params named like a stat are
##                                      added too); duration <= 0 = until the wave ends;
##                                      optional max_stacks (default 1), heal (self)
##                                      ("equip" trigger: permanent while equipped)
##   heal {amount, target: "self"|"lowest_ally"}
##   drain {damage, school}           – heals the wearer for the damage dealt
##   slow {pct, duration}   stun {duration}   gold {amount}
##   shield {amount, duration}        – absorbs damage (default 5 s)
##   reflect {damage, school}         – hits the attacker (when_struck)
##   smite_heal {damage, heal, school} – damage + heal the most injured ally
##   cheat_death {invulnerable}       – lethal damage leaves 1 HP + invulnerable seconds
##                                      (passive, once per wave unless per_wave says more)
##   resource {amount}                – class resource (AbilityRunner.gain_from_proc)
## Riders on every damaging block: slow (%) + slow_duration (default 2 s), stun (s),
## dot (total) + dot_duration (default 3 s) + dot_stacks (default 1), spread (m: when an enemy
## burning with the dot dies, it spreads to up to SPREAD_TARGETS enemies in that radius).
##
## Enchant numbers scale with the rank (EnchantRoll.param, x1 / x1.5 / x2); a key ending in
## "_fixed" (e.g. "targets_fixed") is used unscaled under the plain name ("targets").
## Unique params are used as they are. "school" defaults to EnchantData.school / physical.
## Proc damage = CombatMath.proc_damage (+Spell Power for spell schools, +Attack Power for
## physical; Versatility, Damage %, school %) x Executioner / Slayer. Procs never crit, and
## proc damage is never a weapon hit: it cannot trigger on-hit procs (no chains); extra-attack
## hits cannot trigger more extra attacks. On-kill procs may follow proc kills (MAX_DEPTH).
## All rolls use RunState.rng (only when a roll is needed), target queries go through
## [EnemyGrid]. When-struck enchants on WEAPON items are meant for shields only (the
## generator's job).
##
## M5 (talents and set bonuses, also open to unique items):
## - Extra procs: [method set_extra_procs] stores the rank-resolved "proc" entries of a
##   source (PlayerBonuses: &"talents", &"set_bonus"; it calls [method refresh] afterwards),
##   [method refresh] builds them after the items ([method proc_from_params]: numbers used as
##   written, the label defaults to the entry's label – the talent / set name).
## - Triggers: "on_crit" (the attack's first hit crit – inside [method on_hit], same once-per-
##   attack gate; chance default 100), "on_cast" ([method on_ability_cast]; filter "ability"
##   id or "match" dict as BonusVocabulary.matches – none = every cast), "wave_start"
##   ([method after_wave_start], after the class resources were reset), "on_dodge" /
##   "on_parry" / "on_block" ([method on_avoided]; the attacker is the target, extra_attack
##   allowed). "periodic" rolls "chance" once per interval.
## - Keys: "every" (N: every Nth qualifying event fires instead of the chance roll; the count
##   carries over while the proc is on cooldown / spent for the wave and resets at wave start),
##   "hit_pct" (on_hit / on_crit: every damaging block – bolt, chain, nova, explode, drain,
##   reflect, smite_heal – deals that % of the hit's base amount (Player.on_hit_dealt) through
##   deal_raw(..., target_bonus = false, &"proc"); a dot takes it as its total and ticks with
##   target_bonus = false; a drain heals what it dealt), "max_hp_pct" (heal / shield: % of the
##   receiver's Max HP, added to "amount"), "target": "self" | "lowest_ally" (heal, shield),
##   "label": "" (no floating text of any block; any other string replaces the label – also in
##   a unique item's params and an enchant's params, which default to the item name / prefix).
## - Blocks: cooldown {ability | match, reduce (s) | reset: true} (AbilityRunner.reduce_cooldown:
##   one charge back at most / set_cooldown(a, 0)), forced_crit {count} (Player.forced_crits),
##   resource {resource: <id> | "primary", value} (ClassResource.add(value, true): Resource
##   Regen scales bars, pips are exact) next to the item form resource {amount}.
## - Labels: buff, shield, cheat_death, cooldown, forced_crit, resource {resource} (and heal of
##   talent / set procs) show the proc's label above the hero; damaging blocks show numbers.

## A proc fired (effect id = block id). Also for no-op blocks such as resource.
signal proc_fired(proc_id: StringName, effect: StringName)

const TRIGGER_ON_HIT := &"on_hit"
const TRIGGER_ON_KILL := &"on_kill"
const TRIGGER_WHEN_STRUCK := &"when_struck"
const TRIGGER_LOW_HP := &"low_hp"
const TRIGGER_PERIODIC := &"periodic"
const TRIGGER_EQUIP := &"equip"
const TRIGGER_ON_CRIT := &"on_crit"
const TRIGGER_ON_CAST := &"on_cast"
const TRIGGER_WAVE_START := &"wave_start"
const TRIGGER_ON_DODGE := &"on_dodge"
const TRIGGER_ON_PARRY := &"on_parry"
const TRIGGER_ON_BLOCK := &"on_block"
## Triggers whose event is a weapon hit: "hit_pct" only works there.
const HIT_TRIGGERS: Array[StringName] = [TRIGGER_ON_HIT, TRIGGER_ON_CRIT]

## Every building block ProcSystem runs (unknown effect ids are ignored – e.g. M3 ability
## modifiers on uniques).
const BLOCKS: Array[StringName] = [
	&"bolt", &"chain", &"dot", &"nova", &"explode", &"extra_attack", &"buff", &"heal",
	&"drain", &"slow", &"stun", &"gold", &"shield", &"reflect", &"smite_heal", &"cheat_death",
	&"resource",
]
## The M5 blocks (BonusVocabulary.PROC_BLOCKS = BLOCKS + these): cooldown, forced_crit.
const EXTRA_BLOCKS: Array[StringName] = [&"cooldown", &"forced_crit"]
## Blocks that need a living enemy to do anything (periodic / low-HP procs wait for one).
const NEEDS_ENEMY: Array[StringName] = [
	&"bolt", &"chain", &"dot", &"nova", &"explode", &"extra_attack", &"drain", &"slow", &"stun",
	&"reflect", &"smite_heal",
]

const DEFAULT_THRESHOLD := 30.0
const DEFAULT_INTERVAL := 5.0
## Periodic procs that found no enemy try again after this many seconds.
const PERIODIC_RETRY := 0.25
## Procs without a live hit target (on kill, periodic, low HP ...) pick the nearest enemy
## within this range (m) of the event.
const TARGET_RANGE := 9.0
## Chain lightning jumps at most this far (m).
const CHAIN_RANGE := 5.0
const DOT_TICK := 0.5
## Timers within this of zero count as run out (float steps of 1/60 s).
const TIME_EPSILON := 0.0001
const DEFAULT_DOT_DURATION := 3.0
const DEFAULT_SLOW_DURATION := 2.0
const DEFAULT_SHIELD_DURATION := 5.0
const DEFAULT_RADIUS := 2.5
const DEFAULT_INVULNERABLE := 2.0
const SPREAD_TARGETS := 3
## A spread DoT spreads again at most this many times.
const MAX_SPREAD_GENERATION := 2
## Nested proc resolutions (a proc kill firing on-kill procs ...) stop at this depth.
const MAX_DEPTH := 3
const DAMAGE_TEXT_SIZE := 0.7
const LABEL_TEXT_SIZE := 0.8
const SHIELD_COLOR := Color(0.6, 0.85, 1.0)
const GOLD_COLOR := Color(1.0, 0.82, 0.3)


## One active effect (an enchant roll or a unique item's effect).
class Proc extends RefCounted:
	var uid := 0
	var id: StringName
	## Shown in floating texts ("Bloodlust").
	var label := ""
	var effect: StringName
	var trigger: StringName
	## Resolved params (String keys; enchant numbers already at the rank).
	var params: Dictionary = {}
	var school: StringName = &"physical"
	var ppm := 0.0
	## Percent.
	var chance := 100.0
	var icd := 0.0
	var threshold := DEFAULT_THRESHOLD
	var interval := DEFAULT_INTERVAL
	var per_wave := 0
	var item: ItemInstance
	## M5 "every": fires on every Nth qualifying event instead of rolling (0 = off).
	var every := 0
	## M5 "hit_pct" (on_hit / on_crit only): damaging blocks deal this % of the hit's base
	## amount (0 = their "damage").
	var hit_pct := 0.0
	## M5: a talent / set proc (set_extra_procs) – its heal shows the label too.
	var extra := false
	## M5 on_cast filter: an ability id, else a BonusVocabulary "match" dict (both empty = any).
	var cast_ability: StringName = &""
	var cast_match: Dictionary = {}
	# Runtime state.
	var cd_left := 0.0
	var timer := 0.0
	var armed := true
	var fired_wave := 0
	var fired_total := 0
	## Qualifying events counted towards "every" (reset at wave start).
	var counter := 0

	func num(key: String, default: float = 0.0) -> float:
		var v: Variant = params.get(key, default)
		return float(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else default

	func text(key: String, default: String = "") -> String:
		return str(params.get(key, default))


## A damage-over-time effect on one enemy.
class Dot extends RefCounted:
	var proc: Proc
	var target_id := 0
	var school: StringName
	## Damage per second per stack (already multiplied).
	var rate := 0.0
	var stacks := 1
	var max_stacks := 1
	var duration := 0.0
	var left := 0.0
	var tick_left := 0.0
	var owed := 0.0
	var spread := 0.0
	var generation := 0
	var last_pos := Vector3.ZERO
	## Executioner / Slayer on the ticks (false for a "hit_pct" dot – derived from a hit).
	var target_bonus := true


## A running temporary stat buff.
class Buff extends RefCounted:
	var proc: Proc
	var source: StringName
	var stats: Dictionary = {}
	var stacks := 1
	var max_stacks := 1
	var left := 0.0


## One absorb shield: [member hp] left for [member left] more seconds. Shields of one
## [member source] cast by the same hero share an entry (&"" = item procs and other anonymous
## shields). [member owner_slot] = the slot index of the hero who cast it (the damage meter credits
## the damage it soaks to them; -1 = nobody).
class Shield extends RefCounted:
	var source: StringName = &""
	var owner_slot := -1
	var hp := 0.0
	var left := 0.0


var player: Player
## Every active proc (equipment order).
var procs: Array[Proc] = []
## Total absorb shield HP of every entry (overhead health bar, tests). Read-only: shields come
## from [method add_shield] and go with [method absorb], their timers and [method clear_shields]
## (an assignment only reports an error, so it can never wipe a named entry such as Ice
## Barrier's, and a stray write shows up in smoke runs and the test log).
var shield_hp: float:
	get:
		var total := 0.0
		for s in _shields:
			total += s.hp
		return total
	set(_value):
		push_error("ProcSystem.shield_hp is read-only: use add_shield() / clear_shields()")
## Damage the absorb shields have soaked so far, all entries together (only grows; never
## reset). Effects compare it between ticks to notice hits on any shield (Ice Barrier's Rank
## III chill: whichever shield soaked the blow, the attacker struck the barrier's bubble).
var absorbed_total := 0.0
## Seconds left of the longest-lasting shield (0 = none).
var shield_left: float:
	get:
		var longest := 0.0
		for s in _shields:
			longest = maxf(longest, s.left)
		return longest

var _on_hit: Array[Proc] = []
var _on_kill: Array[Proc] = []
var _when_struck: Array[Proc] = []
var _low_hp: Array[Proc] = []
var _periodic: Array[Proc] = []
var _cheat_death: Array[Proc] = []
var _on_crit: Array[Proc] = []
var _on_cast: Array[Proc] = []
var _wave_start: Array[Proc] = []
var _on_dodge: Array[Proc] = []
var _on_parry: Array[Proc] = []
var _on_block: Array[Proc] = []
var _dots: Array[Dot] = []
var _buffs: Array[Buff] = []
## Absorb shields, one entry per source; each runs out on its own timer.
var _shields: Array[Shield] = []
## Stat sources of "equip"-trigger buffs.
var _equip_sources: Array[StringName] = []
var _gold_carry := 0.0
var _depth := 0
var _next_uid := 1
## M5, see PlayerBonuses: the proc defs of talents / set bonuses per source
## ([method set_extra_procs]), built into [member procs] by [method refresh] after the items.
var _extra_defs: Dictionary[StringName, Array] = {}
## Base amount of the weapon hit being resolved (on_hit / on_crit procs; "hit_pct").
var _hit_base := 0.0


static func create(owner_player: Player) -> ProcSystem:
	var ps := ProcSystem.new()
	ps.name = "Procs"
	ps.player = owner_player
	return ps


## Rebuilds the active list (call on equipment.changed): the equipped items' enchants and
## unique effects, then the talent / set procs of [method set_extra_procs] (source order,
## then entry order). Running buffs from the old list end; DoTs already on enemies keep
## ticking.
func refresh() -> void:
	_clear_buffs()
	for source in _equip_sources:
		if player != null:
			player.stats.remove_source(source)
	_equip_sources.clear()
	procs.clear()
	for list: Array[Proc] in [_on_hit, _on_kill, _when_struck, _low_hp, _periodic, _cheat_death,
			_on_crit, _on_cast, _wave_start, _on_dodge, _on_parry, _on_block]:
		list.clear()
	if player == null:
		return
	if player.equipment != null:
		for s in Items.EquipSlot.values():
			var item := player.equipment.get_item(s)
			if item == null:
				continue
			for roll in item.proc_enchants():
				_add(proc_from_enchant(roll, item))
			if item.unique_effect != &"":
				_add(proc_from_unique(item))
	for source: StringName in _extra_defs:
		var defs: Array = _extra_defs[source]
		for i in defs.size():
			_add(proc_from_def(defs[i], source, i))


## A weapon hit landed (not called for proc damage). [param damage]: the hit's base amount
## (Player.on_hit_dealt; what "hit_pct" blocks derive from). [param is_crit]: on_crit procs
## fire too. [param is_extra]: a hit of an extra attack – it cannot trigger extra_attack procs.
## Called once per attack (the ProcGate hit), so on_hit / on_crit roll once per attack.
func on_hit(target: Node3D, damage: float, weapon: WeaponData, is_crit: bool, is_extra: bool = false) -> void:
	if (_on_hit.is_empty() and (not is_crit or _on_crit.is_empty())) or not _active():
		return
	var cd := weapon.cooldown if weapon != null else 1.0
	var pos := _pos_of(target)
	# An extra_attack block resolves its hits right away (re-entering on_hit): keep ours.
	var outer_base := _hit_base
	_hit_base = damage
	for p in _on_hit:
		if is_extra and p.effect == &"extra_attack":
			continue
		var c := CombatMath.ppm_chance(p.ppm, cd) if p.ppm > 0.0 else p.chance / 100.0
		_try_fire(p, c, target, pos, weapon)
		_hit_base = damage
	if is_crit:
		for p in _on_crit:
			if is_extra and p.effect == &"extra_attack":
				continue
			var c := CombatMath.ppm_chance(p.ppm, cd) if p.ppm > 0.0 else p.chance / 100.0
			_try_fire(p, c, target, pos, weapon)
			_hit_base = damage
	_hit_base = outer_base


func on_kill(enemy: Node3D) -> void:
	if _on_kill.is_empty() or not _active():
		return
	var pos := _pos_of(enemy)
	for p in _on_kill:
		_try_fire(p, p.chance / 100.0, enemy, pos, null)


## The player took a hit (after dodge / block).
func on_struck(attacker: Node3D, _damage: float) -> void:
	if not _active():
		return
	if not _when_struck.is_empty():
		var pos := _pos_of(attacker)
		for p in _when_struck:
			_try_fire(p, p.chance / 100.0, attacker, pos, null)
	_check_low_hp()


## M5, see PlayerBonuses: the proc entries of [param source] (&"talents", &"set_bonus"),
## rank-resolved. Each def is either a whole entry ({"kind": "proc", "proc": {...}, "label",
## "id", ...}: the "proc" dict is used, the entry's label is the default label, its id the
## proc id) or a bare ProcSystem params dict (its own "label" / "id" keys, if any). Stores
## only: replaces the source's defs (an empty array removes the source; identical defs are a
## no-op), and the next [method refresh] builds them – the caller (PlayerBonuses) refreshes
## once after handing over every changed source.
func set_extra_procs(source: StringName, defs: Array[Dictionary]) -> void:
	if _same_defs(_extra_defs.get(source, []), defs):
		return
	if defs.is_empty():
		_extra_defs.erase(source)
	else:
		_extra_defs[source] = defs.duplicate(true)


## The extra defs of [param source] as stored (tests, UI; empty when none).
func extra_defs(source: StringName) -> Array:
	return _extra_defs.get(source, [])


static func _same_defs(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if typeof(a[i]) != TYPE_DICTIONARY or typeof(b[i]) != TYPE_DICTIONARY or a[i] != b[i]:
			return false
	return true


## M5: one of the player's abilities was cast (Player._on_ability_cast) – on_cast procs whose
## filter matches it fire (no hit target: damaging blocks pick the nearest enemy).
func on_ability_cast(ability: AbilityData) -> void:
	if _on_cast.is_empty() or ability == null or not _active():
		return
	var pos := _player_pos()
	var class_id := player.class_data.id if player.class_data != null else &""
	for p in _on_cast:
		if _cast_matches(p, ability, class_id):
			_try_fire(p, p.chance / 100.0, null, pos, null)


static func _cast_matches(p: Proc, ability: AbilityData, class_id: StringName) -> bool:
	if p.cast_ability != &"":
		return ability.id == p.cast_ability
	if not p.cast_match.is_empty():
		return BonusVocabulary.matches(p.cast_match, ability, class_id)
	return true


## M5: the player dodged / parried / blocked ([param kind] &"dodge" / &"parry" / &"block",
## Player.take_damage) a hit of [param attacker] (may be null) – on_dodge / on_parry /
## on_block procs fire with the attacker as their target.
func on_avoided(kind: StringName, attacker: Node3D) -> void:
	var list: Array[Proc] = _on_dodge
	match kind:
		&"parry":
			list = _on_parry
		&"block":
			list = _on_block
		&"dodge":
			pass
		_:
			return
	if list.is_empty() or not _active():
		return
	var pos := _pos_of(attacker)
	for p in list:
		_try_fire(p, p.chance / 100.0, attacker, pos, null)


## M5: called by Player.begin_wave after the class resources were reset
## (AbilityRunner.begin_wave), so a wave_start proc's resource / cooldown effect is not wiped:
## the wave_start procs fire here (after [method begin_wave] re-armed them).
func after_wave_start() -> void:
	if _wave_start.is_empty() or not _active():
		return
	var pos := _player_pos()
	for p in _wave_start:
		_try_fire(p, p.chance / 100.0, null, pos, null)


## Wave start: cooldowns, per-wave limits, "every" counters and low-HP triggers re-arm; DoTs,
## timed buffs and shields from the last wave end.
func begin_wave() -> void:
	for p in procs:
		p.cd_left = 0.0
		p.fired_wave = 0
		p.armed = true
		if p.trigger != TRIGGER_WAVE_START:
			p.counter = 0  # a wave_start "every N" counts waves, so it keeps counting
		p.timer = p.interval
	_dots.clear()
	_clear_buffs()
	clear_shields()


## Wave end (Player.end_wave, as the market opens): the timed and until-the-next-wave buffs
## end, so the market's stats – and Armor Specialization recomputed there – never see them.
## "equip" buffs stay; cooldowns, DoTs and shields wait for [method begin_wave].
func end_wave() -> void:
	_clear_buffs()


## Adds an absorb shield (shield procs, Word of Glory, Ice Barrier ...): [param amount] HP for
## up to [param duration] seconds. Shields of one [param source] from one caster stack in one
## entry (the longer timer wins); shields of different sources (or casters) keep their own
## timers. [param owner_slot] = the slot index of the hero who cast it, credited with the damage
## it absorbs ([method absorb], the damage meter); -1 = this hero's own shield.
func add_shield(amount: float, duration: float, source: StringName = &"", owner_slot: int = -1) -> void:
	if amount <= 0.0:
		return
	var caster := owner_slot if owner_slot >= 0 else Player.slot_index_of(player)
	var entry := _shield_entry(source, caster)
	if entry == null:
		entry = Shield.new()
		entry.source = source
		entry.owner_slot = caster
		_shields.append(entry)
	entry.hp += amount
	entry.left = maxf(entry.left, duration)


## Removes every absorb shield, named entries included ([method begin_wave], tests).
func clear_shields() -> void:
	_shields.clear()


## Shield HP left from [param source], every caster together (0 = none).
func shield_of(source: StringName) -> float:
	var total := 0.0
	for s in _shields:
		if s.source == source:
			total += s.hp
	return total


func _shield_entry(source: StringName, caster: int) -> Shield:
	for s in _shields:
		if s.source == source and s.owner_slot == caster:
			return s
	return null


## Damage left after the absorb shields took their share ("Absorb" text when they took all).
## The shield that runs out first soaks first.
func absorb(damage: float) -> float:
	if _shields.is_empty() or damage <= 0.0:
		return damage
	var rest := damage
	while rest > 0.0 and not _shields.is_empty():
		var first := 0
		for i in range(1, _shields.size()):
			if _shields[i].left < _shields[first].left:
				first = i
		var s := _shields[first]
		var taken := minf(s.hp, rest)
		s.hp -= taken
		rest -= taken
		RunState.record_absorb(s.owner_slot, taken)
		if s.hp <= 0.0001:
			_shields.remove_at(first)
	absorbed_total += damage - rest
	if rest <= 0.0 and player != null:
		Vfx.floating_text(player.self_text_position(1.0), "Absorb", SHIELD_COLOR, Player.SELF_TEXT_SIZE, 1.0)
	return rest


## Lethal damage: a ready cheat_death effect saves the player (true) – the caller leaves it
## at 1 HP; this grants the invulnerability.
func try_cheat_death() -> bool:
	if player == null:
		return false
	for p in _cheat_death:
		if p.cd_left > 0.0 or (p.per_wave > 0 and p.fired_wave >= p.per_wave):
			continue
		_mark_fired(p)
		player.invulnerable_left = maxf(player.invulnerable_left, p.num("invulnerable", DEFAULT_INVULNERABLE))
		var pos := player.global_position if player.is_inside_tree() else player.position
		Vfx.explosion(pos + Vector3.UP * 0.1, 1.6, ProcVfx.school_color(&"frost"))
		_label(p, ProcVfx.school_color(&"frost"))
		proc_fired.emit(p.id, p.effect)
		return true
	return false


## Proc damage of [param school] with base [param base] on [param target] (Spell / Attack
## Power, Versatility, school %, Executioner / Slayer). Never a weapon hit: no on-hit procs,
## no leech. Returns the damage dealt.
func deal(target: Enemy, base: float, school: StringName) -> float:
	if player == null:
		return 0.0
	return deal_raw(target, CombatMath.proc_damage(base, school, player.stats), school, true)


## Applies [param amount] as this player's non-weapon damage (procs, DoT ticks, Thorns,
## abilities – [param source] &"proc" / &"dot" / &"ability" / &"pet" for Mastery hooks):
## records it, credits a kill, shows a number in the school colour. [param target_bonus]:
## Executioner / Slayer apply. Returns the damage dealt.
func deal_raw(target: Enemy, amount: float, school: StringName, target_bonus: bool = true,
		source: StringName = &"proc") -> float:
	if player == null or amount <= 0.0 or not _is_live(target):
		return 0.0
	amount *= player.outgoing_damage_mult(target, school, source)
	if target_bonus:
		var ratio := target.hp / target.max_hp if target.max_hp > 0.0 else 1.0
		amount *= CombatMath.target_damage_mult(player.stats, ratio, target.is_elite())
	var text_pos := target.global_position + Vector3.UP * WeaponRunner.DAMAGE_TEXT_HEIGHT
	var dealt := minf(amount, maxf(0.0, target.hp))
	if player.slot != null:
		RunState.record_damage(player.slot.index, dealt)
	target.take_damage(amount, false, player)
	Vfx.damage_number(null, text_pos, amount, ProcVfx.school_color(school), DAMAGE_TEXT_SIZE)
	# Pet leech (Skull of the Damned): a share of what a pet dealt heals the hero.
	if player.pet_leech_pct > 0.0 and source == &"pet":
		player.heal(dealt * player.pet_leech_pct / 100.0, player.slot.index if player.slot != null else -1)
	return amount


## Times [param proc_id] fired since the list was built (tests, UI).
func fire_count(proc_id: StringName) -> int:
	var n := 0
	for p in procs:
		if p.id == proc_id:
			n += p.fired_total
	return n


## Running DoTs (tests, UI).
func dot_count() -> int:
	return _dots.size()


## Stacks of [param proc_id]'s DoT on [param enemy] (0 = none).
func dot_stacks(enemy: Node3D, proc_id: StringName) -> int:
	if enemy == null:
		return 0
	var id := enemy.get_instance_id()
	for d in _dots:
		if d.target_id == id and d.proc.id == proc_id:
			return d.stacks
	return 0


# --- Building the list ------------------------------------------------------------------

## The proc of an enchant roll (null for EQUIP enchants). The label above the hero is the
## enchant's prefix; a "label" key in its params replaces it ("" = silent).
static func proc_from_enchant(roll: EnchantRoll, item: ItemInstance = null) -> Proc:
	if roll == null or roll.enchant == null or not roll.enchant.is_proc():
		return null
	var e := roll.enchant
	var p := Proc.new()
	p.id = e.id
	p.label = e.prefix
	p.effect = e.effect
	p.item = item
	p.trigger = trigger_for_kind(e.kind)
	var mult := roll.mult()
	for key in e.params:
		var k := String(key)
		var v: Variant = e.params[key]
		if k.ends_with("_fixed"):
			p.params[k.trim_suffix("_fixed")] = v
		elif typeof(v) in [TYPE_INT, TYPE_FLOAT]:
			p.params[k] = float(v) * mult
		elif typeof(v) == TYPE_DICTIONARY:
			p.params[k] = _scaled(v, mult)
		else:
			p.params[k] = v
	p.school = StringName(p.text("school", String(e.school)))
	if p.params.has("label"):
		p.label = p.text("label")  # an own "label" wins, even "" (silent), as in proc_from_params
	p.ppm = e.ppm
	p.chance = e.chance if e.chance > 0.0 else 100.0
	p.icd = e.icd
	_read_trigger_keys(p)
	return p


## The proc of a unique item (unique_effect = block id; params as authored). The label above
## the hero is the item's name; a "label" key in its params replaces it ("" = silent).
static func proc_from_unique(item: ItemInstance) -> Proc:
	if item == null or item.unique_effect == &"":
		return null
	var p := Proc.new()
	p.id = item.source_id if item.source_id != &"" else item.unique_effect
	p.label = item.display_name
	p.item = item
	for key in item.unique_params:
		p.params[String(key)] = item.unique_params[key]
	p.effect = StringName(p.text("effect", String(item.unique_effect)))
	if p.params.has("label"):
		p.label = p.text("label")  # an own "label" wins, even "" (silent), as in proc_from_params
	p.trigger = StringName(p.text("trigger", String(TRIGGER_EQUIP)))
	p.school = StringName(p.text("school", "physical"))
	p.ppm = p.num("ppm")
	p.chance = p.num("chance", 100.0)
	p.icd = p.num("icd")
	_read_trigger_keys(p)
	return p


## The proc of a talent / set "proc" entry (M5): [param params] is a ProcSystem params dict
## (BonusVocabulary, already rank-resolved), used as written (no enchant multiplier, no
## "_fixed" keys). Its own "label" wins (even "" – silent); otherwise [param label] (the talent /
## set name). [param id] names it (fire_count, dot_stacks); default the effect id.
static func proc_from_params(params: Dictionary, label: String = "", id: StringName = &"") -> Proc:
	var p := Proc.new()
	p.extra = true
	var copy: Dictionary = params.duplicate(true)
	for key: Variant in copy:
		p.params[String(key)] = copy[key]
	p.effect = StringName(p.text("effect"))
	p.id = id if id != &"" else p.effect
	p.label = p.text("label") if p.params.has("label") else label
	p.trigger = StringName(p.text("trigger", String(TRIGGER_EQUIP)))
	p.school = StringName(p.text("school", "physical"))
	p.ppm = p.num("ppm")
	p.chance = p.num("chance", 100.0)
	p.icd = p.num("icd")
	_read_trigger_keys(p)
	return p


## The proc of one [method set_extra_procs] def of [param source] (index [param index]): a
## whole entry ("proc" dict + the entry's "label" / "id") or a bare params dict. Null when it
## holds no params.
static func proc_from_def(def: Variant, source: StringName = &"", index: int = 0) -> Proc:
	if typeof(def) != TYPE_DICTIONARY:
		return null
	var d: Dictionary = def
	var params: Dictionary = d
	var label := ""
	if typeof(d.get("proc")) == TYPE_DICTIONARY:
		params = d["proc"]
		label = str(d.get("label", ""))
	var id := StringName(str(d.get("id", "")))
	if id == &"":
		id = StringName("%s:%d" % [source, index])
	return proc_from_params(params, label, id)


static func trigger_for_kind(kind: EnchantData.Kind) -> StringName:
	match kind:
		EnchantData.Kind.ON_HIT:
			return TRIGGER_ON_HIT
		EnchantData.Kind.ON_KILL:
			return TRIGGER_ON_KILL
		EnchantData.Kind.WHEN_STRUCK:
			return TRIGGER_WHEN_STRUCK
	return TRIGGER_EQUIP


static func _read_trigger_keys(p: Proc) -> void:
	p.threshold = p.num("threshold", DEFAULT_THRESHOLD)
	p.interval = maxf(0.1, p.num("interval", DEFAULT_INTERVAL))
	p.per_wave = int(p.num("per_wave", 1.0 if p.effect == &"cheat_death" else 0.0))
	p.timer = p.interval
	p.every = maxi(0, roundi(p.num("every")))
	p.hit_pct = maxf(0.0, p.num("hit_pct")) if p.trigger in HIT_TRIGGERS else 0.0
	if p.trigger == TRIGGER_ON_CAST:
		p.cast_ability = StringName(p.text("ability")) if p.params.has("ability") else &""
		var m: Variant = p.params.get("match")
		p.cast_match = m if typeof(m) == TYPE_DICTIONARY else {}


static func _scaled(d: Dictionary, mult: float) -> Dictionary:
	var out := {}
	for key in d:
		var v: Variant = d[key]
		out[key] = float(v) * mult if typeof(v) in [TYPE_INT, TYPE_FLOAT] else v
	return out


func _add(p: Proc) -> void:
	if p == null or (p.effect not in BLOCKS and p.effect not in EXTRA_BLOCKS):
		return
	p.uid = _next_uid
	_next_uid += 1
	procs.append(p)
	if p.effect == &"cheat_death":
		_cheat_death.append(p)
		return
	match p.trigger:
		TRIGGER_ON_HIT:
			_on_hit.append(p)
		TRIGGER_ON_KILL:
			_on_kill.append(p)
		TRIGGER_WHEN_STRUCK:
			_when_struck.append(p)
		TRIGGER_LOW_HP:
			_low_hp.append(p)
		TRIGGER_PERIODIC:
			_periodic.append(p)
		TRIGGER_ON_CRIT:
			_on_crit.append(p)
		TRIGGER_ON_CAST:
			_on_cast.append(p)
		TRIGGER_WAVE_START:
			_wave_start.append(p)
		TRIGGER_ON_DODGE:
			_on_dodge.append(p)
		TRIGGER_ON_PARRY:
			_on_parry.append(p)
		TRIGGER_ON_BLOCK:
			_on_block.append(p)
		_:
			if p.effect == &"buff" and player != null:
				var source := StringName("proc_equip:%d" % p.uid)
				player.stats.set_source(source, _buff_stats(p, 1))
				_equip_sources.append(source)


# --- Firing -------------------------------------------------------------------------------

func _active() -> bool:
	return player != null and is_instance_valid(player) and player.is_alive()


## One qualifying event of [param p]: with "every" the Nth event fires (no roll; the count
## keeps growing while the proc cannot fire, so the next event that can fires), else
## [param chance] (0..1) is rolled – a RunState.rng draw only below 1.
func _try_fire(p: Proc, chance: float, target: Node3D, pos: Vector3, weapon: WeaponData) -> bool:
	if p.every > 0:
		p.counter += 1
		if p.counter < p.every:
			return false
		chance = 1.0
	if p.cd_left > 0.0 or (p.per_wave > 0 and p.fired_wave >= p.per_wave) or _depth >= MAX_DEPTH:
		return false
	if chance <= 0.0 or (chance < 1.0 and RunState.rng.randf() >= chance):
		return false
	p.counter = 0
	_mark_fired(p)
	_depth += 1
	_run(p, target, pos, weapon)
	_depth -= 1
	proc_fired.emit(p.id, p.effect)
	return true


func _mark_fired(p: Proc) -> void:
	p.cd_left = p.icd
	p.fired_wave += 1
	p.fired_total += 1


func _run(p: Proc, target: Node3D, pos: Vector3, weapon: WeaponData) -> void:
	match p.effect:
		&"bolt":
			_bolt(p, target, pos)
		&"chain":
			_chain(p, target, pos)
		&"dot":
			var e := _target_enemy(target, pos)
			if e != null:
				var derived := p.hit_pct > 0.0
				var total := _hit_base * p.hit_pct / 100.0 if derived else p.num("damage")
				_apply_dot(e, p, total, p.num("duration", DEFAULT_DOT_DURATION),
						int(p.num("stacks", 1.0)), p.num("spread"), 0, -1.0, not derived)
				_riders(p, e, false)
		&"nova":
			var center := _player_pos()
			if p.text("at", "self") == "target":
				var e := _live(target)
				center = e.global_position if e != null else pos
			_area(p, center)
		&"explode":
			var e := _live(target)
			_area(p, e.global_position if e != null else pos)
		&"extra_attack":
			var runner := player.runner_for(weapon)
			if runner != null:
				runner.extra_attack(maxi(1, roundi(p.num("count", 1.0))), _live(target))
		&"buff":
			_buff(p)
		&"heal":
			var who := _receiver(p)
			who.heal(_amount_for(p, who), player.slot_index())
			if p.extra:
				_label(p, Player.HEAL_TEXT_COLOR, who)
		&"drain":
			var e := _target_enemy(target, pos)
			if e != null:
				var hp_before := e.hp
				var dealt := _strike(p, e)
				ProcVfx.beam(_chest(e), player.get_chest_position(), ProcVfx.school_color(p.school))
				_riders(p, e)
				player.heal(minf(dealt, maxf(0.0, hp_before)))
		&"slow":
			var e := _target_enemy(target, pos)
			if e != null:
				e.apply_slow(p.num("pct", 30.0), p.num("duration", DEFAULT_SLOW_DURATION))
				Vfx.hit_spark(_chest(e), ProcVfx.school_color(&"frost"))
		&"stun":
			var e := _target_enemy(target, pos)
			if e != null:
				e.apply_stun(p.num("duration", 1.0))
				Vfx.hit_spark(_chest(e), ProcVfx.school_color(p.school))
		&"gold":
			_gold_carry += maxf(0.0, p.num("amount", 1.0))
			var whole := floori(_gold_carry + 0.000001)
			_gold_carry = maxf(0.0, _gold_carry - whole)
			if whole > 0:
				RunState.add_gold(whole)
				Vfx.floating_text(pos + Vector3.UP * 1.0, "+%d" % whole, GOLD_COLOR, 0.8)
		&"shield":
			var who := _receiver(p)
			var into: ProcSystem = self if who == player else who.procs
			if into != null:
				into.add_shield(_amount_for(p, who), p.num("duration", DEFAULT_SHIELD_DURATION), &"", player.slot_index())
			_label(p, SHIELD_COLOR, who)
		&"reflect":
			var e := _target_enemy(target, pos)
			if e != null:
				ProcVfx.beam(player.get_chest_position(), _chest(e), ProcVfx.school_color(p.school))
				_strike(p, e)
				_riders(p, e)
		&"smite_heal":
			var e := _target_enemy(target, pos)
			if e != null:
				var color := ProcVfx.school_color(p.school)
				Vfx.hit_spark(_chest(e), color)
				_strike(p, e)
				_riders(p, e)
				var ally := _lowest_ally()
				ProcVfx.beam(_chest(e), ally.get_chest_position(), color)
				ally.heal(p.num("heal"), player.slot_index())
		&"resource":
			if player.abilities == null:
				return
			if p.params.has("resource"):
				_resource(p)
			else:
				player.abilities.gain_from_proc(p.num("amount", 1.0))
		&"cooldown":
			_cooldown(p)
		&"forced_crit":
			player.forced_crits += maxi(1, roundi(p.num("count", 1.0)))
			_label(p, WeaponRunner.CRIT_TEXT_COLOR)


## The damage of a damaging block on [param e]: with "hit_pct", that share of the triggering
## hit's base amount, dealt raw (target_bonus false: Executioner / Slayer are not added again,
## the outgoing multipliers of &"proc" apply once – the one derived-damage rule); else the
## block's base "damage" through [method deal]. Returns the damage dealt.
func _strike(p: Proc, e: Enemy) -> float:
	if p.hit_pct > 0.0:
		return deal_raw(e, _hit_base * p.hit_pct / 100.0, p.school, false, &"proc")
	return deal(e, p.num("damage"), p.school)


## The hero a heal / shield goes to: "target" self (default) or lowest_ally.
func _receiver(p: Proc) -> Player:
	return _lowest_ally() if p.text("target", "self") == "lowest_ally" else player


## "amount" + "max_hp_pct" % of [param who]'s (the receiver's) Max HP.
func _amount_for(p: Proc, who: Player) -> float:
	var amount := p.num("amount")
	var pct := p.num("max_hp_pct")
	if pct != 0.0 and who != null:
		amount += who.max_hp() * pct / 100.0
	return amount


## resource {resource: <id> | "primary", value}: ClassResource.add(value, true) – Resource
## Regen scales bar resources, pips get exactly value.
func _resource(p: Proc) -> void:
	var id := StringName(p.text("resource"))
	var res := player.abilities.primary_resource() if id == &"primary" else player.abilities.get_resource(id)
	if res == null:
		return
	res.add(p.num("value"), true)
	_label(p, res.data.color if res.data != null else Color.WHITE)


## cooldown {ability | match, reduce: s | reset: true} on every slotted ability it names:
## reset = AbilityRunner.set_cooldown(a, 0) (every charge back), reduce =
## AbilityRunner.reduce_cooldown (one charge back at most).
func _cooldown(p: Proc) -> void:
	var runner := player.abilities
	if runner == null:
		return
	var id := StringName(p.text("ability")) if p.params.has("ability") else &""
	var m: Variant = p.params.get("match")
	var filter: Dictionary = m if typeof(m) == TYPE_DICTIONARY else {}
	if id == &"" and filter.is_empty():
		return
	var reset: bool = typeof(p.params.get("reset")) == TYPE_BOOL and p.params["reset"]
	var seconds := p.num("reduce")
	var class_id := player.class_data.id if player.class_data != null else &""
	var hit := false
	for a in runner.slots:
		if a == null:
			continue
		if id != &"" and a.id != id:
			continue
		if id == &"" and not BonusVocabulary.matches(filter, a, class_id):
			continue
		if runner.cooldown_left(a) <= 0.0:
			continue  # nothing to reset / shorten: no text either (Sudden Death on a ready Execute)
		hit = true
		if reset:
			runner.set_cooldown(a, 0.0)
		elif seconds > 0.0:
			runner.reduce_cooldown(a, seconds)
	if hit:
		_label(p, ProcVfx.school_color(&"arcane"))


func _bolt(p: Proc, target: Node3D, pos: Vector3) -> void:
	var e := _target_enemy(target, pos)
	if e == null:
		return
	var color := ProcVfx.school_color(p.school)
	ProcVfx.bolt(player.get_chest_position(), _chest(e), color)
	Vfx.hit_spark(_chest(e), color)
	_strike(p, e)
	_riders(p, e)


func _chain(p: Proc, target: Node3D, pos: Vector3) -> void:
	var e := _target_enemy(target, pos)
	if e == null:
		return
	var color := ProcVfx.school_color(p.school)
	var hit_ids: Array[int] = []
	var from := player.get_chest_position()
	var count := maxi(1, roundi(p.num("targets", 3.0)))
	while e != null and hit_ids.size() < count:
		hit_ids.append(e.get_instance_id())
		var at := _chest(e)
		var here := e.global_position
		ProcVfx.beam(from, at, color)
		_strike(p, e)
		_riders(p, e)
		from = at
		e = _nearest_new(here, CHAIN_RANGE, hit_ids) if hit_ids.size() < count else null


## nova / explode: every enemy within the radius (x Area Size) of [param center].
func _area(p: Proc, center: Vector3) -> void:
	var radius := p.num("radius", DEFAULT_RADIUS) * CombatMath.area_mult(player.stats)
	var color := ProcVfx.school_color(p.school)
	Vfx.explosion(Vector3(center.x, 0.1, center.z), radius, color)
	for e in _enemies_within(center, radius):
		if not _is_live(e):
			continue
		_strike(p, e)
		_riders(p, e)


## slow / stun / dot riders of a damaging block on [param e] (when it survived).
func _riders(p: Proc, e: Enemy, with_dot: bool = true) -> void:
	if not _is_live(e):
		return
	var slow := p.num("slow")
	if slow > 0.0:
		e.apply_slow(slow, p.num("slow_duration", DEFAULT_SLOW_DURATION))
	var stun := p.num("stun")
	if stun > 0.0:
		e.apply_stun(stun)
	if with_dot:
		var dot := p.num("dot")
		if dot > 0.0:
			_apply_dot(e, p, dot, p.num("dot_duration", DEFAULT_DOT_DURATION),
					int(p.num("dot_stacks", 1.0)), p.num("spread"), 0, -1.0)


func _buff(p: Proc) -> void:
	var duration := p.num("duration")
	var max_stacks := maxi(1, int(p.num("max_stacks", 1.0)))
	var b: Buff = null
	for existing in _buffs:
		if existing.proc == p:
			b = existing
			break
	if b == null:
		b = Buff.new()
		b.proc = p
		b.source = StringName("proc:%d" % p.uid)
		b.stacks = 1
		_buffs.append(b)
	else:
		b.stacks = mini(b.stacks + 1, max_stacks)
	b.max_stacks = max_stacks
	b.left = duration if duration > 0.0 else INF
	player.stats.set_source(b.source, _buff_stats(p, b.stacks))
	var heal := p.num("heal")
	if heal > 0.0:
		player.heal(heal)
	_label(p, ProcVfx.school_color(p.school))


## The buff's stats x [param stacks]: the "stats" dictionary ("primary" = the class's primary
## stat) plus numeric params named like a stat (so enchant descriptions can show them).
func _buff_stats(p: Proc, stacks: int) -> Dictionary:
	var out := {}
	var raw: Variant = p.params.get("stats", {})
	if typeof(raw) == TYPE_DICTIONARY:
		for key in raw:
			_add_stat(out, String(key), raw[key], stacks)
	for key: String in p.params:
		if key == "primary" or StringName(key) in Stats.ALL:
			_add_stat(out, key, p.params[key], stacks)
	return out


func _add_stat(out: Dictionary, key: String, value: Variant, stacks: int) -> void:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return
	var stat := StringName(key)
	if key == "primary":
		stat = player.class_data.primary_stat if player.class_data != null else Stats.STRENGTH
	out[stat] = float(out.get(stat, 0.0)) + float(value) * stacks


func _clear_buffs() -> void:
	for b in _buffs:
		if player != null:
			player.stats.remove_source(b.source)
	_buffs.clear()


## Adds a DoT stack of [param p] to [param e] (or starts one). [param rate] < 0: computed from
## [param total_base] over [param duration] seconds – as proc damage (Spell / Attack Power,
## damage %) when [param target_bonus], else as it is (a "hit_pct" total derived from a hit:
## its ticks skip Executioner / Slayer).
func _apply_dot(e: Enemy, p: Proc, total_base: float, duration: float, max_stacks: int, spread: float,
		generation: int, rate: float, target_bonus: bool = true) -> void:
	if not _is_live(e) or (total_base <= 0.0 and rate <= 0.0):
		return
	duration = maxf(DOT_TICK, duration)
	if rate < 0.0:
		rate = (CombatMath.proc_damage(total_base, p.school, player.stats) if target_bonus else total_base) / duration
	var id := e.get_instance_id()
	for d in _dots:
		if d.target_id == id and d.proc == p:
			d.stacks = mini(d.stacks + 1, d.max_stacks)
			d.left = duration
			d.duration = duration
			d.rate = rate
			return
	var dot := Dot.new()
	dot.proc = p
	dot.target_id = id
	dot.school = p.school
	dot.rate = rate
	dot.max_stacks = maxi(1, max_stacks)
	dot.duration = duration
	dot.left = duration
	dot.tick_left = DOT_TICK
	dot.spread = spread
	dot.generation = generation
	dot.last_pos = e.global_position
	dot.target_bonus = target_bonus
	_dots.append(dot)


func _spread(d: Dot) -> void:
	var color := ProcVfx.school_color(d.school)
	var n := 0
	for e in _enemies_within(d.last_pos, d.spread):
		if n >= SPREAD_TARGETS:
			break
		if not _is_live(e) or dot_stacks(e, d.proc.id) > 0:
			continue
		ProcVfx.beam(d.last_pos + Vector3.UP * Player.CHEST_HEIGHT, _chest(e), color)
		_apply_dot(e, d.proc, 0.0, d.duration, d.max_stacks, d.spread, d.generation + 1, d.rate, d.target_bonus)
		n += 1


# --- Frame update -------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	for p in procs:
		if p.cd_left > 0.0:
			p.cd_left = maxf(0.0, p.cd_left - delta)
	if not _low_hp.is_empty():
		var pct := player.hp / player.max_hp() * 100.0
		for p in _low_hp:
			if not p.armed and pct >= p.threshold:
				p.armed = true
	if not _periodic.is_empty() and player.is_alive():
		for p in _periodic:
			p.timer -= delta
			if p.timer > 0.0:
				continue
			if p.effect in NEEDS_ENEMY and _nearest(_player_pos(), TARGET_RANGE) == null:
				p.timer = PERIODIC_RETRY
				continue
			p.timer += p.interval
			if p.timer <= 0.0:
				p.timer = p.interval
			_try_fire(p, p.chance / 100.0, null, _player_pos(), null)
	if not _shields.is_empty():
		_tick_shields(delta)
	if not _buffs.is_empty():
		_tick_buffs(delta)
	if not _dots.is_empty():
		_tick_dots(delta)


## Every shield runs out on its own timer.
func _tick_shields(delta: float) -> void:
	for i in range(_shields.size() - 1, -1, -1):
		_shields[i].left -= delta
		if _shields[i].left <= 0.0:
			_shields.remove_at(i)


func _tick_buffs(delta: float) -> void:
	for i in range(_buffs.size() - 1, -1, -1):
		var b := _buffs[i]
		b.left -= delta
		if b.left <= 0.0:
			player.stats.remove_source(b.source)
			_buffs.remove_at(i)


func _tick_dots(delta: float) -> void:
	for i in range(_dots.size() - 1, -1, -1):
		if i >= _dots.size():
			continue
		var d := _dots[i]
		var e := instance_from_id(d.target_id) as Enemy
		if not _is_live(e):
			_dots.remove_at(i)
			if d.spread > 0.0 and d.generation < MAX_SPREAD_GENERATION:
				if e != null and e.is_inside_tree():
					d.last_pos = e.global_position
				_spread(d)
			continue
		d.last_pos = e.global_position
		d.owed += d.rate * d.stacks * clampf(d.left, 0.0, delta)
		d.left -= delta
		d.tick_left -= delta
		if d.tick_left > TIME_EPSILON and d.left > TIME_EPSILON:
			continue
		d.tick_left += DOT_TICK
		var amount := d.owed
		d.owed = 0.0
		if amount > 0.0:
			deal_raw(e, amount, d.school, d.target_bonus, &"dot")
		var died := not _is_live(e)
		if d.left <= TIME_EPSILON or died:
			if i < _dots.size() and _dots[i] == d:
				_dots.remove_at(i)
			else:
				_dots.erase(d)
			if died and d.spread > 0.0 and d.generation < MAX_SPREAD_GENERATION:
				_spread(d)


func _check_low_hp() -> void:
	if _low_hp.is_empty() or player == null:
		return
	var pct := player.hp / player.max_hp() * 100.0
	for p in _low_hp:
		if p.armed and pct < p.threshold:
			p.armed = false
			_try_fire(p, p.chance / 100.0, null, _player_pos(), null)


# --- Queries ------------------------------------------------------------------------------

static func _is_live(e: Variant) -> bool:
	if e == null or not is_instance_valid(e):
		return false
	var enemy := e as Enemy
	return enemy != null and enemy.is_inside_tree() and not enemy.is_dead()


static func _live(node: Variant) -> Enemy:
	return node as Enemy if _is_live(node) else null


## The live hit target, else the nearest living enemy within TARGET_RANGE of [param pos].
func _target_enemy(target: Variant, pos: Vector3) -> Enemy:
	var e := _live(target)
	return e if e != null else _nearest(pos, TARGET_RANGE)


func _nearest(pos: Vector3, max_range: float) -> Enemy:
	if not is_inside_tree():
		return null
	return EnemyGrid.nearest(get_tree(), pos, max_range)


## Nearest living enemy within [param max_range] of [param pos] whose instance id is not in
## [param exclude] (chain jumps).
func _nearest_new(pos: Vector3, max_range: float, exclude: Array[int]) -> Enemy:
	var best: Enemy = null
	var best_d := max_range * max_range
	for node in _gather(pos, max_range):
		var e := node as Enemy
		if not _is_live(e) or e.get_instance_id() in exclude:
			continue
		var d := WeaponRunner.flat(e.global_position - pos).length_squared()
		if d <= best_d:
			best_d = d
			best = e
	return best


## Living enemies whose body touches the circle (XZ) – group order.
func _enemies_within(center: Vector3, radius: float) -> Array[Enemy]:
	var out: Array[Enemy] = []
	for node in _gather(center, radius):
		var e := node as Enemy
		if not _is_live(e):
			continue
		var reach := radius + e.radius
		if WeaponRunner.flat(e.global_position - center).length_squared() <= reach * reach:
			out.append(e)
	return out


func _gather(center: Vector3, radius: float) -> Array[Node]:
	if not is_inside_tree():
		var none: Array[Node] = []
		return none
	return EnemyGrid.gather_around(get_tree(), center, radius)


## The living player with the lowest HP fraction (this player on ties / when alone).
func _lowest_ally() -> Player:
	var best := player
	var best_ratio := player.hp / player.max_hp() if player.is_alive() else INF
	if is_inside_tree():
		for other in Enemy.cached_players(get_tree()):
			if other == player or not Enemy.is_living_player(other):
				continue
			var ratio := other.hp / other.max_hp()
			if ratio < best_ratio:
				best_ratio = ratio
				best = other
	return best


func _pos_of(node: Variant) -> Vector3:
	if node != null and is_instance_valid(node):
		var n := node as Node3D
		if n != null:
			return n.global_position if n.is_inside_tree() else n.position
	return _player_pos()


func _player_pos() -> Vector3:
	if player == null:
		return Vector3.ZERO
	return player.global_position if player.is_inside_tree() else player.position


static func _chest(e: Node3D) -> Vector3:
	return e.global_position + Vector3.UP * Player.CHEST_HEIGHT


## The proc's name above the player ("Bloodlust", "Shield") in [param color] – above
## [param over] instead when the effect went to another hero (a lowest_ally heal / shield).
func _label(p: Proc, color: Color, over: Player = null) -> void:
	if player == null or p.label == "":
		return
	var who := over if over != null and is_instance_valid(over) else player
	Vfx.floating_text(who.get_chest_position() + Vector3.UP * 1.1, p.label, color, LABEL_TEXT_SIZE)
