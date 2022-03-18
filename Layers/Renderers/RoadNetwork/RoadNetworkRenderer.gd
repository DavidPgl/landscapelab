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


const heightmap_size: int = 31250
const heightmap_resolution: int = 500
const sample_rate: int = heightmap_size / heightmap_resolution


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

	# TODO: Maybe move this into main iteration loop
	# Set initial road point heights
	for index in range(road_curve.get_point_count()):
		var point = road_curve.get_point_position(index)
		
		var x_grid = floor(point.x / sample_rate)
		var z_grid = floor(point.z / sample_rate)

		var A = Vector3(x_grid * sample_rate, 0, z_grid * sample_rate)

		var bx = x_grid
		var bz = z_grid
		# Choose B depending on current_points position in quad
		var in_lower_triangle: bool = fmod(point.x, sample_rate) + fmod(point.z, sample_rate) <= sample_rate
		if in_lower_triangle:
			bx += 1
		else:
			bz += 1

		var B = Vector3(bx * sample_rate, 0, bz * sample_rate)
		var C = Vector3((x_grid + 1) * sample_rate, 0, (z_grid + 1) * sample_rate)
		
		A = _move_to_ground_height(A)
		B = _move_to_ground_height(B)
		C = _move_to_ground_height(C)
		
		# Get height for road points with triangular interpolation
		var weights = _triangularInterpolation(point, A, B, C)
		
		point.y = A.y * weights.x + B.y * weights.y + C.y * weights.z
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
			
			var x_grid = floor(current_point.x / sample_rate)
			var z_grid = floor(current_point.z / sample_rate)
			
			# TODO: Limit A, B, C calculation
			# INTERSECTION WITH DIAGONAL
			
			var A = Vector3(x_grid * sample_rate, 0, z_grid * sample_rate)
			var C = Vector3((x_grid + 1) * sample_rate, 0, (z_grid + 1) * sample_rate)
			
			# Calculate intersection values
			var den = (current_point.x - next_point.x) * (C.z - A.z) - (current_point.z - next_point.z) * (C.x - A.x)
			var t = ((current_point.x - C.x) * (C.z - A.z) - (current_point.z - C.z) * (C.x - A.x)) / den
			var u = ((current_point.x - next_point.x) * (current_point.z - C.z) - (current_point.z - next_point.z) * (current_point.x - C.x)) / den
			
			# Only continue if intersection is with the line
			if t >= 0 && t <= 1 && u >= 0 && u <= 1:
				var I = Vector3(
					current_point.x + t * (next_point.x - current_point.x),
					0,
					current_point.z + t * (next_point.z - current_point.z))
				
				# Calculate vectors for projection without z
				var CI = I - C
				var CA = A - C
				
				# Calculate actual intersection point with z
				A = _move_to_ground_height(A)
				C = _move_to_ground_height(C)
				
				var intersection_point = (CI.length() / CA.length()) * (A - C) + C
				
				# Add intersection to curve
				road_curve.add_point(intersection_point, Vector3(), Vector3(), current_point_index + 1)
				current_point_index += 1
				next_point_index += 1
			
			# INTERSECTION WITH GRID AXES
			
			# Direction of curve edge
			var direction = next_point - current_point
			
			# Only calculate grid point if we don't have one from last calculation
			if x_grid_point == null:
				var x_offset = _get_grid_offset(current_point.x, next_point.x)
				if x_offset != 0.0:
					var z = direction.z / direction.x * x_offset
					x_grid_point = Vector3(current_point.x + x_offset, 0, current_point.z + z)
					x_grid_point = _move_to_ground_height(x_grid_point)
			
			if z_grid_point == null :
				var z_offset = _get_grid_offset(current_point.z, next_point.z)
				if z_offset != 0.0:
					var x = direction.x / direction.z * z_offset
					z_grid_point = Vector3(current_point.x + x, 0, current_point.z + z_offset)
					z_grid_point = _move_to_ground_height(z_grid_point)
			
			
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


func _move_to_ground_height(vector :Vector3) -> Vector3:
	return Vector3(vector.x, layer.render_info.ground_height_layer.get_value_at_position(center[0] + vector.x, center[1] - vector.z), vector.z)


func _get_grid_offset(from: float, to: float) -> float:
	var direction: float = to - from
	
	var non_parallel: bool = direction != 0
	var intersects: bool = abs((to / sample_rate) - (from / sample_rate)) >= 1
	
	# Only calculate grid point if we don't have one and there actually is one
	if non_parallel && intersects:
		
		# Calculate sampling grid offset
		var offset

		# If the direction is positive, go to the next grid on the right
		if sign(direction) == 1:
			offset = (sample_rate - fmod(abs(from), sample_rate))
		# If the direction is negative, go to the next grid on the left
		else:
			offset = (fmod(abs(from), sample_rate)) * -1
		
		# Going from one x grid point to the next
		if offset == 0:
			offset += sample_rate * sign(direction)
		
		return offset
	else:
		return 0.0


func _triangularInterpolation(P, A, B, C) -> Vector3:
	var W1 = ((B.z - C.z) * (P.x - C.x) + (C.x - B.x) * (P.z - C.z)) / ((B.z - C.z) * (A.x - C.x) + (C.x - B.x) * (A.z - C.z))
	var W2 = ((C.z - A.z) * (P.x - C.x) + (A.x - C.x) * (P.z - C.z)) / ((B.z - C.z) * (A.x - C.x) + (C.x - B.x) * (A.z - C.z))
	var W3 = 1 - W1 - W2
	
	return Vector3(W1, W2, W3)





