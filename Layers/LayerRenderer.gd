extends Spatial
class_name LayerRenderer


# Dependency comes from the LayerRenderers-Node which should always be above in the tree
var layer: Layer

# Offset to use as the center position
var center := [0, 0]
var shift := [0, 0]

var new_data_applied: bool = false setget set_new_data_applied

# Time management
var time_manager setget set_time_manager
var is_daytime = true

const LOG_MODULE := "LAYERRENDERERS"

signal layer_visibility_changed(is_visible)


func _ready():
	layer.connect("visibility_changed", self, "set_visible")


func set_visible(is_visible):
	emit_signal("layer_visibility_changed", is_visible)
	if new_data_applied:
		.set_visible(is_visible)
	


func set_new_data_applied(value: bool) -> void:
	new_data_applied = value
	if value:
		.set_visible(true)


# Overload with the functionality to load new data, but not use (visualize) it yet. Run in a thread,
#  so watch out for thread safety!
func load_new_data():
	pass


# Overload to return a string with statistics and information about the current state of this
# renderer
func get_debug_info() -> String:
	return ""


# Overload with applying and visualizing the data. Not run in a thread.
func apply_new_data():
	_apply_daytime_change(is_daytime)


func set_time_manager(manager: TimeManager):
	time_manager = manager
	time_manager.connect("daytime_changed", self, "_apply_daytime_change")


# Emitted from the injected time_manager
func _apply_daytime_change(daytime: bool):
	is_daytime = daytime
	
	for child in get_children():
		if child.has_method("apply_daytime_change"):
			child.apply_daytime_change(daytime)
