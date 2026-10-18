class_name EnvironmentData
extends Resource
## An arena environment (GDD 16.1, M6b): the look of the battlefield and its hazard. Instances live
## in res://data/environments/ (loaded by Db into Db.environments); the run draws one at its start
## ([member RunState.environment]) and [method Arena.create] builds the arena from it.
##
## Every field defaults to the Forest Ruin, i.e. to what the arena looked like before environments
## existed: [code]Arena.create()[/code] without an environment, [code]EnvironmentData.new()[/code] and
## data/environments/forest_ruin.tres all build the same arena. An environment .tres only lists what
## differs from the forest.
##
## The arena SIZE is the same for every environment (Arena.SIZE is read statically all over the
## game): an environment changes the palette, the decor set and the hazard, never the playable
## rectangle.

@export var id: StringName
@export var display_name := ""
## One line for the roll animation's card and the end screen.
@export_multiline var description := ""
## Share of the environment roll ([code]roll_weight[/code] 0 = never drawn by the roll, but
## --env=<id> still forces it).
@export var roll_weight := 1.0

## Which decor set [method Arena._build_decor] builds: &"forest" (ArenaDecor.build). The ENV package
## adds the others; an id nobody knows builds the forest.
@export var decor_id: StringName = &"forest"
## Which ground hazard the arena runs during a wave (&"" = none). Read by the ENV package's hazard
## director; every hazard is an EnemyHazard (group enemy_hazards).
@export var hazard_id: StringName = &""
## The hazard's name and one rule line for the roll animation's card ("Grasping Hands", "...").
@export var hazard_name := ""
@export_multiline var hazard_text := ""
## The accent of the environment's roll card (frame and name); the forest's leaf green by default.
@export var card_color := Color(0.5, 0.72, 0.3)

# --- Sky, fog and light --------------------------------------------------------------------------
@export var sky_color := Color(0.56, 0.74, 0.92)
@export var ambient_color := Color(0.6, 0.66, 0.8)
@export var ambient_energy := 0.62
@export var fog_color := Color(0.7, 0.8, 0.88)
@export var fog_density := 0.0045
@export var sun_color := Color(1.0, 0.92, 0.78)
@export var sun_energy := 0.92
## Sun direction (Euler degrees).
@export var sun_rotation := Vector3(-52.0, -128.0, 0.0)
@export var glow_intensity := 0.55
@export var saturation := 1.12
@export var contrast := 1.05

# --- Ground (the arena's ground shader) -----------------------------------------------------------
@export var grass_dark := Color(0.2, 0.4, 0.12)
@export var grass_mid := Color(0.33, 0.56, 0.17)
@export var grass_light := Color(0.5, 0.7, 0.23)
@export var grass_warm := Color(0.66, 0.7, 0.26)
@export var dirt_light := Color(0.62, 0.48, 0.3)
@export var dirt_dark := Color(0.42, 0.3, 0.18)
## The dirt road that leaves through the north gate. Off = no road on the ground.
@export var has_road := true
@export var road_width := 1.7

# --- Walls ----------------------------------------------------------------------------------------
## Multiplied onto the wall stones' vertex colours (white = the forest's stone).
@export var wall_tint := Color.WHITE


## True when the environment runs a ground hazard.
func has_hazard() -> bool:
	return hazard_id != &""


## The colours the arena's ground shader paints (grass and dirt; the road is a dirt tone): what a ground
## hazard's marker has to stand out from ([method ArenaHazard.marker_color]).
func floor_colors() -> Array[Color]:
	return [grass_dark, grass_mid, grass_light, grass_warm, dirt_light, dirt_dark]
