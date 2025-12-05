extends Node3D

# --- CONFIGURACIÓN ---
@export var es_mano_izquierda: bool = false
@export var fuerza_lanzamiento: float = 6.0
@export var offset_reposo_cuerpo: Vector3 = Vector3(0.4, 1.0, -0.6)

# --- REFERENCIAS ---
@onready var mesh: MeshInstance3D = $MeshMano
@onready var pos_accion: Marker3D = $PosicionAccion
@onready var jugador_padre: Node3D = get_parent().get_parent()

# --- ESTADO PÚBLICO ---
var objeto_agarrado: RigidBody3D = null

# --- VARIABLES INTERNAS ---
var _tiempo_pulsado: float = 0.0
var _esta_pulsando: bool = false
var _ignorar_input_soltar: bool = false
var _modo_manosear: bool = false
var _punto_agarre_local: Vector3 = Vector3.ZERO
var _en_disputa_activa: bool = false
var _tiempo_desde_agarre: float = 0.0

func _physics_process(delta: float) -> void:
	_gestionar_temporizadores(delta)
	
	if objeto_agarrado and is_instance_valid(objeto_agarrado):
		_enviar_datos_fisicos()
		_verificar_agarre_fuerte()
	
	_actualizar_visuales(delta)

func _gestionar_temporizadores(delta: float) -> void:
	if _esta_pulsando: _tiempo_pulsado += delta
	else: _tiempo_pulsado = 0.0
	
	if objeto_agarrado:
		_tiempo_desde_agarre += delta
		if _tiempo_desde_agarre > 0.5 and not _en_disputa_activa:
			if objeto_agarrado.get("id_sostenedor_1") != multiplayer.get_unique_id():
				limpiar_estado_local()

func gestionar_input(just_pressed: bool, is_pressed: bool, info: Dictionary) -> void:
	_esta_pulsando = is_pressed
	
	if just_pressed:
		_tiempo_pulsado = 0.0
		if objeto_agarrado:
			soltar(true)
			_ignorar_input_soltar = true
		elif info.cuerpo:
			if info.cuerpo.has_method("interactuar"):
				info.cuerpo.interactuar()
				_modo_manosear = true
				_ignorar_input_soltar = true
			elif info.cuerpo is RigidBody3D:
				_intentar_agarrar(info.cuerpo, info.punto)
				_ignorar_input_soltar = false
	
	if is_pressed:
		if not objeto_agarrado and not _ignorar_input_soltar: _modo_manosear = true
	else:
		_modo_manosear = false
		if objeto_agarrado and not _ignorar_input_soltar and _tiempo_pulsado > 0.25:
			soltar(false)
		_ignorar_input_soltar = false

func _intentar_agarrar(cuerpo: RigidBody3D, punto_impacto: Vector3) -> void:
	if cuerpo.has_method("intentar_coger"):
		_conectar_senales_disputa(cuerpo)
		cuerpo.rpc("intentar_coger", multiplayer.get_unique_id())
		objeto_agarrado = cuerpo
		_punto_agarre_local = cuerpo.to_local(punto_impacto)
		_tiempo_desde_agarre = 0.0
		if jugador_padre: jugador_padre.add_collision_exception_with(cuerpo)

func soltar(lanzar: bool) -> void:
	if not objeto_agarrado: return
	var impulso = -pos_accion.global_transform.basis.z * fuerza_lanzamiento if lanzar else Vector3.ZERO
	if objeto_agarrado.has_method("intentar_soltar"):
		objeto_agarrado.rpc("intentar_soltar", multiplayer.get_unique_id(), impulso)
	limpiar_estado_local()

func forzar_agarre_inmediato(cuerpo: RigidBody3D, posicion_mundo: Vector3) -> void:
	limpiar_estado_local()
	objeto_agarrado = cuerpo
	_punto_agarre_local = cuerpo.to_local(posicion_mundo)
	_tiempo_desde_agarre = 0.0
	_ignorar_input_soltar = true 
	if jugador_padre: jugador_padre.add_collision_exception_with(cuerpo)
	
	# SNAP VISUAL INMEDIATO
	cuerpo.visible = true
	cuerpo.global_position = posicion_mundo
	if cuerpo.has_method("reset_physics_interpolation"): cuerpo.reset_physics_interpolation()
	mesh.global_position = posicion_mundo

func limpiar_estado_local() -> void:
	if objeto_agarrado:
		if jugador_padre: jugador_padre.remove_collision_exception_with(objeto_agarrado)
		_desconectar_senales_disputa(objeto_agarrado)
	objeto_agarrado = null
	_en_disputa_activa = false
	_punto_agarre_local = Vector3.ZERO

func _enviar_datos_fisicos() -> void:
	var offset_rotado = objeto_agarrado.global_transform.basis * _punto_agarre_local
	var pos_destino = pos_accion.global_position - offset_rotado
	var rot_destino = Quaternion(pos_accion.global_transform.basis.orthonormalized())
	objeto_agarrado.rpc("actualizar_objetivo_agarre", pos_destino, rot_destino, multiplayer.get_unique_id())

func _verificar_agarre_fuerte() -> void:
	if is_multiplayer_authority() and _esta_pulsando and _tiempo_pulsado > 0.25:
		objeto_agarrado.rpc("actualizar_tipo_agarre", true)
		if _en_disputa_activa:
			var fuerza = Input.get_action_strength("atras")
			objeto_agarrado.rpc("enviar_fuerza_tiro", fuerza)

# --- FIX: VISUALES SIN ERRORES C++ ---
func _actualizar_visuales(delta: float) -> void:
	var destino: Vector3
	var rot_destino: Vector3
	
	if objeto_agarrado and is_instance_valid(objeto_agarrado):
		destino = objeto_agarrado.to_global(_punto_agarre_local)
		var dist_sq = mesh.global_position.distance_squared_to(destino)
		
		# CASO 1: TELETRANSPORTE / LAG (Distancia > 1.5m)
		# CASO 2: PEGADO PERFECTO (Distancia casi 0)
		if dist_sq > 2.25 or dist_sq < 0.0001:
			mesh.global_position = destino
			mesh.rotation = objeto_agarrado.global_rotation # Copiamos rotación, NO miramos
		else:
			# CASO 3: INTERPOLACIÓN SUAVE (Movimiento normal)
			mesh.global_position = mesh.global_position.lerp(destino, delta * 40.0)
			# LookAt seguro: Solo si hay una dirección clara
			var dir = (destino - mesh.global_position).normalized()
			# Chequeo anti-error C++: Si la dirección no es nula y no es paralela a UP
			if not dir.is_zero_approx() and abs(dir.dot(Vector3.UP)) < 0.99:
				mesh.look_at(destino, Vector3.UP)
			
	elif _modo_manosear:
		destino = pos_accion.global_position
		rot_destino = pos_accion.global_rotation
		_interpolar_reposo(destino, rot_destino, delta)
	else:
		if jugador_padre:
			var offset = offset_reposo_cuerpo
			offset.x = -abs(offset.x) if es_mano_izquierda else abs(offset.x)
			destino = jugador_padre.to_global(offset)
			rot_destino = jugador_padre.global_rotation
		else:
			destino = global_position
			rot_destino = global_rotation
		_interpolar_reposo(destino, rot_destino, delta)

func _interpolar_reposo(dest: Vector3, rot_dest: Vector3, delta: float):
	mesh.global_position = mesh.global_position.lerp(dest, delta * 20.0)
	mesh.global_rotation.x = lerp_angle(mesh.global_rotation.x, rot_dest.x, delta * 15)
	mesh.global_rotation.y = lerp_angle(mesh.global_rotation.y, rot_dest.y, delta * 15)
	mesh.global_rotation.z = lerp_angle(mesh.global_rotation.z, rot_dest.z, delta * 15)

func _conectar_senales_disputa(obj: RigidBody3D) -> void:
	if not obj.disputa_iniciada.is_connected(_on_disputa_iniciada):
		obj.disputa_iniciada.connect(_on_disputa_iniciada.bind(obj))
		obj.disputa_finalizada.connect(_on_disputa_finalizada)

func _desconectar_senales_disputa(obj: RigidBody3D) -> void:
	if is_instance_valid(obj):
		if obj.disputa_iniciada.is_connected(_on_disputa_iniciada):
			obj.disputa_iniciada.disconnect(_on_disputa_iniciada)
		if obj.disputa_finalizada.is_connected(_on_disputa_finalizada):
			obj.disputa_finalizada.disconnect(_on_disputa_finalizada)

func _on_disputa_iniciada(obj) -> void:
	if objeto_agarrado == obj: _en_disputa_activa = true

func _on_disputa_finalizada(ganador_id) -> void:
	_en_disputa_activa = false
	if ganador_id != multiplayer.get_unique_id():
		limpiar_estado_local()
