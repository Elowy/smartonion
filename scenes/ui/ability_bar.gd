class_name AbilityBar
extends HBoxContainer
## The ability icons of a unit frame (GDD 12, beside the HP / resource bars on the frame's
## inner side): one AbilityIcon per AbilityRunner slot. Slots 0 / 1 (the class's two core
## abilities) are always drawn; slots 2 / 3 (learned in M4) appear as soon as something is
## slotted there. Each icon shows the button prompt of the player's own device
## (PlayerInput.ability_button: controller RT / LT / RB / LB, keyboard LMB / RMB / Q / E), a
## clockwise cooldown sweep with the seconds left, a dim state while the ability cannot be used
## and a short flash on AbilityRunner.ability_cast.
## Everything is pushed from the runner (one AbilityRunner.slot_state per slot and rendered
## frame, nothing while the bar is hidden); the bar never touches gameplay state.

const SLOT_COUNT := AbilityRunner.INPUT_SLOTS  # auto-cast slots 4..7: M4 HUD
## Room between two icons; wider when the prompt pills ("LMB" ~50 px) are wider than the
## icons, so neighbouring pills keep PILL_GAP between them.
const SEPARATION := 10
const PILL_GAP := 6
## Costs (item mods can change them) are re-read this often (s).
const COST_REFRESH := 0.25

var runner: AbilityRunner
var input: PlayerInput
var icons: Array[AbilityIcon] = []

var _cost_timer := 0.0


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


## The text of the button prompt for ability [param slot] on [param p_input]'s device: the
## device's own binding (PlayerInput.ability_button) – keyboard LMB / RMB / Q / E, controllers
## RT / LT / RB / LB (no device: the controller default).
static func prompt_text(p_input: PlayerInput, slot: int) -> String:
	if slot < 0 or slot >= PlayerInput.ABILITY_BUTTONS.size():
		return ""
	var button: PlayerInput.Pad = p_input.ability_button(slot) if p_input != null else PlayerInput.ABILITY_BUTTONS[slot]
	if p_input is KeyboardInput:
		match button:
			PlayerInput.Pad.RT:
				return "LMB"
			PlayerInput.Pad.LT:
				return "RMB"
		return UiGlyph.keyboard_name(button)
	return String(PlayerInput.Pad.keys()[button])


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
	add_theme_constant_override(&"separation", separation_for(icons))
	refresh()


## Icon spacing for [param p_icons]: SEPARATION, or more when a prompt pill overhangs its icon.
static func separation_for(p_icons: Array[AbilityIcon]) -> int:
	var overhang := 0.0
	for icon in p_icons:
		if icon.visible:
			overhang = maxf(overhang, icon.prompt_width() - icon.icon_side())
	return maxi(SEPARATION, ceili(overhang) + PILL_GAP)


## Tooltip text of slot [param slot]: the description with the item-modded params filled in
## (AbilityRunner.params_for), numbers without trailing ".0".
func description_for(slot: int) -> String:
	if not is_instance_valid(runner) or slot < 0 or slot >= runner.slots.size() or runner.slots[slot] == null:
		return ""
	return AbilityIcon.format_description(runner.slots[slot], runner.params_for(runner.slots[slot]))


## Pushes cooldown / readiness (and charges) of every slot into the icons, from one
## AbilityRunner.slot_state per slot. [param with_costs] also updates the costs (done every
## COST_REFRESH seconds by the per-frame update).
func refresh(with_costs: bool = false) -> void:
	if not is_instance_valid(runner):
		return
	for i in SLOT_COUNT:
		var icon := icons[i]
		if icon.ability == null:
			continue
		var st := runner.slot_state(i)
		if st.is_empty():
			continue
		if with_costs:
			icon.set_cost(st["cost"])
		# Charges (Blink with the Band of the Blinking Star): a counter while there is more than one.
		icon.set_charges(st["charges"], st["charges_max"])
		icon.set_state(st["ratio"], st["left"], st["ready"])


func _on_ability_cast(slot_index: int, _ability: AbilityData) -> void:
	if slot_index >= 0 and slot_index < icons.size():
		icons[slot_index].flash_cast()
	refresh()


func _process(delta: float) -> void:
	if not is_instance_valid(runner):
		set_process(false)
		return
	if not is_visible_in_tree():
		_cost_timer = 0.0  # costs are re-read on the first frame shown again
		return
	_cost_timer -= delta
	var with_costs := _cost_timer <= 0.0
	if with_costs:
		_cost_timer = COST_REFRESH
	refresh(with_costs)
