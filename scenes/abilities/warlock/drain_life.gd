class_name WarlockDrainLife
extends AbilityEffect
## Drain Life (GDD 3.5, LT, 8 s cooldown): a [code]duration[/code]-second channel on the
## nearest enemy. Every [code]tick[/code] seconds it deals Shadow damage
## (ProcSystem.deal_raw(..., &"ability")) and heals the Warlock for [code]heal_pct[/code]% of
## the damage actually dealt (overkill does not heal). The Warlock keeps moving and attacking
## (no root). When the target dies or leaves [code]range[/code] x [constant BREAK_SLACK] the
## drain jumps to the nearest enemy within [code]range[/code]; with none left it ends early.
## Going down ends it. A green-purple beam ([WarlockDrainBeam]) links the two.
##
## Params: duration, tick, damage (shadow per tick), intellect_scale (per tick per point of
## Intellect), spell_power_scale (per second per point of Spell Power), heal_pct, range,
## auto_cast_hp (bots: cast below this HP %), targets (Soul Siphon: enemies drained at once,
## each with its own beam), overheal_shield (Dark Bargain: healing beyond full health becomes
## an absorb shield, up to this % of Max HP). "power" (Ranks II / IV) scales the damage (and
## so the healing). Rank III: +1 s channel. Rank V: Soul Siphon or Dark Bargain.
##
## Talent params (M5, neutral defaults in warlock_drain_life.tres):
## - Dark Harvest (Affliction modifier): harvest_pct (% of a tick, 0 = off) and
##   harvest_targets – every tick also drains up to harvest_targets enemies within range that
##   carry one of this Warlock's afflictions and are not drained already (nearest first): each
##   takes harvest_pct % of the tick's damage (&"ability", Shadow) and that damage heals too.
##   Bots also channel at full health when 3+ afflicted enemies are in range.
## - Shadowburn (Destruction modifier): shadowburn_pct (% of the channel's nominal damage, 0 =
##   off), shadowburn_window (s), shadowburn_shard_icd (s) – when a channel completes (its last
##   planned tick ran; not when it ends early), every live drained enemy is scorched for
##   tick damage x ticks x shadowburn_pct %; one that dies within shadowburn_window seconds
##   gives the Warlock 1 Soul Shard, at most once every shadowburn_shard_icd seconds (and once
##   per channel). The watch list is cleared at wave start / end and when the Warlock goes
##   down; the shard timer resets at wave start. No RNG.

## The drain holds until the target is this much further than the range.
const BREAK_SLACK := 1.25
const TIME_EPSILON := 0.0001
const SPARK_COLOR := Color(0.6, 0.3, 0.9)
## Dark Bargain shields last this long.
const SHIELD_DURATION := 6.0
## Dark Harvest: the bot rule's afflicted enemies in range.
const HARVEST_AUTO_MIN := 3
const HARVEST_BEAM_COLOR := Color(0.55, 0.9, 0.35)
const SCORCH_COLOR := Color(0.7, 0.3, 0.95)
const SHARD_TEXT := "+1 Pact Shard"
const SHARD_TEXT_COLOR := Color(0.75, 0.45, 1.0)
const SHARD_RESOURCE := &"soul_shard"

## The (first) enemy being drained (null when not channelling).
var target: Enemy
## Seconds of channel left (0 = not channelling).
var channel_left := 0.0
## Ticks done / planned in the current channel.
var ticks_done := 0
var ticks_total := 0
## Totals of the current (or last) channel – tests, stats.
var damage_total := 0.0
var healed_total := 0.0
## Dark Bargain shield granted in the current (or last) channel.
var shield_total := 0.0
## The beam of the first target.
var beam: WarlockDrainBeam
## Every drained enemy and its beam, the first target first (Soul Siphon drains several).
var targets: Array = []
var beams: Array = []
## Dark Harvest totals of the current (or last) channel – tests, stats.
var harvest_total := 0.0
var harvest_hits := 0
## Shadowburn: scorches dealt, shards gained (since the wave started) – tests, stats.
var scorches := 0
var shadowburn_shards := 0
## Shadowburn: seconds until the next shard may come (0 = ready).
var shard_cooldown := 0.0

var _player: Player
var _tick := 0.4
var _tick_left := 0.0
var _tick_damage := 0.0
var _heal_ratio := 1.0
var _range := 8.0
var _count := 1
var _shield_pct := 0.0
var _school: StringName = &"shadow"
var _harvest_ratio := 0.0
var _harvest_targets := 6
var _shadowburn_ratio := 0.0
var _shadowburn_window := 3.0
var _shadowburn_icd := 10.0
## Dark Harvest: enemies harvested in this channel (one beam each, no beam spam).
var _harvested: Dictionary[int, bool] = {}
## Shadowburn: scorched enemy id -> seconds its death still pays a shard.
var _watch: Dictionary[int, float] = {}
var _expired: Array[int] = []


## Shadow damage of one tick for [param stats] with [param params] (before the target
## bonuses and the owner's outgoing multipliers, which ProcSystem.deal_raw applies).
static func tick_damage(stats: StatBlock, params: Dictionary, school: StringName = &"shadow") -> float:
	var tick := float(params.get("tick", 0.4))
	var flat := float(params.get("damage", 0.0)) \
			+ maxf(0.0, stats.get_raw(Stats.INTELLECT)) * float(params.get("intellect_scale", 0.0)) \
			+ maxf(0.0, stats.get_raw(Stats.SPELL_POWER)) * float(params.get("spell_power_scale", 0.0)) * tick
	return maxf(CombatMath.MIN_DAMAGE, flat * CombatMath.damage_mult_for(stats, school) * WarlockSpell.power(params))


func is_channeling() -> bool:
	return ticks_total > 0 and ticks_done < ticks_total


func can_cast(ctx: AbilityContext) -> bool:
	return ctx.target != null and not is_channeling()


func cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree() or not _is_live(ctx.target):
		return false
	var e := ctx.target as Enemy
	_player = p
	_school = ctx.ability.school
	_tick = maxf(0.05, ctx.num("tick", 0.4))
	var duration := maxf(_tick, ctx.num("duration", 2.0))
	_range = maxf(0.5, ctx.num("range", ctx.ability.cast_range))
	_tick_damage = tick_damage(p.stats, ctx.params, _school)
	_heal_ratio = maxf(0.0, ctx.num("heal_pct", 100.0) / 100.0)
	_count = maxi(1, roundi(ctx.num("targets", 1.0)))
	_shield_pct = maxf(0.0, ctx.num("overheal_shield", 0.0))
	_harvest_ratio = maxf(0.0, ctx.num("harvest_pct", 0.0) / 100.0)
	_harvest_targets = maxi(0, roundi(ctx.num("harvest_targets", 6.0)))
	_shadowburn_ratio = maxf(0.0, ctx.num("shadowburn_pct", 0.0) / 100.0)
	_shadowburn_window = maxf(0.0, ctx.num("shadowburn_window", 3.0))
	_shadowburn_icd = maxf(0.0, ctx.num("shadowburn_shard_icd", 10.0))
	channel_left = duration
	ticks_total = maxi(1, roundi(duration / _tick))
	ticks_done = 0
	_tick_left = _tick
	damage_total = 0.0
	healed_total = 0.0
	shield_total = 0.0
	harvest_total = 0.0
	harvest_hits = 0
	_harvested.clear()
	if not p.downed_changed.is_connected(_on_downed_changed):
		p.downed_changed.connect(_on_downed_changed)
	_release_beams()
	_add_target(e)
	_fill_targets()
	return true


func tick(_ctx: AbilityContext, delta: float) -> void:
	_tick_shadowburn(delta)
	if not is_channeling():
		return
	if _player == null or not is_instance_valid(_player) or _player.downed or not _player.is_inside_tree():
		stop()
		return
	channel_left = maxf(0.0, channel_left - delta)
	if not _refresh_targets():
		stop()
		return
	_tick_left -= delta
	while _tick_left <= TIME_EPSILON and is_channeling():
		_tick_left += _tick
		_drain_once()
		if not is_channeling():
			# The last planned tick ran: the channel completed (Shadowburn).
			_shadowburn()
			break
		if not _refresh_targets():
			stop()
			return
	if not is_channeling():
		stop()


## Ends the channel (and the beams) now.
func stop() -> void:
	channel_left = 0.0
	ticks_done = ticks_total
	_release_beams()


## Wave start: a channel never carries over into the next wave; Shadowburn starts afresh.
func begin_wave(_ctx: AbilityContext) -> void:
	if is_channeling():
		stop()
	_clear_watch()
	shard_cooldown = 0.0
	scorches = 0
	shadowburn_shards = 0


## Wave cleared: no beam hangs in the air during the intermission.
func end_wave(_ctx: AbilityContext) -> void:
	if is_channeling():
		stop()
	_clear_watch()


## Bots: hurt (HP below auto_cast_hp %) and an enemy within range; with Dark Harvest also at
## full health when HARVEST_AUTO_MIN afflicted enemies are within range.
func wants_auto_cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or ctx.target == null or is_channeling():
		return false
	var m := p.max_hp()
	if m > 0.0 and p.hp / m * 100.0 < ctx.num("auto_cast_hp", 70.0):
		return true
	return ctx.num("harvest_pct", 0.0) > 0.0 and p.is_inside_tree() \
			and _afflicted_in_range(p, maxf(0.5, ctx.num("range", ctx.ability.cast_range))) >= HARVEST_AUTO_MIN


## One tick on every drained enemy.
func _drain_once() -> void:
	ticks_done += 1
	if _player.procs == null:
		return
	for t: Variant in targets.duplicate():
		if not _is_live(t):
			continue
		var e := t as Enemy
		var hp_before := maxf(0.0, e.hp)
		var dealt := _player.procs.deal_raw(e, _tick_damage, _school, true, &"ability")
		var real := minf(dealt, hp_before)
		damage_total += dealt
		Vfx.hit_spark(e.global_position + Vector3.UP * Player.CHEST_HEIGHT, SPARK_COLOR)
		_heal(real * _heal_ratio)
	if _harvest_ratio > 0.0 and _harvest_targets > 0:
		_harvest()


## Dark Harvest: harvest_pct % of the tick on every afflicted enemy in range that is not drained
## (up to harvest_targets, nearest first); the damage dealt heals like the drain.
func _harvest() -> void:
	var aff := WarlockAfflictions.of(_player, false)
	if aff == null or not _player.is_inside_tree():
		return
	var exclude: Array[Enemy] = []
	for t: Variant in targets:
		if _is_live(t):
			exclude.append(t as Enemy)
	var found := WarlockSpell.nearest_enemies(_player.get_tree(), _player.global_position, _range,
			_harvest_targets, aff.afflicted, exclude)
	var amount := _tick_damage * _harvest_ratio
	for e in found:
		var id := e.get_instance_id()
		var chest := WarlockSpell.chest(e)
		var hp_before := maxf(0.0, e.hp)
		var dealt := _player.procs.deal_raw(e, amount, _school, true, &"ability")
		harvest_total += dealt
		harvest_hits += 1
		Vfx.hit_spark(chest, SPARK_COLOR)
		if not _harvested.has(id):
			_harvested[id] = true
			ProcVfx.beam(chest, _player.global_position + Vector3.UP * Player.CHEST_HEIGHT, HARVEST_BEAM_COLOR)
		_heal(minf(dealt, hp_before) * _heal_ratio)


## Living enemies within [param reach] of [param p] that carry one of its afflictions.
static func _afflicted_in_range(p: Player, reach: float) -> int:
	var aff := WarlockAfflictions.of(p, false)
	if aff == null or aff.count() == 0:
		return 0
	return WarlockSpell.nearest_enemies(p.get_tree(), p.global_position, reach, HARVEST_AUTO_MIN,
			aff.afflicted).size()


## Shadowburn: the channel completed – every live drained enemy is scorched for
## shadowburn_pct % of the channel's nominal damage and watched for shadowburn_window seconds.
func _shadowburn() -> void:
	if _shadowburn_ratio <= 0.0 or _player == null or _player.downed or _player.procs == null:
		return
	var amount := _tick_damage * float(ticks_total) * _shadowburn_ratio
	for t: Variant in targets.duplicate():
		if not _is_live(t):
			continue
		var e := t as Enemy
		var chest := WarlockSpell.chest(e)
		scorches += 1
		# Watch first: the scorch itself may kill it.
		if _shadowburn_window > 0.0:
			_watch[e.get_instance_id()] = _shadowburn_window
			if not e.died.is_connected(_on_scorched_died):
				e.died.connect(_on_scorched_died, CONNECT_ONE_SHOT)
		Vfx.explosion(chest, 0.8, SCORCH_COLOR)
		Vfx.hit_spark(chest, SCORCH_COLOR)
		_player.procs.deal_raw(e, amount, _school, true, &"ability")


## A scorched enemy died: one Soul Shard when it is still watched and the shard is ready.
func _on_scorched_died(e: Enemy, _killer_index: int) -> void:
	var id := e.get_instance_id()
	if not _watch.has(id) or shard_cooldown > 0.0 or _player == null or not is_instance_valid(_player) \
			or _player.downed or _player.abilities == null:
		return
	var res := _player.abilities.get_resource(SHARD_RESOURCE)
	if res == null:
		return
	res.add(1.0, false)
	shadowburn_shards += 1
	shard_cooldown = _shadowburn_icd
	_clear_watch()
	if e.is_inside_tree() and _player.is_inside_tree():
		var to := _player.global_position + Vector3.UP * Player.CHEST_HEIGHT
		ProcVfx.beam(WarlockSpell.chest(e), to, WarlockSpell.SHADOW_COLOR)
		Vfx.floating_text(to + Vector3.UP * 0.9, SHARD_TEXT, SHARD_TEXT_COLOR)


## Counts the Shadowburn watch list and the shard timer down.
func _tick_shadowburn(delta: float) -> void:
	if shard_cooldown > 0.0:
		shard_cooldown = maxf(0.0, shard_cooldown - delta)
	if _watch.is_empty():
		return
	_expired.clear()
	for id in _watch:
		var left := _watch[id] - delta
		if left <= 0.0 or not is_instance_id_valid(id):
			_expired.append(id)
		else:
			_watch[id] = left
	for id in _expired:
		_watch.erase(id)


## True while [param e] is watched by Shadowburn (tests).
func is_watched(e: Node3D) -> bool:
	return e != null and is_instance_valid(e) and _watch.has(e.get_instance_id())


func _clear_watch() -> void:
	_watch.clear()
	_expired.clear()


## Heals the Warlock; Dark Bargain turns the part beyond full health into a shield.
func _heal(amount: float) -> void:
	if amount <= 0.0:
		return
	var before := _player.hp
	var room := maxf(0.0, _player.max_hp() - before)
	_player.heal(amount)
	healed_total += maxf(0.0, _player.hp - before)
	var over := amount - room
	if _shield_pct <= 0.0 or over <= 0.0 or _player.procs == null or _player.downed:
		return
	var cap := _player.max_hp() * _shield_pct / 100.0
	var add := minf(over, cap - _player.procs.shield_hp)
	if add > 0.0:
		_player.procs.add_shield(add, SHIELD_DURATION)
		shield_total += add


## Drops targets that died or broke away, replacing each with the nearest enemy in range
## not drained yet, then fills up to the target count. False when nobody is left.
func _refresh_targets() -> bool:
	var i := 0
	while i < targets.size():
		if _holds(targets[i]):
			i += 1
			continue
		var next := _next_enemy()
		if next != null:
			targets[i] = next
			var b: Variant = beams[i]
			if b != null and is_instance_valid(b):
				(b as WarlockDrainBeam).target = next
			i += 1
		else:
			var b: Variant = beams[i]
			if b != null and is_instance_valid(b):
				(b as WarlockDrainBeam).finish()
			targets.remove_at(i)
			beams.remove_at(i)
	if targets.size() < _count:
		_fill_targets()
	_sync_primary()
	return not targets.is_empty()


func _fill_targets() -> void:
	while targets.size() < _count:
		var next := _next_enemy()
		if next == null:
			break
		_add_target(next)
	_sync_primary()


func _add_target(e: Enemy) -> void:
	targets.append(e)
	beams.append(WarlockDrainBeam.create(_player, e))


## The nearest living enemy within range that is not drained yet (null = none).
func _next_enemy() -> Enemy:
	if _player == null or not _player.is_inside_tree():
		return null
	var exclude: Array[Enemy] = []
	for t: Variant in targets:
		if _is_live(t):
			exclude.append(t as Enemy)
	var found := WarlockSpell.nearest_enemies(_player.get_tree(), _player.global_position, _range, 1,
			Callable(), exclude)
	return found[0] if not found.is_empty() else null


func _sync_primary() -> void:
	target = targets[0] as Enemy if not targets.is_empty() and _is_live(targets[0]) else null
	var b: Variant = beams[0] if not beams.is_empty() else null
	beam = b as WarlockDrainBeam if b != null and is_instance_valid(b) else null


func _release_beams() -> void:
	for b: Variant in beams:
		if b != null and is_instance_valid(b):
			(b as WarlockDrainBeam).finish()
	beams.clear()
	targets.clear()
	beam = null
	target = null


## The target is still drainable (alive, in the tree, within range x BREAK_SLACK).
func _holds(e: Variant) -> bool:
	if not _is_live(e):
		return false
	var reach := _range * BREAK_SLACK
	var pos: Vector3 = (e as Enemy).global_position
	return WeaponRunner.flat(pos - _player.global_position).length_squared() <= reach * reach


func _on_downed_changed(is_downed: bool) -> void:
	if not is_downed:
		return
	if is_channeling():
		stop()
	_clear_watch()


static func _is_live(e: Variant) -> bool:
	if not is_instance_valid(e):
		return false
	var enemy := e as Enemy
	return enemy != null and enemy.is_inside_tree() and not enemy.is_dead()
