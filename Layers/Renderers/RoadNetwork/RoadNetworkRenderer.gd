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

export(bool) var debug_draw: bool = false


var radius = 100000
var max_features = 10000

# Road id to road instance
var roads = {}
var intersections = []
var debug_points = []


const heightmap_size: float = 200.0
const heightmap_resolution: float = 100.0
const sample_rate: float = heightmap_size / heightmap_resolution

func _ready():
	$TerrainLOD0.height_layer = layer.render_info.ground_height_layer


# OVERRIDE #
# Runs in a thread!
func load_new_data():
	if debug_draw:
		$TerrainLOD0.position_x = center[0]
		$TerrainLOD0.position_y = center[1]
		$TerrainLOD0.build()
	
	
	var road_network_info: Layer.RoadNetworkRenderInfo = layer.render_info
	var road_features = road_network_info.road_layer.get_features_near_position(center[0], center[1], radius, max_features)
	var intersection_features = road_network_info.intersection_layer.get_features_near_position(center[0], center[1], radius, max_features)
	
	roads.clear()
	debug_points.clear()
	var i = 0
	for road in road_features:
		if i <= 10:
			_create_road(road, road_network_info.road_instance_scene)
		i += 1


# OVERRIDE #
func apply_new_data():
	if debug_draw:
		$TerrainLOD0.apply_textures()
		for child in $Debug.get_children():
			child.queue_free()
		for point in debug_points:
			$Debug.add_child(point)
	
	
	# Remove old objects
	for child in $Roads.get_children():
		child.queue_free()
	
	# Remove old objects
	for child in $Intersections.get_children():
		child.queue_free()
	
	# Add new objects
	for rode in roads.values():
		$Roads.add_child(rode)
		rode.apply_attributes()
	
	for intersection in intersections:
		$Intersections.add_child(intersection)



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

		var A = Vector3((x_grid + 1) * sample_rate, 0, z_grid * sample_rate)

		var bx = x_grid
		var bz = z_grid
		# Choose B depending on position in quad
		var in_lower_triangle: bool = fmod(point.x, sample_rate) + fmod(point.z, sample_rate) <= sample_rate
		if not in_lower_triangle:
			bx += 1
			bz += 1

		var B = Vector3(bx * sample_rate, 0, bz * sample_rate)
		var C = Vector3(x_grid * sample_rate, 0, (z_grid + 1) * sample_rate)
		
		A = _move_to_ground_height(A)
		B = _move_to_ground_height(B)
		C = _move_to_ground_height(C)
		
		# Get height for road points with triangular interpolation
		var weights = _triangularInterpolation(point, A, B, C)
		
		point.y = A.y * weights.x + B.y * weights.y + C.y * weights.z
		road_curve.set_point_position(index, point)
		
		if debug_draw:
			var debug_point: MeshInstance = $Debug_Point.duplicate()
			debug_point.transform.origin = point
			debug_points.append(debug_point)
	
	
	# Add additional curve points depending on heightmap resolution
	var current_point_index: int = 0
	var curve_point_count = road_curve.get_point_count()
	
	# Go through each road edge
	for i in range(curve_point_count - 1):
		var current_point = road_curve.get_point_position(current_point_index)
		var next_point = road_curve.get_point_position(current_point_index + 1)
	
		var x_grid_point = null
		var z_grid_point = null
		
		while true:
			
			var direction: Vector3 = next_point - current_point
			var x_grid = floor(current_point.x / sample_rate)
			var z_grid = floor(current_point.z / sample_rate)
			
			var is_reverse_grid_x: bool = (current_point.x / sample_rate) == x_grid && direction.x < 0
			var is_reverse_grid_z: bool = (current_point.z / sample_rate) == z_grid && direction.z < 0
			
			# INTERSECTION WITH DIAGONAL
			
			# If point is exactly on grid and direction is negative, move points 'back'
			if is_reverse_grid_x:
				x_grid -= 1
			
			if is_reverse_grid_z:
				z_grid -= 1
			
			
			var A = Vector3((x_grid + 1) * sample_rate, 0, z_grid * sample_rate)
			var C = Vector3(x_grid * sample_rate, 0, (z_grid + 1) * sample_rate)
			
			# Calculate intersection values
			var den: float = (current_point.x - next_point.x) * (C.z - A.z) - (current_point.z - next_point.z) * (C.x - A.x)
			var t: float = ((current_point.x - C.x) * (C.z - A.z) - (current_point.z - C.z) * (C.x - A.x)) / den
			var u: float = -(((current_point.x - next_point.x) * (current_point.z - C.z) - (current_point.z - next_point.z) * (current_point.x - C.x)) / den)
			
			# Only continue if intersection is with the line
			if t >= 0.0 && t <= 1.0 && u >= 0.0 && u <= 1.0:
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
				
				if debug_draw:
					var debug_point: MeshInstance = $Debug_Point_Intersect.duplicate()
					debug_point.transform.origin = intersection_point
					debug_points.append(debug_point)
			
			# INTERSECTION WITH GRID AXES
			
			# Only calculate grid point if we don't have one from last calculation
			if x_grid_point == null:
				var non_parallel: bool = direction.x != 0
				# Negative direction on grid edge case
				var intersections: float = abs(floor(next_point.x / sample_rate) - floor(current_point.x / sample_rate))
				
				if is_reverse_grid_x:
					intersections -= 1
				
				if non_parallel && intersections >= 1:
					# Calculate sampling grid offset
					var offset
					# If the direction is positive, go to the next grid on the right
					if sign(direction.x) == 1:
						offset = (sample_rate - fmod(current_point.x, sample_rate))
					# If the direction is negative, go to the next grid on the left
					else:
						offset = (fmod(current_point.x, sample_rate)) * -1
					
					# Going from one grid point to the next
					if offset == 0:
						offset += sample_rate * sign(direction.x)
						
					var z = direction.z / direction.x * offset
					x_grid_point = Vector3(current_point.x + offset, 0, current_point.z + z)
					x_grid_point = _move_to_ground_height(x_grid_point)
			
			# Same for z
			if z_grid_point == null :
				var non_parallel: bool = direction.z != 0
				var intersections: int = abs(floor(next_point.z / sample_rate) - floor(current_point.z / sample_rate))
				
				if is_reverse_grid_z:
					intersections -= 1
				
				if non_parallel && intersections >= 1:
					var offset
					if sign(direction.z) == 1:
						offset = (sample_rate - fmod(current_point.z, sample_rate))
					else:
						offset = (fmod(current_point.z, sample_rate)) * -1
					
					if offset == 0:
						offset += sample_rate * sign(direction.z)
					
					var x = direction.x / direction.z * offset
					z_grid_point = Vector3(current_point.x + x, 0, current_point.z + offset)
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
			
			if debug_draw:
				var debug_point: MeshInstance = $Debug_Point_Grid.duplicate()
				debug_point.transform.origin = current_point
				debug_points.append(debug_point)
		
		# Required to start from correct next point (while loop stops before)
		current_point_index += 1
	
	# TODO: Handle terrain LOD change
	
	
	road_instance.curve = road_curve
	road_instance.width = road_width
	
	# TODO: Add other road info to road instance
	
	roads[road_id] = road_instance


func _move_to_ground_height(vector :Vector3) -> Vector3:
	var ground_height: float = layer.render_info.ground_height_layer.get_value_at_position(center[0] + vector.x, center[1] - vector.z)
	return Vector3(vector.x, ground_height, vector.z)


func _get_grid_offset(from: float, to: float) -> float:
	var direction: float = to - from
	
	var non_parallel: bool = direction != 0
	# Negative direction edge case
	var intersects: bool = abs(floor(to / sample_rate) - floor(from / sample_rate)) >= 1 if direction >= 0 else 2
	
	# Only calculate grid point if we don't have one and there actually is one
	if non_parallel && intersects:
		
		# Calculate sampling grid offset
		var offset

		# If the direction is positive, go to the next grid on the right
		if sign(direction) == 1:
			offset = (sample_rate - fmod(from, sample_rate))
		# If the direction is negative, go to the next grid on the left
		else:
			offset = (fmod(from, sample_rate)) * -1
		
		# Going from one grid point to the next
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





