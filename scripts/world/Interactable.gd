class_name Interactable
extends Area3D
## Base class for anything the player can walk up to and press Interact on.
##
## Subclasses override `_perform` and, if the action can be blocked, `is_available`
## plus `unavailable_reason`. The HUD only ever sees `prompt_label()`.

signal interacted(by: Node3D)

@export var title: String = "Interagível"
@export var verb: String = "Falar"
@export var radius: float = 2.2

var _shape: CollisionShape3D = null


func _ready() -> void:
	collision_layer = GameLayers.INTERACT
	collision_mask = 0
	monitoring = false
	monitorable = true
	if _shape == null:
		_shape = CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = radius
		_shape.shape = sphere
		add_child(_shape)


func prompt_label() -> String:
	return "%s  %s" % [verb, title]


func is_available() -> bool:
	return true


func unavailable_reason() -> String:
	return ""


## Entry point used by PlayerController. Do not override this - override `_perform`.
func interact(by: Node3D) -> void:
	if not is_available():
		var reason := unavailable_reason()
		if reason != "":
			Notify.warn(reason)
		return
	_perform(by)
	interacted.emit(by)


func _perform(_by: Node3D) -> void:
	pass
