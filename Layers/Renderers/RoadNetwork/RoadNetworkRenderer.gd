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
# lanes_backwards	- Number of lanes in opposite directio
# direction			- 2 both, 1 edge direction, 0 opposite to edge direction, -1 unknown

export(bool) var debug_draw_points: bool = false


const radius = 2000
const max_features = 50000

const mesh_size: float = 150.0
const mesh_resolution: float = 100.0

const lod_sample_rates: Array = [
	1.0,
	3.0,
	9.0,
	27.0
]

var roads_parent: Node

# Road id to road instance
var roads: Dictionary = {}
var debug_points: Array = []

var height_correction_data: PoolByteArray

var height_correction_image: Image = Image.new()
var height_correction_texture: ImageTexture = ImageTexture.new()

var terrain_renderer: RealisticTerrainRenderer


func _ready():
	#height_correction_image.create(mesh_size, mesh_size, false, Image.FORMAT_RF)
	#height_correction_texture.storage = ImageTexture.STORAGE_RAW
	#height_correction_texture.create_from_image(height_correction_image, Image.FORMAT_RF)
	
	#height_correction_data.resize(mesh_size * mesh_size * 4)
	
	# TODO: Replace with better access
	# Find and get terrain renderer
	for renderer in get_parent().get_children():
		if renderer is RealisticTerrainRenderer:
			terrain_renderer = renderer
			return


# OVERRIDE #
# Runs in a thread!
func load_new_data():
	pass
			# Get points on other axis
			#_set_correction_heights(point, sample_rate, road.width)
	
	#for road in roads_to_add.values():
	#	var curve: Curve3D = road.curve
	#	for index in curve.get_point_count():
	#		var point: Vector3 = curve.get_point_position(index)
			# Get points on other axis
			#_set_correction_heights(point, sample_rate, road.width)
	
	#height_correction_image.create_from_data(mesh_size, mesh_size, false, Image.FORMAT_RF, height_correction_data)
	#height_correction_texture.set_data(height_correction_image)
	#terrain_renderer.set_height_correction_texture(height_correction_texture)


# OVERRIDE #
func apply_new_data():
	var road_network_info: Layer.RoadNetworkRenderInfo = layer.render_info
	var road_features = road_network_info.road_layer.get_features_near_position(center[0], center[1], radius, max_features)
	var intersection_features = road_network_info.intersection_layer.get_features_near_position(center[0], center[1], radius, max_features)

	# Reset corrections
	#for i in range(mesh_size * mesh_size * 4):
	#	height_correction_data[i] = 0
	
	roads_parent = Node.new()
	roads_parent.name = "Roads"
	for road in road_features:
		_create_road(road, road_network_info.road_instance_scene)
	
	for road in roads.values():
		var curve: Curve3D = road.curve
		for index in curve.get_point_count():
			var point: Vector3 = curve.get_point_position(index)
			point -= Vector3(shift[0], 0, shift[1])
	
	if debug_draw_points:
		for child in $Debug.get_children():
			child.queue_free()
		for point in debug_points:
			$Debug.add_child(point)
		debug_points.clear()
	
	
	# Remove old objects
	$Roads.free()
	roads.clear()
	
	add_child(roads_parent)


# Creates new road instances and splits the underlying Curve3D depending on ground height mesh
func _create_road(road_feature, road_instance_scene: PackedScene) -> void:
	var road_id: int = int(road_feature.get_attribute("edge_id"))
	
	# Create Road instance
	var road_instance = road_instance_scene.instance()
	# Set road curve
	var road_curve: Curve3D = road_feature.get_offset_curve3d(-center[0], 0, -center[1])
	var road_width = float(road_feature.get_attribute("width"))

	# Set initial road point heights
	for index in range(road_curve.get_point_count()):
		# Make sure all roads are facing up
		road_curve.set_point_tilt(index, 0)
		
		var point = road_curve.get_point_position(index)
		
		# Get the LOD
		var current_lod: int = 0
		var lod_size: float = 0
		for j in range(4):
			lod_size = pow(3, j) * 300
			if abs(point.x) <= lod_size / 2 and abs(point.z) <= lod_size / 2:
				break
			current_lod += 1
		
		var sample_rate = lod_sample_rates[current_lod]
		
		
		var x_grid = floor(point.x / sample_rate)
		var z_grid = floor(point.z / sample_rate)

		var A = Vector3((x_grid + 1) * sample_rate, 0, z_grid * sample_rate)

		var bx = x_grid
		var bz = z_grid
		# Choose B depending on position in quad
		var in_lower_triangle: bool = fposmod(point.x, sample_rate) + fposmod(point.z, sample_rate) <= sample_rate
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
		
		if debug_draw_points:
			var debug_point: MeshInstance = $Debug_Point.duplicate() if index > 0 else $Debug_Point_Start.duplicate()
			debug_point.transform.origin = point
			debug_points.append(debug_point)
	
	
	# Add additional curve points depending on heightmap resolution
	var current_point_index: int = 0
	var curve_point_count = road_curve.get_point_count()
	
	var lod_x_grid_point
	var lod_z_grid_point
	# Go through each road edge
	var i: int = 0
	while(i < curve_point_count - 1):
		var current_point: Vector3 = road_curve.get_point_position(current_point_index)
		var next_point: Vector3 = road_curve.get_point_position(current_point_index + 1)
		
		# Get the LOD
		var current_lod: int = 0
		var lod_size: float = 0
		for j in range(4):
			lod_size = pow(3, j) * 300
			if abs(current_point.x) <= lod_size / 2 and abs(current_point.z) <= lod_size / 2:
				if (current_point == lod_x_grid_point or current_point == lod_z_grid_point) and\
				(abs(next_point.x) > lod_size / 2 or abs(next_point.z) > lod_size / 2):
					current_lod += 1
					break
				lod_size = pow(3, max(0, j - 1)) * 300
				break
			current_lod += 1
		
		
		var sample_rate = lod_sample_rates[current_lod]
		var shift = Vector3(lod_size / 2, 0, lod_size / 2)
		# Get intersections with LOD grid
		lod_x_grid_point = _get_x_grid_intersection(current_point - shift, next_point - shift, lod_size)
		lod_z_grid_point = _get_z_grid_intersection(current_point - shift, next_point - shift, lod_size)
		
		# Add LOD grid intersection as point
		if lod_x_grid_point != null or lod_z_grid_point != null:
			if lod_z_grid_point == null || (lod_x_grid_point != null && current_point.distance_squared_to(lod_x_grid_point + shift) <= current_point.distance_squared_to(lod_z_grid_point + shift)):
				lod_x_grid_point += shift
				
				var x_grid = floor(lod_x_grid_point.x / sample_rate)
				var z_grid = floor(lod_x_grid_point.z / sample_rate)

				var P1 = Vector3(x_grid * sample_rate, 0, z_grid * sample_rate)
				var P2 = Vector3(x_grid * sample_rate, 0, (z_grid + 1) * sample_rate)
				
				var p1_height = _get_ground_height(P1)
				var p2_height = _get_ground_height(P2)
				
				var weight: float = RoadNetworkUtil.inverse_lerp_vector(P1, P2, lod_x_grid_point)
				
				var height = p1_height * (1 - weight) + p2_height * weight
				lod_x_grid_point.y = height
				
				road_curve.add_point(lod_x_grid_point, Vector3.ZERO, Vector3.ZERO, current_point_index + 1)
				next_point = lod_x_grid_point
				
				if debug_draw_points:
					var debug_point: MeshInstance = $Debug_Point_Intersect_LOD.duplicate()
					debug_point.transform.origin = lod_x_grid_point
					debug_points.append(debug_point)
				
			else:
				lod_z_grid_point += shift
				
				var x_grid = floor(lod_z_grid_point.x / sample_rate)
				var z_grid = floor(lod_z_grid_point.z / sample_rate)

				var P1 = Vector3(x_grid * sample_rate, 0, z_grid * sample_rate)
				var P2 = Vector3(x_grid * sample_rate, 0, (z_grid + 1) * sample_rate)
				
				var p1_height = _get_ground_height(P1)
				var p2_height = _get_ground_height(P2)
				
				var weight: float = RoadNetworkUtil.inverse_lerp_vector(P1, P2, lod_z_grid_point)
				
				var height = p1_height * (1 - weight) + p2_height * weight
				lod_z_grid_point.y = height
				
				road_curve.add_point(lod_z_grid_point, Vector3.ZERO, Vector3.ZERO, current_point_index + 1)
				next_point = lod_z_grid_point
				
				if debug_draw_points:
					var debug_point: MeshInstance = $Debug_Point_Intersect_LOD.duplicate()
					debug_point.transform.origin = lod_z_grid_point
					debug_points.append(debug_point)
			i -= 1
		
		i += 1
		
		var x_grid_point = null
		var z_grid_point = null
		while true:
			
			# INTERSECTION WITH DIAGONAL
			var intersection_point = _get_diagonal_point(current_point, next_point, sample_rate)
			if intersection_point != null:
				# Calculate correct height by interpolating between grid points
				var x_grid = floor(intersection_point.x / sample_rate)
				var z_grid = floor(intersection_point.z / sample_rate)
				
				var A = Vector3((x_grid + 1) * sample_rate, 0, z_grid * sample_rate)
				var C = Vector3(x_grid * sample_rate, 0, (z_grid + 1) * sample_rate)
				
				var a_height = _get_ground_height(A)
				var c_height = _get_ground_height(C)
				var weight: float = RoadNetworkUtil.inverse_lerp_vector(A, C, intersection_point)
				var height = a_height * (1 - weight) + c_height * weight
				
				intersection_point.y = height
				
				# Add intersection to curve
				road_curve.add_point(intersection_point, Vector3.ZERO, Vector3.ZERO, current_point_index + 1)
				current_point_index += 1
				
				if debug_draw_points:
					var debug_point: MeshInstance = $Debug_Point_Intersect.duplicate()
					debug_point.transform.origin = intersection_point
					debug_points.append(debug_point)
			
			# INTERSECTION WITH GRID AXES
			
			# Only calculate grid point if we don't have one from last calculation
			if x_grid_point == null:
				x_grid_point = _get_x_grid_intersection(current_point, next_point, sample_rate)
				if x_grid_point != null:
					# Calculate correct height by interpolating between grid points
					var x_grid = floor(x_grid_point.x / sample_rate)
					var z_grid = floor(x_grid_point.z / sample_rate)

					var P1 = Vector3(x_grid * sample_rate, 0, z_grid * sample_rate)
					var P2 = Vector3(x_grid * sample_rate, 0, (z_grid + 1) * sample_rate)
					
					var p1_height = _get_ground_height(P1)
					var p2_height = _get_ground_height(P2)
					
					var weight: float = RoadNetworkUtil.inverse_lerp_vector(P1, P2, x_grid_point)
					var height = p1_height * (1 - weight) + p2_height * weight
					
					x_grid_point.y = height
			
			# Same for z
			if z_grid_point == null:
				z_grid_point = _get_z_grid_intersection(current_point, next_point, sample_rate)
				if z_grid_point != null:
					var x_grid = floor(z_grid_point.x / sample_rate)
					var z_grid = floor(z_grid_point.z / sample_rate)

					var P1 = Vector3(x_grid * sample_rate, 0, z_grid * sample_rate)
					var P2 = Vector3((x_grid + 1) * sample_rate, 0, z_grid * sample_rate)
					
					var p1_height = _get_ground_height(P1)
					var p2_height = _get_ground_height(P2)
					
					var weight: float = RoadNetworkUtil.inverse_lerp_vector(P1, P2, z_grid_point)
					var height = p1_height * (1 - weight) + p2_height * weight
					
					z_grid_point.y = height
			
			# If no grid points, done with this curve edge
			if x_grid_point == null && z_grid_point == null:
				# Move to next points
				current_point_index += 1
				break
			
			# Add closest one
			if z_grid_point == null || (x_grid_point != null && current_point.distance_squared_to(x_grid_point) <= current_point.distance_squared_to(z_grid_point)):
				road_curve.add_point(x_grid_point, Vector3.ZERO, Vector3.ZERO, current_point_index + 1)
				current_point = x_grid_point
				x_grid_point = null
			else:
				road_curve.add_point(z_grid_point, Vector3.ZERO, Vector3.ZERO, current_point_index + 1)
				current_point = z_grid_point
				z_grid_point = null
			
			# Move to newly added point and start from there again
			current_point_index += 1
			
			if debug_draw_points:
				var debug_point: MeshInstance = $Debug_Point_Grid.duplicate()
				debug_point.transform.origin = current_point
				debug_points.append(debug_point)
	
	
	road_instance.curve = road_curve
	road_instance.width = road_width
	
	# TODO: Add other road info to road instance
	roads_parent.add_child(road_instance)

# Moves the given vector to the ground and returns it
func _move_to_ground_height(vector: Vector3) -> Vector3:
	return Vector3(vector.x, _get_ground_height(vector), vector.z)


# Gets the ground height at the given position
func _get_ground_height(vector: Vector3) -> float:
	var space_state = get_world().direct_space_state
	var result = space_state.intersect_ray(Vector3(vector.x, 6000, vector.z),Vector3(vector.x, -1000, vector.z))

	if not result.empty():
		return result.position.y
	else:
		result = space_state.intersect_ray(Vector3(vector.x + 0.01, 6000, vector.z + 0.01),Vector3(vector.x + 0.01, -1000, vector.z + 0.01))
		if not result.empty():
			return result.position.y
		else:
			return 1000.0


# Triangular interpolation with barycentric coordinates. Returns weights as Vector3
func _triangularInterpolation(P, A, B, C) -> Vector3:
	var W1 = ((B.z - C.z) * (P.x - C.x) + (C.x - B.x) * (P.z - C.z)) / ((B.z - C.z) * (A.x - C.x) + (C.x - B.x) * (A.z - C.z))
	var W2 = ((C.z - A.z) * (P.x - C.x) + (A.x - C.x) * (P.z - C.z)) / ((B.z - C.z) * (A.x - C.x) + (C.x - B.x) * (A.z - C.z))
	var W3 = 1 - W1 - W2
	
	return Vector3(W1, W2, W3)


# Gets the intersection with the grid in x direction (parallel to z-axis)
func _get_x_grid_intersection(from: Vector3, to: Vector3, step_size: float):
	var direction = to - from
	
	var offset = _get_grid_offset(from.x, to.x, step_size)
	if offset == null:
		return null
	
	var z = direction.z / direction.x * offset
	return Vector3(from.x + offset, 0, from.z + z)


# Gets the intersection with the grid in z direction (parallel to x-axis)
func _get_z_grid_intersection(from: Vector3, to: Vector3, step_size: float):
	var direction = to - from
	
	var offset = _get_grid_offset(from.z, to.z, step_size)
	if offset == null:
		return null
	
	var x = direction.x / direction.z * offset
	return Vector3(from.x + x, 0, from.z + offset)


# Calculates the remaining distance to the next grid with the given step_size
func _get_grid_offset(from: float, to: float, step_size: float):
	var direction = to - from
	var grid_index = floor(from / step_size)
	
	var non_parallel: bool = direction != 0
	var intersections: int = abs(floor(to / step_size) - grid_index)
	
	# Negative-direction-on-grid edge case
	if (from / step_size) == grid_index && direction < 0:
		intersections -= 1
	
	# Next point being exactly on the grid, causing additional intersects
	if (to / step_size) == floor((to / step_size)):
		intersections -= 1
	
	if non_parallel && intersections >= 1:
		# Calculate sampling grid offset
		var offset: float = 0.0
		
		# If the direction is positive, go to the next grid on the right
		if direction > 0:
			offset = (step_size - fposmod(from, step_size))
		# If the direction is negative, go to the next grid on the left
		else:
			offset = (fposmod(from, step_size)) * -1
		
		# If the offset is zero, go to next grid index
		if offset == 0.0:
			offset += step_size * sign(direction)
		
		return offset
	
	return null


# Gets the intersection point with the quad diagonal (bottom-left to top-right)
func _get_diagonal_point(from: Vector3, to: Vector3, step_size: float):
	var direction: Vector3 = to - from
	
	# Non-Parallel to quad diagonal
	if direction.z != 0 && direction.x / direction.z == -1:
		return null
	
	var x_grid = floor(from.x / step_size)
	var z_grid = floor(from.z / step_size)
	
	var on_x_grid_and_decending: bool = (from.x / step_size) == x_grid && direction.x < 0
	var on_z_grid_and_decending: bool = (from.z / step_size) == z_grid && direction.z < 0
	
	# If point is exactly on grid and direction is negative, move points 'back'
	if on_x_grid_and_decending:
		x_grid -= 1
	
	if on_z_grid_and_decending:
		z_grid -= 1
	
	
	var A = Vector3((x_grid + 1) * step_size, 0, z_grid * step_size)
	var C = Vector3(x_grid * step_size, 0, (z_grid + 1) * step_size)
	
	# Calculate intersection values
	var den: float = (from.x - to.x) * (C.z - A.z) - (from.z - to.z) * (C.x - A.x)
	var t: float = ((from.x - C.x) * (C.z - A.z) - (from.z - C.z) * (C.x - A.x)) / den
	var u: float = -(((from.x - to.x) * (from.z - C.z) - (from.z - to.z) * (from.x - C.x)) / den)
	
	# Only continue if intersection is with the line
	if t >= 0.0 && t <= 1.0 && u >= 0.0 && u <= 1.0:
		var I = Vector3(
			from.x + t * (to.x - from.x),
			0,
			from.z + t * (to.z - from.z))
		
		# Calculate vectors for projection without z
		var CI = I - C
		var CA = A - C
		
		# Calculate actual intersection point with z
		A = _move_to_ground_height(A)
		C = _move_to_ground_height(C)
		
		return (CI.length() / CA.length()) * (A - C) + C
	
	return null


# Calculates neighboring points and adds height difference to the correction texture
func _set_correction_heights(point: Vector3, step_size: float, width: float) -> void:
	var required_points: int = width / step_size
	var smooth_points: int = required_points / 2
	
	var x_grid_point: Vector3
	var z_grid_point: Vector3
	var x: int
	var z: int
	
	
	for i in range(required_points):
		x_grid_point = _get_x_grid_point(point, step_size, i)
		x = x_grid_point.x + mesh_size / 2
		z = x_grid_point.z + mesh_size / 2
		_set_correction_height(point.y, x, z, x_grid_point, 1.0)
		
		x_grid_point = _get_x_grid_point(point, step_size, -i - 1)
		x = x_grid_point.x + mesh_size / 2
		z = x_grid_point.z + mesh_size / 2
		_set_correction_height(point.y, x, z, x_grid_point, 1.0)
		
		z_grid_point = _get_z_grid_point(point, step_size, i)
		x = z_grid_point.x + mesh_size / 2
		z = z_grid_point.z + mesh_size / 2
		_set_correction_height(point.y, x, z, z_grid_point, 1.0)
		
		z_grid_point = _get_z_grid_point(point, step_size, -i - 1)
		x = z_grid_point.x + mesh_size / 2
		z = z_grid_point.z + mesh_size / 2
		_set_correction_height(point.y, x, z, z_grid_point, 1.0)
	
	for i in range(1, smooth_points, 1):
		x_grid_point = _get_x_grid_point(point, step_size, i + required_points - 1)
		x = x_grid_point.x + mesh_size / 2
		z = x_grid_point.z + mesh_size / 2
		_set_correction_height(point.y, x, z, x_grid_point, 1.0 / i)
		
		x_grid_point = _get_x_grid_point(point, step_size, -i - 1 + required_points - 1)
		x = x_grid_point.x + mesh_size / 2
		z = x_grid_point.z + mesh_size / 2
		_set_correction_height(point.y, x, z, x_grid_point, 1.0 / i)
		
		z_grid_point = _get_z_grid_point(point, step_size, i + required_points - 1)
		x = z_grid_point.x + mesh_size / 2
		z = z_grid_point.z + mesh_size / 2
		_set_correction_height(point.y, x, z, z_grid_point, 1.0 / i)
		
		z_grid_point = _get_z_grid_point(point, step_size, -i - 1 + required_points - 1)
		x = z_grid_point.x + mesh_size / 2
		z = z_grid_point.z + mesh_size / 2
		_set_correction_height(point.y, x, z, z_grid_point, 1.0 / i)


# Adds the height difference to the correction texture
func _set_correction_height(point_height: float, x: float, z: float, grid_point: Vector3, interpolation_factor: float) -> void:
	if x >= mesh_size || z >= mesh_size || x < 0 || z < 0:
		return
	var height: float = _get_ground_height(grid_point)
	# Wrap 64-bit float into Vector2 to cast it to 32-bit
	var correction: Vector2 = Vector2(lerp(height, point_height, interpolation_factor), 0.0)
	var position: int = (z * mesh_size + x) * 4
	
	# Check previous correction
	var old_bytes: PoolByteArray
	# Vector2 header
	old_bytes.append(5)
	old_bytes.append(0)
	old_bytes.append(0)
	old_bytes.append(0)
	# height as 32-bit float
	old_bytes.append_array(height_correction_data.subarray(position, position + 3))
	# zero as 32-bit float
	old_bytes.append(0)
	old_bytes.append(0)
	old_bytes.append(0)
	old_bytes.append(0)
	# Reconstruct vector from bytes
	var old_correction: Vector2 = bytes2var(old_bytes)
	
	if old_correction.x != 0.0 and old_correction.x < correction.x:
		return
	
	# Convert Vector2 to bytes
	var bytes: PoolByteArray = var2bytes(correction)
	# Read only 4 bytes from x (Byte 4 to 7)
	for i in range(4):
		height_correction_data[position + i] = bytes[i + 4]


# Calculates the grid point in x direction with the given grid offset
func _get_x_grid_point(point: Vector3, step_size: float, offset_count: int) -> Vector3:
	return Vector3(
		(floor(point.x / step_size) + offset_count) * step_size,
		point.y,
		floor(point.z / step_size) * step_size)


# Calculates the grid point in z direction with the given grid offset
func _get_z_grid_point(point: Vector3, step_size: float, offset_count: int) -> Vector3:
	return Vector3(
		floor(point.x / step_size) * step_size,
		point.y,
		(floor(point.z / step_size) + offset_count) * step_size)
