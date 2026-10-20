extends TestCase
## M4 HUD (GDD 6.2, 12): the unit frame's AbilityBar shows the learned Active slots (RB / LB with
## prompts) and the 2 x 2 auto-cast cluster (small icons, gear mark, sweep, no prompt), the rank
## on every icon (pips, a corner numeral on the small ones), and every class's frame stays within
## UnitFrame.MAX_HEIGHT / MAX_WIDTH with all eight slots filled. Plus the glyph rule (every
## shipped ability id has its own glyph) and the icon redraw cost (sweep step, glyph layer).

const Fakes := preload("res://tests/test_ui_m3_fakes.gd")
const UiFakes := preload("res://tests/ui_fakes.gd")

## The M4 ability pool of GDD 6.4 (ids = icon ids).
const M4_IDS: Array[StringName] = [
	&"thunder_clap", &"heroic_leap", &"execute", &"battle_shout", &"shield_wall", &"bladestorm",
	&"fireball", &"frost_nova", &"arcane_missiles", &"ice_barrier", &"pyroblast", &"meteor",
	&"hammer_of_justice", &"avengers_shield", &"divine_storm", &"blessing_of_kings", &"divine_shield", &"lay_on_hands",
	&"shuriken_toss", &"blade_flurry", &"poison_bomb", &"cheat_death", &"shadowstep", &"killing_spree",
	&"corruption", &"shadow_bolt", &"seed_of_corruption", &"summon_voidwalker", &"fear", &"summon_infernal",
	&"bandage", &"sprint", &"engineers_bomb", &"war_stomp", &"spirit_wolf", &"berserking",
]
const CORE_IDS: Array[StringName] = [
	&"whirlwind", &"charge", &"blizzard", &"blink", &"consecration", &"word_of_glory",
	&"fan_of_knives", &"vanish", &"rain_of_fire", &"drain_life",
]

var world: Node3D
var nodes: Array[Node] = []
var _async := false


func is_async() -> bool:
	return _async


func before_each() -> void:
	UiFakes.reset_players()
	RunState.start_run(1, 5)
	world = Node3D.new()
	world.name = "TrainerHudWorld"
	tree.root.add_child(world)
	tree.current_scene = world


func after_each() -> void:
	for n in nodes:
		UiFakes.free_node(n)
	nodes.clear()
	UiFakes.free_node(world)
	world = null
	UiFakes.reset_players()


static func learned(id: StringName, kind: AbilityData.Kind, cooldown: float = 6.0) -> AbilityData:
	var a := Fakes.ability(id, &"", 0.0, cooldown)
	a.kind = kind
	a.specs = [{"name": "A", "text": "a", "mods": {}}, {"name": "B", "text": "b", "mods": {}}]
	return a


func _frame(index: int = 0, mirrored: bool = false) -> UnitFrame:
	var f := UnitFrame.create(index, mirrored)
	tree.root.add_child(f)
	nodes.append(f)
	return f


## A hero of [param class_id] (its real class abilities and resources) with [param actives]
## learned Active and [param autos] learned Auto-cast abilities.
func _hero(class_id: StringName, actives: int, autos: int, index: int = 0, input: PlayerInput = null) -> Player:
	var slot := PlayerSlot.new(index, input if input != null else UiFakes.HumanInput.new("pad:%d" % index), PlayerManager.PLAYER_COLORS[index])
	slot.class_data = Db.get_class_data(class_id)
	var p := Player.create(slot)
	world.add_child(p)
	for i in actives:
		p.abilities.learn(learned(StringName("active_%d" % i), AbilityData.Kind.ACTIVE))
	for i in autos:
		p.abilities.learn(learned(StringName("auto_%d" % i), AbilityData.Kind.AUTO))
	return p


func _sort(node: Node) -> void:
	if node is Container:
		(node as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
	for c in node.get_children():
		_sort(c)


# --- Learned slots on the frame ---------------------------------------------------------------

func test_learned_active_and_auto_cast_icons_show_up() -> void:
	var frame := _frame()
	var p := _hero(&"mage", 1, 2)
	frame.bind(p)
	var bar := frame.ability_bar
	check_eq(bar.icons.size(), 8, "eight slots")
	check(bar.icons[2].visible and bar.icons[2].ability != null, "the learned Active ability on RB")
	check_eq(bar.icons[2].prompt, "RB", "with the RB prompt")
	check(not bar.icons[3].visible, "LB still empty: hidden")
	check(bar.auto_cluster.visible, "the auto-cast cluster appears")
	check(bar.auto_mark.visible, "with the gear mark")
	check(bar.icons[4].ability != null and bar.icons[5].ability != null, "two auto-cast abilities")
	check(bar.icons[6].is_empty() and bar.icons[7].is_empty(), "the free auto-cast slots are empty sockets")
	for i in range(4, 8):
		var icon := bar.icons[i]
		check_eq(icon.prompt, "", "auto-cast %d: no button prompt" % i)
		check(not icon.show_cooldown_text, "auto-cast %d: the sweep only" % i)
		check_eq(icon.icon_side(), AbilityBar.AUTO_ICON_SIZE, "auto-cast %d: small" % i)
		check(AbilityBar.AUTO_ICON_SIZE >= 26.0 and AbilityBar.AUTO_ICON_SIZE <= 30.0, "26–30 px")
		check_eq(icon.get_combined_minimum_size().y, AbilityBar.AUTO_ICON_SIZE, "no prompt row below it")
		check(icon.get_parent() == bar.auto_grid, "in the 2 x 2 grid")
	p.abilities.forget(4)
	p.abilities.forget(5)
	check(not bar.auto_cluster.visible, "no auto-cast ability left: the cluster hides")


func test_auto_cast_icons_sweep_with_the_cooldown() -> void:
	var frame := _frame()
	var p := _hero(&"warrior", 0, 1)
	frame.bind(p)
	var icon := frame.ability_bar.icons[4]
	frame.ability_bar.refresh()
	check_eq(icon.sweep_ratio, 0.0, "ready")
	check(p.abilities.try_cast(4), "the auto-cast ability fires")
	check_eq(icon.flash, 1.0, "cast flash")
	check_eq(icon.sweep_ratio, 1.0, "full sweep")
	Fakes.step_physics(p, 3.0)
	frame.ability_bar.refresh()
	check_near(icon.sweep_ratio, 0.5, 0.03, "half way through 6 s")
	check(icon.cooldown_text() != "", "the seconds are known (just not drawn on the small icon)")


func test_rank_pips_follow_ranks_and_specs() -> void:
	var frame := _frame()
	var p := _hero(&"rogue", 1, 1)
	frame.bind(p)
	var bar := frame.ability_bar
	for i: int in [0, 1, 2, 4]:
		check_eq(bar.icons[i].rank, 1, "slot %d: Rank I pip" % i)
	var active := p.abilities.slots[2]
	p.abilities.rank_up(active.id)
	check_eq(bar.icons[2].rank, 2, "Rank II after a rank-up (ranks_changed)")
	p.abilities.rank_up(p.abilities.slots[0].id)
	check_eq(bar.icons[0].rank, 2, "core abilities rank up too")
	for k in 3:
		p.abilities.rank_up(active.id)
	check_eq(bar.icons[2].rank, 5, "Rank V")
	check(not bar.icons[2].rank_spec, "no specialisation yet")
	p.abilities.set_spec(active.id, 1)
	check(bar.icons[2].rank_spec, "specialised: orange pips")
	var pips := AbilityIcon.rank_pip_centers(42.0, 5, true)
	check_eq(pips.size(), 5, "five pips")
	for c in pips:
		check(c.y - AbilityIcon.rank_pip_size(42.0) >= 0.0 and c.y + AbilityIcon.rank_pip_size(42.0) <= 42.0 - AbilityIcon.PROMPT_OVERHANG,
			"pip %s stays inside the icon, above the prompt pill" % c)
	check(not bar.icons[2].uses_rank_badge(), "button icons: pips")
	check(bar.icons[4].uses_rank_badge(), "the small auto-cast icons show a numeral instead")
	frame.unbind()
	check_eq(bar.icons[2].rank, 0, "unbound: no pips")
	check_eq(AbilityIcon.roman(4), "IV", "roman numerals")
	check_eq(AbilityIcon.roman(0), "", "none for 0")


func test_auto_cluster_sits_on_the_inner_side() -> void:
	var left := _frame(0, false)
	var right := _frame(1, true)
	left.bind(_hero(&"paladin", 2, 4, 0))
	right.bind(_hero(&"warlock", 2, 4, 1))
	for f: UnitFrame in [left, right]:
		f.size = f.get_combined_minimum_size()
		_sort(f)
		var buttons := f.ability_bar.buttons.get_global_rect()
		var autos := f.ability_bar.auto_grid.get_global_rect()
		var bars := f.hp_bar.get_global_rect()
		if f.mirrored:
			check(autos.end.x <= buttons.position.x + 0.5, "mirrored: auto-cast left of the buttons")
			check(buttons.end.x <= bars.position.x + 0.5, "buttons left of the bars")
		else:
			check(autos.position.x >= buttons.end.x - 0.5, "auto-cast right of the buttons")
			check(buttons.position.x >= bars.end.x - 0.5, "buttons right of the bars")
		check(autos.size.y <= f.ability_bar.icons[0].get_combined_minimum_size().y + 2.0, "the 2 x 2 cluster is as tall as a button icon with its prompt (%s)" % autos.size.y)


func test_every_class_frame_with_all_slots_fits_the_limits() -> void:
	# Learned abilities make the frame wider, never taller (CameraRig keeps the heroes out of
	# fixed bands under the frames).
	var frame := _frame(0, false)
	var right := _frame(3, true)
	var keyboard := KeyboardInput.new()
	for class_id in Db.class_ids:
		for input: PlayerInput in [UiFakes.HumanInput.new("pad:%s" % class_id), keyboard]:
			var p := _hero(class_id, 2, 4, 0, input)
			var heights: Array[float] = []
			for f: UnitFrame in [frame, right]:
				f.bind(p)
				var s := f.get_combined_minimum_size()
				heights.append(s.y)
				check(s.y <= UnitFrame.MAX_HEIGHT, "%s P%d all slots: %s px tall" % [class_id, f.index + 1, s.y])
				check(s.x <= UnitFrame.MAX_WIDTH, "%s P%d all slots: %s px wide" % [class_id, f.index + 1, s.x])
				check(f.ability_bar.auto_cluster.visible, "%s: auto-cast cluster shown" % class_id)
			p.take_damage(1.0e6)
			for f: UnitFrame in [frame, right]:
				f.bind(p)
				check(f.is_downed_shown(), "%s downed" % class_id)
				check_eq(f.get_combined_minimum_size().y, heights[0], "%s P%d: going down keeps the height" % [class_id, f.index + 1])
				f.unbind()
			world.remove_child(p)
			p.free()
	# Learning abilities does not change the height either.
	var bare := _hero(&"warrior", 0, 0)
	frame.bind(bare)
	var h0 := frame.get_combined_minimum_size().y
	bare.abilities.learn(learned(&"x1", AbilityData.Kind.AUTO))
	bare.abilities.learn(learned(&"x2", AbilityData.Kind.ACTIVE))
	check_eq(frame.get_combined_minimum_size().y, h0, "learning keeps the frame height")


func test_full_hud_keeps_the_top_plaque_free() -> void:
	_async = true
	var canvas := Control.new()
	canvas.size = Vector2(1920, 1080)
	tree.root.add_child(canvas)
	nodes.append(canvas)
	var hud := Hud.create()
	canvas.add_child(hud)
	var heroes: Array[Player] = []
	var classes: Array[StringName] = [&"warrior", &"mage", &"paladin", &"warlock"]
	for i in classes.size():
		var input: PlayerInput = KeyboardInput.new() if i == 1 else UiFakes.HumanInput.new("pad:%d" % i)
		heroes.append(_hero(classes[i], 2, 4, i, input))
	hud.bind_players(heroes)
	await tree.process_frame
	await tree.process_frame
	var plaque := hud.wave_label.get_parent().get_parent() as Control
	var plaque_rect := plaque.get_global_rect()
	var rects: Array[Rect2] = []
	for f in hud.frames:
		var r := f.get_global_rect()
		rects.append(r)
		check(r.size.y <= UnitFrame.MAX_HEIGHT, "%s: %s px tall" % [f.name, r.size.y])
		check(not r.intersects(plaque_rect), "%s %s clear of the wave plaque %s" % [f.name, r, plaque_rect])
		check(r.position.x >= 0.0 and r.end.x <= 1920.0, "%s on screen" % f.name)
	check(not rects[0].intersects(rects[1]) and not rects[2].intersects(rects[3]), "frames on one edge do not touch")
	finished.emit()


# --- Glyphs -------------------------------------------------------------------------------------

func test_every_learnable_ability_id_has_its_own_glyph() -> void:
	var seen: Dictionary[int, StringName] = {}
	var all: Array[StringName] = []
	var learnable := 0
	for id in Db.abilities:
		all.append(id)
		if Db.abilities[id].is_learned_kind():
			learnable += 1
	# GDD 6.4: six learnable abilities per class and six general ones.
	check_eq(learnable, 6 * Db.class_ids.size() + 6, "6 learnable abilities per class + 6 general")
	for id in M4_IDS:
		check(Db.abilities.has(id), "the launch ability %s is still there" % id)
	for id in CORE_IDS:
		check(Db.abilities.has(id), "the launch core ability %s is still there" % id)
	for id in all:
		var g := AbilityIcon.glyph_for(id, &"physical", id)
		check(g != AbilityIcon.Glyph.GENERIC, "%s has a real glyph" % id)
		check(AbilityIcon.EXACT_GLYPHS.has(id), "%s is in the exact table" % id)
		check(not seen.has(g), "%s shares its glyph with %s" % [id, seen.get(g, &"")])
		seen[g] = id
	# The display names reach the same glyph (normalised).
	check_eq(AbilityIcon.glyph_for(&"Avenger's Shield"), AbilityIcon.Glyph.AVENGERS_SHIELD, "apostrophes are dropped")
	check_eq(AbilityIcon.glyph_for(&"Engineer's Bomb"), AbilityIcon.Glyph.BOMB, "Engineer's Bomb")


func test_every_shipped_ability_has_a_distinct_glyph() -> void:
	# Whatever .tres files are in data/abilities: no fallback rune, no two sharing a glyph.
	var seen: Dictionary[int, StringName] = {}
	for id: StringName in Db.abilities:
		var a: AbilityData = Db.abilities[id]
		var g := AbilityIcon.glyph_for_ability(a)
		check(g != AbilityIcon.Glyph.GENERIC, "%s (icon %s) has a real glyph" % [id, a.icon])
		check(not seen.has(g), "%s shares its glyph with %s" % [id, seen.get(g, &"")])
		seen[g] = id


func test_new_glyphs_draw() -> void:
	# Drawn for real at every size (a broken polygon would log an error).
	_async = true
	var box := HBoxContainer.new()
	tree.root.add_child(box)
	nodes.append(box)
	var count := 0
	for g in AbilityIcon.Glyph.values():
		if g < AbilityIcon.Glyph.THUNDER_CLAP:
			continue
		for side: float in [26.0, 42.0, 64.0]:
			var icon := AbilityIcon.create(side, side != 26.0)
			icon.set_ability(Fakes.ability(&"x"))
			icon.glyph = g
			icon.set_rank(1 + count % 5, count % 2 == 0)
			icon.set_state(0.4, 2.0, false)
			box.add_child(icon)
			icon.queue_redraw()
			count += 1
	# Every glyph from THUNDER_CLAP on is a "new" one (34 of the M4 pool, plus each M8 class's own).
	check_eq(count, (AbilityIcon.Glyph.size() - AbilityIcon.Glyph.THUNDER_CLAP) * 3, "every new glyph at three sizes")
	check(count >= 34 * 3, "at least the 34 of the M4 pool")
	await tree.process_frame
	await tree.process_frame
	finished.emit()


# --- Redraw cost and the small rank badge ------------------------------------------------------

## Runs a [param seconds] cooldown on [param icon] at 60 Hz (one set_state per frame, like
## AbilityBar) and returns the sweep ratios of the overlay draws.
func _run_cooldown(icon: AbilityIcon, seconds: float) -> Array[float]:
	var drawn: Array[float] = []
	icon.draw.connect(func() -> void: drawn.append(icon.sweep_ratio))
	var left := seconds
	while left > 0.0:
		icon.set_state(left / seconds, left, false)
		await tree.process_frame
		left -= 1.0 / 60.0
	icon.set_state(0.0, 0.0, true)
	await tree.process_frame
	return drawn


func test_small_icons_redraw_once_per_pixel_of_sweep_and_keep_the_glyph() -> void:
	# Regression: every icon redrew on each 0.004-turn sweep step (~0.3 px on a 26 px icon) and
	# whenever the hidden seconds changed, re-recording the whole two-pass glyph each time.
	_async = true
	var small := AbilityIcon.create(AbilityBar.AUTO_ICON_SIZE, false)
	small.show_prompt = false
	small.show_cooldown_text = false
	small.set_ability(learned(&"auto", AbilityData.Kind.AUTO))
	var big := AbilityIcon.create(AbilityIcon.SIZE)
	big.set_ability(learned(&"button", AbilityData.Kind.ACTIVE))
	for icon in [small, big]:
		tree.root.add_child(icon)
		nodes.append(icon)
	await tree.process_frame
	var glyph_draws: Array[int] = [0]
	small._glyph_layer.draw.connect(func() -> void: glyph_draws[0] += 1)
	var drawn := await _run_cooldown(small, 6.0)
	var step := 1.0 / (4.0 * AbilityBar.AUTO_ICON_SIZE)
	check(drawn.size() <= ceili(1.0 / step) + 4, "about one redraw per pixel of sweep edge (%d draws)" % drawn.size())
	check(drawn.size() >= floori(0.8 / step), "but still a smooth sweep (%d draws)" % drawn.size())
	var worst := 0.0
	for i in range(1, drawn.size()):
		worst = maxf(worst, absf(drawn[i] - drawn[i - 1]))
	check(worst <= step * 1.6, "no visible jump (worst %s)" % worst)
	check_eq(drawn.back(), 0.0, "ends empty")
	check_eq(glyph_draws[0], 0, "the glyph layer is not re-recorded by the sweep")
	small.set_ability(learned(&"other", AbilityData.Kind.AUTO))
	await tree.process_frame
	check_eq(glyph_draws[0], 1, "a new ability redraws the glyph")
	# The big icon with its seconds keeps the fine step (and redraws on every new second).
	var big_drawn := await _run_cooldown(big, 6.0)
	check(big_drawn.size() >= 150, "big icon: fine steps (%d draws)" % big_drawn.size())
	finished.emit()


func test_sweep_ending_without_a_state_flip_is_drawn_empty() -> void:
	# A recharging second charge: the slot stays ready (no seconds, no ready flip) while the sweep
	# runs out – the last step to 0 must still be drawn, or a sliver and the veil would stay.
	_async = true
	var icon := AbilityIcon.create(AbilityBar.AUTO_ICON_SIZE, false)
	icon.show_cooldown_text = false
	icon.set_ability(learned(&"charges", AbilityData.Kind.AUTO))
	tree.root.add_child(icon)
	nodes.append(icon)
	var drawn: Array[float] = []
	icon.draw.connect(func() -> void: drawn.append(icon.sweep_ratio))
	icon.set_state(0.5, 0.0, true)
	await tree.process_frame
	var sliver := icon.sweep_redraw_step() * 0.7
	icon.set_state(sliver, 0.0, true)
	await tree.process_frame
	check_eq(drawn.back(), sliver, "a last sliver (with the veil) is drawn")
	icon.set_state(0.0, 0.0, true)
	await tree.process_frame
	check_eq(drawn.back(), 0.0, "the step to empty is drawn although it is below the redraw step")
	finished.emit()


func test_small_icons_show_the_rank_as_a_numeral() -> void:
	# Five 2 px pips cannot be counted on a 26 px icon at 1280 x 720: small icons draw the roman
	# numeral (orange once specialised) in the bottom-left corner instead – small, outlined, on a
	# see-through plate sitting on the rim, so it hides as little of the glyph (the only thing
	# that tells the auto-cast abilities apart) as it can.
	_async = true
	var sq := AbilityBar.AUTO_ICON_SIZE
	var small := AbilityIcon.create(sq, false)
	var button := AbilityIcon.create(42.0)
	check(small.uses_rank_badge(), "below SMALL_ICON: the numeral")
	check(not button.uses_rank_badge(), "button icons keep the pips")
	check(AbilityIcon.RANK_BADGE_FONT < AbilityIcon.SMALL_FONT, "a smaller numeral than the other corner texts")
	var half := sq * 0.5 * AbilityIcon.GLYPH_SCALE
	var glyph_box := Rect2(Vector2.ONE * (sq * 0.5 - half), Vector2.ONE * half * 2.0)
	for r in range(1, AbilityIcon.MAX_RANK + 1):
		var plate := AbilityIcon.rank_badge_rect(AbilityIcon.rank_badge_origin(sq, false), AbilityIcon.roman(r))
		check(plate.position.x >= 0.0 and plate.end.y <= sq, "Rank %d: the plate %s stays on the icon" % [r, plate])
		check(plate.position.x <= 2.0 and plate.end.y >= sq - 2.0, "Rank %d: and sits on the rim in the corner (%s)" % [r, plate])
		# The plate backs the whole outlined numeral (real ink: cap height + outline reach).
		check(plate.get_area() <= 0.22 * sq * sq, "Rank %d: the plate covers %s px², about a fifth of the icon at most" % [r, plate.get_area()])
		var hidden := plate.intersection(glyph_box).get_area() / glyph_box.get_area()
		check(hidden <= 0.3, "Rank %d: it hides %d%% of the glyph's box" % [r, roundi(hidden * 100.0)])
		check(plate.position.y >= sq * 0.5, "Rank %d: in the bottom half, clear of the top corner texts (%s)" % [r, plate])
	var above := AbilityIcon.rank_badge_rect(AbilityIcon.rank_badge_origin(sq, true), "III")
	check(above.end.y <= sq - AbilityIcon.PROMPT_OVERHANG, "above a prompt pill (%s)" % above)
	# The Trainer rows show the rank in their own column: no corner numeral on their 32 px icons.
	var row := TrainerRow.create(4)
	row.show_ability(learned(&"row", AbilityData.Kind.AUTO), 3, 50, true, false, false)
	check_eq(row.rank_label.text, "III", "the row's rank column")
	check_eq(row.icon.rank, 0, "the row's icon draws no rank of its own")
	row.free()
	# Drawn for real at every rank, specialised or not.
	var box := HBoxContainer.new()
	tree.root.add_child(box)
	nodes.append(box)
	for r in range(1, AbilityIcon.MAX_RANK + 1):
		for spec: bool in [false, true]:
			var icon := AbilityIcon.create(sq, false)
			icon.set_ability(learned(StringName("r%d" % r), AbilityData.Kind.AUTO))
			icon.set_rank(r, spec)
			icon.set_charges(1, 2)
			icon.set_state(0.5, 2.0, false)
			box.add_child(icon)
	for icon: AbilityIcon in [small, button]:
		icon.free()
	await tree.process_frame
	await tree.process_frame
	finished.emit()
