extends RigidBody3D
class_name ObjetoAgarrable

# --- CONFIGURACIÓN ---
const RIGIDEZ_MUELLE: float = 150.0
const AMORTIGUACION: float = 10.0
const RIGIDEZ_ANGULAR: float = 10.0
const AMORTIGUACION_ANGULAR: float = 2.0
const LIMBO_POS: Vector3 = Vector3(0, -200, 0) 

# --- ESTADO SINCRONIZADO ---
@export_group("Estado Multiplayer")
@export var id_sostenedor_1: int = 0
@export var id_sostenedor_2: int = 0
@export var en_disputa: bool = false
@export var agarre_fuerte: bool = false
@export var en_bolsillo_de_id: int = 0
@export var es_ilegal: bool = false

# --- REFERENCIAS VISUALES ---
@export var malla_normal: Node3D
@export var malla_rota: Node3D

# --- VARIABLES ---
var _objetivo_posicion: Vector3 = Vector3.ZERO
var _objetivo_rotacion: Quaternion = Quaternion.IDENTITY
var _tiempo_desde_ultima_orden: float = 0.0
var _hay_orden_nueva: bool = false
var _fuerza_tiro_1: float = 0.0
var _fuerza_tiro_2: float = 0.0
var _frame_teletransporte: int = 0 # Para saltar físicas un frame

signal disputa_iniciada
signal disputa_finalizada(ganador_id)

func _ready() -> void:
	can_sleep = false 
	add_to_group("agarrables")
	if es_ilegal: add_to_group("ilegal")
	_actualizar_silueta(false)

# --- WATCHDOG (FIX INTERACCIÓN) ---
func _process(_delta):
	# Este bloque asegura que si el objeto cree que está libre, 
	# realmente tenga las colisiones activas. 
	# Soluciona la pérdida de paquetes RPC.
	if en_bolsillo_de_id == 0 and id_sostenedor_1 == 0 and id_sostenedor_2 == 0:
		if collision_layer == 0:
			_configurar_fisicas_libre()

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# 1. MODO BOLSILLO (Autoridad Absoluta)
	if en_bolsillo_de_id != 0:
		state.transform.origin = LIMBO_POS
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		return

	# 2. MODO TELETRANSPORTE (Pop Instantáneo)
	if _frame_teletransporte > 0:
		state.transform.origin = _objetivo_posicion
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		_frame_teletransporte -= 1
		return

	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server(): return

	_tiempo_desde_ultima_orden += state.step
	
	# Autorreparación Server-Side
	if id_sostenedor_1 == 0 and id_sostenedor_2 == 0 and collision_layer == 0:
		_configurar_fisicas_libre()

	# Fuerzas de muelle
	if (id_sostenedor_1 != 0 or id_sostenedor_2 != 0) and _tiempo_desde_ultima_orden < 0.5:
		if _hay_orden_nueva:
			_aplicar_fuerzas_agarre(state)

func _aplicar_fuerzas_agarre(state: PhysicsDirectBodyState3D) -> void:
	var dist = _objetivo_posicion - state.transform.origin
	var fuerza = (dist * RIGIDEZ_MUELLE) - (state.linear_velocity * AMORTIGUACION)
	state.apply_central_force(fuerza)
	
	var b_limpia = state.transform.basis.orthonormalized()
	var rot_actual = Quaternion(b_limpia)
	var rot_diferencia = rot_actual.inverse() * _objetivo_rotacion
	var eje = rot_diferencia.get_axis()
	var angulo = rot_diferencia.get_angle()
	if angulo > PI: angulo -= 2 * PI
	
	var torque_local = eje * angulo * RIGIDEZ_ANGULAR
	var torque_global = b_limpia * torque_local
	torque_global -= state.angular_velocity * AMORTIGUACION_ANGULAR
	state.apply_torque(torque_global)
	_hay_orden_nueva = false

# --- TELETRANSPORTES Y LOGICA ---

func ejecutar_robo_desde_servidor(nuevo_dueno_id: int, pos_salida: Vector3) -> void:
	en_bolsillo_de_id = 0
	_forzar_teletransporte(pos_salida)
	_asignar_dueno(nuevo_dueno_id)
	_objetivo_posicion = pos_salida
	_objetivo_rotacion = Quaternion(global_transform.basis.orthonormalized())
	rpc("notificar_salida_bolsillo_robo", pos_salida)

@rpc("call_local")
func notificar_salida_bolsillo_robo(posicion: Vector3) -> void:
	en_bolsillo_de_id = 0
	_forzar_teletransporte(posicion)
	visible = true
	# Asegura que el cliente local actualice su física interna
	if has_method("reset_physics_interpolation"): reset_physics_interpolation()

func _forzar_teletransporte(pos: Vector3):
	global_position = pos
	_objetivo_posicion = pos
	_frame_teletransporte = 2 # Saltamos física 2 frames para asentar la posición
	
	# Hard Reset
	var xform = Transform3D(global_transform.basis, pos)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xform)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)

func _asignar_dueno(nuevo_id: int) -> void:
	_gestionar_excepciones_colision(id_sostenedor_1, false)
	id_sostenedor_1 = nuevo_id
	id_sostenedor_2 = 0
	en_disputa = false
	agarre_fuerte = false
	en_bolsillo_de_id = 0
	_configurar_fisicas_agarrado()
	if nuevo_id != 0: _gestionar_excepciones_colision(nuevo_id, true)
	_notificar_estado.rpc(id_sostenedor_1, 0, false)

# --- RPCs ---

@rpc("any_peer", "call_local")
func salir_de_bolsillo(posicion_salida: Vector3) -> void:
	en_bolsillo_de_id = 0
	_forzar_teletransporte(posicion_salida)
	if has_method("reset_physics_interpolation"): reset_physics_interpolation()
	_configurar_fisicas_libre()

@rpc("any_peer", "call_local")
func entrar_en_bolsillo(id_dueno: int) -> void:
	en_bolsillo_de_id = id_dueno
	id_sostenedor_1 = 0
	id_sostenedor_2 = 0
	en_disputa = false
	_configurar_fisicas_bolsillo()

# --- CONFIG ESTADOS FÍSICOS (Con set_deferred para evitar bloqueos) ---

func _configurar_fisicas_libre() -> void:
	visible = true
	set_deferred("freeze", false)
	set_deferred("sleeping", false) # Despertar si estaba dormido
	set_deferred("collision_layer", 1)
	set_deferred("collision_mask", 1)
	gravity_scale = 1.0

func _configurar_fisicas_agarrado() -> void:
	set_deferred("collision_layer", 1)
	set_deferred("collision_mask", 1)
	gravity_scale = 0.0
	visible = true
	set_deferred("freeze", false)
	set_deferred("sleeping", false)

func _configurar_fisicas_bolsillo() -> void:
	set_deferred("freeze", true)
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	gravity_scale = 0.0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_position = LIMBO_POS
	if has_method("reset_physics_interpolation"): reset_physics_interpolation()
	visible = false

# --- INTERACCIÓN ---

@rpc("any_peer", "call_local", "unreliable_ordered")
func actualizar_objetivo_agarre(posicion: Vector3, rotacion: Quaternion, id_jugador: int) -> void:
	if not multiplayer.is_server(): return
	if id_sostenedor_1 == id_jugador or id_sostenedor_2 == id_jugador:
		_objetivo_posicion = posicion
		_objetivo_rotacion = rotacion
		_tiempo_desde_ultima_orden = 0.0
		_hay_orden_nueva = true

@rpc("any_peer", "call_local", "reliable")
func intentar_coger(solicitante_id: int) -> void:
	if not multiplayer.is_server(): return
	
	if en_bolsillo_de_id == solicitante_id:
		en_bolsillo_de_id = 0
		_configurar_fisicas_libre()

	if en_bolsillo_de_id != 0 and en_bolsillo_de_id != solicitante_id: return

	if id_sostenedor_1 == 0:
		_asignar_dueno(solicitante_id)
	elif id_sostenedor_1 != solicitante_id and id_sostenedor_2 == 0:
		if not agarre_fuerte:
			_asignar_dueno(solicitante_id)
		else:
			_iniciar_disputa(solicitante_id)

@rpc("any_peer", "call_local", "reliable")
func intentar_soltar(solicitante_id: int, impulso: Vector3) -> void:
	if not multiplayer.is_server(): return
	if impulso != Vector3.ZERO: apply_central_impulse(impulso)
	
	_gestionar_excepciones_colision(solicitante_id, false)
	
	if id_sostenedor_1 == solicitante_id: id_sostenedor_1 = 0
	elif id_sostenedor_2 == solicitante_id: id_sostenedor_2 = 0
	
	if id_sostenedor_1 == 0 and id_sostenedor_2 == 0:
		_configurar_fisicas_libre()
		en_disputa = false
	
	_notificar_estado.rpc(id_sostenedor_1, id_sostenedor_2, en_disputa)

@rpc("authority", "call_local", "reliable")
func _notificar_estado(id1: int, id2: int, disputando: bool) -> void:
	id_sostenedor_1 = id1
	id_sostenedor_2 = id2
	en_disputa = disputando
	if disputando: disputa_iniciada.emit()
	else: disputa_finalizada.emit(id1)

@rpc("any_peer", "call_local", "reliable")
func actualizar_tipo_agarre(es_fuerte: bool) -> void:
	if multiplayer.get_remote_sender_id() == id_sostenedor_1:
		agarre_fuerte = es_fuerte

func _iniciar_disputa(retador_id: int) -> void:
	id_sostenedor_2 = retador_id
	en_disputa = true
	_notificar_estado.rpc(id_sostenedor_1, id_sostenedor_2, true)
	await get_tree().create_timer(1.5).timeout
	_resolver_disputa()

@rpc("any_peer", "call_local", "unreliable")
func enviar_fuerza_tiro(fuerza: float) -> void:
	if not en_disputa: return
	var s = multiplayer.get_remote_sender_id()
	if s == id_sostenedor_1: _fuerza_tiro_1 += fuerza
	elif s == id_sostenedor_2: _fuerza_tiro_2 += fuerza

func _resolver_disputa() -> void:
	var ganador = id_sostenedor_1
	if _fuerza_tiro_2 > (_fuerza_tiro_1 + 5.0): ganador = id_sostenedor_2
	_fuerza_tiro_1 = 0
	_fuerza_tiro_2 = 0
	_asignar_dueno(ganador)

func _actualizar_silueta(esta_roto: bool) -> void:
	if malla_normal: malla_normal.visible = !esta_roto
	if malla_rota: malla_rota.visible = esta_roto

func _gestionar_excepciones_colision(id_jugador: int, agregar: bool) -> void:
	if id_jugador == 0: return
	var jugador = _buscar_jugador(id_jugador)
	if jugador:
		if agregar: jugador.add_collision_exception_with(self)
		else: jugador.remove_collision_exception_with(self)

func _buscar_jugador(id: int) -> Node:
	var ruta = "/root/Mundo/Jugadores"
	if get_tree().root.has_node(ruta):
		return get_tree().root.get_node(ruta).get_node_or_null(str(id))
	return null
