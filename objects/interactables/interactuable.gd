# Esta línea hace que aparezca un icono personalizado en el editor (opcional)
@icon("res://icon.svg") 

extends StaticBody3D
class_name Interactuable


# Señal para avisar a otros sistemas (ej: abrir puerta)
signal al_interactuar

# Variable para saber si es de "mantener pulsado" (ej: reparar) o "click" (ej: botón)
@export var es_de_mantener: bool = false

# Función que el jugador llamará. 
# La dejaremos vacía aquí para sobrescribirla en cada objeto específico.
func interactuar() -> void:
	print("Interactuado con objeto genérico")
	al_interactuar.emit()

func detener_interaccion() -> void:
	pass
