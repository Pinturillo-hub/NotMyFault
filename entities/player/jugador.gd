extends RigidBody3D

# --- CONFIGURACIÓN ---
@export_group("Movimiento")
@export var velocidad_maxima: float = 6.0
@export var aceleracion_tierra: float = 20.0
@export_group("Cámara")
@export var sensibilidad_raton: float = 0.003
@export var angulo_mirar_abajo: float = -70.0
@export_group("Juego")
@export var tiempo_para_cambiazo: float = 2.0

# --- REFERENCIAS ---
@onready var cabeza: Node3D = $Cabeza
@onready var raycast: RayCast3D = $Cabeza/RayCast3D
@onready var mano_der: Node3D = $Cabeza/ManoDerecha
@onready var mano_izq: Node3D = $Cabeza/ManoIzquierda
@onready var cruceta: ColorRect = $Interfaz/Centro/Cruceta
@onready var visuales: Node3D = $ModeloCocodrilo
@onready var bolsillo_attach: BoneAttachment3D = $ModeloCocodrilo/Armature/Skeleton3D/BolsilloAttachment
@onready var bulto_visual: MeshInstance3D = $ModeloCocodrilo/Armature/Skeleton3D/BolsilloAttachment/BultoVisual
@onready var barra_der: ProgressBar = $Interfaz/Centro/BarraCargaDer
@onready var barra_izq: ProgressBar = $Interfaz/Centro/BarraCargaIzq

var barra_carga: ProgressBar = null
var _rotacion_objetivo_y: float = 0.0
var _direccion_input: Vector3 = Vector3.ZERO
var _altura_base_visuales: float = 0.0
var _objeto_en_bolsillo: RigidBody3D = null

# --- ESTADO ROBO ---
var _timer_cambiazo: float = 0.0
var _victima_cambiazo: Node3D = null
var _mano_activa_cambiazo: Node3D = null

func _enter_tree() -> void: set_multiplayer_authority(name.to_int())

func _ready() -> void:
	add_to_group("jugadores")
	if visuales: _altura_base_visuales = visuales.position.y
	if bulto_visual: bulto_visual.visible = false
	if is_multiplayer_authority():
		mano_der.barra_carga_ui = barra_der
		mano_izq.barra_carga_ui = barra_izq
	else:
		_inicializar_proxy()

func _inicializar_autoridad() -> void:
	_crear_ui_cambiazo()
	$Cabeza/Camera3D.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if mano_izq: mano_izq.es_mano_izquierda = true
	_cambiar_capa_visual(2) 

func _inicializar_proxy() -> void:
	$Cabeza/Camera3D.current = false
	set_process_input(false)
	set_physics_process(false)
	set_process(false)
	_cambiar_capa_visual(1)

# --- INPUT ---
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: return

	if event is InputEventMouseMotion:
		_procesar_mirada(event)
	
	var mirando_abajo = rad_to_deg(cabeza.rotation.x) < angulo_mirar_abajo
	var info_raycast = _obtener_info_raycast()
	
	_gestionar_accion_mano(event, "mano_derecha_accion", mano_der, mirando_abajo, info_raycast)
	_gestionar_accion_mano(event, "mano_izquierda_accion", mano_izq, mirando_abajo, info_raycast)

func _procesar_mirada(event: InputEventMouseMotion) -> void:
	cabeza.rotate_x(-event.relative.y * sensibilidad_raton)
	cabeza.rotation.x = clamp(cabeza.rotation.x, deg_to_rad(-90), deg_to_rad(80))
	_rotacion_objetivo_y -= event.relative.x * sensibilidad_raton

func _gestionar_accion_mano(event: InputEvent, accion: String, mano: Node3D, mirando_abajo: bool, info: Dictionary) -> void:
	# 1. Estado actual de las teclas
	var colocando = Input.is_action_pressed("colocar")
	var click_sostenido = Input.is_action_pressed(accion)
	var just_click = event.is_action_pressed(accion)
	
	# 2. ¿Es este evento relevante para la mano?
	# - Es un click de esta mano
	# - Es un evento de la tecla COLOCAR (Presionar O SOLTAR) <--- ¡ESTO FALTABA!
	# - Estamos en modo colocación y movemos el ratón
	var es_evento_colocar = event.is_action("colocar")
	var es_relevante = event.is_action(accion) or es_evento_colocar or (colocando and event is InputEventMouseMotion)
	
	# Si no hay evento relevante y no estamos manteniendo click, salimos
	if not es_relevante and not click_sostenido: 
		return
	
	# Lógica de Robo
	if click_sostenido and mano.objeto_agarrado and info.cuerpo and info.cuerpo.is_in_group("jugadores"):
		if _es_espalda_valida(info.cuerpo):
			_actualizar_estado_cambiazo(mano, info.cuerpo, true)
			return
	
	if not click_sostenido or not info.cuerpo or not info.cuerpo.is_in_group("jugadores"):
		_actualizar_estado_cambiazo(null, null, false)

	if _victima_cambiazo == null:
		if just_click and mirando_abajo:
			_gestionar_bolsillo_propio(mano)
		else:
			# Pasamos el estado 'colocando' (que será false al soltar) a la mano
			mano.gestionar_input(just_click, click_sostenido, colocando, info)

# --- FÍSICAS ---
func _process(delta: float) -> void:
	if not is_multiplayer_authority(): return
	var input = Input.get_vector("izquierda", "derecha", "adelante", "atras")
	_direccion_input = Vector3(input.x, 0, input.y).normalized()
	_procesar_progreso_cambiazo(delta)
	_actualizar_cruceta()
	_animar_visuales(delta)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not is_multiplayer_authority(): return
	var nueva_rotacion := Basis(Vector3.UP, _rotacion_objetivo_y)
	state.transform.basis = nueva_rotacion
	var dir_mov = nueva_rotacion * _direccion_input
	var vel_actual = state.linear_velocity
	var vel_h = Vector2(vel_actual.x, vel_actual.z)
	var objetivo = Vector2(dir_mov.x, dir_mov.z) * velocidad_maxima
	vel_h = vel_h.move_toward(objetivo, aceleracion_tierra * state.step)
	state.linear_velocity = Vector3(vel_h.x, state.linear_velocity.y, vel_h.y)

# --- HELPERS ---
func _obtener_info_raycast() -> Dictionary:
	if raycast.is_colliding():
		return {
			"cuerpo": raycast.get_collider(), 
			"punto": raycast.get_collision_point(),
			"normal": raycast.get_collision_normal()
		}
	return {"cuerpo": null, "punto": Vector3.ZERO, "normal": Vector3.UP}

# ... (RESTO DE FUNCIONES IGUALES: _gestionar_bolsillo_propio, _meter_objeto_en_bolsillo, _sacar_objeto_de_bolsillo, _actualizar_estado_cambiazo, _procesar_progreso_cambiazo, _finalizar_cambiazo, _servidor_procesar_cambiazo, RPCs, etc.)
# No las repito para ahorrar espacio, mantén las que tenías.

func _gestionar_bolsillo_propio(mano: Node3D) -> void:
	if mano.objeto_agarrado:
		var obj = mano.objeto_agarrado
		mano.soltar(false)
		if _objeto_en_bolsillo:
			_sacar_objeto_de_bolsillo(true, mano)
		_meter_objeto_en_bolsillo(obj)
		return
	if _objeto_en_bolsillo:
		_sacar_objeto_de_bolsillo(true, mano)

func _meter_objeto_en_bolsillo(objeto: RigidBody3D) -> void:
	_objeto_en_bolsillo = objeto
	add_collision_exception_with(objeto)
	objeto.rpc("entrar_en_bolsillo", name.to_int())
	rpc("_actualizar_bulto_visual", true)

func _sacar_objeto_de_bolsillo(equipar: bool, mano_destino: Node3D) -> void:
	if not _objeto_en_bolsillo: return
	var objeto = _objeto_en_bolsillo
	_objeto_en_bolsillo = null
	var pos_salida = mano_destino.pos_accion.global_position if equipar else bolsillo_attach.global_position
	if equipar:
		objeto.global_position = pos_salida
		if objeto.has_method("reset_physics_interpolation"): objeto.reset_physics_interpolation()
		objeto.visible = true 
		mano_destino.forzar_agarre_inmediato(objeto, pos_salida)
		objeto.rpc("intentar_coger", multiplayer.get_unique_id())
	else:
		objeto.rpc("salir_de_bolsillo", pos_salida)
	rpc("_actualizar_bulto_visual", false)

func _actualizar_estado_cambiazo(mano: Node3D, victima: Node3D, activo: bool) -> void:
	if not activo:
		_victima_cambiazo = null
		_mano_activa_cambiazo = null
		_timer_cambiazo = 0.0
		if barra_carga: barra_carga.visible = false
		return
	if _victima_cambiazo != victima:
		_victima_cambiazo = victima
		_mano_activa_cambiazo = mano
		_timer_cambiazo = 0.0
		if barra_carga: barra_carga.visible = true

func _procesar_progreso_cambiazo(delta: float) -> void:
	if not _victima_cambiazo or not _mano_activa_cambiazo: return
	_timer_cambiazo += delta
	if barra_carga: barra_carga.value = (_timer_cambiazo / tiempo_para_cambiazo) * 100.0
	if _timer_cambiazo >= tiempo_para_cambiazo: _finalizar_cambiazo()

func _finalizar_cambiazo() -> void:
	var mi_objeto = _mano_activa_cambiazo.objeto_agarrado
	if not mi_objeto: 
		_actualizar_estado_cambiazo(null, null, false)
		return
	var ruta_mi_objeto = mi_objeto.get_path()
	_mano_activa_cambiazo.limpiar_estado_local() 
	var id_victima = _victima_cambiazo.name.to_int()
	var pos_robo = _mano_activa_cambiazo.pos_accion.global_position
	rpc_id(1, "servidor_procesar_cambiazo", ruta_mi_objeto, id_victima, _mano_activa_cambiazo.name, pos_robo)
	_actualizar_estado_cambiazo(null, null, false)

@rpc("any_peer", "call_local", "reliable")
func servidor_procesar_cambiazo(ruta_obj_entrante: NodePath, id_victima: int, nombre_mano_ladron: String, posicion_robo: Vector3) -> void:
	if not multiplayer.is_server(): return
	var obj_entrante = get_node_or_null(ruta_obj_entrante)
	var nodo_victima = _buscar_jugador_por_id(id_victima)
	var id_ladron = multiplayer.get_remote_sender_id()
	if not nodo_victima: return
	
	var obj_saliente = nodo_victima._objeto_en_bolsillo
	if obj_saliente:
		nodo_victima.rpc("asignar_objeto_bolsillo_remoto", NodePath(""))
		obj_saliente.ejecutar_robo_desde_servidor(id_ladron, posicion_robo)
		var nodo_ladron = _buscar_jugador_por_id(id_ladron)
		if nodo_ladron:
			nodo_ladron.rpc("cliente_recibir_objeto_en_mano", obj_saliente.get_path(), nombre_mano_ladron)
	if obj_entrante:
		obj_entrante.rpc("entrar_en_bolsillo", id_victima)
		nodo_victima.rpc("asignar_objeto_bolsillo_remoto", obj_entrante.get_path())

@rpc("any_peer", "call_local", "reliable")
func cliente_recibir_objeto_en_mano(ruta_objeto: NodePath, nombre_mano: String) -> void:
	var objeto = get_node_or_null(ruta_objeto)
	var mano = cabeza.get_node_or_null(nombre_mano)
	if objeto and mano:
		mano.forzar_agarre_inmediato(objeto, mano.pos_accion.global_position)

@rpc("any_peer", "call_local", "reliable")
func asignar_objeto_bolsillo_remoto(ruta: NodePath) -> void:
	if ruta.is_empty():
		_objeto_en_bolsillo = null
		rpc("_actualizar_bulto_visual", false)
	else:
		_objeto_en_bolsillo = get_node(ruta)
		rpc("_actualizar_bulto_visual", true)

@rpc("any_peer", "call_local")
func _actualizar_bulto_visual(visible_bulto: bool) -> void:
	if bulto_visual: bulto_visual.visible = visible_bulto

func _crear_ui_cambiazo() -> void:
	barra_carga = ProgressBar.new()
	if has_node("Interfaz/Centro"):
		$Interfaz/Centro.add_child(barra_carga)
		barra_carga.custom_minimum_size = Vector2(200, 20)
		barra_carga.show_percentage = false
		barra_carga.visible = false
		barra_carga.modulate = Color(1, 0.5, 0)

func _es_espalda_valida(victima: Node3D) -> bool:
	var mi_frente = -global_transform.basis.z
	var su_frente = -victima.global_transform.basis.z
	return mi_frente.dot(su_frente) > 0.0

func _cambiar_capa_visual(capa: int) -> void:
	if not visuales: return
	var partes = visuales.find_child("PartesOcultables", true, false)
	if partes: partes.layers = 1 << (capa - 1)

func _actualizar_cruceta() -> void:
	var mirando_abajo = rad_to_deg(cabeza.rotation.x) < angulo_mirar_abajo
	var info = _obtener_info_raycast()
	var cuerpo = info.cuerpo
	var color = Color(1, 1, 1, 0.2)
	
	if cuerpo:
		if cuerpo.is_in_group("jugadores"): 
			if (mano_der.objeto_agarrado or mano_izq.objeto_agarrado) and _es_espalda_valida(cuerpo): color = Color(1, 0.5, 0, 1) 
			else: color = Color(1, 1, 1, 0.5)
		elif cuerpo is RigidBody3D: color = Color(1, 0, 0, 1) 
		elif cuerpo.has_method("interactuar"): color = Color(0, 1, 0, 1) 
		elif mirando_abajo and ((mano_der.objeto_agarrado or mano_izq.objeto_agarrado) or _objeto_en_bolsillo):
			color = Color(0.6, 0.0, 0.8, 1.0) 
		else: color = Color(1, 1, 1, 0.5)
	elif mirando_abajo and ((mano_der.objeto_agarrado or mano_izq.objeto_agarrado) or _objeto_en_bolsillo):
		color = Color(0.6, 0.0, 0.8, 1.0)
	cruceta.color = color

func _animar_visuales(delta: float) -> void:
	if not visuales: return
	var vel_local = global_transform.basis.inverse() * linear_velocity
	var velocidad_horizontal = Vector2(vel_local.x, vel_local.z).length()
	var target_z = clamp(vel_local.x * 0.15, -0.4, 0.4) 
	var target_x = clamp(-vel_local.z * 0.15, -0.4, 0.4)
	visuales.rotation.z = lerp_angle(visuales.rotation.z, -target_z, delta * 5.0)
	visuales.rotation.x = lerp_angle(visuales.rotation.x, target_x, delta * 5.0)
	if velocidad_horizontal > 1.0:
		var frecuencia_saltos = 15.0
		var altura_salto = 0.15
		var rebote = abs(sin(Time.get_ticks_msec() * 0.001 * frecuencia_saltos)) * altura_salto
		visuales.position.y = lerp(visuales.position.y, _altura_base_visuales + rebote, delta * 15.0)
	else:
		visuales.position.y = lerp(visuales.position.y, _altura_base_visuales, delta * 5.0)

func _buscar_jugador_por_id(id: int) -> Node:
	var ruta = "/root/Mundo/Jugadores"
	if get_tree().root.has_node(ruta):
		return get_tree().root.get_node(ruta).get_node_or_null(str(id))
	return null

func tiene_objeto_ilegal() -> bool:
	var der = mano_der.objeto_agarrado and mano_der.objeto_agarrado.is_in_group("ilegal")
	var izq = mano_izq.objeto_agarrado and mano_izq.objeto_agarrado.is_in_group("ilegal")
	var bol = _objeto_en_bolsillo and _objeto_en_bolsillo.is_in_group("ilegal")
	return der or izq or bol
