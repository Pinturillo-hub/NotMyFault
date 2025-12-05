extends RigidBody3D

# --- ESTADO SINCRONIZADO ---
@export var id_sostenedor_1: int = 0
@export var id_sostenedor_2: int = 0 
@export var en_disputa: bool = false
@export var agarre_fuerte: bool = false
@export var es_ilegal: bool = false 

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
var _en_bolsillo_de_id: int = 0
var _hay_orden_nueva: bool = false # <--- ¡VARIABLE RECUPERADA!

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

# --- FÍSICAS DE SERVIDOR (MUELLE VIRTUAL) ---

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not multiplayer.has_multiplayer_peer(): return
	if not multiplayer.is_server(): return
	
	# Si está en un bolsillo, anulamos físicas
	if _en_bolsillo_de_id != 0: return 
	
	_tiempo_desde_ultima_orden += state.step
	
	# Seguro de vida: Si nadie lo tiene, forzar colisiones activas
	if id_sostenedor_1 == 0 and id_sostenedor_2 == 0 and collision_layer == 0:
		collision_layer = 1
		collision_mask = 1

	# Si alguien lo sostiene, aplicamos fuerzas de muelle
	if (id_sostenedor_1 != 0 or id_sostenedor_2 != 0) and _tiempo_desde_ultima_orden < 0.5:
		if _hay_orden_nueva:
			# 1. Posición
			var distancia_vector = _objetivo_posicion - state.transform.origin
			var fuerza_muelle = (distancia_vector * RIGIDEZ_MUELLE) - (state.linear_velocity * AMORTIGUACION)
			state.apply_central_force(fuerza_muelle)
			
			# 2. Rotación
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
			
			_hay_orden_nueva = false

# --- COMUNICACIÓN CLIENTE -> SERVIDOR ---

@rpc("any_peer", "call_local", "unreliable_ordered")
func actualizar_objetivo_agarre(posicion: Vector3, rotacion: Quaternion, id_jugador: int):
	if not multiplayer.is_server(): return
	if id_sostenedor_1 == id_jugador or id_sostenedor_2 == id_jugador:
		_objetivo_posicion = posicion
		_objetivo_rotacion = rotacion
		_tiempo_desde_ultima_orden = 0.0
		_hay_orden_nueva = true

# --- GESTIÓN DE ROBO Y DISPUTA ---

@rpc("any_peer", "call_local", "reliable")
func intentar_coger(solicitante_id: int):
	if not multiplayer.is_server(): return
	
	# Si está en bolsillo de otro, no se puede coger con la mano (requiere cambiazo)
	if _en_bolsillo_de_id != 0 and _en_bolsillo_de_id != solicitante_id: return
	
	# Si lo saco de mi propio bolsillo (auto-sacar)
	if _en_bolsillo_de_id == solicitante_id:
		_en_bolsillo_de_id = 0
		_reactivar_fisicas_deferred()

	if id_sostenedor_1 == 0:
		_asignar_dueno(solicitante_id)
		return

	if id_sostenedor_1 != solicitante_id and id_sostenedor_2 == 0:
		if not agarre_fuerte:
			_asignar_dueno(solicitante_id) # Robo rápido
		else:
			# Disputa
			id_sostenedor_2 = solicitante_id
			en_disputa = true
			_notificar_estado.rpc(id_sostenedor_1, id_sostenedor_2, true)
			await get_tree().create_timer(1.5).timeout
			_resolver_disputa()

func _asignar_dueno(nuevo_id):
	# Limpiar dueño anterior
	if id_sostenedor_1 != 0:
		var antiguo = _buscar_jugador_por_id(id_sostenedor_1)
		if antiguo: antiguo.remove_collision_exception_with(self)

	id_sostenedor_1 = nuevo_id
	id_sostenedor_2 = 0
	en_disputa = false
	agarre_fuerte = false
	
	# Antigravedad para que flote hacia la mano
	gravity_scale = 0.0
	
	# Añadir excepción con nuevo dueño
	if nuevo_id != 0:
		var nuevo = _buscar_jugador_por_id(nuevo_id)
		if nuevo: nuevo.add_collision_exception_with(self)
		# Resetear objetivo para evitar saltos
		_objetivo_posicion = global_position
		_objetivo_rotacion = Quaternion(global_transform.basis.orthonormalized())
	
	_notificar_estado.rpc(id_sostenedor_1, 0, false)

@rpc("any_peer", "call_local", "reliable")
func intentar_soltar(solicitante_id: int, impulso: Vector3):
	if not multiplayer.is_server(): return
	
	if impulso != Vector3.ZERO:
		apply_central_impulse(impulso)
	
	var jugador = _buscar_jugador_por_id(solicitante_id)
	if jugador: jugador.remove_collision_exception_with(self)
	
	if id_sostenedor_1 == solicitante_id: id_sostenedor_1 = 0
	elif id_sostenedor_2 == solicitante_id: id_sostenedor_2 = 0
	
	if id_sostenedor_1 == 0 and id_sostenedor_2 == 0:
		en_disputa = false
		_reactivar_fisicas_deferred()
	
	_notificar_estado.rpc(id_sostenedor_1, id_sostenedor_2, en_disputa)

# --- BOLSILLO ---

@rpc("any_peer", "call_local")
func entrar_en_bolsillo(id_dueno: int):
	_en_bolsillo_de_id = id_dueno
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	visible = false 
	collision_layer = 0
	collision_mask = 0
	gravity_scale = 0.0
	# IMPORTANTE: Parar cualquier movimiento residual
	linear_velocity = Vector3.ZERO 
	angular_velocity = Vector3.ZERO

@rpc("any_peer", "call_local")
func salir_de_bolsillo(posicion_salida: Vector3):
	_en_bolsillo_de_id = 0
	global_position = posicion_salida
	visible = true
	freeze = false
	_reactivar_fisicas_deferred()

func _reactivar_fisicas_deferred():
	# Diferir la reactivación para evitar conflictos en el mismo frame
	call_deferred("set_collision_layer", 1)
	call_deferred("set_collision_mask", 1)
	
	# Esperar un poco antes de devolver gravedad para dar tiempo a agarrarlo
	await get_tree().create_timer(0.1).timeout
	if id_sostenedor_1 == 0: 
		gravity_scale = 1.0

# --- SYNC ---

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
