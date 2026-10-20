class_name HunterFeatherBolt
extends Projectile
## A feather bolt of the Owl companion: a regular player [Projectile] (flight, swept hits, EnemyGrid)
## whose hit is PET damage instead of a weapon hit – ProcSystem.deal_raw(..., &"pet") on the Hunter
## (kill credit, damage meter, Beastbond; no on-hit procs, leech or resource gains, no crits, no
## knockback). The owl's Bonded Vigor heal ([member heal_pct]) is paid from the damage dealt.

const COLOR := Color(0.95, 0.85, 0.6)
const FEATHER := Color(0.78, 0.6, 0.38)

## Share (%) of the damage dealt that heals the Hunter (Bonded Vigor).
var heal_pct := 0.0
## Instance ids of the enemies damaged (tests).
var victim_ids: Array[int] = []


## Fires a bolt from [param from] (world, its height is kept) along [param dir] for [param hunter].
## Added under the arena's entities (or next to the Hunter).
static func fire(hunter: Player, from: Vector3, dir: Vector3, p_damage: float, p_range: float,
		p_speed: float = 20.0, p_heal_pct: float = 0.0) -> HunterFeatherBolt:
	var b := HunterFeatherBolt.new()
	b.name = "FeatherBolt"
	b.team = TEAM_PLAYERS
	b.damage = p_damage
	var d := Vector3(dir.x, 0.0, dir.z)
	b.direction = d.normalized() if d.length_squared() > 0.000001 else Vector3.FORWARD
	b.speed = maxf(0.0, p_speed)
	b.max_range = maxf(0.0, p_range)
	b.attacker = hunter
	b.style = &"arrow"
	b.color = COLOR
	b.knockback = 0.0
	b.heal_pct = p_heal_pct
	b.add_to_group(&"projectiles")
	b._build_visual()
	var parent := WeaponRunner.effects_parent(hunter)
	if parent != null:
		parent.add_child(b)
		b.global_position = from
	return b


## A small feather along -Z: a pale quill with a tawny vane.
func _build_visual() -> void:
	var v := Node3D.new()
	v.name = "Visual"
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.cached("hunter:feather", func() -> Mesh:
		var k := MeshKit.new()
		k.add_segment(Vector3(0, 0, 0.22), Vector3(0, 0, -0.24), 0.012, 0.004, Color(0.96, 0.92, 0.8), 4)
		var vane := PackedVector2Array([Vector2(0.0, -0.22), Vector2(0.05, -0.1), Vector2(0.06, 0.05),
				Vector2(0.03, 0.17), Vector2(0.0, 0.2), Vector2(-0.03, 0.17), Vector2(-0.06, 0.05), Vector2(-0.05, -0.1)])
		k.add_extrusion(vane, 0.01, MeshKit.xf(Vector3.ZERO, Vector3(90, 0, 0)), FEATHER)
		return k.build())
	mi.material_override = Mats.toon_vc(false)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	v.add_child(mi)
	var streak := MeshInstance3D.new()
	streak.mesh = MeshKit.cached("hunter:feather_streak", func() -> Mesh:
		var b := BoxMesh.new()
		b.size = Vector3(0.035, 0.015, 0.5)
		return b)
	streak.material_override = Mats.unshaded(Color(COLOR, 0.22))
	streak.position = Vector3(0, 0, 0.4)
	streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	v.add_child(streak)
	v.scale = Vector3.ONE * 1.5
	v.basis = Basis.looking_at(direction, Vector3.UP) * Basis.from_scale(v.scale)
	add_child(v)
	_visual = v


## Replaces the weapon hit of Projectile: pet damage through the Hunter's ProcSystem.
func _apply_hit(body: Node3D, _kb_dir: Vector3, _from_explosion: bool) -> void:
	hit_count += 1
	var e := body as Enemy
	if e == null or attacker == null or not is_instance_valid(attacker):
		return
	var hunter := attacker as Player
	if hunter == null or hunter.procs == null:
		return
	victim_ids.append(e.get_instance_id())
	var dealt := hunter.procs.deal_raw(e, damage, HunterKit.PHYSICAL, true, &"pet")
	if heal_pct > 0.0 and dealt > 0.0 and not hunter.downed:
		hunter.heal(dealt * heal_pct / 100.0)
