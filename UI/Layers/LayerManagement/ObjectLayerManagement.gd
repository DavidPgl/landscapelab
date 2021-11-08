extends AbstractLayerManagement


var edit_cursor = preload("res://Resources/Icons/ModernLandscapeLab/paintbrush.svg")
var edit_action: ActionHandler.Action


func _ready():
	$Edit.connect("toggled", self, "_on_edit")
	$List.connect("toggled", self, "_on_list")
	$List/ListWindow/ItemList.connect("item_selected", self, "_on_feature_list_item_selected")


func set_player(player):
	.set_player(player)
	edit_action = EditAction.new(layer, pc_player.action_handler.cursor, pos_manager, pc_player, false)


class EditAction extends ActionHandler.Action:
	var cursor: RayCast
	var layer: Layer
	var pos_manager: PositionManager
	
	func _init(l, c, p_m, p, blocking).(p, blocking):
		cursor = c
		layer = l
		pos_manager = p_m
	
	func apply(event: InputEvent):
		if event.is_action_pressed("layer_add_feature"):
			var new_feature = layer.create_feature()
			
			var global_center = pos_manager.get_center()
			new_feature.set_offset_vector3(cursor.get_collision_point(), 
					global_center[0], 0, global_center[1])


func _on_edit(toggled):
	if toggled:
		pc_player.action_handler.set_current_action(edit_action, edit_cursor)
	else:
		pc_player.action_handler.stop_current_action()


func load_features_into_list():
	var features = layer.get_features_near_position(0, 0, 1000000000, 100)
	
	for feature in features:
		var new_id = $List/ListWindow/ItemList.get_item_count()
		var position = feature.get_vector3()
		# TODO: Why do we need to reverse the z coordinate? seems like an inconsistency in coordinate handling
		position.z = -position.z
		
		$List/ListWindow/ItemList.add_item(str(position))
		$List/ListWindow/ItemList.set_item_metadata(new_id, position)


func _on_feature_list_item_selected(item_id):
	var global_pos = $List/ListWindow/ItemList.get_item_metadata(item_id)
	pc_player.set_true_position(global_pos)


func _on_list(toggled):
	if toggled:
		$List/ListWindow.popup()
		load_features_into_list()
	else:
		$List/ListWindow.hide()
