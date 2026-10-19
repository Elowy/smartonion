class_name SettingOption
extends RefCounted
## One row of the settings: its key, where it is listed, and how its value is clamped, stepped,
## shown and written to / read from the settings file. Pure data + maths (no engine calls), so
## GameSettings, the Settings page and the tests all read the same table.
##
## Three kinds:
##   PERCENT – an int from min_value to max_value in steps of step (volumes); stepping stops at the ends.
##   CHOICE  – one of [member values] (ints; [member ids] are their names in the file, [member names] the
##             text on screen); stepping wraps around.
##   TOGGLE  – a bool; stepping flips it.

enum Kind { PERCENT, CHOICE, TOGGLE }

var key: StringName = &""
## Heading on the page and section of the file ("Audio" -> [audio]).
var section := ""
var label := ""
var kind := Kind.PERCENT
var default: Variant = 0
var min_value := 0
var max_value := 100
var step := 10
## CHOICE: the selectable values, their names in the settings file and their text on screen.
var values: Array[int] = []
var ids: Array[String] = []
var names: Array[String] = []


static func percent(p_key: StringName, p_section: String, p_label: String, p_default: int) -> SettingOption:
	var o := SettingOption.new()
	o.key = p_key
	o.section = p_section
	o.label = p_label
	o.kind = Kind.PERCENT
	o.default = p_default
	return o


## [param p_ids] and [param p_names] list the choices in display order, [param p_values] their ints.
static func choice(p_key: StringName, p_section: String, p_label: String, p_default: int,
		p_values: Array[int], p_ids: Array[String], p_names: Array[String]) -> SettingOption:
	var o := SettingOption.new()
	o.key = p_key
	o.section = p_section
	o.label = p_label
	o.kind = Kind.CHOICE
	o.default = p_default
	o.values = p_values
	o.ids = p_ids
	o.names = p_names
	return o


static func toggle(p_key: StringName, p_section: String, p_label: String, p_default: bool) -> SettingOption:
	var o := SettingOption.new()
	o.key = p_key
	o.section = p_section
	o.label = p_label
	o.kind = Kind.TOGGLE
	o.default = p_default
	return o


## The nearest legal value to [param value]: percents are rounded to the step and clamped, a choice that
## is not listed (or anything of the wrong type) falls back to the default.
func sanitize(value: Variant) -> Variant:
	match kind:
		Kind.PERCENT:
			if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
				return default
			var on_step := roundi(float(value) / float(step)) * step
			return clampi(on_step, min_value, max_value)
		Kind.CHOICE:
			if typeof(value) == TYPE_INT and values.has(int(value)):
				return int(value)
			return default
		_:
			return bool(value) if typeof(value) == TYPE_BOOL else default


## [param value] moved one step in [param direction] (< 0 left, > 0 right; 0 = unchanged).
func stepped(value: Variant, direction: int) -> Variant:
	var d := signi(direction)
	var current: Variant = sanitize(value)
	match kind:
		Kind.PERCENT:
			return sanitize(int(current) + d * step)
		Kind.CHOICE:
			var i := values.find(int(current))
			return values[wrapi(i + d, 0, values.size())]
		_:
			return (not bool(current)) if d != 0 else current


## The text shown for [param value] ("70%", "Borderless Fullscreen", "On").
func text(value: Variant) -> String:
	var v: Variant = sanitize(value)
	match kind:
		Kind.PERCENT:
			return "%d%%" % int(v)
		Kind.CHOICE:
			return names[values.find(int(v))]
		_:
			return "On" if bool(v) else "Off"


## How [param value] is written to the settings file (an int, a choice's id string, or a bool).
func to_file(value: Variant) -> Variant:
	var v: Variant = sanitize(value)
	match kind:
		Kind.CHOICE:
			return ids[values.find(int(v))]
		_:
			return v


## The value for what the settings file holds ([param raw]); the default when it is missing or not understood.
func from_file(raw: Variant) -> Variant:
	if kind == Kind.CHOICE:
		if typeof(raw) == TYPE_STRING and ids.has(String(raw)):
			return values[ids.find(String(raw))]
		return default
	return sanitize(raw)
