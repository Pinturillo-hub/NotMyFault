extends RigidBody3D

# --- CONFIGURACIÓN ---
@export_group("Físicas")
@export var velocidad_maxima: float = 6.0
@export var aceleracion_tierra: float = 20.0

@export_group("Cámara")
@export var sensibilidad_raton: float = 0.003
@export var angulo_mirar_abajo: float = -70.0 

# --- REFERENCIAS ---
@onready var cabeza: Node3D = $Cabeza
@onready var raycast: RayCast3D = $Cabeza/RayCast3D
@onready var mano_der: Node3D = $Cabeza/ManoDerecha
@onready var mano_izq: Node3D = $Cabeza/ManoIzquierda
@onready var cruceta: ColorRect = $Interfaz/Centro/Cruceta
@onready var visuales: Node3D = $ModeloCocodrilo

@onready var bolsillo_attach: BoneAttachment3D = $ModeloCocodrilo/Armature/Skeleton3D/BolsilloAttachment
@onready var bulto_visual: MeshInstance3D = $ModeloCocodrilo/Armature/Skeleton3D/BolsilloAttachment/BultoVisual

# --- VARIABLES ---
var _rotacion_objetivo_y: float = 0.0
var _direccion_input: Vector3 = Vector3.ZERO
var _altura_base_visuales: float = 0.0
var _objeto_en_bolsillo: RigidBody3D = null

func _enter_tree():
	set_multiplayer_authority(name.to_int())

func _ready():
	if visuales: _altura_base_visuales = visuales.position.y
	add_to_group("jugadores")
	if bulto_visual: bulto_visual.visible = false

	if is_multiplayer_authority():
		$Cabeza/Camera3D.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		var m_izq = $Cabeza/ManoIzquierda
		if m_izq: m_izq.es_mano_izquierda = true
		_cambiar_capa_visual(2)
	else:
		$Cabeza/Camera3D.current = false
		set_process_input(false)
		set_physics_process(false)
		set_process(false)
		_cambiar_capa_visual(1)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: return

	# CÁMARA
	if event is InputEventMouseMotion:
		cabeza.rotate_x(-event.relative.y * sensibilidad_raton)
		cabeza.rotation.x = clamp(cabeza.rotation.x, deg_to_rad(-90), deg_to_rad(80))
		_rotacion_objetivo_y -= event.relative.x * sensibilidad_raton
	
	# DATOS DE ENTORNO
	var mirando_abajo = rad_to_deg(cabeza.rotation.x) < angulo_mirar_abajo
	var info_raycast = _obtener_info()
	var cuerpo_apuntado = info_raycast["cuerpo"]
	
	# --- INPUT MANO DERECHA (CLICK IZQUIERDO) ---
	if event.is_action("mano_derecha_accion"):
		var just = event.is_action_pressed("mano_derecha_accion")
		var held = event.is_pressed()
		
		if just:
			# 1. PRIORIDAD: AGARRAR SUELO (Aunque mire abajo, si hay caja, la cojo)
			if cuerpo_apuntado is RigidBody3D:
				mano_der.gestionar_input(just, held, info_raycast)
			
			# 2. MODO BOLSILLO DERECHO (Mirar abajo + Nada en suelo)
			elif mirando_abajo:
				# ¡SOLO GESTIONAMOS LA MANO DERECHA!
				_gestionar_bolsillo_mano_especifica(mano_der)
				
			# 3. INTERACCIÓN NORMAL
			elif cuerpo_apuntado and cuerpo_apuntado.is_in_group("jugadores"):
				_intentar_cambiazo(cuerpo_apuntado) # El cambiazo siempre usa la derecha por defecto
			else:
				mano_der.gestionar_input(just, held, info_raycast)
		else:
			mano_der.gestionar_input(just, held, info_raycast)

	# --- INPUT MANO IZQUIERDA (CLICK DERECHO) ---
	if event.is_action("mano_izquierda_accion"):
		var just = event.is_action_pressed("mano_izquierda_accion")
		var held = event.is_pressed()
		
		if just:
			# 1. AGARRAR SUELO
			if cuerpo_apuntado is RigidBody3D:
				mano_izq.gestionar_input(just, held, info_raycast)
			
			# 2. MODO BOLSILLO IZQUIERDO (Mirar abajo + Nada en suelo)
			elif mirando_abajo:
				# ¡SOLO GESTIONAMOS LA MANO IZQUIERDA!
				_gestionar_bolsillo_mano_especifica(mano_izq)
			
			# 3. NORMAL
			else:
				mano_izq.gestionar_input(just, held, info_raycast)
		else:
			mano_izq.gestionar_input(just, held, info_raycast)

func _process(delta: float) -> void:
	if not is_multiplayer_authority(): return
	var input = Input.get_vector("izquierda", "derecha", "adelante", "atras")
	_direccion_input = Vector3(input.x, 0, input.y).normalized()
	
	# --- LÓGICA DE CRUCETA ---
	var mirando_abajo = rad_to_deg(cabeza.rotation.x) < angulo_mirar_abajo
	var info = _obtener_info()
	var cuerpo = info["cuerpo"]
	
	# Color Base
	var color_final = Color(1, 1, 1, 0.2)
	
	if cuerpo:
		if cuerpo.is_in_group("jugadores"): color_final = Color(1, 0.5, 0, 1) # Naranja
		elif cuerpo is RigidBody3D: color_final = Color(1, 0, 0, 1) # Rojo
		elif cuerpo is Interactuable: color_final = Color(0, 1, 0, 1) # Verde
		elif mirando_abajo and (_tiene_algo_en_manos() or _objeto_en_bolsillo):
			color_final = Color(0.6, 0.0, 0.8, 1.0) # Morado (Bolsillo)
		else:
			color_final = Color(1, 1, 1, 0.5)
	
	elif mirando_abajo:
		if _tiene_algo_en_manos() or _objeto_en_bolsillo:
			color_final = Color(0.6, 0.0, 0.8, 1.0)
	
	cruceta.color = color_final
	_animar_visuales(delta)

# -------------------------------------------------------------------------
# LÓGICA DE BOLSILLO ESTRICTA (POR MANO)
# -------------------------------------------------------------------------

func _gestionar_bolsillo_mano_especifica(mano_solicitante: Node3D):
	# 1. GUARDAR: Si ESTA mano tiene algo
	if mano_solicitante._objeto_agarrado:
		var objeto_a_guardar = mano_solicitante._objeto_agarrado
		
		# Soltamos de esta mano
		mano_solicitante._soltar(false)
		
		# Si ya hay algo en el bolsillo -> SWAP (Sale a esta misma mano)
		if _objeto_en_bolsillo:
			_sacar_objeto_de_bolsillo(true, mano_solicitante)
		
		# Guardamos lo nuevo
		_meter_objeto_en_bolsillo(objeto_a_guardar)
		return

	# 2. SACAR: Si ESTA mano está vacía y hay algo en el bolsillo
	if _objeto_en_bolsillo:
		_sacar_objeto_de_bolsillo(true, mano_solicitante)

# --- Helpers de Bolsillo ---

func _meter_objeto_en_bolsillo(objeto: RigidBody3D):
	_objeto_en_bolsillo = objeto
	if objeto.has_method("entrar_en_bolsillo"):
		objeto.rpc("entrar_en_bolsillo", name.to_int())
	rpc("_actualizar_bulto_visual", true)

func _sacar_objeto_de_bolsillo(equipar: bool, mano_destino: Node3D = null):
	if not _objeto_en_bolsillo: return
	var objeto = _objeto_en_bolsillo
	_objeto_en_bolsillo = null
	
	# Definimos la mano destino (por defecto derecha)
	var mano_final = mano_destino if mano_destino else mano_der
	
	# Calculamos posición: Si vamos a equipar, vamos directos a la mano.
	# Si no (soltar al aire), vamos a la espalda.
	var pos_salida = bolsillo_attach.global_position + (global_transform.basis.z * 0.5) + Vector3(0, 0.2, 0)
	
	if equipar:
		# TRUCO VISUAL: Teletransportar a la posición de agarre de la mano destino
		# para evitar que se vea el objeto viajando desde la otra mano/espalda.
		pos_salida = mano_final.pos_accion.global_position
	
	if objeto.has_method("salir_de_bolsillo"):
		objeto.rpc("salir_de_bolsillo", pos_salida)
	
	rpc("_actualizar_bulto_visual", false)
	
	if equipar:
		await get_tree().create_timer(0.05).timeout # Breve espera técnica
		if is_instance_valid(objeto):
			# Forzamos posición visual instantánea en la mano también si tiene lógica visual
			objeto.global_position = pos_salida 
			mano_final._intentar_agarrar(objeto, pos_salida)
			
func _tiene_algo_en_manos() -> bool:
	var der = mano_der._objeto_agarrado != null
	var izq = mano_izq._objeto_agarrado != null
	return der or izq

func _obtener_info() -> Dictionary:
	if raycast.is_colliding():
		return {"cuerpo": raycast.get_collider(), "punto": raycast.get_collision_point()}
	return {"cuerpo": null, "punto": Vector3.ZERO}

func _cambiar_capa_visual(capa_destino: int):
	if not visuales: return
	var partes = visuales.find_child("PartesOcultables", true, false)
	if partes: partes.layers = 1 << (capa_destino - 1)

func _animar_visuales(delta):
	if not visuales: return
	var velocidad_local = global_transform.basis.inverse() * linear_velocity
	var target_z = clamp(velocidad_local.x * 0.05, -0.3, 0.3)
	var target_x = clamp(-velocidad_local.z * 0.05, -0.3, 0.3)
	visuales.rotation.z = lerp_angle(visuales.rotation.z, -target_z, delta * 8.0)
	visuales.rotation.x = lerp_angle(visuales.rotation.x, target_x, delta * 8.0)
	if linear_velocity.length() > 1.0:
		var velocidad_bob = 20.0 
		var altura_bob = 0.05
		visuales.position.y = _altura_base_visuales + (sin(Time.get_ticks_msec() * 0.001 * velocidad_bob) * altura_bob)
	else:
		visuales.position.y = lerp(visuales.position.y, _altura_base_visuales, delta * 5.0)

func _integrate_forces(state):
	if not is_multiplayer_authority(): return
	var nueva_rotacion := Basis(Vector3.UP, _rotacion_objetivo_y)
	state.transform.basis = nueva_rotacion
	var dir_mov: Vector3 = nueva_rotacion * _direccion_input
	var vel_actual: Vector3 = state.linear_velocity
	var vel_h: Vector2 = Vector2(vel_actual.x, vel_actual.z)
	var objetivo: Vector2 = Vector2(dir_mov.x, dir_mov.z) * velocidad_maxima
	vel_h = vel_h.move_toward(objetivo, aceleracion_tierra * state.step)
	state.linear_velocity = Vector3(vel_h.x, state.linear_velocity.y, vel_h.y)

func _intentar_cambiazo(victima_node: Node3D):
	var dir = (global_position - victima_node.global_position).normalized()
	var espalda = -victima_node.global_transform.basis.z
	if espalda.dot(dir) < -0.5:
		var obj_mano = mano_der._objeto_agarrado
		if obj_mano: mano_der._soltar(false)
		var ruta = obj_mano.get_path() if obj_mano else NodePath("")
		victima_node.rpc("recibir_cambiazo", ruta)

@rpc("any_peer", "call_local")
func _actualizar_bulto_visual(visible_bulto):
	if bulto_visual: bulto_visual.visible = visible_bulto

@rpc("any_peer", "call_remote")
func recibir_cambiazo(ruta: NodePath):
	var obj_entrante = get_node_or_null(ruta)
	var obj_saliente = _objeto_en_bolsillo
	if obj_saliente:
		_sacar_objeto_de_bolsillo(false, null)
		if obj_saliente is RigidBody3D: obj_saliente.apply_central_impulse(-global_transform.basis.z * 2.0)
	if obj_entrante:
		_meter_objeto_en_bolsillo(obj_entrante)

func tiene_objeto_ilegal() -> bool:
	var der = mano_der._objeto_agarrado and mano_der._objeto_agarrado.is_in_group("ilegal")
	var izq = mano_izq._objeto_agarrado and mano_izq._objeto_agarrado.is_in_group("ilegal")
	var bol = _objeto_en_bolsillo and _objeto_en_bolsillo.is_in_group("ilegal")
	return der or izq or bol
