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
##                                      added too); duration <= 0 = until the next wave;
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

## A proc fired (effect id = block id). Also for no-op blocks such as resource.
signal proc_fired(proc_id: StringName, effect: StringName)

const TRIGGER_ON_HIT := &"on_hit"
const TRIGGER_ON_KILL := &"on_kill"
const TRIGGER_WHEN_STRUCK := &"when_struck"
const TRIGGER_LOW_HP := &"low_hp"
const TRIGGER_PERIODIC := &"periodic"
const TRIGGER_EQUIP := &"equip"

## Every building block ProcSystem runs (unknown effect ids are ignored – e.g. M3 ability
## modifiers on uniques).
const BLOCKS: Array[StringName] = [
	&"bolt", &"chain", &"dot", &"nova", &"explode", &"extra_attack", &"buff", &"heal",
	&"drain", &"slow", &"stun", &"gold", &"shield", &"reflect", &"smite_heal", &"cheat_death",
	&"resource",
]
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
	# Runtime state.
	var cd_left := 0.0
	var timer := 0.0
	var armed := true
	var fired_wave := 0
	var fired_total := 0

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


## A running temporary stat buff.
class Buff extends RefCounted:
	var proc: Proc
	var source: StringName
	var stats: Dictionary = {}
	var stacks := 1
	var max_stacks := 1
	var left := 0.0


var player: Player
## Every active proc (equipment order).
var procs: Array[Proc] = []
## Remaining absorb shield (HP) and its seconds left.
var shield_hp := 0.0
var shield_left := 0.0

var _on_hit: Array[Proc] = []
var _on_kill: Array[Proc] = []
var _when_struck: Array[Proc] = []
var _low_hp: Array[Proc] = []
var _periodic: Array[Proc] = []
var _cheat_death: Array[Proc] = []
var _dots: Array[Dot] = []
var _buffs: Array[Buff] = []
## Stat sources of "equip"-trigger buffs.
var _equip_sources: Array[StringName] = []
var _gold_carry := 0.0
var _depth := 0
var _next_uid := 1


static func create(owner_player: Player) -> ProcSystem:
	var ps := ProcSystem.new()
	ps.name = "Procs"
	ps.player = owner_player
	return ps


## Rebuilds the active enchant list from the player's equipment (call on equipment.changed).
## Running buffs from the old list end; DoTs already on enemies keep ticking.
func refresh() -> void:
	_clear_buffs()
	for source in _equip_sources:
		if player != null:
			player.stats.remove_source(source)
	_equip_sources.clear()
	procs.clear()
	for list: Array[Proc] in [_on_hit, _on_kill, _when_struck, _low_hp, _periodic, _cheat_death]:
		list.clear()
	if player == null or player.equipment == null:
		return
	for s in Items.EquipSlot.values():
		var item := player.equipment.get_item(s)
		if item == null:
			continue
		for roll in item.proc_enchants():
			_add(proc_from_enchant(roll, item))
		if item.unique_effect != &"":
			_add(proc_from_unique(item))


## A weapon hit landed (not called for proc damage). [param is_extra]: a hit of an extra
## attack – it cannot trigger extra_attack procs.
func on_hit(target: Node3D, _damage: float, weapon: WeaponData, _is_crit: bool, is_extra: bool = false) -> void:
	if _on_hit.is_empty() or not _active():
		return
	var cd := weapon.cooldown if weapon != null else 1.0
	var pos := _pos_of(target)
	for p in _on_hit:
		if is_extra and p.effect == &"extra_attack":
			continue
		var c := CombatMath.ppm_chance(p.ppm, cd) if p.ppm > 0.0 else p.chance / 100.0
		_try_fire(p, c, target, pos, weapon)


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


## Wave start: cooldowns, per-wave limits and low-HP triggers re-arm; DoTs, timed buffs and
## shields from the last wave end.
func begin_wave() -> void:
	for p in procs:
		p.cd_left = 0.0
		p.fired_wave = 0
		p.armed = true
		p.timer = p.interval
	_dots.clear()
	_clear_buffs()
	shield_hp = 0.0
	shield_left = 0.0


## Damage left after the absorb shield took its share ("Absorb" text when it took all).
func absorb(damage: float) -> float:
	if shield_hp <= 0.0 or damage <= 0.0:
		return damage
	var taken := minf(shield_hp, damage)
	shield_hp -= taken
	if shield_hp <= 0.0001:
		shield_hp = 0.0
		shield_left = 0.0
	if taken >= damage and player != null:
		Vfx.floating_text(player.self_text_position(1.0), "Absorb", SHIELD_COLOR, Player.SELF_TEXT_SIZE, 1.0)
	return damage - taken


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
	if player.slot != null:
		RunState.record_damage(player.slot.index, minf(amount, maxf(0.0, target.hp)))
	target.take_damage(amount, false, player)
	Vfx.damage_number(null, text_pos, amount, ProcVfx.school_color(school), DAMAGE_TEXT_SIZE)
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

## The proc of an enchant roll (null for EQUIP enchants).
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
	p.ppm = e.ppm
	p.chance = e.chance if e.chance > 0.0 else 100.0
	p.icd = e.icd
	_read_trigger_keys(p)
	return p


## The proc of a unique item (unique_effect = block id; params as authored).
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
	p.trigger = StringName(p.text("trigger", String(TRIGGER_EQUIP)))
	p.school = StringName(p.text("school", "physical"))
	p.ppm = p.num("ppm")
	p.chance = p.num("chance", 100.0)
	p.icd = p.num("icd")
	_read_trigger_keys(p)
	return p


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


static func _scaled(d: Dictionary, mult: float) -> Dictionary:
	var out := {}
	for key in d:
		var v: Variant = d[key]
		out[key] = float(v) * mult if typeof(v) in [TYPE_INT, TYPE_FLOAT] else v
	return out


func _add(p: Proc) -> void:
	if p == null or p.effect not in BLOCKS:
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
		_:
			if p.effect == &"buff" and player != null:
				var source := StringName("proc_equip:%d" % p.uid)
				player.stats.set_source(source, _buff_stats(p, 1))
				_equip_sources.append(source)


# --- Firing -------------------------------------------------------------------------------

func _active() -> bool:
	return player != null and is_instance_valid(player) and player.is_alive()


func _try_fire(p: Proc, chance: float, target: Node3D, pos: Vector3, weapon: WeaponData) -> bool:
	if p.cd_left > 0.0 or (p.per_wave > 0 and p.fired_wave >= p.per_wave) or _depth >= MAX_DEPTH:
		return false
	if chance <= 0.0 or (chance < 1.0 and RunState.rng.randf() >= chance):
		return false
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
				_apply_dot(e, p, p.num("damage"), p.num("duration", DEFAULT_DOT_DURATION),
						int(p.num("stacks", 1.0)), p.num("spread"), 0, -1.0)
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
			var who := player if p.text("target", "self") != "lowest_ally" else _lowest_ally()
			who.heal(p.num("amount"))
		&"drain":
			var e := _target_enemy(target, pos)
			if e != null:
				var hp_before := e.hp
				var dealt := deal(e, p.num("damage"), p.school)
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
			shield_hp += maxf(0.0, p.num("amount"))
			shield_left = maxf(shield_left, p.num("duration", DEFAULT_SHIELD_DURATION))
			_label(p, SHIELD_COLOR)
		&"reflect":
			var e := _target_enemy(target, pos)
			if e != null:
				ProcVfx.beam(player.get_chest_position(), _chest(e), ProcVfx.school_color(p.school))
				deal(e, p.num("damage"), p.school)
				_riders(p, e)
		&"smite_heal":
			var e := _target_enemy(target, pos)
			if e != null:
				var color := ProcVfx.school_color(p.school)
				Vfx.hit_spark(_chest(e), color)
				deal(e, p.num("damage"), p.school)
				_riders(p, e)
				var ally := _lowest_ally()
				ProcVfx.beam(_chest(e), ally.get_chest_position(), color)
				ally.heal(p.num("heal"))
		&"resource":
			if player.abilities != null:
				player.abilities.gain_from_proc(p.num("amount", 1.0))


func _bolt(p: Proc, target: Node3D, pos: Vector3) -> void:
	var e := _target_enemy(target, pos)
	if e == null:
		return
	var color := ProcVfx.school_color(p.school)
	ProcVfx.bolt(player.get_chest_position(), _chest(e), color)
	Vfx.hit_spark(_chest(e), color)
	deal(e, p.num("damage"), p.school)
	_riders(p, e)


func _chain(p: Proc, target: Node3D, pos: Vector3) -> void:
	var e := _target_enemy(target, pos)
	if e == null:
		return
	var color := ProcVfx.school_color(p.school)
	var hit_ids: Array[int] = []
	var from := player.get_chest_position()
	var count := maxi(1, roundi(p.num("targets", 3.0)))
	var damage := p.num("damage")
	while e != null and hit_ids.size() < count:
		hit_ids.append(e.get_instance_id())
		var at := _chest(e)
		var here := e.global_position
		ProcVfx.beam(from, at, color)
		deal(e, damage, p.school)
		_riders(p, e)
		from = at
		e = _nearest_new(here, CHAIN_RANGE, hit_ids) if hit_ids.size() < count else null


## nova / explode: every enemy within the radius (x Area Size) of [param center].
func _area(p: Proc, center: Vector3) -> void:
	var radius := p.num("radius", DEFAULT_RADIUS) * CombatMath.area_mult(player.stats)
	var color := ProcVfx.school_color(p.school)
	Vfx.explosion(Vector3(center.x, 0.1, center.z), radius, color)
	var damage := p.num("damage")
	for e in _enemies_within(center, radius):
		if not _is_live(e):
			continue
		deal(e, damage, p.school)
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
## [param total_base] (proc damage over [param duration] seconds).
func _apply_dot(e: Enemy, p: Proc, total_base: float, duration: float, max_stacks: int, spread: float,
		generation: int, rate: float) -> void:
	if not _is_live(e) or (total_base <= 0.0 and rate <= 0.0):
		return
	duration = maxf(DOT_TICK, duration)
	if rate < 0.0:
		rate = CombatMath.proc_damage(total_base, p.school, player.stats) / duration
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
		_apply_dot(e, d.proc, 0.0, d.duration, d.max_stacks, d.spread, d.generation + 1, d.rate)
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
	if shield_left > 0.0:
		shield_left -= delta
		if shield_left <= 0.0:
			shield_left = 0.0
			shield_hp = 0.0
	if not _buffs.is_empty():
		_tick_buffs(delta)
	if not _dots.is_empty():
		_tick_dots(delta)


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
			deal_raw(e, amount, d.school, true, &"dot")
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


## The proc's name above the player ("Bloodlust", "Shield") in [param color].
func _label(p: Proc, color: Color) -> void:
	if player == null or p.label == "":
		return
	Vfx.floating_text(player.get_chest_position() + Vector3.UP * 1.1, p.label, color, LABEL_TEXT_SIZE)
