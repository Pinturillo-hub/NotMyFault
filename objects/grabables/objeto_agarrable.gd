extends RigidBody3D

# --- ESTADO SINCRONIZADO ---
@export var id_sostenedor_1: int = 0
@export var id_sostenedor_2: int = 0 
@export var en_disputa: bool = false
@export var agarre_fuerte: bool = false
@export var es_ilegal: bool = false 
@export var en_bolsillo_de_id: int = 0 

# --- REFERENCIAS VISUALES ---
@export var malla_normal: Node3D
@export var malla_rota: Node3D 

# --- CONFIGURACIÓN FÍSICA ---
const RIGIDEZ_MUELLE = 150.0  
const AMORTIGUACION = 10.0    
const RIGIDEZ_ANGULAR = 10.0  
const AMORTIGUACION_ANGULAR = 2.0 

# --- VARIABLES INTERNAS ---
var _objetivo_posicion: Vector3 = Vector3.ZERO
var _objetivo_rotacion: Quaternion = Quaternion.IDENTITY
var _tiempo_desde_ultima_orden: float = 0.0
var _hay_orden_nueva: bool = false

# --- SEÑALES ---
signal disputa_iniciada
signal disputa_finalizada(ganador_id)

func _ready():
	can_sleep = false
	add_to_group("agarrables")
	if es_ilegal:
		add_to_group("ilegal")
		_actualizar_silueta(true)
	else:
		_actualizar_silueta(false)

func _actualizar_silueta(esta_roto: bool):
	if malla_normal: malla_normal.visible = !esta_roto
	if malla_rota: malla_rota.visible = esta_roto

# --- FÍSICAS ---

func _physics_process(_delta):
	# Parche visual: Si el synchronizer dice que está en bolsillo, forzamos limbo
	if en_bolsillo_de_id != 0:
		global_position = Vector3(0, -500, 0)
		linear_velocity = Vector3.ZERO
		if visible: visible = false

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not multiplayer.has_multiplayer_peer(): return
	if not multiplayer.is_server(): return
	if en_bolsillo_de_id != 0: 
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		return 
	
	_tiempo_desde_ultima_orden += state.step
	
	# Autorreparación
	if id_sostenedor_1 == 0 and id_sostenedor_2 == 0 and collision_layer == 0:
		collision_layer = 1
		collision_mask = 1
		gravity_scale = 1.0
		if not visible: visible = true

	if (id_sostenedor_1 != 0 or id_sostenedor_2 != 0) and _tiempo_desde_ultima_orden < 0.5:
		if _hay_orden_nueva:
			var dist = _objetivo_posicion - state.transform.origin
			var fuerza = (dist * RIGIDEZ_MUELLE) - (state.linear_velocity * AMORTIGUACION)
			state.apply_central_force(fuerza)
			
			# --- CORRECCIÓN NOMBRE VARIABLE (b_limpia) ---
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

# --- RPCs ---

@rpc("any_peer", "call_local", "unreliable_ordered")
func actualizar_objetivo_agarre(posicion: Vector3, rotacion: Quaternion, id_jugador: int):
	if not multiplayer.is_server(): return
	if id_sostenedor_1 == id_jugador or id_sostenedor_2 == id_jugador:
		_objetivo_posicion = posicion
		_objetivo_rotacion = rotacion
		_tiempo_desde_ultima_orden = 0.0
		_hay_orden_nueva = true

@rpc("any_peer", "call_local", "reliable")
func intentar_coger(solicitante_id: int):
	if not multiplayer.is_server(): return
	
	if en_bolsillo_de_id != 0 and en_bolsillo_de_id != solicitante_id: return
	
	if en_bolsillo_de_id == solicitante_id:
		en_bolsillo_de_id = 0
		_reactivar_fisicas_deferred()

	if id_sostenedor_1 == 0:
		_asignar_dueno(solicitante_id)
		return

	if id_sostenedor_1 != solicitante_id and id_sostenedor_2 == 0:
		if not agarre_fuerte:
			_asignar_dueno(solicitante_id)
		else:
			id_sostenedor_2 = solicitante_id
			en_disputa = true
			_notificar_estado.rpc(id_sostenedor_1, id_sostenedor_2, true)
			await get_tree().create_timer(1.5).timeout
			_resolver_disputa()

func _asignar_dueno(nuevo_id):
	if id_sostenedor_1 != 0:
		var ant = _buscar_jugador_por_id(id_sostenedor_1)
		if ant: ant.remove_collision_exception_with(self)

	id_sostenedor_1 = nuevo_id
	id_sostenedor_2 = 0
	en_disputa = false
	agarre_fuerte = false
	gravity_scale = 0.0
	en_bolsillo_de_id = 0 
	collision_layer = 1
	collision_mask = 1
	visible = true
	freeze = false
	
	if nuevo_id != 0:
		var nue = _buscar_jugador_por_id(nuevo_id)
		if nue: nue.add_collision_exception_with(self)
		_objetivo_posicion = global_position
		_objetivo_rotacion = Quaternion(global_transform.basis.orthonormalized())
	
	_notificar_estado.rpc(id_sostenedor_1, 0, false)

@rpc("any_peer", "call_local", "reliable")
func intentar_soltar(solicitante_id: int, impulso: Vector3):
	if not multiplayer.is_server(): return
	if impulso != Vector3.ZERO: apply_central_impulse(impulso)
	
	var jug = _buscar_jugador_por_id(solicitante_id)
	if jug: jug.remove_collision_exception_with(self)
	
	if id_sostenedor_1 == solicitante_id: id_sostenedor_1 = 0
	elif id_sostenedor_2 == solicitante_id: id_sostenedor_2 = 0
	
	if id_sostenedor_1 == 0 and id_sostenedor_2 == 0:
		_reactivar_fisicas_deferred()
		en_disputa = false
	
	_notificar_estado.rpc(id_sostenedor_1, id_sostenedor_2, en_disputa)

@rpc("any_peer", "call_local")
func entrar_en_bolsillo(id_dueno: int):
	en_bolsillo_de_id = id_dueno
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	collision_layer = 0
	collision_mask = 0
	gravity_scale = 0.0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	id_sostenedor_1 = 0
	id_sostenedor_2 = 0
	
	# Mandar al limbo
	global_position = Vector3(0, -500, 0)
	visible = false

@rpc("any_peer", "call_local")
func salir_de_bolsillo(posicion_salida: Vector3):
	en_bolsillo_de_id = 0
	
	# ORDEN CRÍTICO: Primero posición, luego visible
	global_position = posicion_salida
	visible = true
	freeze = false
	
	_reactivar_fisicas_deferred()

func _reactivar_fisicas_deferred():
	call_deferred("set_collision_layer", 1)
	call_deferred("set_collision_mask", 1)
	await get_tree().create_timer(0.1).timeout
	if id_sostenedor_1 == 0: 
		gravity_scale = 1.0

@rpc("any_peer", "call_local", "reliable")
func actualizar_tipo_agarre(es_fuerte: bool):
	if multiplayer.get_remote_sender_id() == id_sostenedor_1:
		agarre_fuerte = es_fuerte

@rpc("authority", "call_local", "reliable")
func _notificar_estado(id1, id2, disputando):
	id_sostenedor_1 = id1
	id_sostenedor_2 = id2
	en_disputa = disputando
	if disputando: disputa_iniciada.emit()
	else: disputa_finalizada.emit(id1)

var _f1 = 0.0
var _f2 = 0.0

@rpc("any_peer", "call_local", "unreliable")
func enviar_fuerza_tiro(fuerza: float):
	if not en_disputa: return
	var s = multiplayer.get_remote_sender_id()
	if s == id_sostenedor_1: _f1 += fuerza
	elif s == id_sostenedor_2: _f2 += fuerza

func _resolver_disputa():
	var ganador = id_sostenedor_1
	if _f2 > (_f1 + 5.0): ganador = id_sostenedor_2
	_f1 = 0
	_f2 = 0
	_asignar_dueno(ganador)

func _buscar_jugador_por_id(id: int) -> Node:
	var ruta = "/root/Mundo/Jugadores" 
	if has_node(ruta):
		var c = get_node(ruta)
		if c.has_node(str(id)): return c.get_node(str(id))
	return null
