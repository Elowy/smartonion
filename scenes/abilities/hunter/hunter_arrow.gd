class_name HunterArrow
extends Projectile
## An arrow of a Hunter ability (Arrow Fan, Long Shot, Backstep's Parting Volley): an ordinary
## player [Projectile] (swept hits, EnemyGrid, pierce) whose hits are WEAPON hits of
## [member weapon] (crits, leech, Executioner / Slayer, the Mastery and outgoing multipliers; the
## on-hit procs roll once per cast through the shared proc gate) – the Rogue's knives (RogueBlade)
## with the plain arrow model of the bow. Two extras for Long Shot:
##   [member execute_threshold] / [member execute_bonus] – an enemy below that share (%) of its
##                       health takes that many % more from this arrow,
##   [member bleed_total] – a living enemy the arrow struck bleeds for that much damage over
##                       [member bleed_duration] seconds ([HunterBleed], source &"dot").
## A boss is ONE big target ([member boss_hits], [constant BOSS_REPEAT_MULT]): of the arrows of
## one cast that hit the same boss only the first deals its full damage (the Knife Bloom rule).

const BOSS_REPEAT_MULT := 0.4
## Spread (degrees) of the little volley Backstep looses as it lands.
const VOLLEY_SPREAD := 24.0
## Default look of the arrows (the fletching colour).
const COLOR := Color(0.95, 0.78, 0.4)

## Hits per boss instance id this cast has landed so far – one dictionary shared by the cast's arrows.
var boss_hits: Dictionary[int, int] = {}
var execute_threshold := 0.0
var execute_bonus := 0.0
var bleed_total := 0.0
var bleed_duration := 4.0
## Hits that got the execute bonus / opened a bleed (tests).
var executed := 0
var bled := 0


## An arrow of [param player] flying along [param dir] with [param p_weapon]'s hit rules. Not in
## the tree yet: the caller adds it (WeaponRunner.effects_parent) and places it.
static func make(player: Player, p_weapon: WeaponData, p_damage: float, p_crit: bool, dir: Vector3,
		p_speed: float, p_range: float, p_pierce: int, p_color: Color = COLOR) -> HunterArrow:
	var a := HunterArrow.new()
	a.name = "HunterArrow"
	a.team = TEAM_PLAYERS
	a.damage = p_damage
	a.is_crit = p_crit
	var d := Vector3(dir.x, 0.0, dir.z)
	a.direction = d.normalized() if d.length_squared() > 0.000001 else Vector3.FORWARD
	a.speed = maxf(0.0, p_speed)
	a.max_range = maxf(0.0, p_range)
	a.pierce = maxi(0, p_pierce)
	a._pierce_left = a.pierce
	a.attacker = player
	a.style = &"arrow"
	a.color = p_color
	a.weapon = p_weapon
	a.is_extra = true
	a.knockback = 0.6
	a.add_to_group(&"projectiles")
	a._build_visual()
	return a


## Looses [param count] arrows in a fan of [param spread_deg] degrees centred on [param dir]
## (unit, XZ), each for [param damage] (before its own crit roll: a talent script that forces
## crits is asked first, then CombatMath.roll_crit – one RunState.rng draw per arrow). The arrows
## of one call share one on-hit proc roll and one boss rule. [param options] may hold
## execute_threshold, execute_bonus, bleed_total, bleed_duration. Returns the arrows (empty when
## the hero has no weapon or no place to put them).
static func fan(player: Player, dir: Vector3, count: int, spread_deg: float, damage: float, p_speed: float,
		p_range: float, p_pierce: int, target: Node3D = null, options: Dictionary = {},
		p_color: Color = COLOR) -> Array[HunterArrow]:
	var out: Array[HunterArrow] = []
	var w := HunterKit.weapon(player)
	var parent := WeaponRunner.effects_parent(player)
	if player == null or w == null or parent == null or count <= 0:
		return out
	var crit_mult := CombatMath.crit_multiplier(w, player.stats)
	var gate := WeaponRunner.ProcGate.new()
	var boss_hits_shared: Dictionary[int, int] = {}
	var origin := player.global_position
	var facing := WeaponRunner.flat(dir)
	facing = facing.normalized() if facing.length_squared() > 0.0001 else Vector3.FORWARD
	for i in count:
		var angle := 0.0
		if count > 1:
			angle = deg_to_rad(spread_deg) * (float(i) / float(count - 1) - 0.5)
		var shot := facing.rotated(Vector3.UP, angle)
		var crit := HunterKit.bonus_crit(player, target) or CombatMath.roll_crit(player.stats, RunState.rng)
		var arrow := HunterArrow.make(player, w, damage * (crit_mult if crit else 1.0), crit, shot,
				p_speed, p_range, p_pierce, p_color)
		arrow.proc_gate = gate
		arrow.boss_hits = boss_hits_shared
		arrow.execute_threshold = float(options.get("execute_threshold", 0.0))
		arrow.execute_bonus = float(options.get("execute_bonus", 0.0))
		arrow.bleed_total = float(options.get("bleed_total", 0.0))
		arrow.bleed_duration = float(options.get("bleed_duration", 4.0))
		parent.add_child(arrow)
		arrow.global_position = origin + Vector3.UP * Player.CHEST_HEIGHT + shot * (Player.RADIUS + HunterKit.MUZZLE_GAP)
		out.append(arrow)
	player.face_attack(facing)
	return out


func _apply_hit(body: Node3D, kb_dir: Vector3, from_explosion: bool) -> void:
	var enemy := body as Enemy
	var full_damage := damage
	var mult := boss_repeat_mult(body)
	var executes := false
	if execute_bonus > 0.0 and enemy != null and is_instance_valid(enemy) and enemy.max_hp > 0.0 \
			and enemy.hp / enemy.max_hp * 100.0 < execute_threshold:
		mult *= 1.0 + execute_bonus / 100.0
		executes = true
	damage = full_damage * mult
	super._apply_hit(body, kb_dir, from_explosion)
	damage = full_damage
	if executes:
		executed += 1
	if bleed_total > 0.0 and HunterKit.is_live(enemy) and attacker != null and is_instance_valid(attacker):
		var hero := attacker as Player
		if hero != null and HunterBleed.apply(enemy, hero, bleed_total, bleed_duration, &"long_shot", &"dot") != null:
			bled += 1


## The share of its damage this arrow's hit on [param body] deals, and counts the hit: 1 for anything
## but a boss and for the first hit of the cast on a boss, [constant BOSS_REPEAT_MULT] for the later ones.
func boss_repeat_mult(body: Node3D) -> float:
	var boss := body as Enemy
	if boss == null or not is_instance_valid(boss) or not boss.is_boss():
		return 1.0
	var id := boss.get_instance_id()
	var seen: int = boss_hits.get(id, 0)
	boss_hits[id] = seen + 1
	return 1.0 if seen == 0 else BOSS_REPEAT_MULT
