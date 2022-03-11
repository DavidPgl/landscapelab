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


const heightmap_size: int = 500
const heightmap_resolution: int = 100
const heightmap_sample_rate: int = heightmap_size / heightmap_resolution


# OVERRIDE #
# Runs in a thread!
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


func _create_road(road_feature, road_instance_scene: PackedScene) -> void:
	var road_id = road_feature.get_attribute("edge_id")
	var road_width = float(road_feature.get_attribute("width"))
	
	# Create Road instance
	var road_instance = road_instance_scene.instance()
	# Set road curve
	var road_curve: Curve3D = road_feature.get_offset_curve3d(-center[0], 0, -center[1])
	
	# Apply terrain height to roads
	for index in range(road_curve.get_point_count()):
		var point = road_curve.get_point_position(index)
		point = Vector3(point.x, _get_height_at_ground(point), point.z)
		road_curve.set_point_position(index, point)
	
	
	# Add additional curve points depending on heightmap resolution
	var current_point_index: int = 0
	var curve_point_count = road_curve.get_point_count()
	
	# Go through each road edge
	for i in range(curve_point_count - 1):
		var current_point = road_curve.get_point_position(current_point_index)
		var next_point = road_curve.get_point_position(current_point_index + 1)
	
		var x_grid_point = null
		var z_grid_point = null
		
		var next_point_index = current_point_index + 1
		while current_point_index < next_point_index:
			# Direction of curve edge
			var direction = next_point - current_point
			
			# Only calculate grid point if we don't have one and there actually is one
			if x_grid_point == null && abs((next_point.x / heightmap_sample_rate) - (current_point.x / heightmap_sample_rate)) >= 1:
				
				# Calculate x sampling grid offset
				var x_offset

				# If the direction is positive, go to the next grid on the right
				if sign(direction.x) == 1:
					x_offset = (heightmap_sample_rate - fmod(abs(current_point.x), heightmap_sample_rate))
				# If the direction is negative, go to the next grid on the left
				else:
					x_offset = (fmod(abs(current_point.x), heightmap_sample_rate)) * -1 
				
				# Going from one x grid point to the next
				if x_offset == 0:
					x_offset += heightmap_sample_rate * sign(direction.x)
				
				var z = direction.z / direction.x * x_offset
				x_grid_point = Vector3(current_point.x + x_offset, 0, current_point.z + z)
				x_grid_point = Vector3(x_grid_point.x, _get_height_at_ground(x_grid_point), x_grid_point.z)
			
			# Only calculate grid point if we don't have one and there actually is one
			if z_grid_point == null && abs((next_point.z / heightmap_sample_rate) - (current_point.z / heightmap_sample_rate)) >= 1:
				
				# Calculate sampling grid z offset
				var z_offset

				# If the direction is positive, go to the next grid on the right
				if sign(direction.z) == 1:
					z_offset = (heightmap_sample_rate - fmod(abs(current_point.z), heightmap_sample_rate))
				# If the direction is negative, go to the next grid on the left
				else:
					z_offset = (fmod(abs(current_point.z), heightmap_sample_rate)) * -1
				
				# Going from one z grid point to the next
				if z_offset == 0:
					z_offset += heightmap_sample_rate * sign(direction.z)
				
				var x = direction.x / direction.z * z_offset
				z_grid_point = Vector3(current_point.x + x, 0, current_point.z + z_offset)
				z_grid_point = Vector3(z_grid_point.x, _get_height_at_ground(z_grid_point), z_grid_point.z)
			
			# If no grid points, done with this curve edge
			if x_grid_point == null && z_grid_point == null:
				break
			
			# Add closest one
			if z_grid_point == null || x_grid_point != null && current_point.distance_squared_to(x_grid_point) <= current_point.distance_squared_to(z_grid_point):
				road_curve.add_point(x_grid_point, Vector3(), Vector3(), current_point_index + 1)
				current_point = x_grid_point
				x_grid_point = null
			else:
				road_curve.add_point(z_grid_point, Vector3(), Vector3(), current_point_index + 1)
				current_point = z_grid_point
				z_grid_point = null
			
			# Move to newly added point and start from there again
			current_point_index += 1
			next_point_index += 1
		
		# Required to start from correct next point (while loop stops before)
		current_point_index += 1
	
	# TODO: Handle terrain LOD change
	
	
	road_instance.curve = road_curve
	road_instance.width = road_width
	
	# TODO: Add other road info to road instance
	
	roads[road_id] = road_instance


# Returns the current ground height
func _get_height_at_ground(position: Vector3):
	return layer.render_info.ground_height_layer.get_value_at_position(
		center[0] + position.x, center[1] - position.z)



func customCompare(a: Vector3, b: Vector3):
	return a.length_squared() < b.length_squared()







