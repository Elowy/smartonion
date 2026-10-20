class_name BonusVocabulary
extends RefCounted
## The bonus-effect vocabulary in code (M5): the only entries talents (TalentData.effects) and
## set bonuses (SetData.bonuses[*].effects) may use – the contract between the content and the
## engine (PlayerBonuses). Reference with examples: talent_vocabulary.md.
##
## An entry is a Dictionary with String keys: "kind" (KINDS) plus the kind's fields, optional
## "requires" ({"weapon": WEAPON_REQUIREMENTS} or {"knows": <ability id>}), and "rank" (>= 1),
## "id", "label", which the source (TalentState.effects, SetBonuses.effects_for) adds:
##   stats        {"stats": {<Stats id> | "primary": n}}
##   ability      {"match": {<one of MATCH_KEYS>}, "mods": {AbilityRunner.apply_mods keys}}
##   damage       {"pct": n, "source", "school", "target" (+ "target_pct"), "self_below_pct" /
##                "self_above_pct"}
##   damage_taken {"pct": n, "kind_filter": melee | projectile | aoe}
##   resource     {"resource": <class resource id> | "primary", "<RESOURCE_FIELDS>_add": n}
##   proc         {"proc": {ProcSystem params: "trigger" (TRIGGERS), "effect" (PROC_BLOCKS) ...},
##                "scale": [proc keys multiplied by the rank]}
##   script       {"script": "res://scenes/talents/<class>/<tree>_<name>.gd", "params": {...}}
##   proficiency  {"grant": <GRANTABLE_PROFICIENCIES id>} – a proficiency the class does not have
##                (the Shaman's dual wield, from a Warspirit talent): PlayerBonuses.has_proficiency
##                / Equipment.can_dual_wield; the rank does not scale it
## Everything here is pure (no Player): [method validate] is the content check of the data
## tests, [method resolve] the rank scaling, [method matches] / [method matches_id] the ability
## filter of "ability" entries and on_cast / cooldown procs.

const KINDS: Array[StringName] = [&"stats", &"ability", &"damage", &"damage_taken", &"resource", &"proc", &"script", &"proficiency"]
## ClassData.proficiencies ids a "proficiency" entry may grant at runtime (Equipment asks
## PlayerBonuses.has_proficiency besides ClassData.can_dual_wield).
const GRANTABLE_PROFICIENCIES: Array[StringName] = [&"dual_wield"]
## "source" filter of damage entries (Player.outgoing_damage_mult sources).
const DAMAGE_SOURCES: Array[StringName] = [&"weapon", &"ability", &"dot", &"pet", &"proc"]
const SCHOOLS: Array[StringName] = [&"physical", &"fire", &"frost", &"arcane", &"holy", &"shadow", &"nature"]
## AbilityData.tags values ({"match": {"tag": ...}}).
const TAGS: Array[StringName] = [&"aoe", &"projectile", &"dot", &"heal", &"shield", &"buff", &"cc", &"movement", &"pet", &"weapon", &"spell", &"ground", &"stealth", &"lightning"]
## "target" filter of damage entries (below_pct / above_pct compare with "target_pct").
const TARGET_CONDITIONS: Array[StringName] = [&"elite", &"boss", &"stunned", &"slowed", &"feared", &"below_pct", &"above_pct"]
## {"requires": {"weapon": ...}} conditions.
const WEAPON_REQUIREMENTS: Array[StringName] = [&"two_handed", &"one_handed", &"dual_wield", &"shield", &"melee", &"ranged", &"magic"]
## Proc triggers of talent / set procs (ProcSystem's item triggers + the M5 ones).
const TRIGGERS: Array[StringName] = [&"on_hit", &"on_crit", &"on_kill", &"when_struck", &"low_hp", &"periodic", &"wave_start", &"on_cast", &"on_dodge", &"on_parry", &"on_block"]
## ProcSystem.BLOCKS + [&"cooldown", &"forced_crit"] (written out: a constant expression).
const PROC_BLOCKS: Array[StringName] = [
	&"bolt", &"chain", &"dot", &"nova", &"explode", &"extra_attack", &"buff", &"heal",
	&"drain", &"slow", &"stun", &"gold", &"shield", &"reflect", &"smite_heal", &"cheat_death",
	&"resource", &"cooldown", &"forced_crit",
]
## The only mod keys generic matches (school, tag, kind, resource, class, ids) may use: they
## mean the same on every ability (a "_pct" of a param an ability lacks would set a new param).
const SAFE_GENERIC_MOD_KEYS: Array[String] = ["power_pct", "cooldown_pct", "cooldown_add", "cost_pct", "cost_add", "charges_add", "free_chance_add"]
## ResourceData fields a "resource" entry may change ("<field>_add").
const RESOURCE_FIELDS: Array[String] = ["max_value", "start_value", "regen_per_second", "decay_per_second", "gain_on_hit", "gain_on_damage_taken", "gain_on_crit", "gain_per_hits", "gain_per_kills"]
## Pseudo ability ids (non-ability numbers read by kits through player.ability_mods). Closed
## registry: a new one is an integrator request (talent_vocabulary.md §5).
## An id may name a class that has no data yet (M8: hunter_companion, shaman_totems): validation
## compares the owner's id only, never Db.classes.
const PSEUDO_IDS: Dictionary[StringName, StringName] = {&"warlock_imp": &"warlock", &"warlock_shards": &"warlock", &"warlock_afflictions": &"warlock", &"paladin_aura": &"paladin", &"rogue_deadly_poison": &"rogue", &"hunter_companion": &"hunter", &"shaman_totems": &"shaman", &"shaman_echo": &"shaman"}

## Keys every entry may carry besides its kind's fields.
const META_KEYS: Array[String] = ["kind", "requires", "rank", "id", "label"]
## Fields per kind ("resource" adds the RESOURCE_FIELDS "_add" keys).
const KIND_KEYS: Dictionary[StringName, Array] = {
	&"stats": ["stats"],
	&"ability": ["match", "mods"],
	&"damage": ["pct", "source", "school", "target", "target_pct", "self_below_pct", "self_above_pct"],
	&"damage_taken": ["pct", "kind_filter"],
	&"resource": ["resource"],
	&"proc": ["proc", "scale"],
	&"script": ["script", "params"],
	&"proficiency": ["grant"],
}
## Keys of a "match" filter (exactly one per filter).
const MATCH_KEYS: Array[String] = ["id", "ids", "school", "tag", "kind", "resource", "class"]
## {"match": {"kind": ...}} values -> AbilityData.Kind.
const ABILITY_KINDS: Dictionary[String, int] = {"core": AbilityData.Kind.CORE, "active": AbilityData.Kind.ACTIVE, "auto": AbilityData.Kind.AUTO}
## "kind_filter" of damage_taken entries (CombatMath.KIND_*).
const DAMAGE_TAKEN_KINDS: Array[StringName] = [&"melee", &"projectile", &"aoe"]
## Keys a proc dict may use (ProcSystem header + the M5 additions). A "buff" may also name stats
## directly ({"crit": 5} = {"stats": {"crit": 5}}).
const PROC_KEYS: Array[String] = [
	"trigger", "effect", "chance", "ppm", "icd", "per_wave", "every", "label", "school",
	"threshold", "interval", "damage", "hit_pct", "targets", "duration", "stacks", "radius", "at",
	"slow", "slow_duration", "stun", "dot", "dot_duration", "dot_stacks", "spread", "count",
	"stats", "max_stacks", "heal", "amount", "max_hp_pct", "target", "pct", "invulnerable",
	"resource", "value", "ability", "match", "reduce", "reset",
]
## Proc keys that hold numbers (the ones "scale" may list, besides "stats").
const PROC_NUMBER_KEYS: Array[String] = [
	"chance", "ppm", "icd", "per_wave", "every", "threshold", "interval", "damage", "hit_pct",
	"targets", "duration", "stacks", "radius", "slow", "slow_duration", "stun", "dot",
	"dot_duration", "dot_stacks", "spread", "count", "max_stacks", "heal", "amount", "max_hp_pct",
	"pct", "invulnerable", "value", "reduce",
]
## Triggers whose event is a weapon hit ("hit_pct" needs one).
const HIT_TRIGGERS: Array[StringName] = [&"on_hit", &"on_crit"]


# --- Validation --------------------------------------------------------------------------------

## The contract check of one entry: "" = valid, else the first problem found. [param class_id]
## is the owner's class (a tree's / set's class_id): a "match" / "knows" id must be a Db ability
## of that class (or a general one) or a PSEUDO_IDS id registered for that class – mod keys of
## a pseudo id are not checked (their params live in kit code). Mods of a named ability must
## change one of its params ([method param_names]); a "<x>_pct" key whose <x> param does not
## exist is refused when it would replace an existing "<x>_pct" param (use "<x>_pct_add"),
## the replace trap of talent_vocabulary §3.2. Resource ids must be resources of that class.
## Without a class every class's abilities and resources are accepted and no pseudo id is.
## Script entries are checked for their shape only (the data test loads them).
static func validate(entry: Dictionary, class_id: StringName = &"") -> String:
	var kind := _name(entry.get("kind"))
	if kind not in KINDS:
		return "unknown kind '%s'" % kind
	var allowed: Array = KIND_KEYS[kind]
	for key: Variant in entry:
		var k := String(key)
		if k in META_KEYS or k in allowed:
			continue
		if kind == &"resource" and k.ends_with("_add") and k.trim_suffix("_add") in RESOURCE_FIELDS:
			continue
		return "unknown key '%s' in a %s entry" % [k, kind]
	if entry.has("rank") and (typeof(entry["rank"]) != TYPE_INT or int(entry["rank"]) < 1):
		return "rank must be a whole number >= 1"
	if entry.has("requires"):
		var req_error := _validate_requires(entry["requires"], class_id)
		if req_error != "":
			return req_error
	match kind:
		&"stats":
			return _validate_stats(entry.get("stats"), "stats")
		&"ability":
			return _validate_ability(entry, class_id)
		&"damage":
			return _validate_damage(entry)
		&"damage_taken":
			return _validate_damage_taken(entry)
		&"resource":
			return _validate_resource(entry, class_id)
		&"proc":
			return _validate_proc(entry, class_id)
		&"script":
			return _validate_script(entry)
		&"proficiency":
			return _validate_proficiency(entry)
	return ""


static func _validate_requires(req: Variant, class_id: StringName) -> String:
	if typeof(req) != TYPE_DICTIONARY or (req as Dictionary).is_empty():
		return "requires must be {\"weapon\": ...} or {\"knows\": ...}"
	for key: Variant in req:
		var v: Variant = req[key]
		match String(key):
			"weapon":
				if _name(v) not in WEAPON_REQUIREMENTS:
					return "unknown weapon requirement '%s'" % str(v)
			"knows":
				var e := _ability_id_error(_name(v), class_id, false)
				if e != "":
					return "requires knows: " + e
			_:
				return "unknown requirement '%s'" % String(key)
	return ""


static func _validate_stats(stats: Variant, what: String) -> String:
	if typeof(stats) != TYPE_DICTIONARY or (stats as Dictionary).is_empty():
		return "%s must be a non-empty dictionary" % what
	for key: Variant in stats:
		var k := String(key)
		if k != "primary" and StringName(k) not in Stats.ALL:
			return "unknown stat '%s'" % k
		if not _is_number(stats[key]):
			return "stat '%s' must be a number" % k
	return ""


static func _validate_ability(entry: Dictionary, class_id: StringName) -> String:
	var filter: Variant = entry.get("match")
	var match_error := _validate_match(filter, class_id)
	if match_error != "":
		return match_error
	var mods: Variant = entry.get("mods")
	if typeof(mods) != TYPE_DICTIONARY or (mods as Dictionary).is_empty():
		return "mods must be a non-empty dictionary"
	var by_id: bool = (filter as Dictionary).has("id")
	var id := _name(filter.get("id")) if by_id else &""
	var pseudo := by_id and PSEUDO_IDS.has(id)
	var names := param_names(Db.get_ability(id)) if by_id and not pseudo else {}
	for key: Variant in mods:
		var k := String(key)
		var v: Variant = mods[key]
		if (k.ends_with("_add") or k.ends_with("_pct")) and not _is_number(v):
			return "mod '%s' must be a number" % k
		if not by_id:
			if k not in SAFE_GENERIC_MOD_KEYS:
				return "generic matches may only use %s, not '%s'" % [", ".join(SAFE_GENERIC_MOD_KEYS), k]
			continue
		if pseudo or k in SAFE_GENERIC_MOD_KEYS:
			continue
		if k.ends_with("_add"):
			if not names.has(k.trim_suffix("_add")):
				return "'%s': %s has no param '%s'" % [k, id, k.trim_suffix("_add")]
		elif k.ends_with("_pct"):
			# AbilityRunner.apply_mods scales <param> when it exists; otherwise it REPLACES the
			# "<param>_pct" param itself (and resolve would scale the replacement by the rank):
			# Whirlwind {"damage_pct": 10} sets 10 instead of 150 (talent_vocabulary §3.2).
			var base := k.trim_suffix("_pct")
			if names.has(base):
				continue
			if names.has(k):
				return "'%s' would replace %s's %s (no '%s' param); use %s_add" % [k, id, k, base, k]
			return "'%s' changes no param of %s" % [k, id]
		elif not names.has(k):
			return "'%s' changes no param of %s" % [k, id]
	return ""


## A "match" filter: exactly one of MATCH_KEYS with a known value.
static func _validate_match(filter: Variant, class_id: StringName) -> String:
	if typeof(filter) != TYPE_DICTIONARY or (filter as Dictionary).size() != 1:
		return "match needs exactly one of %s" % ", ".join(MATCH_KEYS)
	var key := String((filter as Dictionary).keys()[0])
	var v: Variant = filter.values()[0]
	match key:
		"id":
			return _ability_id_error(_name(v), class_id, true)
		"ids":
			if typeof(v) != TYPE_ARRAY or (v as Array).is_empty():
				return "match ids must be a non-empty array"
			for x: Variant in v:
				var e := _ability_id_error(_name(x), class_id, false)
				if e != "":
					return e
		"school":
			if _name(v) not in SCHOOLS:
				return "unknown school '%s'" % str(v)
		"tag":
			if _name(v) not in TAGS:
				return "unknown tag '%s'" % str(v)
		"kind":
			if str(v) not in ABILITY_KINDS:
				return "unknown ability kind '%s'" % str(v)
		"resource":
			return _resource_id_error(_name(v), class_id, false)
		"class":
			if typeof(v) != TYPE_BOOL or not v:
				return "match class must be true"
		_:
			return "unknown match key '%s'" % key
	return ""


static func _validate_damage(entry: Dictionary) -> String:
	if not _is_number(entry.get("pct")):
		return "damage needs a number pct"
	if entry.has("source"):
		var e := _names_error(entry["source"], DAMAGE_SOURCES, "damage source")
		if e != "":
			return e
	if entry.has("school"):
		var e := _names_error(entry["school"], SCHOOLS, "school")
		if e != "":
			return e
	var target := _name(entry.get("target", ""))
	if entry.has("target") and target not in TARGET_CONDITIONS:
		return "unknown target condition '%s'" % target
	var compares := target == &"below_pct" or target == &"above_pct"
	if compares and not _is_number(entry.get("target_pct")):
		return "target %s needs a number target_pct" % target
	if entry.has("target_pct") and not compares:
		return "target_pct only goes with target below_pct / above_pct"
	for key in ["self_below_pct", "self_above_pct"]:
		if entry.has(key) and not _is_number(entry[key]):
			return "%s must be a number" % key
	return ""


static func _validate_damage_taken(entry: Dictionary) -> String:
	if not _is_number(entry.get("pct")):
		return "damage_taken needs a number pct"
	if entry.has("kind_filter") and _name(entry["kind_filter"]) not in DAMAGE_TAKEN_KINDS:
		return "unknown kind_filter '%s'" % str(entry["kind_filter"])
	return ""


static func _validate_resource(entry: Dictionary, class_id: StringName) -> String:
	var id := _name(entry.get("resource", ""))
	var e := _resource_id_error(id, class_id, true)
	if e != "":
		return e
	var fields := 0
	for key: Variant in entry:
		var k := String(key)
		if not k.ends_with("_add"):
			continue
		if not _is_number(entry[key]):
			return "'%s' must be a number" % k
		fields += 1
		if k == "max_value_add":
			var data := _resource_data(id, class_id)
			if data != null and data.display == ResourceData.Display.PIPS:
				return "max_value_add: %s is a pip resource (fixed maximum)" % data.id
	if fields == 0:
		return "a resource entry needs a <field>_add key (%s)" % ", ".join(RESOURCE_FIELDS)
	return ""


static func _validate_proc(entry: Dictionary, class_id: StringName) -> String:
	var p: Variant = entry.get("proc")
	if typeof(p) != TYPE_DICTIONARY:
		return "proc must be a dictionary"
	var trigger := _name(p.get("trigger", ""))
	if trigger not in TRIGGERS:
		return "unknown trigger '%s'" % trigger
	var effect := _name(p.get("effect", ""))
	if effect not in PROC_BLOCKS:
		return "unknown proc block '%s'" % effect
	for key: Variant in p:
		var k := String(key)
		var v: Variant = p[key]
		if k not in PROC_KEYS:
			if effect == &"buff" and (k == "primary" or StringName(k) in Stats.ALL) and _is_number(v):
				continue
			return "unknown proc key '%s'" % k
		if k in PROC_NUMBER_KEYS and not _is_number(v):
			return "proc key '%s' must be a number" % k
	if p.has("school") and _name(p["school"]) not in SCHOOLS:
		return "unknown school '%s'" % str(p["school"])
	if p.has("at") and str(p["at"]) not in ["self", "target"]:
		return "proc at must be self / target"
	if p.has("target") and str(p["target"]) not in ["self", "lowest_ally"]:
		return "proc target must be self / lowest_ally"
	if p.has("label") and typeof(p["label"]) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return "proc label must be text"
	if p.has("reset") and typeof(p["reset"]) != TYPE_BOOL:
		return "proc reset must be true / false"
	if p.has("stats"):
		var e := _validate_stats(p["stats"], "proc stats")
		if e != "":
			return e
	if p.has("hit_pct") and trigger not in HIT_TRIGGERS:
		return "hit_pct needs an on_hit / on_crit trigger"
	if p.has("every") and float(p["every"]) < 1.0:
		return "every must be at least 1"
	if p.has("ability"):
		var e := _ability_id_error(_name(p["ability"]), class_id, false)
		if e != "":
			return e
	if p.has("match"):
		var e := _validate_match(p["match"], class_id)
		if e != "":
			return e
	if (trigger == &"on_cast" or effect == &"cooldown") and int(p.has("ability")) + int(p.has("match")) != 1:
		return "%s needs exactly one of ability / match" % ("on_cast" if trigger == &"on_cast" else "cooldown")
	if effect == &"cooldown" and not p.has("reduce") and not (p.has("reset") and p["reset"]):
		return "cooldown needs reduce (seconds) or reset: true"
	if effect == &"resource" and p.has("resource"):
		var e := _resource_id_error(_name(p["resource"]), class_id, true)
		if e != "":
			return e
		if not _is_number(p.get("value")):
			return "resource with an id needs a number value"
	var scale: Variant = entry.get("scale", [])
	if typeof(scale) != TYPE_ARRAY:
		return "scale must be an array of proc keys"
	for key: Variant in scale:
		var k := str(key)
		if k == "stats":
			if typeof(p.get("stats")) != TYPE_DICTIONARY:
				return "scale lists stats but the proc has none"
		elif not p.has(k) or not _is_number(p[k]):
			return "scale lists '%s', which is not a number key of the proc" % k
	return ""


static func _validate_proficiency(entry: Dictionary) -> String:
	var grant := _name(entry.get("grant"))
	if grant not in GRANTABLE_PROFICIENCIES:
		return "grant must be one of %s, not '%s'" % [str(GRANTABLE_PROFICIENCIES), grant]
	return ""


static func _validate_script(entry: Dictionary) -> String:
	var path: Variant = entry.get("script")
	if typeof(path) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return "script needs a res:// path"
	var s := String(path)
	if not s.begins_with("res://") or not s.ends_with(".gd"):
		return "script must be a res://....gd path, not '%s'" % s
	if entry.has("params") and typeof(entry["params"]) != TYPE_DICTIONARY:
		return "script params must be a dictionary"
	return ""


## "" when [param id] names an ability [param class_id] may target: a Db ability of that class
## or a general one, or (with [param allow_pseudo]) a PSEUDO_IDS id of that class.
static func _ability_id_error(id: StringName, class_id: StringName, allow_pseudo: bool) -> String:
	if PSEUDO_IDS.has(id):
		if not allow_pseudo:
			return "pseudo id '%s' only works in {\"match\": {\"id\": ...}}" % id
		if PSEUDO_IDS[id] != class_id:
			return "pseudo id '%s' belongs to the %s class" % [id, PSEUDO_IDS[id]]
		return ""
	var a := Db.get_ability(id)
	if a == null:
		return "unknown ability '%s'" % id
	if class_id != &"" and a.class_id != &"" and a.class_id != class_id:
		return "ability '%s' belongs to the %s class" % [id, a.class_id]
	return ""


## "" when [param id] is a resource of [param class_id] (any class's without one) or, with
## [param allow_primary], "primary".
static func _resource_id_error(id: StringName, class_id: StringName, allow_primary: bool) -> String:
	if id == &"primary":
		return "" if allow_primary else "'primary' is not a resource id here"
	if _resource_data(id, class_id) == null:
		if class_id != &"":
			return "'%s' is not a resource of the %s class" % [id, class_id]
		return "unknown resource '%s'" % id
	return ""


## The ResourceData [param id] ("primary" = the class's first) of [param class_id] (of any class
## when [param class_id] is empty); null when unknown.
static func _resource_data(id: StringName, class_id: StringName) -> ResourceData:
	for cid in Db.classes:
		if class_id != &"" and cid != class_id:
			continue
		var cls := Db.classes[cid]
		for r in cls.resources:
			if r == null:
				continue
			if r.id == id or (id == &"primary" and class_id != &"" and r == cls.resources[0]):
				return r
	return null


## Every param name [param ability] has after AbilityRunner's defaults, its params and the names
## its Rank III / Rank V mods create (a set: name -> true). Empty for null.
static func param_names(ability: AbilityData) -> Dictionary:
	var names := {}
	if ability == null:
		return names
	for key in ["cooldown", "cost", "charges", "power"]:
		names[key] = true
	for key: Variant in ability.params:
		names[String(key)] = true
	var mod_sets: Array[Dictionary] = [ability.rank3]
	for spec in ability.specs:
		var m: Variant = spec.get("mods", {})
		if typeof(m) == TYPE_DICTIONARY:
			mod_sets.append(m)
	for mods in mod_sets:
		for key: Variant in mods:
			var k := String(key)
			if k.ends_with("_add"):
				names[k.trim_suffix("_add")] = true
			elif k.ends_with("_pct") and names.has(k.trim_suffix("_pct")):
				pass
			else:
				names[k] = true
	return names


# --- Rank scaling ------------------------------------------------------------------------------

## A deep copy of [param entry] with its amounts multiplied by [param rank] (talent_vocabulary.md
## §2): stats – every number; ability – the numbers of "_add" / "_pct" mods (replace keys never);
## damage / damage_taken – "pct"; resource – every "_add"; proc – only the keys listed in
## "scale" (a listed "stats" dict scales all its numbers); script – nothing. Rank 1 (and below)
## returns an unscaled copy. Every "_pct" mod of a validated entry scales an existing param
## ([method validate] refuses the "_pct" keys that would replace one), so scaling it is right.
static func resolve(entry: Dictionary, rank: int) -> Dictionary:
	var out: Dictionary = entry.duplicate(true)
	if rank <= 1:
		return out
	match _name(out.get("kind")):
		&"stats":
			if typeof(out.get("stats")) == TYPE_DICTIONARY:
				_scale_all(out["stats"], rank)
		&"ability":
			var mods: Variant = out.get("mods")
			if typeof(mods) == TYPE_DICTIONARY:
				for key: Variant in mods:
					var k := String(key)
					if (k.ends_with("_add") or k.ends_with("_pct")) and _is_number(mods[key]):
						mods[key] = mods[key] * rank
		&"damage", &"damage_taken":
			if _is_number(out.get("pct")):
				out["pct"] = out["pct"] * rank
		&"resource":
			for key: Variant in out:
				if String(key).ends_with("_add") and _is_number(out[key]):
					out[key] = out[key] * rank
		&"proc":
			var p: Variant = out.get("proc")
			var scale: Variant = out.get("scale", [])
			if typeof(p) == TYPE_DICTIONARY and typeof(scale) == TYPE_ARRAY:
				for key: Variant in scale:
					var k := str(key)
					if not p.has(k):
						continue
					if typeof(p[k]) == TYPE_DICTIONARY:
						_scale_all(p[k], rank)
					elif _is_number(p[k]):
						p[k] = p[k] * rank
	return out


static func _scale_all(d: Dictionary, rank: int) -> void:
	for key: Variant in d:
		if _is_number(d[key]):
			d[key] = d[key] * rank


# --- Matching ----------------------------------------------------------------------------------

## True when [param ability] passes [param filter] (an entry's "match" dict; every key present
## must hold): "id", "ids", "school", "tag", "kind" (core / active / auto), "resource" (the
## resource it spends), "class": true (every ability of [param owner_class], core included –
## general abilities are not). Null ability / empty filter: false – a pseudo id has no
## AbilityData, so lookups by id go through [method matches_id].
static func matches(filter: Dictionary, ability: AbilityData, owner_class: StringName) -> bool:
	if ability == null or filter.is_empty():
		return false
	for key: Variant in filter:
		var v: Variant = filter[key]
		match String(key):
			"id":
				if ability.id != _name(v):
					return false
			"ids":
				if typeof(v) != TYPE_ARRAY:
					return false
				var found := false
				for x: Variant in v:
					if ability.id == _name(x):
						found = true
						break
				if not found:
					return false
			"school":
				if ability.school != _name(v):
					return false
			"tag":
				if _name(v) not in ability.tags:
					return false
			"kind":
				if int(ABILITY_KINDS.get(str(v), -1)) != ability.kind:
					return false
			"resource":
				if ability.resource == &"" or ability.resource != _name(v):
					return false
			"class":
				if typeof(v) != TYPE_BOOL or not v or owner_class == &"" or ability.class_id != owner_class:
					return false
			_:
				return false
	return true


## [method matches] by ability id, pseudo ids included – the lookup PlayerBonuses.ability_mods_for
## uses (Player.ability_mods asks by id, and a PSEUDO_IDS id has no AbilityData, so [method
## matches] alone can never match one). A pseudo id matches only {"id": <that id>} (validate
## allows nothing else for it; generic filters never reach pseudo numbers); any other id goes
## through [method matches] with its Db ability (false when unknown).
static func matches_id(filter: Dictionary, ability_id: StringName, owner_class: StringName) -> bool:
	if PSEUDO_IDS.has(ability_id):
		return filter.size() == 1 and filter.has("id") and _name(filter["id"]) == ability_id
	return matches(filter, Db.get_ability(ability_id), owner_class)


# --- Helpers -----------------------------------------------------------------------------------

static func _is_number(v: Variant) -> bool:
	return typeof(v) in [TYPE_INT, TYPE_FLOAT]


## [param v] as a StringName (Strings in .tres data, StringNames from code); &"" for others.
static func _name(v: Variant) -> StringName:
	if typeof(v) in [TYPE_STRING, TYPE_STRING_NAME]:
		return StringName(v)
	return &""


## "" when [param v] (a name or an array of names) only holds names from [param allowed].
static func _names_error(v: Variant, allowed: Array[StringName], what: String) -> String:
	var list: Array = v if typeof(v) == TYPE_ARRAY else [v]
	if list.is_empty():
		return "%s must not be empty" % what
	for x: Variant in list:
		if _name(x) not in allowed:
			return "unknown %s '%s'" % [what, str(x)]
	return ""
