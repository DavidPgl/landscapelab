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

const lod_sample_rates: Array = [
	1.0,
	3.0,
	9.0,
	27.0
]

var roads_parent: Spatial

# Road id to road instance
var roads: Dictionary = {}
var debug_points: Array = []

var height_correction_textures: Array = [
	HeightCorrectionTexture.new(300),
	HeightCorrectionTexture.new(100)
]

var terrain_renderer: RealisticTerrainRenderer


func _ready():
	# TODO: Replace with better access
	# Find and get terrain renderer
	for renderer in get_parent().get_children():
		if renderer is RealisticTerrainRenderer:
			terrain_renderer = renderer
			return


# OVERRIDE #
# Runs in a thread!
func load_new_data():
	var road_network_info: Layer.RoadNetworkRenderInfo = layer.render_info
	var road_features = road_network_info.road_layer.get_features_near_position(center[0], center[1], radius, max_features)
	var intersection_features = road_network_info.intersection_layer.get_features_near_position(center[0], center[1], radius, max_features)
	
	roads_parent = Spatial.new()
	roads_parent.name = "Roads"
	for road in road_features:
		_create_road(road, road_network_info.road_instance_scene)
	
	for height_correction_texture in height_correction_textures:
		height_correction_texture.update_texture()
	
	terrain_renderer.set_height_correction_texture(0, height_correction_textures[0].texture)
	terrain_renderer.set_height_correction_texture(1, height_correction_textures[1].texture)


# OVERRIDE #
func apply_new_data():	
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
		var weights = RoadNetworkUtil.triangularInterpolation(point, A, B, C)
		
		point.y = A.y * weights.x + B.y * weights.y + C.y * weights.z
		road_curve.set_point_position(index, point)
		
		if current_lod < height_correction_textures.size():
			_set_correction_heights(height_correction_textures[current_lod], point, sample_rate, road_width)
		
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
				
				_add_point_to_curve(road_curve, lod_x_grid_point, current_point_index + 1, current_lod, sample_rate, road_width)
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
				
				_add_point_to_curve(road_curve, lod_z_grid_point, current_point_index + 1, current_lod, sample_rate, road_width)
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
				_add_point_to_curve(road_curve, intersection_point, current_point_index + 1, current_lod, sample_rate, road_width)
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
				_add_point_to_curve(road_curve, x_grid_point, current_point_index + 1, current_lod, sample_rate, road_width)
				current_point = x_grid_point
				x_grid_point = null
			else:
				_add_point_to_curve(road_curve, z_grid_point, current_point_index + 1, current_lod, sample_rate, road_width)
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


func _add_point_to_curve(curve: Curve3D, point: Vector3, point_index: int, lod_index: int, step_size: float, point_width: float):
	curve.add_point(point, Vector3.ZERO, Vector3.ZERO, point_index)
	if lod_index < height_correction_textures.size():
		_set_correction_heights(height_correction_textures[lod_index], point, step_size, point_width)


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
		# If nothing was hit (e.g. border between LODs has a gap) try again with offset
		result = space_state.intersect_ray(Vector3(vector.x + 0.01, 6000, vector.z + 0.01),Vector3(vector.x + 0.01, -1000, vector.z + 0.01))
		if not result.empty():
			return result.position.y
		else:
			return 0.0


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
func _set_correction_heights(texture: HeightCorrectionTexture, point: Vector3, step_size: float, width: float) -> void:
	var size = texture.size
	var required_points: int = width / step_size
	var smooth_points: int = required_points / 2
	
	var x_grid_point: Vector3
	var z_grid_point: Vector3
	var x: int
	var z: int
	
	# Set required points depending on width, going left/right and up/down
	for i in range(required_points):
		x_grid_point = RoadNetworkUtil.get_x_grid_point(point, step_size, i)
		x = x_grid_point.x + size / 2
		z = x_grid_point.z + size / 2
		texture.set_height(x, z, point.y, _get_ground_height(x_grid_point), 1.0)
		
		x_grid_point = RoadNetworkUtil.get_x_grid_point(point, step_size, -i - 1)
		x = x_grid_point.x + size / 2
		z = x_grid_point.z + size / 2
		texture.set_height(x, z, point.y, _get_ground_height(x_grid_point), 1.0)
		
		z_grid_point = RoadNetworkUtil.get_z_grid_point(point, step_size, i)
		x = z_grid_point.x + size / 2
		z = z_grid_point.z + size / 2
		texture.set_height(x, z, point.y, _get_ground_height(z_grid_point), 1.0)
		
		z_grid_point = RoadNetworkUtil.get_z_grid_point(point, step_size, -i - 1)
		x = z_grid_point.x + size / 2
		z = z_grid_point.z + size / 2
		texture.set_height(x, z, point.y, _get_ground_height(z_grid_point), 1.0)
	
	# Interpolate between correction height and original height to smooth out
	for i in range(1, smooth_points, 1):
		x_grid_point = RoadNetworkUtil.get_x_grid_point(point, step_size, i + required_points - 1)
		x = x_grid_point.x + size / 2
		z = x_grid_point.z + size / 2
		texture.set_height(x, z, point.y, _get_ground_height(x_grid_point), 1.0 / i)
		
		x_grid_point = RoadNetworkUtil.get_x_grid_point(point, step_size, -i - 1 + required_points - 1)
		x = x_grid_point.x + size / 2
		z = x_grid_point.z + size / 2
		texture.set_height(x, z, point.y, _get_ground_height(x_grid_point), 1.0 / i)
		
		z_grid_point = RoadNetworkUtil.get_z_grid_point(point, step_size, i + required_points - 1)
		x = z_grid_point.x + size / 2
		z = z_grid_point.z + size / 2
		texture.set_height(x, z, point.y, _get_ground_height(z_grid_point), 1.0 / i)
		
		z_grid_point = RoadNetworkUtil.get_z_grid_point(point, step_size, -i - 1 + required_points - 1)
		x = z_grid_point.x + size / 2
		z = z_grid_point.z + size / 2
		texture.set_height(x, z, point.y, _get_ground_height(z_grid_point), 1.0 / i)

