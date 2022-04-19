extends SpecificLayerUI


func _ready():
	$RightBox/CheckBox.connect("toggled", self, "_toggle_color_menu")
	$RightBox/ButtonMin.connect("pressed", self, "_pop_color_picker", [$RightBox/ButtonMin])
	$RightBox/ButtonMax.connect("pressed", self, "_pop_color_picker", [$RightBox/ButtonMax])


func _toggle_color_menu(toggled: bool):
	$RightBox/ButtonMax.visible = toggled
	$LeftBox/ColorMax.visible = toggled
	$RightBox/ButtonMin.visible = toggled
	$LeftBox/ColorMin.visible = toggled
	$LeftBox/Alpha.visible = toggled
	$RightBox/AlphaSpinBox.visible = toggled


func _pop_color_picker(button: Button):
	var color_dialog = button.get_node("ConfirmationDialog")
	var color_picker = color_dialog.get_node("ColorPicker")
	color_dialog.connect("confirmed", self, "_set_color", [button, color_picker])
	color_dialog.popup(Rect2(button.rect_global_position, Vector2(0,0)))


func _set_color(button: Button, color_picker: ColorPicker):
	button.color = color_picker.color


func assign_specific_layer_info(layer):
	if layer.render_info == null:
		layer.render_info = Layer.BasicTerrainRenderInfo.new()
	
	var texture_layer = $RightBox/GeodataChooserTexture.get_geo_layer(true)
	var height_layer = $RightBox/GeodataChooserHeight.get_geo_layer(true)

	if !validate(texture_layer) or !validate(height_layer):
		print_warning("Texture- or height-layer is invalid!")
		return
	
	layer.render_info.height_layer = height_layer.clone()
	layer.render_info.texture_layer = texture_layer.clone()
	layer.render_info.is_color_shaded = $RightBox/CheckBox.pressed
	layer.render_info.max_color = $RightBox/ButtonMax.color
	layer.render_info.min_color = $RightBox/ButtonMin.color
	layer.render_info.alpha = $RightBox/AlphaSpinBox.value


# TODO: implement this function accordingly, so when editing an existing one, all configurations will be applied
func init_specific_layer_info(layer):
	if layer == null:
		return
	
	#file_path_height = 
	#file_path_
