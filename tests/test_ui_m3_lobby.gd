extends TestCase
## Lobby card (M3): the class's two core abilities with icons / names / this device's buttons,
## and the Mastery line.

const Fakes := preload("res://tests/test_ui_m3_fakes.gd")
const UiFakes := preload("res://tests/ui_fakes.gd")

var lobby: Lobby


func before_each() -> void:
	UiFakes.reset_players()
	lobby = Lobby.create()
	UiFakes.add_to_root(tree, lobby)


func after_each() -> void:
	UiFakes.free_node(lobby)
	lobby = null
	UiFakes.reset_players()


func _class(abilities: Array[AbilityData], mastery_text: String) -> ClassData:
	var c := ClassData.new()
	c.id = &"test_class"
	c.display_name = "Tester"
	c.role = "Test role"
	c.description = "A test class."
	c.abilities = abilities
	c.mastery_text = mastery_text
	return c


func _join(input: PlayerInput, data: ClassData) -> LobbyCard:
	var slot := PlayerManager.join(input, data)
	UiFakes.step(lobby)
	return lobby.cards[slot.index]


func test_card_shows_both_abilities_with_names_and_icons() -> void:
	var a := Fakes.ability(&"whirlwind", &"rage", 40.0)
	a.display_name = "Whirlwind"
	var b := Fakes.ability(&"charge", &"", 0.0, 8.0)
	b.display_name = "Charge"
	var card := _join(UiFakes.HumanInput.new("pad:a"), _class([a, b], "Battle Fury: more damage the lower your health."))
	check_eq(card.ability_icons.size(), 2, "two core abilities")
	check_eq(card.ability_name_labels[0].text, "Whirlwind", "first name")
	check_eq(card.ability_name_labels[1].text, "Charge", "second name")
	check(card.ability_icons[0].ability == a and card.ability_icons[1].ability == b, "icons show the abilities")
	check_eq(card.ability_icons[0].glyph, AbilityIcon.Glyph.WHIRLWIND, "procedural glyph")
	check_eq(card.ability_icons[0].cost, 40.0, "cost shown")
	check(card.ability_icons[0].is_visible_in_tree(), "visible in the card")
	check(not card.ability_icons[0].is_dimmed() and card.ability_icons[0].sweep_ratio == 0.0, "no cooldown state in the lobby")


func test_card_prompts_follow_the_device() -> void:
	var abilities: Array[AbilityData] = [Fakes.ability(&"a"), Fakes.ability(&"b")]
	var data := _class(abilities, "Fury: text")
	var pad_card := _join(UiFakes.HumanInput.new("pad:a"), data)
	check_eq(pad_card.ability_icons[0].prompt, "RT", "controller: RT")
	check_eq(pad_card.ability_icons[1].prompt, "LT", "controller: LT")
	var kb_card := _join(KeyboardInput.new(), data)
	check_eq(kb_card.ability_icons[0].prompt, "LMB", "keyboard: LMB")
	check_eq(kb_card.ability_icons[1].prompt, "RMB", "keyboard: RMB")
	check(kb_card.ability_icons[0].prompt_keyboard and not pad_card.ability_icons[0].prompt_keyboard, "key cap vs pill")


func test_mastery_line_comes_from_class_data() -> void:
	var abilities: Array[AbilityData] = [Fakes.ability(&"a"), Fakes.ability(&"b")]
	var card := _join(UiFakes.HumanInput.new("pad:a"), _class(abilities, "Battle Fury: the lower your health, the harder you hit."))
	check(card.mastery_title_label.visible and card.mastery_label.visible, "Mastery shown")
	check_eq(card.mastery_title_label.text, "Mastery: Battle Fury", "title with the Mastery name")
	check_eq(card.mastery_label.text, "the lower your health, the harder you hit.", "the rest of mastery_text")
	var plain := _join(UiFakes.HumanInput.new("pad:b"), _class(abilities, "Hits harder when hurt."))
	check_eq(plain.mastery_title_label.text, "Mastery", "no name in the text")
	check_eq(plain.mastery_label.text, "Hits harder when hurt.", "whole text")


func test_mastery_parts() -> void:
	check_eq(LobbyCard.mastery_parts("Ignite: crits burn."), ["Ignite", "crits burn."], "name: text")
	check_eq(LobbyCard.mastery_parts("  Aura of Devotion: allies gain Armor: 5.  "), ["Aura of Devotion", "allies gain Armor: 5."], "first colon only")
	check_eq(LobbyCard.mastery_parts("Allies nearby gain bonuses and then something: else"), ["", "Allies nearby gain bonuses and then something: else"], "a long lead-in is not a name")
	check_eq(LobbyCard.mastery_parts(""), ["", ""], "empty")


func test_class_without_m3_data_hides_the_block() -> void:
	var card := _join(UiFakes.HumanInput.new("pad:a"), _class([] as Array[AbilityData], ""))
	check(not card._abilities_panel.visible, "nothing to show: no panel")
	check_eq(card.ability_icons.size(), 0, "no icons")


func test_changing_class_swaps_the_abilities() -> void:
	var input := UiFakes.HumanInput.new("pad:a")
	var slot := PlayerManager.join(input, Db.get_class_data(&"warrior"))
	UiFakes.step(lobby)
	var card := lobby.cards[0]
	var warrior_names: Array[String] = []
	for l in card.ability_name_labels:
		warrior_names.append(l.text)
	UiFakes.nudge(lobby, input, Vector2.RIGHT)
	check(slot.class_data.id != &"warrior", "class changed")
	var other: Array[String] = []
	for l in card.ability_name_labels:
		other.append(l.text)
	check(warrior_names != other or card.ability_name_labels.is_empty(), "the card shows the new class's abilities")


func test_every_shipped_class_card_matches_its_data() -> void:
	for class_id in Db.class_ids:
		var data := Db.get_class_data(class_id)
		var card := _join(UiFakes.HumanInput.new("pad:%s" % class_id), data)
		var expected := mini(data.abilities.size(), AbilityRunner.CORE_SLOTS)
		check_eq(card.ability_icons.size(), expected, "%s: icons match ClassData.abilities" % class_id)
		for i in card.ability_icons.size():
			check_eq(card.ability_name_labels[i].text, data.abilities[i].display_name, "%s: ability %d name" % [class_id, i])
		if data.mastery_text != "":
			var parts := LobbyCard.mastery_parts(data.mastery_text)
			check_eq(card.mastery_label.text, parts[1], "%s: Mastery text" % class_id)
		PlayerManager.leave(PlayerManager.get_slots().back().index)
