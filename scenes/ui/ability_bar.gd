class_name AbilityBar
extends HBoxContainer
## The ability icons of a unit frame (GDD 6.2, 12; beside the HP / resource bars on the frame's
## inner side): one AbilityIcon per AbilityRunner slot.
##  - Button slots (BUTTON_SLOTS icons in a row): 0 / 1 (RT / LT, the class's two core
##    abilities) are always drawn; 2 / 3 (RB / LB, learned Active abilities) appear as soon as
##    something is slotted there. Each shows the button prompt of the player's own device
##    (PlayerInput.ability_button: controller RT / LT / RB / LB, keyboard LMB / RMB / Q / E).
##  - Auto-cast slots 4..7: a 2 x 2 cluster of smaller icons (AUTO_ICON_SIZE, no prompt, no
##    seconds – the sweep only) behind a small gear mark ("these cast by themselves"), at the
##    inner end of the bar; shown once any auto-cast ability is learned (the free slots of the
##    cluster as faint sockets).
## Every icon shows a clockwise cooldown sweep, a dim state while the ability cannot be used, a
## short flash on AbilityRunner.ability_cast and its rank (AbilityIcon.set_rank: gold pips I–V,
## orange once the Rank V specialisation is chosen; follows AbilityRunner.ranks_changed).
## Everything is pushed from the runner (one AbilityRunner.slot_state per filled slot and
## rendered frame, nothing while the bar is hidden); the bar never touches gameplay state.
## Mirrored bars (right-hand frames) put the auto-cast cluster on the left (the inner side).

const SLOT_COUNT := AbilityRunner.MAX_SLOTS
## Slots with a button (RT, LT, RB, LB); the rest are auto-cast.
const BUTTON_SLOTS := AbilityRunner.INPUT_SLOTS
## Room between two button icons; wider when the prompt pills ("LMB" ~50 px) are wider than the
## icons, so neighbouring pills keep PILL_GAP between them.
const SEPARATION := 10
const PILL_GAP := 6
## Auto-cast icon side and the gap inside the 2 x 2 cluster.
const AUTO_ICON_SIZE := 26.0
const AUTO_GAP := 2
## Gap between the button row and the auto-cast cluster (the gear mark sits in it).
const GROUP_GAP := 4
const AUTO_MARK_WIDTH := 16.0
## Costs (item mods can change them) are re-read this often (s).
const COST_REFRESH := 0.25

var runner: AbilityRunner
var input: PlayerInput
## One icon per slot, in slot order (0..3 buttons, 4..7 auto-cast).
var icons: Array[AbilityIcon] = []
## Row of the button icons and the auto-cast cluster (gear mark + 2 x 2 grid).
var buttons: HBoxContainer
var auto_cluster: HBoxContainer
var auto_grid: GridContainer
var auto_mark: AutoMark

var _cost_timer := 0.0


## The gear between the button icons and the auto-cast cluster: a thin gold rule with a small
## gear on it.
class AutoMark extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var col := Color(UiTheme.GOLD_BORDER, 0.55)
		draw_line(Vector2(c.x, 2.0), Vector2(c.x, c.y - 10.0), col, 2.0)
		draw_line(Vector2(c.x, c.y + 10.0), Vector2(c.x, size.y - 2.0), col, 2.0)
		AbilityIcon.draw_gear(self, c, 7.5, Color(0.9, 0.84, 0.7))


static func create(mirrored: bool = false, icon_size: float = AbilityIcon.SIZE, auto_size: float = AUTO_ICON_SIZE) -> AbilityBar:
	var b := AbilityBar.new()
	b.name = "AbilityBar"
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_theme_constant_override(&"separation", GROUP_GAP)
	b.alignment = BoxContainer.ALIGNMENT_END if mirrored else BoxContainer.ALIGNMENT_BEGIN
	b.buttons = UiTheme.hbox(SEPARATION)
	b.buttons.name = "Buttons"
	b.buttons.alignment = b.alignment
	b.buttons.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for i in BUTTON_SLOTS:
		var icon := AbilityIcon.create(icon_size)
		icon.slot_index = i
		b.buttons.add_child(icon)
		b.icons.append(icon)
	b.auto_cluster = UiTheme.hbox(GROUP_GAP)
	b.auto_cluster.name = "AutoCast"
	b.auto_cluster.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.auto_mark = AutoMark.new()
	b.auto_mark.name = "AutoMark"
	b.auto_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.auto_mark.custom_minimum_size = Vector2(AUTO_MARK_WIDTH, auto_size * 2.0 + AUTO_GAP)
	b.auto_grid = GridContainer.new()
	b.auto_grid.name = "AutoGrid"
	b.auto_grid.columns = 2
	b.auto_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.auto_grid.add_theme_constant_override(&"h_separation", AUTO_GAP)
	b.auto_grid.add_theme_constant_override(&"v_separation", AUTO_GAP)
	for i in range(BUTTON_SLOTS, SLOT_COUNT):
		var icon := AbilityIcon.create(auto_size, false)
		icon.slot_index = i
		icon.show_prompt = false
		icon.show_cooldown_text = false
		b.auto_grid.add_child(icon)
		b.icons.append(icon)
	if mirrored:
		b.auto_cluster.add_child(b.auto_grid)
		b.auto_cluster.add_child(b.auto_mark)
		b.add_child(b.auto_cluster)
		b.add_child(b.buttons)
	else:
		b.auto_cluster.add_child(b.auto_mark)
		b.auto_cluster.add_child(b.auto_grid)
		b.add_child(b.buttons)
		b.add_child(b.auto_cluster)
	b.auto_cluster.visible = false
	b.set_process(false)
	return b


## The text of the button prompt for ability [param slot] on [param p_input]'s device: the
## device's own binding (PlayerInput.ability_button) – keyboard LMB / RMB / Q / E, controllers
## RT / LT / RB / LB (no device: the controller default). "" for the auto-cast slots.
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


## Follows [param p_runner]'s slots and ranks (null unbinds); [param p_input] picks the prompts.
func bind(p_runner: AbilityRunner, p_input: PlayerInput) -> void:
	unbind()
	if not is_instance_valid(p_runner):
		return
	runner = p_runner
	input = p_input
	runner.slots_changed.connect(_rebuild)
	runner.ability_cast.connect(_on_ability_cast)
	runner.ranks_changed.connect(_on_ranks_changed)
	_rebuild()
	set_process(true)


func unbind() -> void:
	if is_instance_valid(runner):
		if runner.slots_changed.is_connected(_rebuild):
			runner.slots_changed.disconnect(_rebuild)
		if runner.ability_cast.is_connected(_on_ability_cast):
			runner.ability_cast.disconnect(_on_ability_cast)
		if runner.ranks_changed.is_connected(_on_ranks_changed):
			runner.ranks_changed.disconnect(_on_ranks_changed)
	runner = null
	input = null
	set_process(false)
	for icon in icons:
		icon.set_ability(null)
		icon.set_prompt("")
		icon.set_rank(0)
	auto_cluster.visible = false


## Whether slot [param index] is an auto-cast slot (no button).
static func is_auto_slot(index: int) -> bool:
	return index >= BUTTON_SLOTS and index < SLOT_COUNT


## Room between two neighbouring button icons (see [method separation_for]).
func button_separation() -> int:
	return buttons.get_theme_constant(&"separation")


## Re-reads the slot contents (abilities, costs, prompts, ranks).
func _rebuild() -> void:
	if not is_instance_valid(runner):
		return
	var keyboard := input is KeyboardInput
	var any_auto := false
	for i in SLOT_COUNT:
		var a := runner.slots[i] if i < runner.slots.size() else null
		var icon := icons[i]
		var cost_color := Color(0, 0, 0, 0)
		if a != null and a.resource != &"":
			var res := runner.get_resource(a.resource)
			if res != null and res.data != null:
				cost_color = res.data.color
		icon.set_ability(a, runner.cost_of(a) if a != null else 0.0, cost_color)
		_set_rank(icon, a)
		if is_auto_slot(i):
			any_auto = any_auto or a != null
			continue
		icon.set_prompt(prompt_text(input, i) if a != null else "", keyboard)
		icon.visible = i < AbilityRunner.CORE_SLOTS or a != null
	auto_cluster.visible = any_auto
	var button_icons: Array[AbilityIcon] = icons.slice(0, BUTTON_SLOTS)
	buttons.add_theme_constant_override(&"separation", separation_for(button_icons))
	refresh()


func _set_rank(icon: AbilityIcon, a: AbilityData) -> void:
	if a == null or not is_instance_valid(runner):
		icon.set_rank(0)
	else:
		icon.set_rank(runner.rank_of(a.id), runner.spec_of(a.id) >= 0)


func _on_ranks_changed(ability_id: StringName) -> void:
	for icon in icons:
		if icon.ability != null and icon.ability.id == ability_id:
			_set_rank(icon, icon.ability)


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


## Pushes cooldown / readiness (and charges) of every filled slot into the icons, from one
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
