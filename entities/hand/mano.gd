extends Node3D

# --- CONFIGURACIÓN ---
@export var es_mano_izquierda: bool = false
@export var velocidad_movimiento_visual: float = 20.0
@export var fuerza_agarre: float = 200.0
@export var fuerza_lanzamiento: float = 6.0 
@export var offset_reposo_cuerpo: Vector3 = Vector3(0.4, 1.0, -0.6) 
@export var debug_visual: bool = false

# --- REFERENCIAS ---
@onready var mesh: MeshInstance3D = $MeshMano
@onready var pos_accion: Marker3D = $PosicionAccion
@onready var jugador_padre = get_parent().get_parent()

# --- ESTADO ---
var _objeto_agarrado: RigidBody3D = null
var _esta_pulsando: bool = false
var _tiempo_pulsado: float = 0.0
var _punto_agarre_local: Vector3 = Vector3.ZERO
var _modo_manosear: bool = false
var _ignorar_input_soltar: bool = false 
var _en_disputa_activa: bool = false
var _tiempo_desde_agarre: float = 0.0
var _esfera_debug: MeshInstance3D = null

func _ready() -> void:
	if debug_visual: _crear_debug()

func _physics_process(delta: float) -> void:
	if _esta_pulsando: _tiempo_pulsado += delta
	else: _tiempo_pulsado = 0.0

	# AUTO-SOLTAR
	if _objeto_agarrado and is_instance_valid(_objeto_agarrado):
		_tiempo_desde_agarre += delta
		if _tiempo_desde_agarre > 0.5: 
			if _objeto_agarrado.get("id_sostenedor_1") != multiplayer.get_unique_id() and not _en_disputa_activa:
				_limpiar_estado()
				return

	# LÓGICA AGARRE
	if _objeto_agarrado and is_instance_valid(_objeto_agarrado):
		_enviar_datos_al_servidor()
		if is_multiplayer_authority():
			var agarre_es_fuerte = _esta_pulsando and _tiempo_pulsado > 0.25
			if _objeto_agarrado.has_method("actualizar_tipo_agarre"):
				_objeto_agarrado.rpc("actualizar_tipo_agarre", agarre_es_fuerte)
			if _en_disputa_activa:
				var fuerza = Input.get_action_strength("atras")
				if _objeto_agarrado.has_method("enviar_fuerza_tiro"):
					_objeto_agarrado.rpc("enviar_fuerza_tiro", fuerza)

	_actualizar_visuales(delta)

func _enviar_datos_al_servidor():
	var offset_rotado = _objeto_agarrado.global_transform.basis * _punto_agarre_local
	var posicion_destino_caja = pos_accion.global_position - offset_rotado
	var rotacion_destino = Quaternion(pos_accion.global_transform.basis.orthonormalized())
	_objeto_agarrado.rpc("actualizar_objetivo_agarre", posicion_destino_caja, rotacion_destino, multiplayer.get_unique_id())

# --- FUNCIÓN CORREGIDA Y BLINDADA ---
func _actualizar_visuales(delta):
	var destino: Vector3
	var rotacion_destino: Vector3
	var velocidad_actual = velocidad_movimiento_visual
	
	if _objeto_agarrado and is_instance_valid(_objeto_agarrado):
		# Destino real
		destino = _objeto_agarrado.to_global(_punto_agarre_local)
		
		# --- CORRECCIÓN 1: ERROR COLINEAR (LookAt) ---
		var direccion_obj = (destino - mesh.global_position).normalized()
		var producto_punto = abs(direccion_obj.dot(Vector3.UP))
		
		# Solo miramos si NO es colinear (Producto punto < 0.99) y hay distancia
		if mesh.global_position.distance_to(destino) > 0.05 and producto_punto < 0.99:
			mesh.look_at(destino, Vector3.UP)
		# --------------------------------------------
		
		velocidad_actual = 30.0 
		
	elif _modo_manosear:
		destino = pos_accion.global_position
		rotacion_destino = pos_accion.global_rotation
	else:
		if jugador_padre:
			var offset = offset_reposo_cuerpo
			if es_mano_izquierda: offset.x = -abs(offset.x)
			else: offset.x = abs(offset.x)
			destino = jugador_padre.to_global(offset)
			rotacion_destino = jugador_padre.global_rotation
			if _esfera_debug: _esfera_debug.global_position = destino
		else:
			destino = global_position
			rotacion_destino = global_rotation

	# --- CORRECCIÓN 2: GLITCH VISUAL HOST ---
	# Si el destino está a más de 2 metros (ej: viene del Limbo -500), TELETRANSPORTE
	if mesh.global_position.distance_to(destino) > 2.0:
		mesh.global_position = destino # Snap instantáneo
	else:
		mesh.global_position = mesh.global_position.lerp(destino, delta * velocidad_actual)
	# ----------------------------------------

	if not _objeto_agarrado:
		mesh.global_rotation.x = lerp_angle(mesh.global_rotation.x, rotacion_destino.x, delta * 15)
		mesh.global_rotation.y = lerp_angle(mesh.global_rotation.y, rotacion_destino.y, delta * 15)
		mesh.global_rotation.z = lerp_angle(mesh.global_rotation.z, rotacion_destino.z, delta * 15)

func forzar_agarre_inmediato(cuerpo: RigidBody3D, punto_impacto: Vector3):
	_objeto_agarrado = cuerpo
	_punto_agarre_local = cuerpo.to_local(punto_impacto)
	_tiempo_desde_agarre = 0.0
	
	if _objeto_agarrado:
		_objeto_agarrado.visible = true
		# Forzamos posición del objeto para evitar parpadeo
		_objeto_agarrado.global_position = punto_impacto
		
	if jugador_padre is RigidBody3D: 
		jugador_padre.add_collision_exception_with(cuerpo)
	
	# Teletransporte visual de la mano también
	mesh.global_position = punto_impacto

func gestionar_input(just_pressed: bool, is_pressed: bool, info_raycast: Dictionary) -> void:
	_esta_pulsando = is_pressed
	if just_pressed:
		_tiempo_pulsado = 0.0 
		if _objeto_agarrado:
			_soltar(true)
			_ignorar_input_soltar = true
		elif info_raycast["cuerpo"] and info_raycast["cuerpo"].has_method("interactuar"):
			info_raycast["cuerpo"].interactuar()
			_modo_manosear = true
			_ignorar_input_soltar = true
		elif info_raycast["cuerpo"] is RigidBody3D:
			intentar_agarrar(info_raycast["cuerpo"], info_raycast["punto"])
			_ignorar_input_soltar = false 
	
	if is_pressed:
		if not _objeto_agarrado and not _ignorar_input_soltar: _modo_manosear = true
	else:
		_modo_manosear = false

	if not is_pressed and not just_pressed:
		if _objeto_agarrado and not _ignorar_input_soltar:
			if _tiempo_pulsado > 0.25: _soltar(false) 
		_ignorar_input_soltar = false

func intentar_agarrar(cuerpo: RigidBody3D, punto_impacto: Vector3):
	if cuerpo.has_method("intentar_coger"):
		if not cuerpo.disputa_iniciada.is_connected(_on_disputa_iniciada):
			cuerpo.disputa_iniciada.connect(_on_disputa_iniciada.bind(cuerpo))
			cuerpo.disputa_finalizada.connect(_on_disputa_finalizada)
		
		cuerpo.rpc("intentar_coger", multiplayer.get_unique_id())
		_objeto_agarrado = cuerpo
		_punto_agarre_local = cuerpo.to_local(punto_impacto)
		_tiempo_desde_agarre = 0.0
		if jugador_padre is RigidBody3D: jugador_padre.add_collision_exception_with(cuerpo)

func _soltar(lanzar: bool):
	if not _objeto_agarrado: return
	var impulso = Vector3.ZERO
	if lanzar: impulso = -pos_accion.global_transform.basis.z * fuerza_lanzamiento
	if _objeto_agarrado.has_method("intentar_soltar"):
		_objeto_agarrado.rpc("intentar_soltar", multiplayer.get_unique_id(), impulso)
	_limpiar_estado()

func _limpiar_estado():
	if _objeto_agarrado:
		if jugador_padre is RigidBody3D: jugador_padre.remove_collision_exception_with(_objeto_agarrado)
		if _objeto_agarrado.has_signal("disputa_iniciada"):
			if _objeto_agarrado.disputa_iniciada.is_connected(_on_disputa_iniciada):
				_objeto_agarrado.disputa_iniciada.disconnect(_on_disputa_iniciada)
			if _objeto_agarrado.disputa_finalizada.is_connected(_on_disputa_finalizada):
				_objeto_agarrado.disputa_finalizada.disconnect(_on_disputa_finalizada)
	_objeto_agarrado = null
	_en_disputa_activa = false
	_punto_agarre_local = Vector3.ZERO

func _on_disputa_iniciada(objeto):
	if _objeto_agarrado == objeto: _en_disputa_activa = true

func _on_disputa_finalizada(ganador_id):
	_en_disputa_activa = false
	if ganador_id != multiplayer.get_unique_id():
		_limpiar_estado()

func _crear_debug():
	pass
