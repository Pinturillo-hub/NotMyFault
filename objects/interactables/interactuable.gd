## Interactuable — Base class for static interactable objects.
## Override interactuar() in subclasses.
extends StaticBody3D
class_name Interactuable

signal al_interactuar

@export var es_de_mantener: bool = false

func interactuar() -> void:
	al_interactuar.emit()

func detener_interaccion() -> void:
	pass
