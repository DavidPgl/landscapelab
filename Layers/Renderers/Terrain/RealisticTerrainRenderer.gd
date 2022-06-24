extends LayerRenderer
class_name RealisticTerrainRenderer


var lods = []
var LOD0


func _ready():
	# Spawn LODs
	for scales in range(4):
		for x in range(-1, 2):
			for y in range(-1, 2):
				var lod = preload("res://Layers/Renderers/Terrain/TerrainLOD.tscn").instance()
				
				if x == 0 and y == 0:
					if scales == 0:
						lod.mesh = preload("res://Layers/Renderers/Terrain/lod_mesh_300x300.obj")
						lod.mesh_resolution = 300
						LOD0 = lod
					else:
						continue
				
				if scales == 0:
					lod.load_detail_textures = true
					lod.load_fade_textures = true
				elif scales == 1:
					lod.load_fade_textures = true
				else:
					lod.always_load_landuse = true
				
				var size = pow(3.0, scales) * 300.0
				lod.translation.x = x * size
				lod.translation.z = y * size
				lod.size = size
				
				lod.height_layer = layer.render_info.height_layer.clone()
				lod.texture_layer = layer.render_info.texture_layer.clone()
				lod.landuse_layer = layer.render_info.landuse_layer.clone()
				lod.surface_height_layer = layer.render_info.surface_height_layer.clone()
				
				lods.append(lod)
	
	for lod in lods:
		$LODs.add_child(lod)
	
	# Setup Road Network
	$RoadNetworkRenderer.road_layer = layer.render_info.road_layer
	$RoadNetworkRenderer.intersection_layer = layer.render_info.intersection_layer
	$RoadNetworkRenderer.road_instance_scene = layer.render_info.road_instance_scene
	$RoadNetworkRenderer.intersection_instance_scene = layer.render_info.intersection_instance_scene


func load_new_data():
	for lod in lods:
		lod.position_x = center[0]
		lod.position_y = center[1]
		
		lod.build()
	
	


func apply_new_data():
	for lod in lods:
		lod.apply_textures()
	
	$RoadNetworkRenderer.center = center
	$RoadNetworkRenderer.load_data()
	$RoadNetworkRenderer.apply_data()


func set_height_correction_texture(height_correction_texture) -> void:
	LOD0.set_height_correction_texture(height_correction_texture)


func get_debug_info() -> String:
	return "{0} LODs with a maximum size of {1} m.".format([
		lods.size(),
		lods.back().size
	])
