class_name PadIdentity
extends RefCounted
## What identifies one physical (or virtual) controller beyond its joypad id. Godot hands out joypad ids lowest
## free first, so after a disconnect the same id may belong to a different pad: a slot never trusts "joy:N"
## alone, it remembers this fingerprint from the moment the player joined (see [PlayerSlot.identity]).

var device := -1
var pad_name := ""
var guid := ""
var vendor_id := ""
var product_id := ""
## The Steam Input handle of a Steam-provided virtual pad (Input.get_joy_info "steam_input_index"); "" for any other pad.
var steam_input_index := ""


## From what Godot knows about [param p_device] right now (an empty identity for an id that is not connected).
static func read(p_device: int) -> PadIdentity:
	var id := PadIdentity.new()
	id.device = p_device
	id.pad_name = Input.get_joy_name(p_device)
	id.guid = Input.get_joy_guid(p_device)
	var info := Input.get_joy_info(p_device)
	id.vendor_id = String(info.get("vendor_id", ""))
	id.product_id = String(info.get("product_id", ""))
	id.steam_input_index = String(info.get("steam_input_index", ""))
	return id


## A made-up pad (tests, the fake pad source).
static func make(p_device: int, p_name: String = "Fake Pad", p_guid: String = "", p_steam_index: String = "",
		p_vendor: String = "", p_product: String = "") -> PadIdentity:
	var id := PadIdentity.new()
	id.device = p_device
	id.pad_name = p_name
	id.guid = p_guid
	id.steam_input_index = p_steam_index
	id.vendor_id = p_vendor
	id.product_id = p_product
	return id


## The id-independent description of the pad: two identities with the same fingerprint are the same pad (or an
## identical model: nothing more can be known).
func fingerprint() -> String:
	return "%s|%s:%s|%s|%s" % [guid, vendor_id, product_id, steam_input_index, pad_name]


## True when [param other] is the same pad (the joypad id is not compared).
func same_pad(other: PadIdentity) -> bool:
	return other != null and fingerprint() == other.fingerprint()
