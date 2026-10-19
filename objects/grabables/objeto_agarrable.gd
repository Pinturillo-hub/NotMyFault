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
# Weight classes
# ---------------------------------------------------------------------------
## Gameplay weight class. This is the single source of truth for weight:
## physical mass, spring response, carry slowdown, throw speed and grip
## strength all come from CONFIG_PESO. To add a class, add the enum value and
## a matching table entry.
##
## "fuerza_tropiezo" is the minimum throw charge (0..1) this class needs to
## knock a player over on impact: light at 90%, medium at 50%, heavy at 70%.
## "tropiezo" is how long the victim stays down.
enum Peso { LIGERO, MEDIO, PESADO }

const CONFIG_PESO: Dictionary = {
	Peso.LIGERO: {
		"masa": 0.8,
		"muelle": 1.0,
		"gravedad_sostenido": 0.0,
		"arrastre": false,
		"velocidad_arrastre": 0.0,
		"aceleracion_arrastre": 0.0,
		"ralentizacion": 1.0,
		"lanzamiento": 1.3,
		"tiron_max": INF,
		"tropiezo": 0.7,
		"fuerza_tropiezo": 0.9,
	},
	Peso.MEDIO: {
		"masa": 5.0,
		"muelle": 0.8,
		"gravedad_sostenido": 0.0,
		"arrastre": false,
		"velocidad_arrastre": 0.0,
		"aceleracion_arrastre": 0.0,
		"ralentizacion": 0.85,
		"lanzamiento": 0.6,
		"tiron_max": INF,
		"tropiezo": 0.85,
		"fuerza_tropiezo": 0.5,
	},
	Peso.PESADO: {
		"masa": 25.0,
		"muelle": 0.0,
		"gravedad_sostenido": 1.0,
		"arrastre": true,
		"velocidad_arrastre": 3.4,
		"aceleracion_arrastre": 10.0,
		"ralentizacion": 0.5,
		"lanzamiento": 0.3,
		"tiron_max": 1.2,
		"tropiezo": 1.0,
		"fuerza_tropiezo": 0.7,
	},
}

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
const SPRING_STIFFNESS  : float = 150.0
const SPRING_DAMPING    : float = 10.0
const ANGULAR_STIFFNESS : float = 10.0
const ANGULAR_DAMPING   : float = 2.0
const ARRASTRE_GANANCIA : float = 4.0
const ARRASTRE_GIRO     : float = 0.2
const LIMBO_POSITION    : Vector3 = Vector3(0.0, -200.0, 0.0)
## Extra force when both hands of the same player drive the prop.
const FUERZA_DOS_MANOS  : float  = 1.8
## Minimum gap between two impact knocks from the same thrown object.
const GOLPE_COOLDOWN_MS : int    = 600
## Total pull (both players) needed to settle a tug.
const TUG_UMBRAL        : float  = 4.0
## Safety timeout: if nobody reaches the threshold, the current holder keeps it.
const TUG_DURACION_MAX  : float  = 6.0
## Speed the object shoots away at when a tug is abandoned (both stumble).
const TUG_ESCAPE_SPEED  : float  = 7.0
## How close the thief must be to a victim's hand to try a hand steal.
const ROBO_ALCANCE      : float  = 3.5

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------
@export_group("Config")
## Weight class. Overrides any mass set on the scene: mass is derived from it.
@export var peso: Peso = Peso.LIGERO:
	set(valor):
		peso = valor
		if is_node_ready():
			_aplicar_config_peso()
@export var es_ilegal: bool = false
## True when this illegal object has been repaired. GameManager reads this
## during the Boss inspection / end-of-day matrix to tell a broken object
## from a repaired one. Ignored for non-illegal objects.
@export var esta_reparado: bool = false
## Distance (metres) from its spawn point within which the object still
## counts as being on its original pedestal.
@export var radio_pedestal: float = 1.0
## Clue shown to a player who successfully performs a risky inspection while
## this object is hidden in another player's pocket.
@export_multiline var pista_inspeccion: String = ""
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
## Tug-of-war pull accumulated by each holder, replicated for the power UI.
var tug_pull_1: float = 0.0
var tug_pull_2: float = 0.0

# ---------------------------------------------------------------------------
# Public weight values (read by Mano / Jugador; derived from CONFIG_PESO)
# ---------------------------------------------------------------------------
## Carry-speed multiplier (1.0 = no slowdown).
var factor_ralentizacion: float = 1.0
## Throw-speed multiplier.
var factor_lanzamiento: float = 1.0
## Max hand-to-object distance before the grip snaps (INF = never).
var tiron_max: float = INF
## Stumble time applied when the grip snaps or the object knocks a player over.
var tiempo_tropiezo: float = 0.0
## Minimum throw charge (0..1) that knocks a player over on impact.
var fuerza_tropiezo: float = 1.0

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
var _tug_pull_1: float = 0.0
var _tug_pull_2: float = 0.0
var _tug_inicio_ms: int = 0
var _stiffness_multiplier: float = 1.0
var _original_collision_mask: int = 0
var _teleport_frames: int = 0
## Position where the object spawned; used as its original pedestal.
var _posicion_pedestal: Vector3 = Vector3.ZERO
var _pedestal_registrado: bool = false
## Cached weight config (avoid dictionary lookups in the physics loop).
var _escala_muelle: float = 1.0
var _gravedad_sostenido: float = 0.0
var _arrastre: bool = false
var _velocidad_arrastre: float = 0.0
var _aceleracion_arrastre: float = 0.0
## Both hands of the same player hold this object (server-only): extra force.
var agarre_doble: bool = false
## True while this object is flying from a throw (armed for impact knocks).
var _lanzado: bool = false
## Charge (0..1) of the last throw; compared against fuerza_tropiezo.
var _fuerza_lanzamiento: float = 0.0
## Peer id that threw it, so the thrower cannot knock themselves out.
var _ultimo_lanzador_id: int = 0
var _ultimo_golpe_ms: int = 0

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_aplicar_config_peso()
	can_sleep = false
	_original_collision_mask = collision_mask
	_posicion_pedestal = global_position
	_pedestal_registrado = true
	# Needed to detect thrown-object impacts against players.
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_objeto_body_entered)
	add_to_group("agarrables")
	if es_ilegal:
		add_to_group("ilegal")
		if esta_reparado and multiplayer.is_server():
			GameManager.notify_object_repaired()
	_set_visual_state(es_ilegal and not esta_reparado)

## Applies the weight-class table to the physical body and the cached values.
func _aplicar_config_peso() -> void:
	mass = _dato_peso("masa")
	_escala_muelle = _dato_peso("muelle")
	_gravedad_sostenido = _dato_peso("gravedad_sostenido")
	_arrastre = bool(CONFIG_PESO[peso]["arrastre"])
	_velocidad_arrastre = _dato_peso("velocidad_arrastre")
	_aceleracion_arrastre = _dato_peso("aceleracion_arrastre")
	factor_ralentizacion = _dato_peso("ralentizacion")
	factor_lanzamiento = _dato_peso("lanzamiento")
	tiron_max = _dato_peso("tiron_max")
	tiempo_tropiezo = _dato_peso("tropiezo")
	fuerza_tropiezo = _dato_peso("fuerza_tropiezo")

func _dato_peso(clave: String) -> float:
	return float(CONFIG_PESO[peso][clave])

## Heavy props are too big to fit in the blind pocket.
func se_puede_guardar() -> bool:
	return peso != Peso.PESADO

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

	if not GameManager.es_servidor_activo():
		return

	# A contested prop hangs between the two pullers: it does not chase either
	# hand, it just damps in place until the tug resolves.
	if en_disputa:
		state.linear_velocity  *= 0.8
		state.angular_velocity *= 0.8
		return

	_time_since_last_order += state.step

	if (id_sostenedor_1 != 0 or id_sostenedor_2 != 0) and _time_since_last_order < 0.5:
		if _pending_order:
			_apply_spring_forces(state)

func _apply_limbo(state: PhysicsDirectBodyState3D) -> void:
	state.transform.origin = LIMBO_POSITION
	state.linear_velocity  = Vector3.ZERO
	state.angular_velocity = Vector3.ZERO

## A second hand of the same player on the prop multiplies the force.
func _factor_dos_manos() -> float:
	return FUERZA_DOS_MANOS if agarre_doble else 1.0

func _apply_spring_forces(state: PhysicsDirectBodyState3D) -> void:
	# Heavy props use a drag servo instead of the spring: see _apply_drag().
	if _arrastre:
		_apply_drag(state)
		return

	# The response is a property of the weight class, not of the raw mass, so
	# designers tune "feel" in CONFIG_PESO instead of per-object kilograms.
	var fuerza_manos := _factor_dos_manos()
	var delta_pos := _target_position - state.transform.origin
	var force := (delta_pos * SPRING_STIFFNESS * _escala_muelle * _stiffness_multiplier * fuerza_manos) \
		- (state.linear_velocity * SPRING_DAMPING * _escala_muelle * fuerza_manos)
	state.apply_central_force(force)

	var clean_basis := state.transform.basis.orthonormalized()
	var current_rot := Quaternion(clean_basis)
	var rot_delta   := current_rot.inverse() * _target_rotation
	var axis        := rot_delta.get_axis()
	var angle       := rot_delta.get_angle()
	if angle > PI:
		angle -= TAU
	var torque_local  := axis * angle * ANGULAR_STIFFNESS * _escala_muelle * fuerza_manos
	var torque_global := clean_basis * torque_local - state.angular_velocity * ANGULAR_DAMPING * _escala_muelle * fuerza_manos
	state.apply_torque(torque_global)
	_pending_order = false

## Heavy props stay on the floor (gravity stays on) and are dragged with a
## capped horizontal speed, so the hand can move them but never lift them.
func _apply_drag(state: PhysicsDirectBodyState3D) -> void:
	var fuerza_manos := _factor_dos_manos()
	var delta := _target_position - state.transform.origin
	var destino := Vector2(delta.x, delta.z) * ARRASTRE_GANANCIA
	destino = destino.limit_length(_velocidad_arrastre * fuerza_manos)
	var vel := state.linear_velocity
	var vel_h := Vector2(vel.x, vel.z).move_toward(destino, _aceleracion_arrastre * fuerza_manos * state.step)
	state.linear_velocity = Vector3(vel_h.x, vel.y, vel_h.y)

	var clean_basis := state.transform.basis.orthonormalized()
	var current_rot := Quaternion(clean_basis)
	var rot_delta   := current_rot.inverse() * _target_rotation
	var axis        := rot_delta.get_axis()
	var angle       := rot_delta.get_angle()
	if angle > PI:
		angle -= TAU
	var torque_local  := axis * angle * ANGULAR_STIFFNESS * ARRASTRE_GIRO
	var torque_global := clean_basis * torque_local - state.angular_velocity * ANGULAR_DAMPING * ARRASTRE_GIRO
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
	# A hand steal must be within reach of the object.
	var solicitante := _find_player(solicitante_id)
	if solicitante != null and solicitante.global_position.distance_to(global_position) > ROBO_ALCANCE:
		return

	if id_sostenedor_1 == 0:
		_assign_holder(solicitante_id)
	elif id_sostenedor_1 == solicitante_id:
		# Second hand of the same player: double grip, more force.
		agarre_doble = true
	elif id_sostenedor_1 != solicitante_id and id_sostenedor_2 == 0:
		if agarre_fuerte:
			# Strong grip: the thief must out-pull the holder in a tug-of-war.
			_start_tug_of_war(solicitante_id)
		else:
			# Weak grip (simple click): stolen outright.
			_assign_holder(solicitante_id)

@rpc("any_peer", "call_local", "reliable")
func intentar_soltar(solicitante_id: int, impulso: Vector3, carga: float = 0.0, velocidad_final: Vector3 = Vector3.ZERO) -> void:
	if not multiplayer.is_server():
		return
	# Letting go mid-tug abandons the contest: both players stumble and the
	# object shoots away.
	if en_disputa and (id_sostenedor_1 == solicitante_id or id_sostenedor_2 == solicitante_id):
		_abortar_disputa()
		return
	# velocidad_final replaces the current velocity (a swing throw, so the hand's
	# momentum is not added on top); impulso adds to it (legacy throws).
	_lanzado = impulso != Vector3.ZERO or velocidad_final != Vector3.ZERO
	if _lanzado:
		_fuerza_lanzamiento = carga
		_ultimo_lanzador_id = solicitante_id
		if velocidad_final != Vector3.ZERO:
			linear_velocity = velocidad_final
		else:
			apply_central_impulse(impulso)
	_remove_collision_exception(solicitante_id)
	if id_sostenedor_1 == solicitante_id:
		id_sostenedor_1 = 0
	elif id_sostenedor_2 == solicitante_id:
		id_sostenedor_2 = 0
	if id_sostenedor_1 == 0 and id_sostenedor_2 == 0:
		agarre_doble = false
		_configure_physics_free()
		en_disputa = false
	_broadcast_state.rpc(id_sostenedor_1, id_sostenedor_2, en_disputa)

@rpc("any_peer", "call_local", "reliable")
func actualizar_tipo_agarre(es_fuerte: bool) -> void:
	# Host-local RPCs have no remote sender; fall back to our own id.
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	if sender == id_sostenedor_1:
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
	# Clear the previous holder's physics exception before zeroing the ids;
	# otherwise a stale exception survives across pocket cycles.
	_remove_collision_exception(id_sostenedor_1)
	_remove_collision_exception(id_sostenedor_2)
	en_bolsillo_de_id = id_dueno
	id_sostenedor_1   = 0
	id_sostenedor_2   = 0
	en_disputa        = false
	agarre_doble      = false
	agarre_fuerte     = false
	_lanzado          = false
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
	# Ghost mode is an authority-only RPC: only the server may trigger it.
	# Clients run usar_objeto locally via call_local, but calling the RPC from
	# a client is rejected ("RPC ... is not allowed ... Mode is authority").
	if usar_animacion_golpe and multiplayer.is_server():
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
# Public API — Repair state (illegal object / Boss inspection)
# ---------------------------------------------------------------------------

## Marks the illegal object as repaired. Server-authoritative.
func marcar_como_reparado() -> void:
	if not multiplayer.is_server():
		return
	if esta_reparado:
		return
	_rpc_set_reparado.rpc(true)
	if es_ilegal:
		GameManager.notify_object_repaired()

## Marks the illegal object as broken again. Server-authoritative.
func marcar_como_roto() -> void:
	if not multiplayer.is_server():
		return
	if not esta_reparado:
		return
	_rpc_set_reparado.rpc(false)

## Repaired + physically back on the spot where it spawned.
func esta_en_pedestal() -> bool:
	if not _pedestal_registrado:
		return false
	if id_sostenedor_1 != 0 or id_sostenedor_2 != 0 or en_bolsillo_de_id != 0:
		return false
	return global_position.distance_to(_posicion_pedestal) <= radio_pedestal

@rpc("authority", "call_local", "reliable")
func _rpc_set_reparado(valor: bool) -> void:
	esta_reparado = valor
	_set_visual_state(es_ilegal and not esta_reparado)

# ---------------------------------------------------------------------------
# Tug-of-war
# ---------------------------------------------------------------------------

func _start_tug_of_war(retador_id: int) -> void:
	id_sostenedor_2 = retador_id
	en_disputa      = true
	_tug_pull_1     = 0.0
	_tug_pull_2     = 0.0
	_tug_inicio_ms  = Time.get_ticks_msec()
	_broadcast_state.rpc(id_sostenedor_1, id_sostenedor_2, true)
	_rpc_tug_progreso.rpc(0.0, 0.0)
	# Server-side: hold the prop in the air while the tug lasts.
	gravity_scale = 0.0

## Each holder reports the distance they pulled this frame. First to drag the
## object past TUG_UMBRAL wins; a timeout favours whoever pulled more.
@rpc("any_peer", "call_local", "unreliable")
func enviar_fuerza_tiro(fuerza: float) -> void:
	if not multiplayer.is_server() or not en_disputa or fuerza <= 0.0:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	if sender == id_sostenedor_1:
		_tug_pull_1 += fuerza
	elif sender == id_sostenedor_2:
		_tug_pull_2 += fuerza
	else:
		return
	_rpc_tug_progreso.rpc(_tug_pull_1, _tug_pull_2)
	var agotado := Time.get_ticks_msec() - _tug_inicio_ms >= int(TUG_DURACION_MAX * 1000.0)
	var total := _tug_pull_1 + _tug_pull_2
	if total >= TUG_UMBRAL or agotado:
		var gana_1 := _tug_pull_1 >= _tug_pull_2
		_resolver_disputa(id_sostenedor_1 if gana_1 else id_sostenedor_2)

@rpc("authority", "call_local", "unreliable")
func _rpc_tug_progreso(pull1: float, pull2: float) -> void:
	tug_pull_1 = pull1
	tug_pull_2 = pull2

func _resolver_disputa(ganador_id: int) -> void:
	var perdedor_id := id_sostenedor_2 if ganador_id == id_sostenedor_1 else id_sostenedor_1
	tug_pull_1 = 0.0
	tug_pull_2 = 0.0
	_assign_holder(ganador_id)
	_hacer_tropezar(perdedor_id)

## Someone let go mid-tug: both stumble and the object flies free.
func _abortar_disputa() -> void:
	var p1 := id_sostenedor_1
	var p2 := id_sostenedor_2
	tug_pull_1 = 0.0
	tug_pull_2 = 0.0
	_remove_collision_exception(p1)
	_remove_collision_exception(p2)
	id_sostenedor_1  = 0
	id_sostenedor_2  = 0
	en_disputa       = false
	agarre_doble     = false
	_lanzado         = true
	_fuerza_lanzamiento = 1.0
	_ultimo_lanzador_id = p1
	_configure_physics_free()
	set_deferred("freeze", false)
	var dir := Vector3(randf_range(-1.0, 1.0), 1.0, randf_range(-1.0, 1.0)).normalized()
	linear_velocity = dir * TUG_ESCAPE_SPEED
	_broadcast_state.rpc(0, 0, false)
	_hacer_tropezar(p1)
	_hacer_tropezar(p2)

func _hacer_tropezar(player_id: int) -> void:
	var player := _find_player(player_id) as Node3D
	if player == null:
		return
	var dir: Vector3 = player.global_position - global_position
	dir.y = 0.0
	if dir.is_zero_approx():
		dir = Vector3.FORWARD
	player.rpc("_rpc_tropiezo", dir.normalized(), tiempo_tropiezo)

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
	gravity_scale = _gravedad_sostenido
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
	agarre_doble      = false
	_lanzado          = false
	en_bolsillo_de_id = 0
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

## A thrown prop that hits a player hard enough knocks them over. Only the
## server resolves the hit; the victim's own client plays the fall.
func _on_objeto_body_entered(cuerpo: Node3D) -> void:
	if not multiplayer.is_server() or not _lanzado:
		return
	if cuerpo == null or not cuerpo.is_in_group("jugadores"):
		return
	if cuerpo.name.to_int() == _ultimo_lanzador_id:
		return
	if _fuerza_lanzamiento < fuerza_tropiezo:
		return
	var ahora := Time.get_ticks_msec()
	if ahora - _ultimo_golpe_ms < GOLPE_COOLDOWN_MS:
		return
	_ultimo_golpe_ms = ahora
	var dir := cuerpo.global_position - global_position
	dir.y = 0.0
	if dir.is_zero_approx():
		dir = -global_transform.basis.z
	cuerpo.rpc("_rpc_tropiezo", dir.normalized(), tiempo_tropiezo)

# ---------------------------------------------------------------------------
# State broadcast
# ---------------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _broadcast_state(id1: int, id2: int, disputando: bool) -> void:
	id_sostenedor_1 = id1
	id_sostenedor_2 = id2
	en_disputa      = disputando
	# Keep the weight physics in sync on every peer: held heavy props keep
	# gravity and are dragged, held light/medium ones float in the hand.
	if id1 != 0 or id2 != 0:
		_configure_physics_held()
	else:
		_configure_physics_free()
	if disputando:
		disputa_iniciada.emit()
	else:
		disputa_finalizada.emit(id1)
