class_name GoblinSpawner
extends Node
## The Loot Goblin's spawner (GDD 8, M5, architecture §2.6): a child of the WaveDirector
## (PAUSABLE) that decides once per wave whether a Loot Goblin comes and when, and announces
## it ([signal announced] → Main → Hud.show_banner).
##
## P0 stub: created and wired by Main, no behaviour (never spawns, never announces). GOBLIN
## implements it.

## Banner text for the HUD ("A Loot Goblin appeared!", gold / "The Loot Goblin escaped!", grey).
signal announced(text: String, color: Color)

const BASE_CHANCE := 0.15
## Chance added per point of the team's highest Fortune.
const CHANCE_PER_FORTUNE := 0.005
const MAX_CHANCE := 0.5
## Seconds before the goblin opens its portal.
const ESCAPE_TIME := 15.0

## --goblin-chance (0..1; < 0 = the normal chance). RunState.start_run resets it to -1, then Main
## applies the launch option.
static var chance_override := -1.0

var director: WaveDirector
## The living goblin of this wave (GOBLIN types it as its LootGoblin).
var goblin: Enemy


static func create(p_director: WaveDirector) -> GoblinSpawner:
	var s := GoblinSpawner.new()
	s.name = "GoblinSpawner"
	s.director = p_director
	return s


## Spawn chance in wave [param _wave] with the team's highest Fortune [param _team_fortune]
## (0 below wave 3 and on boss / elite waves).
static func chance_for(_wave: int, _team_fortune: float) -> float:
	return 0.0


## Highest Fortune of the living heroes.
static func team_fortune() -> float:
	return 0.0


## Seconds into the wave the goblin will spawn (-1 = none this wave).
func pending_time() -> float:
	return -1.0
