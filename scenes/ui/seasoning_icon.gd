class_name SeasoningIcon
extends Control
## A Seasoning's picture (M9): the target ability's icon (AbilityIcon, the companion / Storm Echo use a stand-in
## ability) with a small spice badge in the bottom-right corner – a red pouch-coloured disc with three peppercorns.
## [method set_state] dims it while the Seasoning is locked. Used by the lobby picker and the slot chips; the
## Onion Patch can reuse it.

const BADGE_COLOR := Color(0.78, 0.2, 0.12)
const BADGE_RIM := Color(1.0, 0.82, 0.4)
const PEPPERCORN := Color(1.0, 0.9, 0.62)
const LOCKED_TINT := Color(0.45, 0.45, 0.5)

var seasoning: SeasoningData
var icon: AbilityIcon
var _badge: Control
var _side := 44.0


## [param p_seasoning] drawn [param p_size] px wide (null = an empty slot socket without a badge).
static func create(p_seasoning: SeasoningData, p_size: float = 44.0) -> SeasoningIcon:
	var s := SeasoningIcon.new()
	s._side = p_size
	s.custom_minimum_size = Vector2(p_size, p_size)
	s.size = Vector2(p_size, p_size)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.icon = AbilityIcon.create(p_size, false)
	s.add_child(s.icon)
	s._badge = _Badge.new()
	s._badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(s._badge)
	s.set_seasoning(p_seasoning)
	return s


func set_seasoning(p_seasoning: SeasoningData) -> void:
	seasoning = p_seasoning
	var a := p_seasoning.icon_ability() if p_seasoning != null else null
	icon.set_ability(a, 0.0, Color(0, 0, 0, 0))
	var badge_size := _side * 0.46
	_badge.size = Vector2(badge_size, badge_size)
	_badge.position = Vector2(_side - badge_size * 0.78, _side - badge_size * 0.78)
	_badge.visible = p_seasoning != null
	_badge.queue_redraw()


## Dims the icon (a locked Seasoning).
func set_state(locked: bool) -> void:
	modulate = LOCKED_TINT if locked else Color.WHITE


## The spice badge: a disc with a gold rim and three peppercorns.
class _Badge extends Control:
	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.5
		var c := size * 0.5
		draw_circle(c, r, Color(0.05, 0.03, 0.02, 0.95))
		draw_circle(c, r * 0.86, SeasoningIcon.BADGE_RIM)
		draw_circle(c, r * 0.72, SeasoningIcon.BADGE_COLOR)
		for offset: Vector2 in [Vector2(-0.3, 0.2), Vector2(0.3, 0.2), Vector2(0.0, -0.32)]:
			draw_circle(c + offset * r, r * 0.2, SeasoningIcon.PEPPERCORN)


## One Seasoning slot of a hero (the lobby card's pill): the picked Seasoning's icon, an empty gold socket for a free
## slot, or a dim one for a slot the class has not unlocked yet.
class SeasoningSocket extends Control:
	var content: SeasoningIcon
	var locked := false

	static func create(p_seasoning: SeasoningData, p_locked: bool, p_size: float) -> SeasoningSocket:
		var s := SeasoningSocket.new()
		s.locked = p_locked and p_seasoning == null
		s.custom_minimum_size = Vector2(p_size, p_size)
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if p_seasoning != null:
			s.content = SeasoningIcon.create(p_seasoning, p_size)
			s.add_child(s.content)
		return s

	func _draw() -> void:
		if content != null:
			return
		var rect := Rect2(Vector2.ZERO, custom_minimum_size).grow(-1.0)
		var line := Color(0.4, 0.36, 0.32, 0.7) if locked else UiTheme.GOLD_DARK
		draw_rect(rect, Color(0.0, 0.0, 0.0, 0.35))
		draw_rect(rect, line, false, 1.5)
		if locked:
			draw_line(rect.position + rect.size * 0.3, rect.end - rect.size * 0.3, line, 1.5)
