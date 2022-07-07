extends WindowDialog
class_name RoadNetworkUI


export(PackedScene) var road_network_info_scene: PackedScene


func set_window_title(title: String) -> void:
	self.window_title = title


func add_info(info_title: String, info_value: String) -> void:
	var info: RoadNetworkInfoUI = road_network_info_scene.instance()
	info.set_title(info_title)
	info.set_value(info_value)
	$ScrollContainer/VBoxContainer.add_child(info)


func clear_info() -> void:
	for child in $ScrollContainer/VBoxContainer.get_children():
		child.free()
