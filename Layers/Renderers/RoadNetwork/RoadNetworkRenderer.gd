extends LayerRenderer
class_name RoadNetworkRenderer

##### RoadNetwork data structure #####
### Roads
# edge_id			- Road id (equals LINK_ID in GIP)
# name				- Name of road, NONE if unknown
# width				- Average width of road
# speed_forward		- Max speed in road direction
# speed_backwards	- Max speed in opposite direction
# lanes_forward		- Number of lanes in road direction
# lanes_backwards	- Number of lanes in opposite direction
# direction			- 2 both, 1 edge direction, 0 opposite to edge direction, -1 unknown


var radius = 100000
var max_features = 1000

# Road id to road instance
var roads = {}
var intersections = []


# OVERRIDE #
func load_new_data():
	var road_network_info: Layer.RoadNetworkRenderInfo = layer.render_info
	var road_features = road_network_info.road_layer.get_features_near_position(center[0], center[1], radius, max_features)
	var intersection_features = road_network_info.intersection_layer.get_features_near_position(center[0], center[1], radius, max_features)
	
	for road in road_features:
		_create_road(road, road_network_info.road_instance_scene)
	

# OVERRIDE #
func apply_new_data():
	# Remove old objects
	for child in get_children():
		child.queue_free()
	
	# Add new objects
	for rode in roads.values():
		add_child(rode)
		rode.apply_attributes()
	
	for intersection in intersections:
		add_child(intersection)

# Runs in a thread!
func _create_road(road_feature, road_instance_scene: PackedScene) -> void:
	var road_id = road_feature.get_attribute("edge_id")
	var road_width = float(road_feature.get_attribute("width"))
	
	# Create Road instance
	var road_instance = road_instance_scene.instance()
	# Set road curve
	var road_curve = road_feature.get_offset_curve3d(-center[0], 0, -center[1])
	
	
	# TODO: Handle terrain LOD change
	for index in range(road_curve.get_point_count()):
		var point = road_curve.get_point_position(index)
		point = Vector3(point.x, _get_height_at_ground(point), point.z)
		road_curve.set_point_position(index, point)
	
	road_instance.curve = road_curve
	road_instance.width = road_width
	
	# TODO: Add other road info to road instance
	
	roads[road_id] = road_instance


# Returns the current ground height
func _get_height_at_ground(position: Vector3):
	return layer.render_info.ground_height_layer.get_value_at_position(
		center[0] + position.x, center[1] - position.z)











