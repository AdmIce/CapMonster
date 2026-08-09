class_name CreaturePreview
extends SubViewportContainer
## Reusable 3D portrait of a creature: its model on a turntable, lit the same
## way everywhere. Used by the starter picker now and by the creature menu later.

const DEFAULT_SIZE := Vector2i(240, 240)

var _pivot: Node3D = null
var _model: Node3D = null
var _spin_speed: float = 0.5
var _interactive: bool = false
var _dragging: bool = false


func _init(species: CreatureSpecies = null, preview_size: Vector2i = DEFAULT_SIZE, spin: float = 0.5) -> void:
	stretch = true
	custom_minimum_size = Vector2(preview_size)
	# Decorative by default; set_interactive() opts back into input.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spin_speed = spin

	var viewport := SubViewport.new()
	viewport.size = preview_size
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_2X
	add_child(viewport)

	var scene_root := Node3D.new()
	viewport.add_child(scene_root)

	_pivot = Node3D.new()
	scene_root.add_child(_pivot)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.0
	camera.position = Vector3(0, 1.15, 3.6)
	camera.rotation_degrees = Vector3(-10, 0, 0)
	scene_root.add_child(camera)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.6
	key.rotation_degrees = Vector3(-40, 30, 0)
	scene_root.add_child(key)

	var rim := DirectionalLight3D.new()
	rim.light_energy = 0.7
	rim.light_color = Color("#8FA8C4")
	rim.rotation_degrees = Vector3(-8, -150, 0)
	scene_root.add_child(rim)

	if species != null:
		set_species(species)


func set_species(species: CreatureSpecies) -> void:
	if _model != null:
		_model.queue_free()
	_model = CreatureModelBuilder.build(species)
	_pivot.add_child(_model)


## Lets the player drag to rotate instead of only auto-spinning.
func set_interactive(enabled: bool) -> void:
	_interactive = enabled
	mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if _pivot != null and not _dragging:
		_pivot.rotation.y += delta * _spin_speed


func _gui_input(event: InputEvent) -> void:
	if not _interactive:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		_pivot.rotation.y -= event.relative.x * 0.01
