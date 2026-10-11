class_name GeneralTremorVfx
extends Node3D
## War Stomp's Tremor Field look: shock rings that keep rippling out from the centre of the
## shaking [AbilityArea] (two rings, half a cycle apart), so the field never reads as a plain
## dirt patch. A child of the area (dies with it); purely visual.

const CYCLE := 0.8
const COLOR := Color(0.95, 0.8, 0.5)

var _area: AbilityArea
var _rings: Array[MeshInstance3D] = []
var _age := 0.0


static func attach(area: AbilityArea) -> GeneralTremorVfx:
	if area == null:
		return null
	var fx := GeneralTremorVfx.new()
	fx.name = "Tremor"
	fx._area = area
	area.add_child(fx)
	return fx


func _ready() -> void:
	for i in 2:
		var mi := MeshInstance3D.new()
		mi.mesh = MeshKit.cached("general:aura_quad", func() -> Mesh:
			var q := PlaneMesh.new()
			q.size = Vector2(2.0, 2.0)
			return q)
		mi.material_override = Mats.ring()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position.y = 0.07
		add_child(mi)
		_rings.append(mi)
	_update()


func _process(delta: float) -> void:
	_age += delta
	_update()


func _update() -> void:
	var radius := _area.radius if _area != null and is_instance_valid(_area) else 2.0
	var life := 1.0
	if _area != null and is_instance_valid(_area):
		life = clampf((_area.duration - _age) / 0.4, 0.0, 1.0) * clampf(_age / 0.2, 0.0, 1.0)
	for i in _rings.size():
		var k := fmod(_age / CYCLE + 0.5 * i, 1.0)
		var r := maxf(0.1, radius * (0.2 + 0.8 * k))
		_rings[i].scale = Vector3(r, 1.0, r)
		Mats.set_ring(_rings[i], Color(COLOR.r, COLOR.g, COLOR.b, 0.75 * (1.0 - k) * life), 0.8, 0.97, 0.0)
