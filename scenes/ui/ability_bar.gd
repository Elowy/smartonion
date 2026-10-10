class_name AbilityBar
extends HBoxContainer
## The ability bar under a unit frame (GDD 12): one AbilityIcon per AbilityRunner slot.
## Slots 0 / 1 (RT / LT, the class's two core abilities) are always drawn; slots 2 / 3 (RB / LB,
## abilities learned in M4) appear as soon as something is slotted there. Each icon shows the
## button prompt of the player's own device (controller RT / LT / RB / LB, keyboard LMB / RMB /
## E / Q), a clockwise cooldown sweep with the seconds left, a dim state while the ability cannot
## be used (AbilityRunner.is_ready) and a short flash on AbilityRunner.ability_cast.
## Everything is pushed from the runner every frame; the bar never touches gameplay state.

const SLOT_COUNT := AbilityRunner.MAX_SLOTS
const SEPARATION := 6

var runner: AbilityRunner
var input: PlayerInput
var icons: Array[AbilityIcon] = []


static func create(mirrored: bool = false, icon_size: float = AbilityIcon.SIZE) -> AbilityBar:
	var b := AbilityBar.new()
	b.name = "AbilityBar"
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_theme_constant_override(&"separation", SEPARATION)
	b.alignment = BoxContainer.ALIGNMENT_END if mirrored else BoxContainer.ALIGNMENT_BEGIN
	for i in SLOT_COUNT:
		var icon := AbilityIcon.create(icon_size)
		icon.slot_index = i
		b.add_child(icon)
		b.icons.append(icon)
	b.set_process(false)
	return b


## The text of the button prompt for ability [param slot] on [param p_input]'s device.
static func prompt_text(p_input: PlayerInput, slot: int) -> String:
	if slot < 0 or slot >= PlayerInput.ABILITY_BUTTONS.size():
		return ""
	if p_input is KeyboardInput:
		match slot:
			0:
				return "LMB"
			1:
				return "RMB"
		return UiGlyph.keyboard_name(PlayerInput.ABILITY_BUTTONS[slot])
	return String(PlayerInput.Pad.keys()[PlayerInput.ABILITY_BUTTONS[slot]])


## Follows [param p_runner]'s slots (null unbinds); [param p_input] picks the prompts.
func bind(p_runner: AbilityRunner, p_input: PlayerInput) -> void:
	unbind()
	if not is_instance_valid(p_runner):
		return
	runner = p_runner
	input = p_input
	runner.slots_changed.connect(_rebuild)
	runner.ability_cast.connect(_on_ability_cast)
	_rebuild()
	set_process(true)


func unbind() -> void:
	if is_instance_valid(runner):
		if runner.slots_changed.is_connected(_rebuild):
			runner.slots_changed.disconnect(_rebuild)
		if runner.ability_cast.is_connected(_on_ability_cast):
			runner.ability_cast.disconnect(_on_ability_cast)
	runner = null
	input = null
	set_process(false)
	for icon in icons:
		icon.set_ability(null)
		icon.set_prompt("")


## Re-reads the slot contents (abilities, costs, prompts).
func _rebuild() -> void:
	if not is_instance_valid(runner):
		return
	var keyboard := input is KeyboardInput
	for i in SLOT_COUNT:
		var a := runner.slots[i] if i < runner.slots.size() else null
		var icon := icons[i]
		var cost_color := Color(0, 0, 0, 0)
		if a != null and a.resource != &"":
			var res := runner.get_resource(a.resource)
			if res != null and res.data != null:
				cost_color = res.data.color
		icon.set_ability(a, runner.cost_of(a) if a != null else 0.0, cost_color)
		icon.set_prompt(prompt_text(input, i) if a != null else "", keyboard)
		icon.visible = i < AbilityRunner.CORE_SLOTS or a != null
	refresh()


## Pushes cooldown / readiness of every slot into the icons.
func refresh() -> void:
	if not is_instance_valid(runner):
		return
	for i in SLOT_COUNT:
		var icon := icons[i]
		if icon.ability == null:
			continue
		var left := runner.remaining(i)
		icon.set_state(runner.cooldown_ratio(i), left, left <= 0.0 and runner.is_ready(i))


func _on_ability_cast(slot_index: int, _ability: AbilityData) -> void:
	if slot_index >= 0 and slot_index < icons.size():
		icons[slot_index].flash_cast()
	refresh()


func _process(_delta: float) -> void:
	if not is_instance_valid(runner):
		set_process(false)
		return
	refresh()
