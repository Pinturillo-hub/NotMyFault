extends RigidBody3D

# --- ESTADO ---
@export var id_sostenedor_1: int = 0
@export var id_sostenedor_2: int = 0 
@export var en_disputa: bool = false
@export var agarre_fuerte: bool = false
@export var es_ilegal: bool = false 

@export var malla_normal: Node3D
@export var malla_rota: Node3D 

const RIGIDEZ_MUELLE = 150.0  
const AMORTIGUACION = 10.0    
const RIGIDEZ_ANGULAR = 10.0  
const AMORTIGUACION_ANGULAR = 2.0 

var _objetivo_posicion: Vector3 = Vector3.ZERO
var _objetivo_rotacion: Quaternion = Quaternion.IDENTITY
var _tiempo_desde_ultima_orden: float = 0.0
var _en_bolsillo_de_id: int = 0

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

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# --- CORRECCIÓN: EVITAR CRASH AL CERRAR ---
	if not multiplayer.has_multiplayer_peer(): return
	# ------------------------------------------
	
	if not multiplayer.is_server(): return
	if _en_bolsillo_de_id != 0: return 
	
	_tiempo_desde_ultima_orden += state.step
	
	if id_sostenedor_1 == 0 and id_sostenedor_2 == 0 and collision_layer == 0:
		collision_layer = 1
		collision_mask = 1

	if (id_sostenedor_1 != 0 or id_sostenedor_2 != 0) and _tiempo_desde_ultima_orden < 0.5:
		var distancia_vector = _objetivo_posicion - state.transform.origin
		var fuerza_muelle = (distancia_vector * RIGIDEZ_MUELLE) - (state.linear_velocity * AMORTIGUACION)
		state.apply_central_force(fuerza_muelle)
		
		var basis_limpia = state.transform.basis.orthonormalized()
		var rot_actual = Quaternion(basis_limpia)
		var rot_diferencia = rot_actual.inverse() * _objetivo_rotacion
		var eje = rot_diferencia.get_axis()
		var angulo = rot_diferencia.get_angle()
		if angulo > PI: angulo -= 2 * PI
		
		var torque_local = eje * angulo * RIGIDEZ_ANGULAR
		var torque_global = basis_limpia * torque_local
		torque_global -= state.angular_velocity * AMORTIGUACION_ANGULAR
		state.apply_torque(torque_global)

@rpc("any_peer", "call_local", "unreliable_ordered")
func actualizar_objetivo_agarre(posicion: Vector3, rotacion: Quaternion, id_jugador: int):
	if not multiplayer.is_server(): return
	if id_sostenedor_1 == id_jugador or id_sostenedor_2 == id_jugador:
		_objetivo_posicion = posicion
		_objetivo_rotacion = rotacion
		_tiempo_desde_ultima_orden = 0.0

# --- ROBO Y DISPUTA ---

@rpc("any_peer", "call_local", "reliable")
func intentar_coger(solicitante_id: int):
	if not multiplayer.is_server(): return
	if _en_bolsillo_de_id != 0 and _en_bolsillo_de_id != solicitante_id: return
	
	if _en_bolsillo_de_id == solicitante_id:
		_en_bolsillo_de_id = 0
		collision_layer = 1
		collision_mask = 1

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
		var antiguo = _buscar_jugador_por_id(id_sostenedor_1)
		if antiguo: antiguo.remove_collision_exception_with(self)

	id_sostenedor_1 = nuevo_id
	id_sostenedor_2 = 0
	en_disputa = false
	agarre_fuerte = false
	gravity_scale = 0.0
	collision_layer = 1
	collision_mask = 1
	
	if nuevo_id != 0:
		var nuevo = _buscar_jugador_por_id(nuevo_id)
		if nuevo: nuevo.add_collision_exception_with(self)
		_objetivo_posicion = global_position
		_objetivo_rotacion = Quaternion(global_transform.basis.orthonormalized())
	
	_notificar_estado.rpc(id_sostenedor_1, 0, false)

@rpc("any_peer", "call_local", "reliable")
func intentar_soltar(solicitante_id: int, impulso: Vector3):
	if not multiplayer.is_server(): return
	if impulso != Vector3.ZERO: apply_central_impulse(impulso)
	
	var jugador = _buscar_jugador_por_id(solicitante_id)
	if jugador: jugador.remove_collision_exception_with(self)
	
	if id_sostenedor_1 == solicitante_id: id_sostenedor_1 = 0
	elif id_sostenedor_2 == solicitante_id: id_sostenedor_2 = 0
	
	if id_sostenedor_1 == 0 and id_sostenedor_2 == 0:
		gravity_scale = 1.0 
		en_disputa = false
		collision_layer = 1
		collision_mask = 1
	
	_notificar_estado.rpc(id_sostenedor_1, id_sostenedor_2, en_disputa)

@rpc("any_peer", "call_local")
func entrar_en_bolsillo(id_dueno: int):
	_en_bolsillo_de_id = id_dueno
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	visible = false 
	collision_layer = 0
	collision_mask = 0

@rpc("any_peer", "call_local")
func salir_de_bolsillo(posicion_salida: Vector3):
	_en_bolsillo_de_id = 0
	global_position = posicion_salida
	visible = true
	freeze = false
	collision_layer = 1
	collision_mask = 1
	await get_tree().create_timer(0.1).timeout
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

var _fuerza_acumulada_1 = 0.0
var _fuerza_acumulada_2 = 0.0

@rpc("any_peer", "call_local", "unreliable")
func enviar_fuerza_tiro(fuerza: float):
	if not en_disputa: return
	var sender = multiplayer.get_remote_sender_id()
	if sender == id_sostenedor_1: _fuerza_acumulada_1 += fuerza
	elif sender == id_sostenedor_2: _fuerza_acumulada_2 += fuerza

func _resolver_disputa():
	var ganador = id_sostenedor_1
	if _fuerza_acumulada_2 > (_fuerza_acumulada_1 + 5.0):
		ganador = id_sostenedor_2
	_fuerza_acumulada_1 = 0
	_fuerza_acumulada_2 = 0
	_asignar_dueno(ganador)

func _buscar_jugador_por_id(id: int) -> Node:
	var ruta_jugadores = "/root/Mundo/Jugadores" 
	if has_node(ruta_jugadores):
		var contenedor = get_node(ruta_jugadores)
		if contenedor.has_node(str(id)):
			return contenedor.get_node(str(id))
	return null
