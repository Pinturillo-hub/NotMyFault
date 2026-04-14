## GameManager — Autoload singleton
## Authoritative game state: roles, phase, win/loss logic.
## All mutating methods are server-only; clients receive state via MultiplayerSynchronizer.
extends Node

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
signal game_phase_changed(new_phase: Phase)
signal role_assigned(player_id: int, role: Role)
signal game_ended(result: GameResult)

# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------
enum Phase { LOBBY, WORKING, BOSS_INSPECTION, ENDED }
enum Role  { UNASSIGNED, INNOCENT, LIABILITY }

enum GameResult {
	LIABILITY_REPAIRED,          # Liability fixed object, 18:00 reached → Liability wins
	INNOCENTS_SURVIVED,          # 18:00 reached, object still broken → Innocents win
	BOSS_CAUGHT_INNOCENT,        # Boss found broken object on innocent → Liability wins
	BOSS_CAUGHT_LIABILITY,       # Boss found broken object on liability → Innocents win
	BOSS_FOUND_OBJECT_FLOOR,     # Object on floor during inspection → Everyone loses
	BOSS_FOUND_REPAIRED_ON_LIABILITY, # Repaired object in Liability's hand + boss out → Everyone loses
	VOTE_CORRECT,                # Red phone voted correctly → Innocents win
	VOTE_WRONG,                  # Red phone voted incorrectly → Liability wins
}

# ---------------------------------------------------------------------------
# Synchronized state (written server-side, read everywhere)
# ---------------------------------------------------------------------------
@export var current_phase: Phase = Phase.LOBBY :
	set(v):
		if current_phase == v:
			return
		current_phase = v
		game_phase_changed.emit(v)

@export var roles: Dictionary = {}          # player_id (int) → Role
@export var broken_object_repaired: bool = false

# ---------------------------------------------------------------------------
# Private
# ---------------------------------------------------------------------------
var _vote_target_id: int = -1

# ---------------------------------------------------------------------------
# Public API (server-only mutation)
# ---------------------------------------------------------------------------

func start_game(player_ids: Array[int]) -> void:
	assert(multiplayer.is_server(), "start_game must run on server")
	_assign_roles(player_ids)
	current_phase = Phase.WORKING
	_sync_roles.rpc(roles)

func get_role(player_id: int) -> Role:
	return roles.get(player_id, Role.UNASSIGNED)

func notify_object_repaired() -> void:
	if not multiplayer.is_server():
		return
	broken_object_repaired = true

func trigger_boss_inspection() -> void:
	if not multiplayer.is_server():
		return
	if current_phase != Phase.WORKING:
		return
	current_phase = Phase.BOSS_INSPECTION
	_run_inspection.rpc()

func trigger_end_of_day() -> void:
	if not multiplayer.is_server():
		return
	if current_phase != Phase.WORKING:
		return
	_evaluate_end_of_day()

func submit_vote(_voter_id: int, target_id: int) -> void:
	if not multiplayer.is_server():
		return
	if current_phase != Phase.WORKING:
		return
	_vote_target_id = target_id
	var liability_id := _get_liability_id()
	if target_id == liability_id:
		_end_game(GameResult.VOTE_CORRECT)
	else:
		_end_game(GameResult.VOTE_WRONG)

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

func _assign_roles(player_ids: Array[int]) -> void:
	roles.clear()
	var shuffled := player_ids.duplicate()
	shuffled.shuffle()
	roles[shuffled[0]] = Role.LIABILITY
	for i in range(1, shuffled.size()):
		roles[shuffled[i]] = Role.INNOCENT

func _get_liability_id() -> int:
	for id in roles:
		if roles[id] == Role.LIABILITY:
			return id
	return -1

func _evaluate_end_of_day() -> void:
	if broken_object_repaired:
		_end_game(GameResult.LIABILITY_REPAIRED)
	else:
		_end_game(GameResult.INNOCENTS_SURVIVED)

func _run_inspection_logic() -> void:
	# Called server-side after clients receive the RPC.
	await get_tree().create_timer(3.0).timeout

	if current_phase != Phase.BOSS_INSPECTION:
		return  # State changed while waiting — abort.

	var liability_id := _get_liability_id()

	# --- Check 1: Broken object on the floor (nobody holding it) ---
	for obj in get_tree().get_nodes_in_group("ilegal"):
		# Access properties dynamically — avoids class reference issues in autoload
		var sostenedor : int = obj.get("id_sostenedor_1") if obj.get("id_sostenedor_1") != null else 0
		var en_bolsillo: int = obj.get("en_bolsillo_de_id") if obj.get("en_bolsillo_de_id") != null else 0
		if sostenedor == 0 and en_bolsillo == 0:
			_end_game(GameResult.BOSS_FOUND_OBJECT_FLOOR)
			return

	# --- Check 2: Scan players ---
	for player_node in get_tree().get_nodes_in_group("jugadores"):
		if not player_node.has_method("tiene_objeto_ilegal"):
			continue
		var pid := player_node.name.to_int()

		if not player_node.tiene_objeto_ilegal():
			continue

		# GDD: "Sale el Jefe (Caos) + Reparado en mano de Torpe → TODOS PIERDEN"
		if pid == liability_id and broken_object_repaired:
			_end_game(GameResult.BOSS_FOUND_REPAIRED_ON_LIABILITY)
			return

		if pid == liability_id:
			_end_game(GameResult.BOSS_CAUGHT_LIABILITY)
		else:
			_end_game(GameResult.BOSS_CAUGHT_INNOCENT)
		return

	# --- Nobody caught — false alarm ---
	_end_game_false_alarm.rpc()

func _end_game(result: GameResult) -> void:
	current_phase = Phase.ENDED
	_broadcast_end.rpc(result)

# ---------------------------------------------------------------------------
# RPCs
# ---------------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _sync_roles(role_dict: Dictionary) -> void:
	roles = role_dict
	var my_id := multiplayer.get_unique_id()
	if my_id in roles:
		role_assigned.emit(my_id, roles[my_id])

@rpc("authority", "call_local", "reliable")
func _run_inspection() -> void:
	current_phase = Phase.BOSS_INSPECTION
	if multiplayer.is_server():
		_run_inspection_logic()

@rpc("authority", "call_local", "reliable")
func _broadcast_end(result: GameResult) -> void:
	current_phase = Phase.ENDED
	game_ended.emit(result)

@rpc("authority", "call_local", "reliable")
func _end_game_false_alarm() -> void:
	current_phase = Phase.WORKING
	var boss := get_tree().get_first_node_in_group("boss_manager")
	if boss and boss.has_method("reset_after_false_alarm"):
		boss.reset_after_false_alarm()
