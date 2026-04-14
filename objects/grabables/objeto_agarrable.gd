## ObjetoAgarrable — Base class for all grabbable physics objects.
##
## Responsibilities (this class only):
##   • Spring-joint physics while held
##   • Grab / release / tug-of-war authority (server-authoritative)
##   • Pocket enter/exit
##   • Collision exception management
##
## NOT responsible for: gameplay logic, role checks, win conditions.
extends RigidBody3D
class_name ObjetoAgarrable

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
const SPRING_STIFFNESS  : float = 150.0
const SPRING_DAMPING    : float = 10.0
const ANGULAR_STIFFNESS : float = 10.0
const ANGULAR_DAMPING   : float = 2.0
const LIMBO_POSITION    : Vector3 = Vector3(0.0, -200.0, 0.0)
const TUG_RESOLVE_DELAY : float  = 1.5
const TUG_WIN_MARGIN    : float  = 5.0

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------
@export_group("Config")
@export var es_ilegal: bool = false
@export var usar_animacion_golpe: bool = true
@export var distancia_golpe: float = 0.5

@export_group("Visuals")
@export var malla_normal: Node3D
@export var malla_rota:   Node3D

# ---------------------------------------------------------------------------
# Synchronized state
# ---------------------------------------------------------------------------
## Primary holder peer id (0 = nobody)
@export var id_sostenedor_1: int = 0
## Secondary holder peer id during tug-of-war (0 = nobody)
@export var id_sostenedor_2: int = 0
## True while tug-of-war is active
@export var en_disputa: bool = false
## True when held with strong grip (prevents second grab)
@export var agarre_fuerte: bool = false
## Peer id of the player who pocketed this object (0 = nobody)
@export var en_bolsillo_de_id: int = 0

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
signal disputa_iniciada
signal disputa_finalizada(ganador_id: int)

# ---------------------------------------------------------------------------
# Private state
# ---------------------------------------------------------------------------
var _target_position: Vector3  = Vector3.ZERO
var _target_rotation: Quaternion = Quaternion.IDENTITY
var _time_since_last_order: float = 0.0
var _pending_order: bool = false
var _tug_force_holder_1: float = 0.0
var _tug_force_holder_2: float = 0.0
var _stiffness_multiplier: float = 1.0
var _original_collision_mask: int = 0
var _teleport_frames: int = 0
## Cancellation token for tug-of-war coroutine
var _tug_active: bool = false

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	can_sleep = false
	_original_collision_mask = collision_mask
	add_to_group("agarrables")
	if es_ilegal:
		add_to_group("ilegal")
	_set_visual_state(false)

func _process(_delta: float) -> void:
	# If nobody holds us and collision_layer was cleared, restore it.
	if en_bolsillo_de_id == 0 and id_sostenedor_1 == 0 and id_sostenedor_2 == 0:
		if collision_layer == 0:
			_configure_physics_free()

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if en_bolsillo_de_id != 0:
		_apply_limbo(state)
		return

	if _teleport_frames > 0:
		state.transform.origin = _target_position
		state.linear_velocity  = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		_teleport_frames -= 1
		return

	if not multiplayer.is_server():
		return

	_time_since_last_order += state.step

	if (id_sostenedor_1 != 0 or id_sostenedor_2 != 0) and _time_since_last_order < 0.5:
		if _pending_order:
			_apply_spring_forces(state)

func _apply_limbo(state: PhysicsDirectBodyState3D) -> void:
	state.transform.origin = LIMBO_POSITION
	state.linear_velocity  = Vector3.ZERO
	state.angular_velocity = Vector3.ZERO

func _apply_spring_forces(state: PhysicsDirectBodyState3D) -> void:
	var delta_pos := _target_position - state.transform.origin
	var effective_stiffness := SPRING_STIFFNESS * _stiffness_multiplier
	var force := (delta_pos * effective_stiffness) - (state.linear_velocity * SPRING_DAMPING)
	state.apply_central_force(force)

	var clean_basis := state.transform.basis.orthonormalized()
	var current_rot := Quaternion(clean_basis)
	var rot_delta   := current_rot.inverse() * _target_rotation
	var axis        := rot_delta.get_axis()
	var angle       := rot_delta.get_angle()
	if angle > PI:
		angle -= TAU
	var torque_local  := axis * angle * ANGULAR_STIFFNESS
	var torque_global := clean_basis * torque_local - state.angular_velocity * ANGULAR_DAMPING
	state.apply_torque(torque_global)
	_pending_order = false

# ---------------------------------------------------------------------------
# Public API — Grab / Release
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func intentar_coger(solicitante_id: int) -> void:
	if not multiplayer.is_server():
		return
	# Edge case: object was in this player's pocket
	if en_bolsillo_de_id == solicitante_id:
		en_bolsillo_de_id = 0
		_configure_physics_free()
	# Blocked: someone else's pocket
	if en_bolsillo_de_id != 0 and en_bolsillo_de_id != solicitante_id:
		return

	if id_sostenedor_1 == 0:
		_assign_holder(solicitante_id)
	elif id_sostenedor_1 != solicitante_id and id_sostenedor_2 == 0:
		if agarre_fuerte:
			_start_tug_of_war(solicitante_id)
		else:
			_assign_holder(solicitante_id)

@rpc("any_peer", "call_local", "reliable")
func intentar_soltar(solicitante_id: int, impulso: Vector3) -> void:
	if not multiplayer.is_server():
		return
	if impulso != Vector3.ZERO:
		apply_central_impulse(impulso)
	_remove_collision_exception(solicitante_id)
	if id_sostenedor_1 == solicitante_id:
		id_sostenedor_1 = 0
	elif id_sostenedor_2 == solicitante_id:
		id_sostenedor_2 = 0
	if id_sostenedor_1 == 0 and id_sostenedor_2 == 0:
		_configure_physics_free()
		en_disputa = false
	_broadcast_state.rpc(id_sostenedor_1, id_sostenedor_2, en_disputa)

@rpc("any_peer", "call_local", "reliable")
func actualizar_tipo_agarre(es_fuerte: bool) -> void:
	if multiplayer.get_remote_sender_id() == id_sostenedor_1:
		agarre_fuerte = es_fuerte

# ---------------------------------------------------------------------------
# Public API — Movement update (unreliable, high frequency)
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_local", "unreliable_ordered")
func actualizar_objetivo_agarre(posicion: Vector3, rotacion: Quaternion, id_jugador: int) -> void:
	if not multiplayer.is_server():
		return
	if id_sostenedor_1 != id_jugador and id_sostenedor_2 != id_jugador:
		return
	_target_position      = posicion
	_target_rotation      = rotacion
	_time_since_last_order = 0.0
	_pending_order        = true

# ---------------------------------------------------------------------------
# Public API — Pocket
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func entrar_en_bolsillo(id_dueno: int) -> void:
	en_bolsillo_de_id = id_dueno
	id_sostenedor_1   = 0
	id_sostenedor_2   = 0
	en_disputa        = false
	_configure_physics_pocket()

@rpc("any_peer", "call_local", "reliable")
func salir_de_bolsillo(posicion_salida: Vector3) -> void:
	en_bolsillo_de_id = 0
	_teleport_to(posicion_salida)
	_configure_physics_free()

# ---------------------------------------------------------------------------
# Public API — Use / Steal
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_local")
func usar_objeto() -> void:
	if usar_animacion_golpe:
		_activate_ghost_mode.rpc(0.4)

@rpc("any_peer", "call_local", "reliable")
func modificar_rigidez_temporal(factor: float, duracion: float) -> void:
	_stiffness_multiplier = factor
	await get_tree().create_timer(duracion).timeout
	_stiffness_multiplier = 1.0

## Called server-side from the steal system in Jugador.
func ejecutar_robo_desde_servidor(nuevo_dueno_id: int, pos_salida: Vector3) -> void:
	en_bolsillo_de_id = 0
	_teleport_to(pos_salida)
	_assign_holder(nuevo_dueno_id)
	_target_position = pos_salida
	_target_rotation = Quaternion(global_transform.basis.orthonormalized())
	_notify_pocket_exit_steal.rpc(pos_salida)

@rpc("call_local", "reliable")
func _notify_pocket_exit_steal(posicion: Vector3) -> void:
	en_bolsillo_de_id = 0
	_teleport_to(posicion)
	visible = true
	if has_method("reset_physics_interpolation"):
		reset_physics_interpolation()

# ---------------------------------------------------------------------------
# Tug-of-war
# ---------------------------------------------------------------------------

func _start_tug_of_war(retador_id: int) -> void:
	id_sostenedor_2 = retador_id
	en_disputa      = true
	_tug_active     = true
	_broadcast_state.rpc(id_sostenedor_1, id_sostenedor_2, true)
	disputa_iniciada.emit()
	_resolve_tug_of_war()

func _resolve_tug_of_war() -> void:
	await get_tree().create_timer(TUG_RESOLVE_DELAY).timeout
	if not _tug_active:
		return  # Was cancelled (e.g. someone let go during the wait)
	_tug_active = false
	var winner := id_sostenedor_1
	if _tug_force_holder_2 > (_tug_force_holder_1 + TUG_WIN_MARGIN):
		winner = id_sostenedor_2
	_tug_force_holder_1 = 0.0
	_tug_force_holder_2 = 0.0
	_assign_holder(winner)

@rpc("any_peer", "call_local", "unreliable")
func enviar_fuerza_tiro(fuerza: float) -> void:
	if not en_disputa:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == id_sostenedor_1:
		_tug_force_holder_1 += fuerza
	elif sender == id_sostenedor_2:
		_tug_force_holder_2 += fuerza

# ---------------------------------------------------------------------------
# Physics configuration helpers
# ---------------------------------------------------------------------------

func _configure_physics_free() -> void:
	visible = true
	set_deferred("freeze", false)
	set_deferred("sleeping", false)
	set_deferred("collision_layer", _original_collision_mask)
	set_deferred("collision_mask",  _original_collision_mask)
	gravity_scale = 1.0

func _configure_physics_held() -> void:
	set_deferred("collision_layer", _original_collision_mask)
	set_deferred("collision_mask",  _original_collision_mask)
	gravity_scale = 0.0
	visible = true
	set_deferred("freeze", false)
	set_deferred("sleeping", false)

func _configure_physics_pocket() -> void:
	set_deferred("freeze", true)
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask",  0)
	gravity_scale = 0.0
	linear_velocity  = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_position  = LIMBO_POSITION
	if has_method("reset_physics_interpolation"):
		reset_physics_interpolation()
	visible = false

# ---------------------------------------------------------------------------
# Ghost mode (pass through objects briefly when striking)
# ---------------------------------------------------------------------------

@rpc("call_local")
func _activate_ghost_mode(duration: float) -> void:
	# Remove layer 3 (small objects) from mask temporarily.
	var ghost_mask := collision_mask & ~(1 << 2)
	collision_mask = ghost_mask
	await get_tree().create_timer(duration).timeout
	if id_sostenedor_1 != 0:
		collision_mask = _original_collision_mask

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _assign_holder(new_id: int) -> void:
	_remove_collision_exception(id_sostenedor_1)
	id_sostenedor_1   = new_id
	id_sostenedor_2   = 0
	en_disputa        = false
	agarre_fuerte     = false
	en_bolsillo_de_id = 0
	_tug_active       = false
	_configure_physics_held()
	if new_id != 0:
		_add_collision_exception(new_id)
	_broadcast_state.rpc(id_sostenedor_1, 0, false)
	disputa_finalizada.emit(new_id)

func _teleport_to(pos: Vector3) -> void:
	global_position  = pos
	_target_position = pos
	_teleport_frames = 2
	var xform := Transform3D(global_transform.basis, pos)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xform)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY,  Vector3.ZERO)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)

func _set_visual_state(is_broken: bool) -> void:
	if malla_normal: malla_normal.visible = not is_broken
	if malla_rota:   malla_rota.visible   = is_broken

func _add_collision_exception(player_id: int) -> void:
	var player := _find_player(player_id)
	if player:
		player.add_collision_exception_with(self)

func _remove_collision_exception(player_id: int) -> void:
	if player_id == 0:
		return
	var player := _find_player(player_id)
	if player and is_instance_valid(player):
		player.remove_collision_exception_with(self)

func _find_player(id: int) -> Node:
	var root := get_tree().root
	# Try canonical path first, then fallback to group search.
	var path := "/root/Mundo/Jugadores/%d" % id
	var node := root.get_node_or_null(path)
	if node:
		return node
	for p in get_tree().get_nodes_in_group("jugadores"):
		if p.name.to_int() == id:
			return p
	return null

# ---------------------------------------------------------------------------
# State broadcast
# ---------------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _broadcast_state(id1: int, id2: int, disputando: bool) -> void:
	id_sostenedor_1 = id1
	id_sostenedor_2 = id2
	en_disputa      = disputando
	if disputando:
		disputa_iniciada.emit()
	else:
		disputa_finalizada.emit(id1)
