class_name FpsOverlay
extends CanvasLayer
## The "Show FPS" counter (M7a settings): a small label in the top-right corner above every other screen.
## Owned by the Settings autoload, which creates it the first time the option is switched on.

const LAYER := 120
const REFRESH := 0.25
const MARGIN := 14.0

var label: Label

var _timer := 0.0


static func create() -> FpsOverlay:
	var o := FpsOverlay.new()
	o.name = "FpsOverlay"
	o.layer = LAYER
	o.process_mode = Node.PROCESS_MODE_ALWAYS
	o._build()
	return o


func _build() -> void:
	label = UiTheme.label("", &"", UiTheme.FONT_BODY, UiTheme.GOLD_BRIGHT)
	label.theme = UiTheme.get_theme()
	label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	label.offset_right = -MARGIN
	label.offset_top = MARGIN
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(label)
	refresh()


func refresh() -> void:
	label.text = "%d FPS" % Engine.get_frames_per_second()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH
		refresh()
