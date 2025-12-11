extends StaticBody3D

# --- CONFIGURACIÓN GENERAL ---
enum TipoBandeja { ENTRADA, SALIDA }
@export var tipo: TipoBandeja = TipoBandeja.ENTRADA

@export_group("Visuales")
@export var color_entrada: Color = Color.BLUE
@export var color_salida: Color = Color.RED
@export var mesh_bandeja: MeshInstance3D

@export_group("Configuración Entrada (Spawner)")
@export var documento_escena: PackedScene
@export var tiempo_entre_spawns: float = 4.0
@export var maximos_documentos: int = 5

# --- REFERENCIAS INTERNAS ---
@onready var punto_spawn: Marker3D = $PuntoSpawn
@onready var timer: Timer = $Timer
@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var detector: Area3D = $DetectorSalida

# Variables lógicas
var documentos_activos: Array = []
var boss_manager: BossManager

func _ready() -> void:
	_configurar_visuales()
	
	# DECISIÓN LÓGICA: ¿QUÉ SOY?
	match tipo:
		TipoBandeja.ENTRADA:
			_iniciar_modo_entrada()
		TipoBandeja.SALIDA:
			_iniciar_modo_salida()

func _configurar_visuales() -> void:
	if mesh_bandeja:
		var mat = StandardMaterial3D.new()
		if tipo == TipoBandeja.ENTRADA:
			mat.albedo_color = color_entrada
		else:
			mat.albedo_color = color_salida
		
		# Asignamos el material nuevo (o usa override si prefieres)
		mesh_bandeja.set_surface_override_material(0, mat)

# --- LÓGICA MODO ENTRADA (SPAWNER) ---
func _iniciar_modo_entrada() -> void:
	# 1. Borramos lo que no sirve para ahorrar recursos
	detector.queue_free() # No necesitamos detectar nada
	
	# 2. Configurar Spawner
	spawner.spawn_path = get_path()
	# ¡IMPORTANTE! Asegúrate de añadir documento_escena al "Auto Spawn List" en el editor
	# aunque lo usemos por código, el nodo debe tenerlo registrado.
	
	if multiplayer.is_server():
		timer.wait_time = tiempo_entre_spawns
		timer.timeout.connect(_on_timer_spawn)
		timer.start()

func _on_timer_spawn() -> void:
	# Limpieza de lista
	for i in range(documentos_activos.size() - 1, -1, -1):
		if not is_instance_valid(documentos_activos[i]):
			documentos_activos.remove_at(i)
	
	if documentos_activos.size() < maximos_documentos and documento_escena:
		var nuevo_doc = documento_escena.instantiate()
		var offset = Vector3(randf_range(-0.05, 0.05), 0, randf_range(-0.05, 0.05))
		nuevo_doc.position = punto_spawn.position + offset
		nuevo_doc.rotation_degrees.y = randf_range(-10, 10)
		
		add_child(nuevo_doc, true)
		documentos_activos.append(nuevo_doc)

# --- LÓGICA MODO SALIDA (VALIDADOR) ---
func _iniciar_modo_salida() -> void:
	# 1. Borramos lo que no sirve
	timer.queue_free()
	punto_spawn.queue_free()
	# spawner.queue_free() -> Cuidado, a veces da error si se borra en red, mejor déjalo quieto o bórralo si estás seguro.
	
	# 2. Configurar Detector
	if multiplayer.is_server():
		boss_manager = get_tree().current_scene.find_child("SistemaJefe", true, false)
		detector.body_entered.connect(_on_objeto_recibido)

func _on_objeto_recibido(cuerpo: Node3D) -> void:
	if not multiplayer.is_server(): return
	
	if cuerpo is Documento:
		if cuerpo.esta_sellado:
			_procesar_exito(cuerpo)
		else:
			_rechazar_documento(cuerpo)

func _procesar_exito(doc: Documento) -> void:
	print("[BANDEJA] Trabajo completado.")
	if boss_manager: boss_manager.rpc("agregar_caos", -5.0)
	doc.queue_free()

func _rechazar_documento(doc: Documento) -> void:
	doc.apply_central_impulse(Vector3.UP * 3.0)
