class_name TalentTab
extends Control
## The Talents tab of a player's between-wave panel (GDD 7, 12; PlayerPanel tab 3, M5): the
## hero's three talent trees (TalentState), spent with A, taken back with X, reset from the
## shared wallet (architecture §2.2). Same wiring as the TrainerTab: PlayerPanel routes the
## input (handle_input – LT / RT switch tabs unless [method is_modal]), shows [signal message]
## as its toast and rebuilds the prompt row from [method prompt_spec] on
## [signal prompts_changed].
##
## P0 stub: a centred "Talents" label, no input. T-UI implements the tab.

## Text for the panel's toast: [param bbcode] shown, [param plain] kept as PlayerPanel.last_message.
signal message(bbcode: String, plain: String, color: Color, coin: bool)
## Something the prompt row shows changed.
signal prompts_changed

var slot: PlayerSlot

var _focused := false


static func create(p_slot: PlayerSlot) -> TalentTab:
	var t := TalentTab.new()
	t.slot = p_slot
	t.name = "TalentTab"
	t._build()
	return t


## The hero (null when the slot has none).
func player() -> Player:
	if slot == null or not is_instance_valid(slot.player):
		return null
	return slot.player as Player


## Rebuilds from the hero's TalentState.
func refresh() -> void:
	pass


## Whether the tab receives its player's input (the panel has the focus and shows this tab).
func set_focused(on: bool) -> void:
	_focused = on


## One frame of the player's input. Returns true when a press was used (B only when it
## cancelled a confirm / hold, so the Intermission can unready with B).
func handle_input(_input: PlayerInput, _delta: float) -> bool:
	return false


## A confirm / hold is open: LT / RT must not switch tabs.
func is_modal() -> bool:
	return false


## Button prompts for the panel's prompt row: [button, text] pairs (PlayerInput.Pad or
## TrainerTab.NAV_PROMPT / NAV_PROMPT_SIDEWAYS).
func prompt_spec() -> Array:
	return []


## Short context text for the panel's prompt row.
func context_text() -> String:
	return ""


func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var title := UiTheme.label("Talents", &"", UiTheme.FONT_LARGE, UiTheme.GOLD)
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(title)
