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
	var road_curve: Curve3D = road_feature.get_offset_curve3d(-center[0], 0, -center[1])
	
	# Apply terrain height to roads
	for index in range(road_curve.get_point_count()):
		var point = road_curve.get_point_position(index)
		point = Vector3(point.x, _get_height_at_ground(point), point.z)
		road_curve.set_point_position(index, point)
	
	# TODO: Lower resolution causes addtional points to be outside of curve
	# Add additional curve points depending on heightmap resolution
	var current_point_index: int = 0
	var next_point_index: int = 1
	var curve_point_count: int = road_curve.get_point_count()
	for curve_point_index in range(curve_point_count):
		# Actual curve points
		var current_point = road_curve.get_point_position(current_point_index)
		var next_point = road_curve.get_point_position(next_point_index)
		# Direction of curve edge
		var direction = next_point - current_point
		# Additional curve points on x axis
		var points_to_add_on_x = []
		# Number of intersections with the sample grid on x
		var number_of_x_intersects: int = ceil(abs(direction.x) / heightmap_sample_rate)
		for i in range(number_of_x_intersects):
			var x
			
			# If the direction is positive, go to the next grid on the right
			if sign(direction.x) == 1:
				x = (heightmap_sample_rate * (i + 1) - fmod(abs(current_point.x), heightmap_sample_rate))
			# If the direction is negative, go to the next grid on the left
			else:
				x = (fmod(abs(current_point.x), heightmap_sample_rate) + heightmap_sample_rate * i) * -1 
			
			# Calculate z with the z,x ratio of the direction
			var z = direction.z / direction.x * x
			
			# Add values as offsets to original point
			var point = Vector3(current_point.x + x, 0, current_point.z + z)
			# Get height for additional point
			point = Vector3(point.x, _get_height_at_ground(point), point.z)
			points_to_add_on_x.append(point)
		
		# Additional curve points on x axis
		var points_to_add_on_z = []
		# Number of intersections with the sample grid on z
		var number_of_z_intersects: int = ceil(abs(direction.z) / heightmap_sample_rate)
		for i in range(number_of_z_intersects):
			var z
			
			# If the direction is positive, go to the next grid on the right
			if sign(direction.z) == 1:
				z = (heightmap_sample_rate * (i + 1) - fmod(abs(current_point.z), heightmap_sample_rate))
			# If the direction is negative, go to the next grid on the left
			else:
				z = (fmod(abs(current_point.z), heightmap_sample_rate) + heightmap_sample_rate * i) * -1 
			
			# Calculate x with the x,z ratio of the direction
			var x = direction.x / direction.z * z
			
			# Add values as offsets to original point
			var point = Vector3(current_point.x + x, 0, current_point.z + z)
			# Get height for additional point
			point = Vector3(point.x, _get_height_at_ground(point), point.z)
			points_to_add_on_z.append(point)
		
		var x_index = 0
		var z_index = 0
		for i in range(points_to_add_on_x.size() + points_to_add_on_z.size()):
			current_point_index += 1
			if x_index >= points_to_add_on_x.size():
				road_curve.add_point(points_to_add_on_z[z_index], Vector3(), Vector3(), current_point_index)
				z_index += 1
				continue
			if z_index >= points_to_add_on_z.size():
				road_curve.add_point(points_to_add_on_x[x_index], Vector3(), Vector3(), current_point_index)
				x_index += 1
				continue
			
			if current_point.distance_squared_to(points_to_add_on_x[x_index]) < current_point.distance_squared_to(points_to_add_on_z[z_index]):
				road_curve.add_point(points_to_add_on_x[x_index], Vector3(), Vector3(), current_point_index)
				x_index += 1
			else:
				road_curve.add_point(points_to_add_on_z[z_index], Vector3(), Vector3(), current_point_index)
				z_index += 1
		
		
		
		next_point_index = current_point_index + 1
	
	
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







