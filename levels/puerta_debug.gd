extends Node3D

@onready var label: Label3D = $Label3D
@onready var area: Area3D = $Area3D

@export var jefe_sistema: BossManager 

var _jugador_escuchando: bool = false

func _ready() -> void:
	print("[PUERTA] Iniciando PuertaDebug...")
	
	# 1. Chequeo de Nodos Hijos
	if not label: print("[ERROR] Falta el Label3D")
	if not area: print("[ERROR] Falta el Area3D")
	
	# 2. Búsqueda del Jefe
	if not jefe_sistema:
		print("[PUERTA] Buscando nodo 'SistemaJefe'...")
		jefe_sistema = get_tree().current_scene.find_child("SistemaJefe", true, false)
	
	if jefe_sistema:
		print("[PUERTA] ✅ Jefe encontrado correctamente.")
	else:
		print("[PUERTA] ❌ ERROR CRÍTICO: No encuentro al nodo 'SistemaJefe'. Revisa el nombre en la escena o asígnalo manualmente.")

	label.text = "DEBUG: INICIADO"
	
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

func _process(_delta: float) -> void:
	# Si no hay jefe, no hacemos nada
	if not jefe_sistema: return

	# Debug en consola constante (Solo para probar, luego bórralo)
	# print("Ira actual: ", jefe_sistema.ira_actual) 

	if _jugador_escuchando:
		var ira = jefe_sistema.ira_actual
		label.text = "IRA: %d%%" % int(ira)
		label.visible = true

func _on_body_entered(body: Node3D) -> void:
	print("[PUERTA] Algo ha entrado: ", body.name)
	
	if body.is_in_group("jugadores"):
		print("[PUERTA] ✅ Es un jugador. Activando UI.")
		_jugador_escuchando = true
		label.visible = true
		label.text = "ESCUCHANDO..."
	else:
		print("[PUERTA] ⚠️ Objeto detectado pero NO está en grupo 'jugadores'.")

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("jugadores"):
		print("[PUERTA] Jugador salió.")
		_jugador_escuchando = false
		label.text = "ALEJADO"
