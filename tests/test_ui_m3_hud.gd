extends TestCase
## M3 unit frames: live class resources (bar + "value / max", pips), the ability bar under the
## frame (prompts per device, cooldown sweep and seconds, dimming, cast flash, slot room).

const Fakes := preload("res://tests/test_ui_m3_fakes.gd")
const UiFakes := preload("res://tests/ui_fakes.gd")

var world: Node3D
var frame: UnitFrame
var nodes: Array[Node] = []


func before_each() -> void:
	UiFakes.reset_players()
	RunState.start_run(1, 5)
	world = Node3D.new()
	world.name = "M3HudWorld"
	tree.root.add_child(world)
	tree.current_scene = world
	frame = UnitFrame.create(0, false)
	tree.root.add_child(frame)
	nodes.append(frame)


func after_each() -> void:
	for n in nodes:
		UiFakes.free_node(n)
	nodes.clear()
	UiFakes.free_node(world)
	world = null
	frame = null
	UiFakes.reset_players()


func _hero(resources: Array[ResourceData], abilities: Array[AbilityData], input: PlayerInput = null, class_id: StringName = &"warrior") -> Player:
	var p := Fakes.hero(world, input if input != null else UiFakes.HumanInput.new("pad:1"), resources, abilities, class_id)
	frame.bind(p)
	return p


# --- Resources ---------------------------------------------------------------------------

func test_primary_bar_shows_value_over_max_in_resource_colour() -> void:
	var data := Fakes.rage()
	var p := _hero([data], [])
	var bar := frame.resource_bar
	check(bar != null, "a bar for Rage")
	check_eq(bar.text, "0 / 100", "starts empty")
	check(bar.fill_color.is_equal_approx(data.color), "bar uses ResourceData.color")
	p.abilities.get_resource(&"rage").add(37.9, false)
	check_eq(bar.text, "37 / 100", "follows ClassResource.changed, never rounds up")
	check_near(bar.value, 37.9, 0.001, "bar value")
	check_near(bar.max_value, 100.0, 0.001, "bar max")
	check(frame.resource_bar.font_size >= 18, "text >= 18 px")


func test_big_spend_flashes_the_bar_and_small_changes_do_not() -> void:
	var p := _hero([Fakes.rage()], [])
	var res := p.abilities.get_resource(&"rage")
	res.set_value(80.0)
	var bar := frame.resource_bar
	bar.flash = 0.0
	res.add(-3.0, false)
	check_eq(bar.flash, 0.0, "a small drop (decay) does not flash")
	res.spend(40.0)
	check(bar.flash > 0.0, "paying for an ability flashes the bar")
	check_eq(bar.text, "37 / 100", "and shows the new value")


func test_pips_follow_the_resource_and_energy_keeps_its_bar() -> void:
	var p := _hero([Fakes.energy(), Fakes.combo()], [])
	var display := frame.resource_display
	check_eq(display.row_count(), 2, "Energy + Combo Points")
	check(display.bar_for(&"energy") != null, "Energy is a bar")
	check_eq(frame.resource_bar.text, "100 / 100", "Energy starts full")
	check(display.bar_for(&"combo_points") == null, "Combo Points is not a bar")
	var pips := display.pips_for(&"combo_points")
	check(pips != null, "Combo Points are pips")
	check_eq(pips.count, 5, "five pips")
	check_eq(pips.filled, 0, "none lit")
	var combo := p.abilities.get_resource(&"combo_points")
	combo.add(3.0, false)
	check_eq(pips.filled, 3, "three combo points lit")
	combo.add(10.0, false)
	check_eq(pips.filled, 5, "capped at the maximum")
	check(pips.is_full(), "full row")
	combo.set_value(0.0)
	check_eq(pips.filled, 0, "spent")
	check(display.pips_for(&"combo_points").color.is_equal_approx(Fakes.combo().color), "pip colour from the data")


func test_pips_count_whole_pips_only() -> void:
	check_eq(ResourceDisplay.Pips.filled_for(2.99, 5), 2, "2.99 shows two pips")
	check_eq(ResourceDisplay.Pips.filled_for(3.0, 5), 3, "3 shows three")
	check_eq(ResourceDisplay.Pips.filled_for(-1.0, 5), 0, "never negative")
	check_eq(ResourceDisplay.Pips.filled_for(9.0, 3), 3, "never above the count")


func test_pip_only_class_has_a_trough_of_pips_and_no_bar() -> void:
	var p := _hero([Fakes.holy_power()], [])
	check(frame.resource_bar == null, "no bar for a pips-only class")
	var pips := frame.resource_display.pips_for(&"holy_power")
	check_eq(pips.count, 3, "Holy Power has three pips")
	check(pips.trough, "the primary pips sit in a trough")
	p.abilities.get_resource(&"holy_power").add(2.0, false)
	check_eq(pips.filled, 2, "two lit")


func test_soul_shards_use_the_shard_shape() -> void:
	_hero([Fakes.resource(&"soul_shard", ResourceData.Display.PIPS, 5.0, Color(0.7, 0.3, 0.95), 1.0)], [])
	var pips := frame.resource_display.pips_for(&"soul_shard")
	check(pips.shard, "Soul Shards are crystals")
	check_eq(pips.filled, 1, "starts with the start value")


func test_too_many_pips_fall_back_to_a_bar() -> void:
	_hero([Fakes.resource(&"big", ResourceData.Display.PIPS, 25.0, Color.WHITE)], [])
	check(frame.resource_bar != null, "25 pips would not fit: a bar instead")
	check_eq(frame.resource_bar.text, "0 / 25", "with the value text")


func test_resource_display_rebinds_cleanly() -> void:
	var p := _hero([Fakes.energy(), Fakes.combo()], [])
	var combo := p.abilities.get_resource(&"combo_points")
	frame.unbind()
	check_eq(frame.resource_display.row_count(), 0, "unbound: no rows")
	check_eq(frame.resource_display.get_child_count(), 0, "unbound: no nodes")
	check(not frame.visible, "unbound frame hides")
	combo.add(2.0, false)
	frame.bind(p)
	check_eq(frame.resource_display.pips_for(&"combo_points").filled, 2, "rebinding reads the current value")
	check_eq(frame.resource_display.get_child_count(), 2, "one node per resource")


func test_class_without_resources_keeps_the_placeholder_bar() -> void:
	var p := _hero([], [])
	check(frame.resource_display.is_placeholder, "placeholder")
	check_eq(frame.resource_bar.text, UiTheme.resource_name(p.class_data.resource_type), "named after the class resource")
	check(frame.resource_bar.fill_color.is_equal_approx(p.class_data.resource_color), "class colour")


func test_freed_player_unbinds_resources_and_abilities() -> void:
	var p := _hero([Fakes.rage()], [Fakes.ability(&"a", &"rage", 10.0, 2.0)])
	world.remove_child(p)
	p.free()
	frame._process(0.016)
	check(not frame.visible, "frame hides")
	check_eq(frame.resource_display.row_count(), 0, "resources dropped")
	check(frame.ability_bar.runner == null, "ability bar unbound")


# --- Ability bar -------------------------------------------------------------------------

func test_ability_bar_shows_the_core_slots_and_reserves_the_learned_ones() -> void:
	var a := Fakes.ability(&"whirlwind", &"rage", 40.0)
	var b := Fakes.ability(&"charge", &"", 0.0, 8.0)
	var p := _hero([Fakes.rage()], [a, b])
	var bar := frame.ability_bar
	check_eq(bar.icons.size(), 4, "four slots")
	check(bar.icons[0].visible and bar.icons[1].visible, "core slots shown")
	check(not bar.icons[2].visible and not bar.icons[3].visible, "learned slots hidden until slotted")
	check(bar.icons[0].ability == a and bar.icons[1].ability == b, "icons show the slot abilities")
	check_eq(bar.icons[0].cost, 40.0, "cost shown")
	check_eq(bar.icons[1].cost, 0.0, "free ability: no cost")
	p.abilities.set_slot(2, Fakes.ability(&"extra", &"", 0.0, 5.0))
	check(bar.icons[2].visible, "a learned ability appears")
	check_eq(bar.icons[2].prompt, "RB", "on RB")
	p.abilities.set_slot(2, null)
	check(not bar.icons[2].visible, "and goes away")


func test_prompts_follow_the_players_device() -> void:
	check_eq(AbilityBar.prompt_text(UiFakes.HumanInput.new("x"), 0), "RT", "pad slot 0")
	check_eq(AbilityBar.prompt_text(UiFakes.HumanInput.new("x"), 1), "LT", "pad slot 1")
	check_eq(AbilityBar.prompt_text(UiFakes.HumanInput.new("x"), 2), "RB", "pad slot 2")
	check_eq(AbilityBar.prompt_text(UiFakes.HumanInput.new("x"), 3), "LB", "pad slot 3")
	check_eq(AbilityBar.prompt_text(ScriptedInput.new(), 0), "RT", "bots read like a pad")
	check_eq(AbilityBar.prompt_text(KeyboardInput.new(), 0), "LMB", "keyboard slot 0 = left mouse button")
	check_eq(AbilityBar.prompt_text(KeyboardInput.new(), 1), "RMB", "keyboard slot 1 = right mouse button")
	check_eq(AbilityBar.prompt_text(KeyboardInput.new(), 2), "E", "keyboard slot 2 = E")
	check_eq(AbilityBar.prompt_text(KeyboardInput.new(), 3), "Q", "keyboard slot 3 = Q")
	check_eq(AbilityBar.prompt_text(KeyboardInput.new(), 7), "", "no such slot")


func test_bound_icons_carry_the_prompts_of_their_device() -> void:
	var abilities: Array[AbilityData] = [Fakes.ability(&"a"), Fakes.ability(&"b")]
	_hero([], abilities, UiFakes.HumanInput.new("pad:7"))
	check_eq(frame.ability_bar.icons[0].prompt, "RT", "controller RT")
	check_eq(frame.ability_bar.icons[1].prompt, "LT", "controller LT")
	check(not frame.ability_bar.icons[0].prompt_keyboard, "drawn as a pill")
	frame.unbind()
	var kb_frame := UnitFrame.create(1, true)
	tree.root.add_child(kb_frame)
	nodes.append(kb_frame)
	var kb := Fakes.hero(world, KeyboardInput.new(), [], abilities, &"warrior", 1)
	kb_frame.bind(kb)
	check_eq(kb_frame.ability_bar.icons[0].prompt, "LMB", "keyboard LMB")
	check_eq(kb_frame.ability_bar.icons[1].prompt, "RMB", "keyboard RMB")
	check(kb_frame.ability_bar.icons[0].prompt_keyboard, "drawn as a key cap")
	check_eq(kb_frame.ability_bar.alignment, BoxContainer.ALIGNMENT_END, "right-hand frames are mirrored")


func test_cooldown_sweep_ratio_and_seconds() -> void:
	var p := _hero([], [Fakes.ability(&"charge", &"", 0.0, 4.0)])
	var icon := frame.ability_bar.icons[0]
	frame.ability_bar.refresh()
	check_eq(icon.sweep_ratio, 0.0, "no sweep while ready")
	check_eq(icon.cooldown_text(), "", "no number while ready")
	check(icon.usable, "ready")
	check(p.abilities.try_cast(0), "cast")
	check_eq(icon.sweep_ratio, 1.0, "a cast starts the full sweep")
	check_eq(icon.cooldown_text(), "4", "4 s left")
	check(not icon.usable, "not usable on cooldown")
	check(not icon.is_dimmed(), "a cooldown is not the dim state")
	Fakes.step_physics(p, 2.0)
	frame.ability_bar.refresh()
	check_near(icon.sweep_ratio, 0.5, 0.02, "half way")
	check(icon.cooldown_text() in ["2.0", "2.1", "1.9"], "2 s left, one decimal: %s" % icon.cooldown_text())
	Fakes.step_physics(p, 1.2)
	frame.ability_bar.refresh()
	check_near(icon.sweep_ratio, 0.2, 0.02, "a fifth to go")
	check_eq(icon.cooldown_text(), "0.8", "under 3 s one decimal")
	Fakes.step_physics(p, 1.0)
	frame.ability_bar.refresh()
	check_eq(icon.sweep_ratio, 0.0, "done")
	check_eq(icon.cooldown_text(), "", "number gone")
	check(icon.usable, "usable again")


func test_cooldown_sweep_follows_cooldown_reduction() -> void:
	var p := _hero([], [Fakes.ability(&"charge", &"", 0.0, 10.0)])
	p.stats.set_source(&"t", {Stats.COOLDOWN_REDUCTION: 50.0})
	p.abilities.try_cast(0)
	frame.ability_bar.refresh()
	var icon := frame.ability_bar.icons[0]
	check_eq(icon.sweep_ratio, 1.0, "full sweep of the shortened cooldown")
	check_eq(icon.cooldown_text(), "5", "5 s with 50% cooldown reduction")


func test_unaffordable_abilities_are_dimmed() -> void:
	var p := _hero([Fakes.rage()], [Fakes.ability(&"whirlwind", &"rage", 40.0, 1.0)])
	var icon := frame.ability_bar.icons[0]
	var rage := p.abilities.get_resource(&"rage")
	frame.ability_bar.refresh()
	check(icon.is_dimmed(), "no Rage: dimmed")
	check(not icon.usable, "not usable")
	rage.set_value(39.0)
	frame.ability_bar.refresh()
	check(icon.is_dimmed(), "39 / 40: still dimmed")
	rage.set_value(40.0)
	frame.ability_bar.refresh()
	check(not icon.is_dimmed(), "40 / 40: lit")
	check(icon.usable, "usable")
	p.abilities.try_cast(0)
	check(not icon.is_dimmed(), "paid and on cooldown: shows the sweep, not the dim")
	check_eq(icon.cooldown_text(), "1.0", "cooldown number")
	Fakes.step_physics(p, 1.1)
	frame.ability_bar.refresh()
	check(icon.is_dimmed(), "cooldown over but Rage spent: dimmed again")


func test_downed_player_dims_every_ability() -> void:
	var p := _hero([], [Fakes.ability(&"a"), Fakes.ability(&"b")])
	frame.ability_bar.refresh()
	check(not frame.ability_bar.icons[0].is_dimmed(), "alive: lit")
	p.take_damage(1000.0)
	check(p.downed, "downed")
	frame.ability_bar.refresh()
	check(frame.ability_bar.icons[0].is_dimmed() and frame.ability_bar.icons[1].is_dimmed(), "downed: both dimmed")
	p.revive(0.5)
	frame.ability_bar.refresh()
	check(not frame.ability_bar.icons[0].is_dimmed(), "revived: lit again")


func test_cast_flashes_the_icon_and_the_flash_fades() -> void:
	var p := _hero([], [Fakes.ability(&"a", &"", 0.0, 1.0), Fakes.ability(&"b", &"", 0.0, 1.0)])
	var icons := frame.ability_bar.icons
	check_eq(icons[1].flash, 0.0, "no flash yet")
	check(p.abilities.try_cast(1), "cast LT")
	check_eq(icons[1].flash, 1.0, "the cast icon flashes")
	check_eq(icons[0].flash, 0.0, "the other one does not")
	icons[1]._process(AbilityIcon.FLASH_TIME * 0.5)
	check_near(icons[1].flash, 0.5, 0.01, "fading")
	check(icons[1].scale.x > 1.0, "popped")
	icons[1]._process(AbilityIcon.FLASH_TIME)
	check_eq(icons[1].flash, 0.0, "gone")
	check_eq(icons[1].scale, Vector2.ONE, "scale back to normal")


func test_costs_follow_item_mods() -> void:
	var p := _hero([Fakes.rage()], [Fakes.ability(&"whirlwind", &"rage", 40.0)])
	var icon := frame.ability_bar.icons[0]
	check_eq(icon.cost, 40.0, "base cost")
	var item := ItemInstance.new()
	item.slot_type = Items.SlotType.HEAD
	item.armor_type = Items.NO_ARMOR
	item.unique_effect = &"ability_mod"
	item.unique_params = {"ability": "whirlwind", "mods": {"cost_add": -10.0}}
	check(p.equipment.equip(item), "equip the mod item")
	frame.ability_bar.refresh(true)
	check_eq(icon.cost, 30.0, "the corner cost reads the modded cost")
	check_eq(frame.ability_bar.description_for(0), "", "no description text on the fake")


func test_description_uses_the_modded_params() -> void:
	var a := Fakes.ability(&"fan_of_knives")
	a.description = "Throws {knives} knives for {damage_pct}% in {radius} m. {unknown}"
	a.params = {"knives": 8, "damage_pct": 60.0, "radius": 2.5}
	var p := _hero([], [a])
	check_eq(frame.ability_bar.description_for(0), "Throws 8 knives for 60% in 2.5 m. {unknown}", "floats lose the .0, unknown placeholders stay")
	var item := ItemInstance.new()
	item.slot_type = Items.SlotType.HEAD
	item.armor_type = Items.NO_ARMOR
	item.unique_effect = &"ability_mod"
	item.unique_params = {"ability": "fan_of_knives", "mods": {"knives_add": 2.0, "damage_pct_pct": 50.0}}
	p.equipment.equip(item)
	check_eq(frame.ability_bar.description_for(0), "Throws 10 knives for 90% in 2.5 m. {unknown}", "item mods are applied")
	check_eq(frame.ability_bar.description_for(3), "", "empty slot")


func test_frame_stays_compact() -> void:
	_hero([Fakes.energy(), Fakes.combo()], [Fakes.ability(&"a"), Fakes.ability(&"b")])
	frame.reset_size()
	check(frame.custom_minimum_size.x <= 345.0, "~340 px wide")
	check(frame.get_combined_minimum_size().y <= 190.0, "no taller than ~190 px even with pips (%s)" % frame.get_combined_minimum_size().y)
	check(AbilityIcon.COOLDOWN_FONT >= 18 and AbilityIcon.PROMPT_FONT >= 18 and AbilityIcon.COST_FONT >= 18, "icon texts >= 18 px")


func test_charges_are_shown_when_the_effect_publishes_them() -> void:
	var blink := Fakes.ability(&"blink", &"", 0.0, 6.0)
	blink.effect = Fakes.ChargeEffect
	var p := _hero([], [blink, Fakes.ability(&"b")])
	var icon := frame.ability_bar.icons[0]
	frame.ability_bar.refresh()
	check_eq(icon.charges_max, 2, "two charges possible")
	check_eq(icon.charges, 1, "one left")
	var effect := p.abilities.effect_for(blink) as Fakes.ChargeEffect
	effect.available = 0
	frame.ability_bar.refresh()
	check_eq(icon.charges, 0, "none left")
	check_eq(frame.ability_bar.icons[1].charges_max, 0, "abilities without charges show no counter")
	effect.maximum = 1
	frame.ability_bar.refresh()
	check_eq(icon.charges_max, 1, "a single charge hides the counter (charges_max <= 1)")


func test_resource_rows_do_not_leak_the_class_resource() -> void:
	# A frame freed without unbind() (the whole HUD is torn down) must not keep the
	# ClassResource / ResourceData alive through the changed-signal connection.
	var data := Fakes.rage()
	var res := ClassResource.new(data)
	var runner := AbilityRunner.new()
	runner.resources[&"rage"] = res
	runner.resource_order.append(&"rage")
	var res_refs := res.get_reference_count()
	var data_refs := data.get_reference_count()
	var display := ResourceDisplay.create()
	display.bind(runner, null)
	check_eq(display.row_count(), 1, "bound")
	display.free()
	check_eq(res.get_reference_count(), res_refs, "ClassResource is released again")
	check_eq(data.get_reference_count(), data_refs, "ResourceData is released again")
	check_eq(res.changed.get_connections().size(), 0, "no connection left on the signal")
	res.set_value(10.0)
	runner.free()
