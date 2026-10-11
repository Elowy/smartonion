class_name WarriorWhirlwind
extends AbilityEffect
## Whirlwind (GDD 3.1): a short spin that hits every enemy around the hero for weapon damage.
## The hero keeps moving and can use Charge meanwhile; the spin cannot be recast while it runs.
##
## Params (AbilityData.params; items and ranks change them):
##   damage_pct     total weapon damage per enemy over the BASE duration (150 = 150%), times
##                  "power" (Rank II / IV)
##   duration       spin length in seconds (item: duration_add)
##   tick_interval  seconds between two hits; each hit is damage_pct / base ticks, so a longer
##                  spin hits more often (and harder in total)
##   radius         reach around the hero in metres (Area Size scales it; Rank III +1 m)
##   slow, slow_duration   % movement slow on every hit enemy (0 = none)
##   leech          % of the damage dealt healed to the hero (Rank V "Bloodbath")
## Rank V "Unrelenting" lowers the Rage cost (cost_add).

## Bots spin when at least this many enemies are within reach ...
const AUTO_MIN_ENEMIES := 3
## ... or one enemy when the Rage bar is full (do not waste Rage).
const AUTO_FULL_RAGE_ENEMIES := 1
const DEFAULT_RADIUS := 3.0
const DEFAULT_INTERVAL := 0.25
const DEFAULT_SLOW_DURATION := 1.5
const SPARK_COLOR := Color(1.0, 0.55, 0.3)

var _player: Player
var _spin := WarriorSpin.new()


func is_spinning() -> bool:
	return _spin.is_running()


## The running spin (tests: totals of the last spin).
func spin() -> WarriorSpin:
	return _spin


func can_cast(_ctx: AbilityContext) -> bool:
	return not is_spinning()


func wants_auto_cast(ctx: AbilityContext) -> bool:
	if ctx.player == null:
		return false
	var count := WarriorKit.enemies_within(ctx.player, reach_of(ctx)).size()
	if count >= AUTO_MIN_ENEMIES:
		return true
	var rage := ctx.player.abilities.primary_resource() if ctx.player.abilities != null else null
	return count >= AUTO_FULL_RAGE_ENEMIES and rage != null and rage.is_full()


## Reach around the hero in metres, with Area Size.
func reach_of(ctx: AbilityContext) -> float:
	return ctx.num("radius", DEFAULT_RADIUS) * CombatMath.area_mult(ctx.player.stats)


func cast(ctx: AbilityContext) -> bool:
	if ctx.player == null or is_spinning():
		return false
	_player = ctx.player
	var interval := maxf(0.05, ctx.num("tick_interval", DEFAULT_INTERVAL))
	var duration := maxf(interval, ctx.num("duration", 1.0))
	var base_duration := maxf(interval, float(ctx.ability.params.get("duration", duration)))
	var base_ticks := maxi(1, roundi(base_duration / interval))
	_spin.interval = interval
	_spin.radius = reach_of(ctx)
	_spin.hit_pct = ctx.num("damage_pct", 150.0) * ctx.num("power", 1.0) / float(base_ticks)
	_spin.school = ctx.ability.school
	_spin.slow = ctx.num("slow")
	_spin.slow_duration = ctx.num("slow_duration", DEFAULT_SLOW_DURATION)
	_spin.leech = ctx.num("leech")
	_spin.rage_per_hit = 0.0
	_spin.spark_color = SPARK_COLOR
	_spin.look = WarriorSpinVfx.spawn(_player, _spin.radius, duration, ctx.ability.color)
	if not _player.downed_changed.is_connected(_on_downed_changed):
		_player.downed_changed.connect(_on_downed_changed)
	# The first hit lands with the cast, the rest follow every interval.
	_spin.start(_player, _player, duration)
	return true


func tick(_ctx: AbilityContext, delta: float) -> void:
	_spin.tick(delta)


func begin_wave(_ctx: AbilityContext) -> void:
	_spin.stop()


## The market shows no spin (also when the ability is forgotten).
func end_wave(_ctx: AbilityContext) -> void:
	_spin.stop()


func _on_downed_changed(is_downed: bool) -> void:
	if is_downed:
		_spin.stop()
