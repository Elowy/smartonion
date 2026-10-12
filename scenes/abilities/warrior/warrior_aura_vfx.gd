class_name WarriorAuraVfx
extends WarriorFx
## A faint ring on the ground under the hero that slowly pulses – the look of the Warrior
## talent capstones while they run (Rampage's ember ring at 5+ stacks, Unbreakable's golden
## ring). Child of the hero; held until [method WarriorFx.dismiss]. [member strength] (0..1)
## scales its opacity (Rampage: stacks / 10). Purely visual.

const GROUND_Y := 0.04
const RADIUS := 0.95
const INNER := 0.78
const PULSE_SPEED := 3.0
const PULSE_AMOUNT := 0.25

## 0..1 opacity factor on top of the fades.
var strength := 1.0
var color := Color(1.0, 0.3, 0.1, 0.55)

var _ring: MeshInstance3D


## A held ring of [param p_color] under [param hero] (null when the hero is not in the tree).
static func spawn(hero: Node3D, p_color: Color, p_strength: float = 1.0, node_name: String = "WarriorAura") -> WarriorAuraVfx:
	if hero == null or not hero.is_inside_tree():
		return null
	var fx := WarriorAuraVfx.new()
	fx.name = node_name
	fx.color = p_color
	fx.strength = clampf(p_strength, 0.0, 1.0)
	fx.life = 0.0
	fx.fade_in = 0.15
	fx.fade_out = 0.3
	hero.add_child(fx)
	fx.position = Vector3(0.0, GROUND_Y, 0.0)
	return fx


func _ready() -> void:
	_ring = add_part(ring_mesh(INNER), color)
	_ring.scale = Vector3(RADIUS, 1.0, RADIUS)


func fade() -> float:
	return super() * strength


func _animate(_delta: float) -> void:
	if _ring != null:
		var s := RADIUS * (1.0 + sin(age * PULSE_SPEED) * PULSE_AMOUNT * 0.2)
		_ring.scale = Vector3(s, 1.0, s)
