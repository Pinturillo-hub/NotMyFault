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
enum Phase { LOBBY, WORKING, BOSS_INSPECTION, BOARDROOM_VOTING, ENDED }
enum Role  { UNASSIGNED, INNOCENT, LIABILITY }

const VOTING_DURATION: float = 45.0
const VOTING_INCONCLUSIVE_CHAOS: float = 25.0

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
@export var voting_active: bool = false
@export var voting_time_left: float = 0.0

# ---------------------------------------------------------------------------
# Private
# ---------------------------------------------------------------------------
var _votes: Dictionary = {}                 # voter_id (int) → target_id (int)
var _voting_resolved: bool = false
var _vote_target_id: int = -1
## Pre-vote transforms, used to send players back if the meeting is inconclusive.
var _posiciones_antes_votacion: Dictionary = {}

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Keep processing enabled on every peer; _process checks authoritative
	# status itself. Doing it here would be unreliable because the scene loads
	# before the host/join choice assigns the MultiplayerPeer.
	set_process(true)

func _process(delta: float) -> void:
	if current_phase != Phase.BOARDROOM_VOTING:
		return
	if _voting_resolved:
		return

	# All peers count down locally so every client HUD shows the same timer;
	# only the server resolves when it reaches 0.
	voting_time_left = maxf(voting_time_left - delta, 0.0)
	if not es_servidor_activo():
		return
	if voting_time_left <= 0.0:
		_resolve_vote()

## True only when a MultiplayerPeer is active and we are the server.
## Safe to call every frame, unlike multiplayer.is_server() after a disconnect.
func es_servidor_activo() -> bool:
	var peer := multiplayer.multiplayer_peer
	if peer == null:
		return false
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	return multiplayer.is_server()

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

## Starts the 45-second Boardroom vote. Called by the red phone.
func start_voting() -> void:
	if not multiplayer.is_server():
		return
	if current_phase != Phase.WORKING:
		return

	_votes.clear()
	_voting_resolved = false
	voting_active = true
	voting_time_left = VOTING_DURATION
	_guardar_posiciones_antes_de_votar()
	_teleportar_jugadores_a_sala_juntas()
	current_phase = Phase.BOARDROOM_VOTING
	_broadcast_voting_started.rpc(VOTING_DURATION)

## Stores one vote. The result is only resolved when the timer ends (or when
## every eligible player has voted).
func submit_vote(voter_id: int, target_id: int) -> void:
	if not multiplayer.is_server():
		return
	if current_phase != Phase.BOARDROOM_VOTING:
		return
	if not roles.has(voter_id):
		return
	if voter_id == target_id:
		return

	_votes[voter_id] = target_id
	_vote_target_id = target_id

	if _votes.size() >= roles.size():
		_resolve_vote()

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

# ---------------------------------------------------------------------------
# Boardroom teleport
# ---------------------------------------------------------------------------

func _guardar_posiciones_antes_de_votar() -> void:
	_posiciones_antes_votacion.clear()
	for p in get_tree().get_nodes_in_group("jugadores"):
		var id := p.name.to_int()
		var nodo := p as Node3D
		_posiciones_antes_votacion[id] = {
			"pos": nodo.global_position,
			"yaw": nodo.global_rotation.y,
		}

func _teleportar_jugadores_a_sala_juntas() -> void:
	var sala := get_tree().get_first_node_in_group("sala_juntas")
	if sala == null:
		push_warning("GameManager: no se encontró ningún nodo en el grupo 'sala_juntas'.")
		return

	var centro_nodo := sala.get_node_or_null("PuntoCentro") as Node3D
	var centro: Vector3 = (
		centro_nodo.global_position
		if centro_nodo != null
		else (sala as Node3D).global_position
	)

	var ids: Array[int] = []
	for p in get_tree().get_nodes_in_group("jugadores"):
		ids.append(p.name.to_int())
	ids.sort()
	var total := ids.size()
	if total == 0:
		return

	# Place players evenly on a circle around the table, facing its centre.
	for i in total:
		var angulo := TAU * float(i) / float(total)
		var pos := centro + Vector3(cos(angulo), 0.0, sin(angulo)) * 2.2
		var yaw := atan2(-(centro.x - pos.x), -(centro.z - pos.z))
		var jugador := _find_player_node(ids[i])
		if jugador == null:
			continue
		if ids[i] == multiplayer.get_unique_id() and multiplayer.is_server():
			jugador.call("teleport_to", pos, yaw)
		else:
			jugador.rpc_id(ids[i], "_rpc_teleport_to_boardroom", pos, yaw)

func _devolver_jugadores_desde_sala_juntas() -> void:
	if _posiciones_antes_votacion.is_empty():
		return
	for p in get_tree().get_nodes_in_group("jugadores"):
		var id := p.name.to_int()
		if not _posiciones_antes_votacion.has(id):
			continue
		var datos: Dictionary = _posiciones_antes_votacion[id]
		var pos: Vector3 = datos["pos"]
		var yaw: float = datos["yaw"]
		if id == multiplayer.get_unique_id() and multiplayer.is_server():
			p.call("teleport_to", pos, yaw)
		else:
			p.rpc_id(id, "_rpc_teleport_to_boardroom", pos, yaw)
	_posiciones_antes_votacion.clear()

func _find_player_node(id: int) -> Node:
	for p in get_tree().get_nodes_in_group("jugadores"):
		if p.name.to_int() == id:
			return p
	return null

# ---------------------------------------------------------------------------
# Voting resolution (Qualified Majority)
# ---------------------------------------------------------------------------

func _resolve_vote() -> void:
	if not multiplayer.is_server():
		return
	if current_phase != Phase.BOARDROOM_VOTING or _voting_resolved:
		return

	_voting_resolved = true
	voting_active = false
	voting_time_left = 0.0

	# Whoever did not vote in time has their vote turned against themselves.
	if _votes.size() < roles.size():
		for voter_id in roles:
			if not _votes.has(voter_id):
				_votes[voter_id] = voter_id

	var total_voters := roles.size()
	var required := int(ceil(float(total_voters) * 0.5))

	var counts: Dictionary = {}
	for voter_id in _votes:
		var target_id: int = int(_votes[voter_id])
		counts[target_id] = int(counts.get(target_id, 0)) + 1

	var top_target := -1
	var top_votes := 0
	var tied := false
	for target_id in counts:
		var votes: int = int(counts[target_id])
		if votes > top_votes:
			top_target = target_id
			top_votes = votes
			tied = false
		elif votes == top_votes:
			tied = true

	# No qualified majority (empty, tied or dispersed votes): the meeting fails.
	if top_target == -1 or tied or top_votes < required:
		_resolve_inconclusive_vote()
		return

	if top_target == _get_liability_id():
		_end_game(GameResult.VOTE_CORRECT)
	else:
		_end_game(GameResult.VOTE_WRONG)

func _resolve_inconclusive_vote() -> void:
	_votes.clear()
	_vote_target_id = -1
	voting_active = false
	voting_time_left = 0.0

	# Provisional reveal: show the verdict briefly before returning to work.
	# _voting_resolved stays true so _process does not resolve again during it.
	_broadcast_resultado.rpc("🕊️ REUNIÓN INCONCLUYENTE\nNo hay mayoría clara.\n¡El Jefe está furioso!")
	await get_tree().create_timer(2.5).timeout

	# Everyone returns to work, the Boss is angered and the phone breaks.
	_devolver_jugadores_desde_sala_juntas()
	_broadcast_vote_inconclusive.rpc()

	var boss := get_tree().get_first_node_in_group("boss_manager")
	if boss and boss.has_method("agregar_caos"):
		boss.agregar_caos(VOTING_INCONCLUSIVE_CHAOS)

	var telefono := get_tree().get_first_node_in_group("telefono_rojo")
	if telefono and telefono.has_method("romper"):
		telefono.romper()

func _evaluate_end_of_day() -> void:
	var objetos := _get_illegal_objects()

	# Fallback for scenes without a physical illegal object (legacy flag).
	if objetos.is_empty():
		if broken_object_repaired:
			_end_game(GameResult.LIABILITY_REPAIRED)
		else:
			_end_game(GameResult.INNOCENTS_SURVIVED)
		return

	var todas_reparadas := true
	var todas_en_pedestal := true

	for obj in objetos:
		if not _is_object_repaired(obj):
			todas_reparadas = false
			break
		if not _is_object_on_pedestal(obj):
			todas_en_pedestal = false

	# GDD: repaired AND back on its original pedestal = perfect crime (Torpe wins).
	if todas_reparadas and todas_en_pedestal:
		_end_game(GameResult.LIABILITY_REPAIRED)
	else:
		_end_game(GameResult.INNOCENTS_SURVIVED)

func _run_inspection_logic() -> void:
	# Called server-side after clients receive the RPC.
	await get_tree().create_timer(3.0).timeout

	if current_phase != Phase.BOSS_INSPECTION:
		return  # State changed while waiting — abort.

	var liability_id := _get_liability_id()
	var objetos := _get_illegal_objects()

	if objetos.is_empty():
		_end_game_false_alarm.rpc()
		return

	# --- Pass 1: broken objects have priority, wherever they are ---
	# GDD 3.2: broken on an Innocent -> Torpe wins; broken on the Torpe ->
	# Innocents win; broken left on the floor -> everyone loses.
	for obj in objetos:
		if _is_object_repaired(obj):
			continue

		var portador := _get_object_holder_id(obj)
		if portador != 0:
			if portador == liability_id:
				_end_game(GameResult.BOSS_CAUGHT_LIABILITY)
			else:
				_end_game(GameResult.BOSS_CAUGHT_INNOCENT)
			return

		# Broken and nobody is carrying it: it is exposed on the floor.
		_end_game(GameResult.BOSS_FOUND_OBJECT_FLOOR)
		return

	# --- Pass 2: repaired objects ---
	# GDD 3.2: repaired but still in the Torpe's hands (not on its pedestal)
	# while the Boss storms out because of chaos -> everyone loses.
	for obj in objetos:
		if not _is_object_repaired(obj):
			continue
		if _get_object_holder_id(obj) == liability_id and not _is_object_on_pedestal(obj):
			_end_game(GameResult.BOSS_FOUND_REPAIRED_ON_LIABILITY)
			return

	# --- Nothing incriminating — false alarm ---
	_end_game_false_alarm.rpc()

# ---------------------------------------------------------------------------
# Inspection helpers (dynamic access keeps the autoload decoupled)
# ---------------------------------------------------------------------------

func _get_illegal_objects() -> Array[Node]:
	return get_tree().get_nodes_in_group("ilegal")

func _is_object_repaired(obj: Node) -> bool:
	return obj.get("esta_reparado") == true

func _is_object_on_pedestal(obj: Node) -> bool:
	if obj.has_method("esta_en_pedestal"):
		return bool(obj.call("esta_en_pedestal"))
	return false

## Returns the peer id carrying the object (hand, tug-of-war or pocket), or 0.
func _get_object_holder_id(obj: Node) -> int:
	var en_bolsillo: Variant = obj.get("en_bolsillo_de_id")
	if en_bolsillo != null and int(en_bolsillo) != 0:
		return int(en_bolsillo)

	var id1: Variant = obj.get("id_sostenedor_1")
	if id1 != null and int(id1) != 0:
		return int(id1)

	var id2: Variant = obj.get("id_sostenedor_2")
	if id2 != null and int(id2) != 0:
		return int(id2)

	return 0

func _end_game(result: GameResult) -> void:
	voting_active = false
	voting_time_left = 0.0
	_posiciones_antes_votacion.clear()
	current_phase = Phase.ENDED
	_broadcast_end.rpc(result)

# ---------------------------------------------------------------------------
# RPCs
# ---------------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _sync_roles(role_dict: Dictionary) -> void:
	roles = role_dict
	# Clients must also enter the working phase; otherwise their local
	# GameManager stays in LOBBY and interactions are rejected.
	current_phase = Phase.WORKING
	var my_id := multiplayer.get_unique_id()
	if my_id in roles:
		role_assigned.emit(my_id, roles[my_id])
		var nombre_rol := "INOCENTE"
		if roles[my_id] == Role.LIABILITY:
			nombre_rol = "TORPE"
		print("[ROL] peer ", my_id, " = ", nombre_rol)

@rpc("authority", "call_local", "reliable")
func _broadcast_voting_started(duration: float) -> void:
	current_phase = Phase.BOARDROOM_VOTING
	voting_active = true
	voting_time_left = duration
	# Each peer opens the ballot locally for its own player.
	var telefono := get_tree().get_first_node_in_group("telefono_rojo")
	if telefono and telefono.has_method("abrir_ui_local"):
		telefono.abrir_ui_local(multiplayer.get_unique_id())

@rpc("authority", "call_local", "reliable")
func _broadcast_vote_inconclusive() -> void:
	current_phase = Phase.WORKING
	voting_active = false
	voting_time_left = 0.0
	var ui := get_tree().get_first_node_in_group("voting_ui")
	if ui and ui.has_method("cerrar_ui"):
		ui.cerrar_ui()

@rpc("authority", "call_local", "reliable")
func _run_inspection() -> void:
	current_phase = Phase.BOSS_INSPECTION
	if multiplayer.is_server():
		_run_inspection_logic()

@rpc("authority", "call_local", "reliable")
func _broadcast_end(result: GameResult) -> void:
	current_phase = Phase.ENDED
	voting_active = false
	voting_time_left = 0.0
	# Provisional end feedback: show the verdict instead of closing the HUD.
	var ui := get_tree().get_first_node_in_group("voting_ui")
	if ui and ui.has_method("mostrar_resultado"):
		ui.mostrar_resultado(_resultado_texto(result))
	game_ended.emit(result)

## Shows a provisional result banner on every peer (used before a non-final
## transition such as an inconclusive meeting).
@rpc("authority", "call_local", "reliable")
func _broadcast_resultado(mensaje: String) -> void:
	var ui := get_tree().get_first_node_in_group("voting_ui")
	if ui and ui.has_method("mostrar_resultado"):
		ui.mostrar_resultado(mensaje)

## Provisional Spanish text for each ending. Placeholder until real end screens.
func _resultado_texto(result: GameResult) -> String:
	match result:
		GameResult.VOTE_CORRECT:
			return "✅ HABÉIS DESPEDIDO AL TORPE\n¡Ganáis los inocentes!"
		GameResult.VOTE_WRONG:
			return "❌ HABÉIS DESPEDIDO A UN INOCENTE\n¡Gana el Torpe!"
		GameResult.LIABILITY_REPAIRED:
			return "🕵️ EL TORPE LO ARREGLÓ A TIEMPO\n¡Gana el Torpe!"
		GameResult.INNOCENTS_SURVIVED:
			return "☀️ FIN DE JORNADA\nEl objeto sigue roto: ganan los inocentes."
		GameResult.BOSS_CAUGHT_INNOCENT:
			return "😱 EL JEFE PILLÓ A UN INOCENTE\n¡Gana el Torpe!"
		GameResult.BOSS_CAUGHT_LIABILITY:
			return "🚨 EL JEFE PILLÓ AL TORPE\n¡Ganáis los inocentes!"
		GameResult.BOSS_FOUND_OBJECT_FLOOR:
			return "💥 OBJETO ROTO EN EL SUELO\n¡Pierde todo el mundo!"
		GameResult.BOSS_FOUND_REPAIRED_ON_LIABILITY:
			return "💥 EL TORPE LO LLEVABA ENCIMA\n¡Pierde todo el mundo!"
	return "FIN DE LA PARTIDA"

@rpc("authority", "call_local", "reliable")
func _end_game_false_alarm() -> void:
	current_phase = Phase.WORKING
	var boss := get_tree().get_first_node_in_group("boss_manager")
	if boss and boss.has_method("reset_after_false_alarm"):
		boss.reset_after_false_alarm()
