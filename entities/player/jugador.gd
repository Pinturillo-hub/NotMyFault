extends RigidBody3D

# --- CONFIGURACIÓN ---
@export_group("Físicas")
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

var barra_carga: ProgressBar = null

# --- VARIABLES ---
var _rotacion_objetivo_y: float = 0.0
var _direccion_input: Vector3 = Vector3.ZERO
var _altura_base_visuales: float = 0.0
var _objeto_en_bolsillo: RigidBody3D = null

# --- ESTADO CAMBIAZO ---
var _timer_cambiazo: float = 0.0
var _victima_cambiazo: Node3D = null
var _mano_activa_cambiazo: Node3D = null 

func _enter_tree():
	set_multiplayer_authority(name.to_int())

func _ready():
	if visuales: _altura_base_visuales = visuales.position.y
	add_to_group("jugadores")
	if bulto_visual: bulto_visual.visible = false
	
	if is_multiplayer_authority():
		_crear_ui_cambiazo()
		$Cabeza/Camera3D.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if $Cabeza/ManoIzquierda: $Cabeza/ManoIzquierda.es_mano_izquierda = true
		_cambiar_capa_visual(2)
	else:
		$Cabeza/Camera3D.current = false
		set_process_input(false)
		set_physics_process(false)
		set_process(false)
		_cambiar_capa_visual(1)

func _crear_ui_cambiazo():
	barra_carga = ProgressBar.new()
	if has_node("Interfaz/Centro"):
		$Interfaz/Centro.add_child(barra_carga)
		barra_carga.custom_minimum_size = Vector2(200, 20)
		barra_carga.show_percentage = false
		barra_carga.visible = false
		barra_carga.modulate = Color(1, 0.5, 0) 

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: return

	if event is InputEventMouseMotion:
		cabeza.rotate_x(-event.relative.y * sensibilidad_raton)
		cabeza.rotation.x = clamp(cabeza.rotation.x, deg_to_rad(-90), deg_to_rad(80))
		_rotacion_objetivo_y -= event.relative.x * sensibilidad_raton
	
	var mirando_abajo = rad_to_deg(cabeza.rotation.x) < angulo_mirar_abajo
	var info_raycast = _obtener_info()
	
	_procesar_input_mano(event, "mano_derecha_accion", mano_der, mirando_abajo, info_raycast)
	_procesar_input_mano(event, "mano_izquierda_accion", mano_izq, mirando_abajo, info_raycast)

func _procesar_input_mano(event, accion, mano, mirando_abajo, info):
	if event.is_action(accion):
		var just = event.is_action_pressed(accion)
		var held = event.is_pressed()
		var released = event.is_action_released(accion)
		
		if held and mano._objeto_agarrado and info["cuerpo"] and info["cuerpo"].is_in_group("jugadores"):
			if _es_espalda_valida(info["cuerpo"]):
				_iniciar_o_continuar_cambiazo(mano, info["cuerpo"])
				return 
		
		if released or (held and (not info["cuerpo"] or not info["cuerpo"].is_in_group("jugadores"))):
			_cancelar_cambiazo()
		
		if held and not mano._objeto_agarrado and _victima_cambiazo:
			_cancelar_cambiazo()
		
		if _victima_cambiazo == null:
			if just:
				if info["cuerpo"] is RigidBody3D:
					mano.gestionar_input(just, held, info)
				elif mirando_abajo:
					_gestionar_bolsillo_mano_especifica(mano)
				else:
					mano.gestionar_input(just, held, info)
			else:
				mano.gestionar_input(just, held, info)

func _process(delta: float) -> void:
	if not is_multiplayer_authority(): return
	var input = Input.get_vector("izquierda", "derecha", "adelante", "atras")
	_direccion_input = Vector3(input.x, 0, input.y).normalized()
	
	_actualizar_cruceta()
	_procesar_progreso_cambiazo(delta)
	_animar_visuales(delta)

func _es_espalda_valida(victima_node: Node3D) -> bool:
	var mi_frente = -global_transform.basis.z
	var su_frente = -victima_node.global_transform.basis.z
	return mi_frente.dot(su_frente) > 0.0

func _iniciar_o_continuar_cambiazo(mano: Node3D, victima: Node3D):
	if _victima_cambiazo != victima or _mano_activa_cambiazo != mano:
		_timer_cambiazo = 0.0
		_victima_cambiazo = victima
		_mano_activa_cambiazo = mano
		if barra_carga: barra_carga.visible = true

func _cancelar_cambiazo():
	_victima_cambiazo = null
	_mano_activa_cambiazo = null
	_timer_cambiazo = 0.0
	if barra_carga: barra_carga.visible = false

func _procesar_progreso_cambiazo(delta: float):
	if _victima_cambiazo and _mano_activa_cambiazo:
		_timer_cambiazo += delta
		if barra_carga:
			barra_carga.value = (_timer_cambiazo / tiempo_para_cambiazo) * 100.0
		if _timer_cambiazo >= tiempo_para_cambiazo:
			_ejecutar_intercambio_final()
			_cancelar_cambiazo()

func _ejecutar_intercambio_final():
	var mi_objeto = _mano_activa_cambiazo._objeto_agarrado
	if not mi_objeto: 
		_cancelar_cambiazo()
		return
	
	var ruta_mi_objeto = mi_objeto.get_path()
	_mano_activa_cambiazo._soltar(false)
	
	var id_victima = _victima_cambiazo.name.to_int()
	var posicion_recepcion = _mano_activa_cambiazo.pos_accion.global_position
	
	rpc_id(1, "servidor_procesar_cambiazo", ruta_mi_objeto, id_victima, _mano_activa_cambiazo.name, posicion_recepcion)

@rpc("any_peer", "call_local", "reliable")
func servidor_procesar_cambiazo(ruta_obj_entrante: NodePath, id_victima: int, nombre_mano_ladron: String, posicion_robo: Vector3):
	if not multiplayer.is_server(): return
	
	var obj_entrante = get_node_or_null(ruta_obj_entrante)
	var nodo_victima = _buscar_jugador_por_id(id_victima)
	var id_ladron = multiplayer.get_remote_sender_id()
	
	if not nodo_victima: return
	
	var obj_saliente = nodo_victima._objeto_en_bolsillo
	
	if obj_saliente:
		nodo_victima.rpc("asignar_objeto_bolsillo_remoto", NodePath("")) 
		obj_saliente.rpc("salir_de_bolsillo", posicion_robo)
		
		var nodo_ladron = _buscar_jugador_por_id(id_ladron)
		if nodo_ladron:
			nodo_ladron.rpc("cliente_recibir_objeto_en_mano", obj_saliente.get_path(), nombre_mano_ladron)
	
	if obj_entrante:
		obj_entrante.rpc("entrar_en_bolsillo", id_victima)
		nodo_victima.rpc("asignar_objeto_bolsillo_remoto", obj_entrante.get_path())

@rpc("any_peer", "call_local", "reliable")
func asignar_objeto_bolsillo_remoto(ruta: NodePath):
	if ruta.is_empty():
		_objeto_en_bolsillo = null
		rpc("_actualizar_bulto_visual", false)
	else:
		_objeto_en_bolsillo = get_node(ruta)
		rpc("_actualizar_bulto_visual", true)

@rpc("any_peer", "call_local", "reliable")
func cliente_recibir_objeto_en_mano(ruta_objeto: NodePath, nombre_mano: String):
	var objeto = get_node_or_null(ruta_objeto)
	var mano = cabeza.get_node_or_null(nombre_mano)
	
	if objeto and mano:
		# FORZAR ESTADO VISIBLE LOCALMENTE
		objeto.global_position = mano.pos_accion.global_position
		objeto.visible = true 
		
		# Agarrar
		mano.forzar_agarre_inmediato(objeto, mano.pos_accion.global_position)
		print("Objeto recibido: ", objeto.name)

@rpc("any_peer", "call_remote")
func recibir_cambiazo(_ruta: NodePath):
	pass 

func _gestionar_bolsillo_mano_especifica(mano_solicitante: Node3D):
	if mano_solicitante._objeto_agarrado:
		var objeto = mano_solicitante._objeto_agarrado
		mano_solicitante._soltar(false)
		if _objeto_en_bolsillo:
			_sacar_objeto_de_bolsillo(true, mano_solicitante)
		_meter_objeto_en_bolsillo(objeto)
		return

	if _objeto_en_bolsillo:
		_sacar_objeto_de_bolsillo(true, mano_solicitante)

func _meter_objeto_en_bolsillo(objeto: RigidBody3D):
	_objeto_en_bolsillo = objeto
	
	# --- SEGURIDAD ANTI-EXPLOSIÓN ---
	add_collision_exception_with(objeto)
	# --------------------------------
	
	if objeto.has_method("entrar_en_bolsillo"):
		objeto.rpc("entrar_en_bolsillo", name.to_int())
	rpc("_actualizar_bulto_visual", true)

func _sacar_objeto_de_bolsillo(equipar: bool, mano_destino: Node3D = null):
	if not _objeto_en_bolsillo: return
	var objeto = _objeto_en_bolsillo
	_objeto_en_bolsillo = null
	
	var mano_final = mano_destino if mano_destino else mano_der
	
	# Si equipamos, vamos directos a la mano. Si no, a la espalda.
	var pos_salida = mano_final.pos_accion.global_position if equipar else bolsillo_attach.global_position + (global_transform.basis.z * 0.5)
	
	if objeto.has_method("salir_de_bolsillo"):
		objeto.rpc("salir_de_bolsillo", pos_salida)
	
	rpc("_actualizar_bulto_visual", false)
	
	if equipar:
		# --- CORRECCIÓN: Usar la función de agarre forzoso de la mano ---
		# Esto asegura que visualmente esté pegado desde el frame 0
		if is_instance_valid(objeto):
			objeto.global_position = pos_salida # Teletransporte objeto
			mano_final.forzar_agarre_inmediato(objeto, pos_salida) # Teletransporte mano
		
		# ----------------------------------------------------------------
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not is_multiplayer_authority(): return
	var nueva_rotacion := Basis(Vector3.UP, _rotacion_objetivo_y)
	state.transform.basis = nueva_rotacion
	
	var en_disputa = false
	var objeto_disputado = null
	if mano_der._en_disputa_activa:
		en_disputa = true
		objeto_disputado = mano_der._objeto_agarrado
	elif mano_izq._en_disputa_activa:
		en_disputa = true
		objeto_disputado = mano_izq._objeto_agarrado
	
	if en_disputa and objeto_disputado:
		var dist = (objeto_disputado.global_position - global_position).length()
		if dist > 2.0:
			var fuerza = (objeto_disputado.global_position - global_position).normalized() * 50.0
			state.linear_velocity += fuerza * state.step
		else:
			state.linear_velocity = state.linear_velocity.move_toward(Vector3.ZERO, 50.0 * state.step)
	else:
		var dir_mov = nueva_rotacion * _direccion_input
		var vel_actual = state.linear_velocity
		var vel_h = Vector2(vel_actual.x, vel_actual.z)
		var objetivo = Vector2(dir_mov.x, dir_mov.z) * velocidad_maxima
		vel_h = vel_h.move_toward(objetivo, aceleracion_tierra * state.step)
		state.linear_velocity = Vector3(vel_h.x, state.linear_velocity.y, vel_h.y)

func _actualizar_cruceta():
	var mirando_abajo = rad_to_deg(cabeza.rotation.x) < angulo_mirar_abajo
	var info = _obtener_info()
	var cuerpo = info["cuerpo"]
	var color = Color(1, 1, 1, 0.2)
	
	if cuerpo:
		if cuerpo.is_in_group("jugadores"): 
			if _tiene_algo_en_manos() and _es_espalda_valida(cuerpo): color = Color(1, 0.5, 0, 1) 
			else: color = Color(1, 1, 1, 0.5)
		elif cuerpo is RigidBody3D: color = Color(1, 0, 0, 1) 
		elif cuerpo is Interactuable: color = Color(0, 1, 0, 1) 
		elif mirando_abajo and (_tiene_algo_en_manos() or _objeto_en_bolsillo):
			color = Color(0.6, 0.0, 0.8, 1.0) 
		else: color = Color(1, 1, 1, 0.5)
	elif mirando_abajo:
		if _tiene_algo_en_manos() or _objeto_en_bolsillo:
			color = Color(0.6, 0.0, 0.8, 1.0)
	cruceta.color = color

func _obtener_info() -> Dictionary:
	if raycast.is_colliding():
		return {"cuerpo": raycast.get_collider(), "punto": raycast.get_collision_point()}
	return {"cuerpo": null, "punto": Vector3.ZERO}

func _tiene_algo_en_manos() -> bool:
	return (mano_der and mano_der._objeto_agarrado) or (mano_izq and mano_izq._objeto_agarrado)

func tiene_objeto_ilegal() -> bool:
	var der = mano_der._objeto_agarrado and mano_der._objeto_agarrado.is_in_group("ilegal")
	var izq = mano_izq._objeto_agarrado and mano_izq._objeto_agarrado.is_in_group("ilegal")
	var bol = _objeto_en_bolsillo and _objeto_en_bolsillo.is_in_group("ilegal")
	return der or izq or bol

func _cambiar_capa_visual(capa_destino: int):
	if not visuales: return
	var partes = visuales.find_child("PartesOcultables", true, false)
	if partes: partes.layers = 1 << (capa_destino - 1)

func _animar_visuales(delta):
	if not visuales: return
	var vel_local = global_transform.basis.inverse() * linear_velocity
	var target_z = clamp(vel_local.x * 0.05, -0.3, 0.3)
	var target_x = clamp(-vel_local.z * 0.05, -0.3, 0.3)
	visuales.rotation.z = lerp_angle(visuales.rotation.z, -target_z, delta * 8.0)
	visuales.rotation.x = lerp_angle(visuales.rotation.x, target_x, delta * 8.0)
	if linear_velocity.length() > 1.0:
		var vel_bob = 20.0 
		var altura_bob = 0.05
		visuales.position.y = _altura_base_visuales + (sin(Time.get_ticks_msec() * 0.001 * vel_bob) * altura_bob)
	else:
		visuales.position.y = lerp(visuales.position.y, _altura_base_visuales, delta * 5.0)

@rpc("any_peer", "call_local")
func _actualizar_bulto_visual(visible_bulto):
	if bulto_visual: bulto_visual.visible = visible_bulto

func _buscar_jugador_por_id(id: int) -> Node:
	var ruta = "/root/Mundo/Jugadores"
	if get_tree().root.has_node(ruta):
		var cont = get_tree().root.get_node(ruta)
		if cont.has_node(str(id)): return cont.get_node(str(id))
	return null
