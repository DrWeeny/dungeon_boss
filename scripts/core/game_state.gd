extends Node

## Autoload (GameState): holds the current GameSession and emits change signals
## for the UI. All rules live in GameSession so they stay testable headless.

signal changed
signal wave_finished(result: WaveSim.WaveResult)

var session: GameSession


func _ready() -> void:
	new_game()


func new_game(p_seed: int = -1, p_difficulty: GameSession.Difficulty = GameSession.Difficulty.NORMAL) -> void:
	session = GameSession.new(p_seed, p_difficulty)
	changed.emit()


func place_content(room: Room, def: ContentDef) -> bool:
	var ok := session.place_content(room, def)
	if ok:
		changed.emit()
	return ok


func remove_content(room: Room, idx: int) -> bool:
	var ok := session.remove_content(room, idx)
	if ok:
		changed.emit()
	return ok


func place_modifier(elem: StructuralElement, def: ContentDef) -> bool:
	var ok := session.place_modifier(elem, def)
	if ok:
		changed.emit()
	return ok


func remove_modifier(elem: StructuralElement, idx: int) -> bool:
	var ok := session.remove_modifier(elem, idx)
	if ok:
		changed.emit()
	return ok


func build_room(from_id: String, size: Room.Size, to_id: String = "") -> bool:
	var n := session.build_room(from_id, size, to_id)
	if n != null:
		changed.emit()
	return n != null


func run_wave() -> WaveSim.WaveResult:
	if session.game_over:
		return null
	var res := session.run_wave()
	wave_finished.emit(res)
	changed.emit()
	return res
