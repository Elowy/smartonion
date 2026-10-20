extends TestCase
## M7a IP-2: no names copied from Blizzard games in anything the player can read.
##
## Four checks over PLAYER-VISIBLE text only (never ids, file names, comments or node names):
##   1. no display name (ability, Rank V specialisation, talent, talent tree, enchant prefix, boss
##      ability, enemy, resource, set, unique, class mastery name) equals one of the old names;
##   2. no description / text / flavor / tooltip in res://data/ (every .tres, found by walking the
##      folder, nothing is listed by hand) and no string literal in res://scenes/, res://core/ and
##      res://autoload/ (comments, &"StringName" ids, ^"NodePath"s, res:// paths and triple-quoted
##      shader code are skipped) contains one of the banned phrases or brand names;
##   3. every new name of the rename table really is present;
##   4. ability, specialisation, talent and tree names are unique game-wide.
## The matchers are unit-tested with synthetic strings (including the false-positive cases), so
## the test fails if a banned name comes back and does not fire on plain English.

const DATA_DIR := "res://data/"
const CODE_DIRS: Array[String] = ["res://scenes/", "res://core/", "res://autoload/"]

## Resource properties holding names; every other String property is text too (ids are StringNames).
## Dictionaries (params, effects, specs, bonuses ...) hold ids as well: only these keys are text.
const NAME_PROPS: Array[String] = ["display_name", "prefix", "suffix", "pair_name", "hazard_name"]
const TEXT_KEYS: Array[String] = ["name", "text", "short", "label", "description", "intro", "flavor"]

## Literal tokens of a .gd file, in source order and non-overlapping: a comment, a triple-quoted
## block, a &"StringName" / ^"NodePath", a "string", a 'string'. Only the last two are text.
const TOKEN_PATTERN := r"#[^\n]*|\"\"\"[\s\S]*?\"\"\"|[&^]\"(?:\\.|[^\"\\\n])*\"|\"(?:\\.|[^\"\\\n])*\"|'(?:\\.|[^'\\\n])*'"

## String literals in the code that are node names, not text (the list is the whole allowance).
const CODE_ALLOWED: Array[Array] = [
	["res://scenes/abilities/warlock/infernal.gd", "Infernal"],
	["res://scenes/abilities/warlock/voidwalker.gd", "Voidwalker"],
]

## The exact old display names (rename table A1-A8). Kept on purpose: Imp, Wild Imp, Imp Swarm,
## Skeleton Grunt (generic words), Aftershock (War Stomp's own spec) and Soul Siphon (the Skull's
## property).
const OLD_NAMES: Array[String] = [
	"Berserking", "War Stomp", "Spirit Wolf", "Arcane Missiles", "Blizzard", "Frost Nova",
	"Ice Barrier", "Pyroblast", "Avenger's Shield", "Blessing of Kings", "Consecration",
	"Divine Shield", "Divine Storm", "Hammer of Justice", "Lay on Hands", "Word of Glory",
	"Blade Flurry", "Cheat Death", "Fan of Knives", "Killing Spree", "Shadowstep", "Shuriken Toss",
	"Vanish", "Drain Life", "Rain of Fire", "Seed of Corruption", "Shadow Bolt", "Summon Infernal",
	"Summon Voidwalker", "Battle Shout", "Bladestorm", "Heroic Leap", "Shield Wall", "Thunder Clap",
	"Focused Missiles", "Arcane Barrage", "Ice Block", "Pyroclasm", "Hot Streak",
	"Blessing of Might", "Blessing of Sanctuary", "Hallowed Ground", "Hands of Mercy",
	"Light of Dawn", "Relentless Flurry", "Adrenaline Surge", "Deadly Fan", "Smoke Bomb",
	"Siphon Life", "Abyssal Guardian", "Consuming Shadows", "Commanding Shout",
	"Intimidating Shout", "Ravager", "Warbringer", "Sweeping Strikes", "Spiked Wall",
	"Booming Voice", "Spirit Link", "Arms", "Fury", "Protection", "Arcane", "Fire", "Frost", "Holy",
	"Retribution", "Assassination", "Combat", "Subtlety", "Affliction", "Demonology", "Destruction",
	"Tactical Mastery", "Deep Wounds", "Two-Handed Specialization", "Sudden Death", "Mortal Strike",
	"Unbridled Wrath", "Blood Craze", "Dual Wield Specialization", "Meat Cleaver", "Flurry",
	"Death Wish", "Rampage", "Shield Specialization", "Revenge", "Shield Mastery",
	"Blood and Thunder", "Arcane Concentration", "Mirror Image", "Arcane Power", "Critical Mass",
	"Playing with Fire", "Living Bomb", "Molten Fury", "Combustion", "Ice Armor", "Winter's Chill",
	"Arctic Winds", "Deep Freeze", "Flash Freeze", "Chilled to the Bone", "Ice Lance",
	"Aura Mastery", "Eternal Glory", "Unyielding Faith", "Light's Grace", "Light's Hammer",
	"Divine Guardian", "Purifying Power", "Holy Shock", "Consecrated Ground",
	"Guarded by the Light", "Ardent Defender", "Righteous Fury", "Shield of the Templar",
	"Reckoning", "Holy Shield", "Art of War", "Sanctity of Battle", "Sanctified Retribution",
	"Righteous Vengeance", "Seal of Command", "Seal Fate", "Coup de Grace", "Envenom",
	"Venomous Wounds", "Master Poisoner", "Cold Blood", "Lightning Reflexes", "Combat Potency",
	"Unfair Advantage", "Restless Blades", "Hack and Slash", "Adrenaline Rush", "Premeditation",
	"Enveloping Shadows", "Master of Subtlety", "Shadow Focus", "Deadened Nerves", "Find Weakness",
	"Sleight of Hand", "Shadow Dance", "Curse of Agony", "Shadow Mastery", "Curse of Exhaustion",
	"Writhe in Agony", "Death's Embrace", "Unstable Affliction", "Demonic Embrace", "Improved Imp",
	"Unholy Power", "Soul Harvest", "Demonic Aegis", "Master Demonologist", "Fel Synergy",
	"Soul Link", "Emberstorm", "Soul Leech", "Shadowburn", "Burning Embers", "Conflagrate",
	"Improved Blizzard", "Improved Drain Life", "Wild Imps", "Aura of Devotion", "Deadly Poison",
	"Demonic Pact", "Battle Fury", "Holy Power", "Soul Shards", "Voidwalker", "Infernal",
	"Raise Dead", "Loot Goblin", "Troll Axethrower", "Spirit Healer", "Resurrection Sickness",
	"Frostweave Cowl", "Warbringer's Greaves", "Libram of Devotion", "Battlegear of Fury",
	"Breastplate of Fury", "Gauntlets of Fury", "Helm of Fury", "Legplates of Fury",
	"Pauldrons of Fury", "Felfire Raiment", "Felfire Robes", "Felfire Gloves", "Felfire Hood",
	"Felfire Leggings", "Felfire Mantle", "Bloodlust", "Shadowflame",
	# M9 (meta-progression): the WoW system names the game replaced (Valor -> Seeds). Only as the WHOLE display name: the
	# kept names "Call of Valor", "Boundless Valor", "Generous Valor" and the specialisation "Raging Echo" contain the words.
	"Valor", "Raging",
]

## Old names that are plain English words (or damage schools): the exact-name check of the
## code literals skips them ("Fire" is a school label there); the data check does not.
const OLD_NAMES_PLAIN: Array[String] = [
	"Arms", "Fury", "Protection", "Arcane", "Fire", "Frost", "Holy", "Retribution", "Assassination",
	"Combat", "Subtlety", "Affliction", "Demonology", "Destruction", "Flurry", "Revenge",
	"Reckoning", "Combustion",
]

## Multi-word phrases: banned in any case, in data text and in code literals.
const PHRASES: Array[String] = [
	"Frost Nova", "Ice Barrier", "Ice Block", "Ice Lance", "Arcane Missiles", "Mirror Image",
	"Living Bomb", "Arcane Power", "Hot Streak", "Divine Shield", "Divine Storm", "Hammer of Justice",
	"Lay on Hands", "Word of Glory", "Light of Dawn", "Avenger's Shield", "Blessing of Kings",
	"Blessing of Might", "Blessing of Sanctuary", "Holy Shock", "Holy Shield", "Holy Power",
	"Seal of Command", "Righteous Fury", "Ardent Defender", "Blade Flurry", "Cheat Death",
	"Fan of Knives", "Fans of Knives", "Fan(s) of Knives", "Killing Spree", "Shuriken Toss",
	"Cold Blood", "Adrenaline Rush", "Shadow Dance", "Deadly Poison", "Drain Life", "Rain of Fire",
	"Seed of Corruption", "Shadow Bolt", "Summon Infernal", "Summon Voidwalker", "Curse of Agony",
	"Curse of Exhaustion", "Unstable Affliction", "Soul Shard", "Soul Shards", "Soul Link",
	"Demonic Pact", "Battle Shout", "Heroic Leap", "Shield Wall", "Thunder Clap", "Mortal Strike",
	"Mortal Wound", "Sweeping Strikes", "Death Wish", "Meat Cleaver", "Spirit Healer",
	"Resurrection Sickness", "Loot Goblin", "Troll Axethrower", "Aura of Devotion", "Battle Fury",
	"War Stomp", "Spirit Wolf", "Spirit Wolves", "Spirit Link", "Consecrated Ground", "Hands of Mercy",
	"Smoke Bomb", "Arcane Barrage", "Siphon Life", "Intimidating Shout", "Commanding Shout",
	"Spiked Wall", "Booming Voice", "Libram of Devotion", "Battlegear of Fury", "Arcane Dust",
]

## Single capitalised words that are also English: banned only with this exact spelling.
const WORDS_CASE: Array[String] = ["Infernal", "Rampage", "Berserking", "Envenom", "Torment", "Agony"]

## Single-word coinages: banned in any case in data text, with this spelling in code literals
## (where the lower-case spelling is an id, a cache key or a param name).
const WORDS_COINED: Array[String] = [
	"Blizzard", "Pyroblast", "Bladestorm", "Shadowstep", "Consecration", "Voidwalker", "Felfire",
	"Frostweave", "Bloodlust", "Shadowflame", "Conflagrate", "Shadowburn", "Premeditation",
	"Warbringer",
	# M9: WoW's difficulty / system names (Pungent and Tear-Jerker replace Heroic and Mythic, the Wardrobe replaces
	# Transmog) and the Mythic+ affix names (the Tear-Jerker pressures have names of their own). "Glyph" is a plain word
	# and "Valor" / "Raging" are exact-name bans (OLD_NAMES), none of them is listed here.
	"Heroic", "Mythic", "Transmog", "Bolstering", "Volcanic", "Sanguine", "Bursting", "Necrotic", "Fortified",
	"Tyrannical",
]

## Brand and proper names (GDD chapter 14 plus the Blizzard IPs): whole words, any case.
const BRANDS: Array[String] = [
	"azeroth", "murloc", "horde", "alliance", "thunderfury", "ashbringer", "frozen throne",
	"silver hand", "frostmourne", "warcraft", "lich king", "sylvanas", "windrunner", "arthas",
	"illidan", "thrall", "stormwind", "orgrimmar", "time is money", "felheart", "shadowcraft",
	"lightforged", "gorehowl", "sulfuras", "doomhammer", "atiesh", "warglaive", "friz quadrata",
	"world of warcraft", "wow", "diablo", "hearthstone", "overwatch", "starcraft", "nephalem",
	"horadric", "tristram", "deathwing", "ragnaros", "onyxia", "nefarian", "kel'thuzad", "dalaran",
	"ironforge", "darnassus", "undercity", "draenor", "outland", "northrend", "battle.net",
]

## The new names of the rename table: every one must exist as a display name in the data.
const NEW_NAMES: Array[String] = [
	"Savage Haste", "Crowd Stomp", "Phantom Wolf", "Arcane Darts", "Hailstorm", "Rime Burst",
	"Frozen Layer", "Magma Bolt", "Ricochet Shield", "Boon of Crowns", "Sacred Circle",
	"Gilded Halo", "Radiant Whirl", "Smiting Hammer", "Mending Touch", "Call of Valor",
	"Cleaving Blades", "Narrow Escape", "Knife Bloom", "Cutthroat Rush", "Duskstep",
	"Throwing Stars", "Melt Away", "Vital Siphon", "Ember Rain", "Blight Seed", "Umbral Bolt",
	"Summon Cinder Brute", "Summon Gloomguard", "Battle Roar", "Steel Cyclone", "Soaring Slam",
	"Stalwart Guard", "Ground Slam", "Focused Darts", "Burst Darts", "Glacial Cocoon",
	"Piercing Blaze", "Quickfire", "Boon of Vigor", "Boon of Warding", "Healing Circle",
	"Touch of Many", "Chorus of Dawn", "Relentless Blades", "Racing Pulse", "Deadly Bloom",
	"Smoke Pellet", "Leeching Curse", "Burning Guardian", "Smothering Dark", "Commanding Roar",
	"Dread Roar", "Whirling Axe", "Battering Ram", "Reaping Arc", "Spiked Guard", "Raging Echo",
	"Pack Bond", "Warblade", "Berserker", "Ironwall", "Starlore", "Pyrelore", "Rimelore",
	"Radiance", "Vigil", "Verdict", "Toxins", "Bladework", "Gloaming", "Hexcraft", "Pactcraft",
	"Cinderfall", "Rage Reserve", "Gashing Blows", "Two-Hander Prowess", "Culling Instinct",
	"Ruinous Strike", "Furious Spark", "Savoured Kills", "Twin-Blade Prowess", "Reaping Spin",
	"Rising Tempo", "Desperate Might", "Carnage", "Shield Prowess", "Payback", "Shieldcraft",
	"Whirl and Slam", "Thrifty Casting", "Phantom Double", "Overchannel", "Fiery Precision",
	"Reckless Flame", "Ticking Ember", "Finishing Flame", "Chain Ignition", "Rime Plating",
	"Numbing Cold", "Boreal Winds", "Glacial Finale", "Snap Freeze", "Frozen Marrow", "Frost Spike",
	"Aura Reach", "Boundless Valor", "Steadfast Prayer", "Generous Valor", "Gifted Circle",
	"Warding Presence", "Sunlit Might", "Radiant Pulse", "Lasting Circle", "Shielded by Faith",
	"Dauntless Rally", "Provoking Light", "Vigilant Shield", "Swift Rebuke", "Gleaming Shield",
	"Rhythm of Battle", "Sacred Cadence", "Sanctified Fervor", "Branding Strikes", "Sunbrand",
	"Fateful Cuts", "Finishing Flourish", "Overdose", "Toxic Harvest", "Venom Savant",
	"Steel Nerve", "Quicksilver Reflexes", "Battle Verve", "Sly Counter", "Hastening Blades",
	"Twin Strike", "Crowd Surge", "Forethought", "Veiling Dusk", "Veiled Aggression", "Quiet Mind",
	"Callous Hide", "Opportunist's Eye", "Quick Fingers", "Dusk Waltz", "Hex of Anguish",
	"Umbral Affinity", "Hex of Fatigue", "Spreading Anguish", "Doomed Prey", "Volatile Blight",
	"Fiendish Vigor", "Pampered Imp", "Pack Command", "Shard Hunger", "Pact Ward", "Pactmaster",
	"Kindly Fiends", "Soul Tether", "Stoked Flames", "Bloody Tithe", "Parting Scorch",
	"Pocketed Shards", "Lingering Blaze", "Improved Hailstorm", "Improved Vital Siphon",
	"Imp Brood", "Aura of Fealty", "Lethal Venom", "Ember Pact", "Cornered Fury", "Resolve",
	"Pact Shards", "Coin Gremlin", "Troll Hatchet-Hurler", "Call the Fallen", "Rimeweave Cowl",
	"Vanguard's Greaves", "Hymnal of Devotion", "Ragebound Plate", "Ragebound Breastplate",
	"Ragebound Gauntlets", "Ragebound Helm", "Ragebound Legplates", "Ragebound Pauldrons",
	"Hexfire Raiment", "Hexfire Robes", "Hexfire Gloves", "Hexfire Hood", "Hexfire Leggings",
	"Hexfire Mantle", "Warfever", "Duskflame", "Reprisal", "Echoing Slam", "Threefold Drain",
]

var _rx_phrases: RegEx
var _rx_words_case: RegEx
var _rx_coined_any: RegEx
var _rx_coined_case: RegEx
var _rx_brands: RegEx
var _rx_tokens: RegEx
var _old_exact: Dictionary = {}
var _old_exact_code: Dictionary = {}


func before_each() -> void:
	_rx_phrases = _compile(PHRASES, true)
	_rx_words_case = _compile(WORDS_CASE, false)
	_rx_coined_any = _compile(WORDS_COINED, true)
	_rx_coined_case = _compile(WORDS_COINED, false)
	_rx_brands = _compile(BRANDS, true)
	_rx_tokens = RegEx.new()
	_rx_tokens.compile(TOKEN_PATTERN)
	for n in OLD_NAMES:
		_old_exact[n] = true
		if not OLD_NAMES_PLAIN.has(n):
			_old_exact_code[n] = true


# --- the matchers (also unit-tested below) ---------------------------------------------------

## One alternation of whole-word phrases: the boundary is "not a letter, digit or underscore", so
## "Soul Shard" does not match inside "Soul Shards" (both are listed) and "Hordes" is not "horde".
func _compile(words: Array[String], any_case: bool) -> RegEx:
	var parts: PackedStringArray = []
	for w in words:
		parts.append(_escape(w))
	var rx := RegEx.new()
	var pattern := "(?<![A-Za-z0-9_])(?:%s)(?![A-Za-z0-9_])" % "|".join(parts)
	var err := rx.compile(("(?i)" if any_case else "") + pattern)
	check_eq(err, OK, "the ban regex compiles")
	return rx


func _escape(s: String) -> String:
	var out := ""
	for ch in s:
		if ".^$*+?()[]{}|\\".contains(ch):
			out += "\\"
		out += ch
	return out


## The banned names in a player-visible text. [param code]: a string literal of the code, where
## the coined words only count with their capital letter (lower case is an id there).
func _text_hits(text: String, code: bool) -> Array[String]:
	var t := text.replace("’", "'")
	var hits: Array[String] = []
	for rx in [_rx_phrases, _rx_words_case, _rx_coined_case if code else _rx_coined_any, _rx_brands]:
		for m in (rx as RegEx).search_all(t):
			hits.append(m.get_string())
	return hits


func _is_old_name(name: String) -> bool:
	return _old_exact.has(name.strip_edges())


# --- reading the content ---------------------------------------------------------------------

## Every name and text the data holds: {"names": [[where, name, pool]], "texts": [[where, text]]}.
## pool is "ability" / "spec" / "talent" / "tree" for the names of the uniqueness check, else "".
func _read_data() -> Dictionary:
	var out := {"names": [], "texts": []}
	var seen: Dictionary = {}
	for path in _files_under(DATA_DIR, ".tres"):
		var res := load(path) as Resource
		if res == null:
			check(false, "%s loads" % path)
			continue
		_scan_resource(res, path, out, seen)
	return out


func _files_under(dir: String, ext: String) -> Array[String]:
	var found: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(ext):
			found.append(dir + f)
	for d in DirAccess.get_directories_at(dir):
		found.append_array(_files_under("%s%s/" % [dir, d], ext))
	found.sort()
	return found


func _scan_resource(res: Resource, where: String, out: Dictionary, seen: Dictionary) -> void:
	if seen.has(res.get_instance_id()):
		return
	seen[res.get_instance_id()] = true
	for prop in res.get_property_list():
		if (int(prop["usage"]) & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var pname: String = prop["name"]
		var pool := ""
		if res is AbilityData and pname == "display_name":
			pool = "ability"
		elif res is TalentData and pname == "display_name":
			pool = "talent"
		elif res is TalentTreeData and pname == "display_name":
			pool = "tree"
		_scan_value(res.get(pname), "%s %s" % [where, pname], pname, pool, res, out, seen)
	if res is ClassData:
		var parts := (res as ClassData).mastery_text.split(":", true, 1)
		if parts.size() == 2:
			out["names"].append(["%s mastery" % where, parts[0].strip_edges(), ""])


func _scan_value(v: Variant, where: String, key: String, pool: String, owner: Resource, out: Dictionary, seen: Dictionary, in_dict := false) -> void:
	match typeof(v):
		TYPE_STRING:
			var s: String = v
			if s.is_empty() or (in_dict and not key in TEXT_KEYS):
				return
			if key in NAME_PROPS:
				out["names"].append([where, s, pool])
			# Every String property is text (ids are StringNames).
			out["texts"].append([where, s])
		TYPE_ARRAY:
			for item in v:
				_scan_value(item, where, key, pool, owner, out, seen, in_dict)
		TYPE_DICTIONARY:
			var d: Dictionary = v
			for k in d:
				var val: Variant = d[k]
				if val is String and str(k) in TEXT_KEYS:
					out["texts"].append(["%s [%s]" % [where, k], val])
					if str(k) == "name":
						var spec_pool := "spec" if owner is AbilityData else ""
						out["names"].append(["%s [name]" % where, val, spec_pool])
				elif val is Array or val is Dictionary:
					_scan_value(val, where, str(k), "", owner, out, seen, true)
		TYPE_OBJECT:
			if v is Resource and not (v is Script):
				_scan_resource(v, where, out, seen)


## The visible string literals of the code: [[file, line, text]].
func _read_code() -> Array:
	var out: Array = []
	for dir in CODE_DIRS:
		for path in _files_under(dir, ".gd"):
			var src := FileAccess.get_file_as_string(path)
			for m in _rx_tokens.search_all(src):
				var tok := m.get_string()
				var first := tok[0]
				if first == "#" or first == "&" or first == "^" or tok.begins_with("\"\"\""):
					continue
				var body := tok.substr(1, tok.length() - 2)
				if body.begins_with("res://") or body.begins_with("user://") or body.is_empty():
					continue
				out.append([path, src.count("\n", 0, m.get_start()) + 1, body])
	return out


# --- the checks ------------------------------------------------------------------------------

func test_no_old_display_name_is_left_in_the_data() -> void:
	var data := _read_data()
	var names: Array = data["names"]
	check(names.size() > 700, "the scan finds the names of the whole content (%d)" % names.size())
	var bad: Array[String] = []
	for n in names:
		if _is_old_name(n[1]):
			bad.append("%s = \"%s\"" % [n[0], n[1]])
	check(bad.is_empty(), "old display names: %s" % ", ".join(bad.slice(0, 12)))


func test_no_banned_phrase_in_the_data_texts() -> void:
	var data := _read_data()
	var texts: Array = data["texts"]
	check(texts.size() > 1200, "the scan finds the texts of the whole content (%d)" % texts.size())
	var bad: Array[String] = []
	for t in texts:
		var hits := _text_hits(t[1], false)
		if not hits.is_empty():
			bad.append("%s: %s in \"%s\"" % [t[0], hits[0], str(t[1]).left(70)])
	check(bad.is_empty(), "banned names in data texts: %s" % " | ".join(bad.slice(0, 8)))


func test_no_banned_name_in_the_code_string_literals() -> void:
	var lits := _read_code()
	check(lits.size() > 4000, "the scan finds the string literals of the code (%d)" % lits.size())
	var bad: Array[String] = []
	for l in lits:
		var path: String = l[0]
		var text: String = l[2]
		if CODE_ALLOWED.has([path, text]):
			continue
		var hits := _text_hits(text, true)
		if _old_exact_code.has(text.strip_edges()):
			hits.append(text.strip_edges())
		if not hits.is_empty():
			bad.append("%s:%d: %s in \"%s\"" % [path.trim_prefix("res://"), l[1], hits[0], text.left(60)])
	check(bad.is_empty(), "banned names in string literals: %s" % " | ".join(bad.slice(0, 8)))


func test_every_new_name_of_the_rename_table_is_present() -> void:
	var data := _read_data()
	var present: Dictionary = {}
	for n in data["names"]:
		present[str(n[1]).strip_edges()] = true
	var missing: Array[String] = []
	for n in NEW_NAMES:
		if not present.has(n):
			missing.append(n)
	check(missing.is_empty(), "new names missing from the data: %s" % ", ".join(missing))


func test_ability_spec_talent_and_tree_names_are_unique() -> void:
	var data := _read_data()
	var seen: Dictionary = {}
	var dups: Array[String] = []
	var counted := 0
	for n in data["names"]:
		var pool: String = n[2]
		if pool.is_empty():
			continue
		counted += 1
		var key := str(n[1]).strip_edges()
		if seen.has(key):
			dups.append("\"%s\" (%s, %s)" % [key, seen[key], pool])
		else:
			seen[key] = pool
	var specs := 0
	for a in Db.abilities.values():
		specs += (a as AbilityData).specs.size()
	var expected := Db.abilities.size() + specs + Db.talents.size() + Db.talent_trees.size()
	check_eq(counted, expected, "the pools hold every ability, specialisation, talent and tree Db knows")
	check(dups.is_empty(), "names used twice: %s" % ", ".join(dups))


# --- the matchers themselves -----------------------------------------------------------------

func test_matchers_catch_the_old_names() -> void:
	for text in ["Your Vital Siphon and Word of Glory", "Summon Voidwalker", "gain a Soul Shard", "3 Soul Shards",
			"The BLIZZARD hits", "a blizzard of arrows", "Fan(s) of Knives", "Spirit Healer: 6 s",
			"Holy Power", "Rampage!", "Berserking", "Arcane dust", "the Horde", "WoW-flavoured", "Diablo",
			"Heroic mode", "a heroic run", "Mythic+ keys", "Transmog set", "Bolstering enemies", "Volcanic ash", "Sanguine pools",
			"Bursting foes", "Necrotic wounds", "Fortified bosses", "Tyrannical bosses", "the Tyrannical week"]:
		check(not _text_hits(text, false).is_empty(), "data text \"%s\" is caught" % text)
	for text in ["Word of Glory", "Soul Shards: %d", "Rampage!", "Infernal", "Voidwalker", "Blizzard", "Alliance",
			"Heroic", "Mythic", "Transmog", "Bolstering", "Volcanic", "Sanguine", "Bursting", "Necrotic", "Fortified",
			"Tyrannical"]:
		check(not _text_hits(text, true).is_empty(), "code literal \"%s\" is caught" % text)
	check(_is_old_name("Vanish") and _is_old_name(" Fury ") and _is_old_name("Imp Swarm") == false, "exact names")
	check(_is_old_name("Valor") and _is_old_name(" Raging ") and _old_exact_code.has("Valor"), "Valor and Raging as whole names (M9)")
	check(_is_old_name("Wild Imps") and _is_old_name("Improved Imp") and _is_old_name("Retribution"), "exact names, more")


func test_matchers_spare_plain_english_and_kept_names() -> void:
	for text in ["The cloud will vanish at dawn", "Flask of Fury", "Reckless Fury", "Fell on wave 4", "Improved Charge",
			"Impale needs Gashing Blows", "A rampage of knives", "He went berserk", "agony and torment", "combat is fun",
			"Protection from fire and frost", "Divine Strength", "Divine Verdict", "Hallowed", "Imp Brood", "Pampered Imp",
			"Wild Imps fight for you", "Skeleton Grunt", "Soul Siphon", "Aftershock", "Shockwave", "Whirlwind", "Corruption",
			"Ignite", "Artifact", "Dawnbreaker", "Hailstorm", "Melt Away", "Sacred Circle", "Ember Rain", "Resolve", "Pact Shards",
			"Glimmer Dust", "Need", "Greed", "Disenchant", "Dust", "Goblin Coin Purse", "Coin Gremlin", "Grave Tender", "Wilted",
			"Throne room", "Alliances are made", "Hordes", "Call of Valor", "Boundless Valor", "Generous Valor", "Raging Echo",
			"Glyph", "Seasoning", "Seeds", "Wardrobe", "Pungent", "Tear-Jerker", "Salt Rain", "Hardened Peel", "Paring Knives",
			"Wilting Heat", "Weeping Fog", "Bitter Harvest", "heroes", "a hero's journey", "mythical beasts", "burst of flame",
			"bursts", "volcano", "fortify", "fortress", "necromancer", "tyrant", "sanguine_pool", "heroic_leap"]:
		var hits := _text_hits(text, false)
		check(hits.is_empty(), "\"%s\" is not flagged: %s" % [text, hits])
	for text in ["warlock:infernal:body", "warlock:voidwalker:eyes", "ConsecrationVfx", "BlizzardShards", "torment_radius",
			"envenom_pct", "blizzard", "consecration", "shadowstep", "pyroblast", "bladestorm"]:
		var hits2 := _text_hits(text, true)
		check(hits2.is_empty(), "code id/key \"%s\" is not flagged: %s" % [text, hits2])
	check(not _is_old_name("Melt Away") and not _is_old_name("Arcane Focus") and not _is_old_name("Imp"), "new / kept names are not old")
	check(not _is_old_name("Call of Valor") and not _is_old_name("Boundless Valor") and not _is_old_name("Raging Echo")
			and not _is_old_name("Valorous") and not _is_old_name("Raging Bull"), "Valor / Raging only as the exact name")


func test_code_scanner_skips_comments_ids_and_paths() -> void:
	var src := "var a := \"Word of Glory\" # \"Vanish\" in a comment\nvar b := &\"holy_power\"\nvar c := \"res://x/Blizzard.gd\"\n" \
		+ "const D := 'it\\'s Holy Power'\n## doc: \"Rampage\"\nvar e := \"\"\"Blizzard\"\"\"\n"
	var found: Array[String] = []
	for m in _rx_tokens.search_all(src):
		var tok := m.get_string()
		if tok[0] in ["#", "&", "^"] or tok.begins_with("\"\"\""):
			continue
		found.append(tok.substr(1, tok.length() - 2))
	check_eq(found, ["Word of Glory", "res://x/Blizzard.gd", "it\\'s Holy Power"] as Array[String], "only the real string literals")
