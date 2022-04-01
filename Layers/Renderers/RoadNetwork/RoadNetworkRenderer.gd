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

export(bool) var debug_draw_points: bool = false
export(bool) var debug_draw_mesh: bool = false


const radius = 100
const max_features = 100000

const mesh_size: float = 100.0
const mesh_resolution: float = 100.0
const sample_rate: float = mesh_size / mesh_resolution


# Road id to road instance
var roads: Dictionary = {}
var roads_to_add: Dictionary = {}
var roads_to_delete: Array = []
var debug_points: Array = []

var height_correction_image: Image = Image.new()
var height_correction_texture: ImageTexture = ImageTexture.new()


func _ready():
	$TerrainLOD0.height_layer = layer.render_info.ground_height_layer
	
	height_correction_image.create(mesh_size, mesh_size, false, Image.FORMAT_R8)
	height_correction_texture.create_from_image(height_correction_image, Image.FORMAT_R8)


# OVERRIDE #
# Runs in a thread!
func load_new_data():
	if debug_draw_mesh:
		$TerrainLOD0.position_x = center[0]
		$TerrainLOD0.position_y = center[1]
		$TerrainLOD0.build()
	
	var road_network_info: Layer.RoadNetworkRenderInfo = layer.render_info
	var road_features = road_network_info.road_layer.get_features_near_position(center[0], center[1], radius, max_features)
	var intersection_features = road_network_info.intersection_layer.get_features_near_position(center[0], center[1], radius, max_features)

	# Reset correction texture
	height_correction_image.fill(Color(0,0,0))
	
	
	var i = 0
	for road in road_features:
		_create_road(road, road_network_info.road_instance_scene)



# OVERRIDE #
func apply_new_data():
	if debug_draw_mesh:
		height_correction_texture.set_data(height_correction_image)
		$TerrainLOD0.height_correction_texture = height_correction_texture
		$TerrainLOD0.apply_textures()
	if debug_draw_points:
		for child in $Debug.get_children():
			child.queue_free()
		for point in debug_points:
			$Debug.add_child(point)
	
	
	# Remove old objects
	for road in $Roads.get_children():
		var road_id: int = int(road.name)
		if roads_to_delete.has(road_id):
			roads.erase(road_id)
			road.queue_free()
		# TODO: This check should not be necessary!
		elif roads.has(road_id):
			roads[road_id].transform.origin -= Vector3(shift[0], 0, shift[1])
	
	# Add new objects
	for road_id in roads_to_add.keys():
		var road = roads_to_add[road_id]
		road.name = str(road_id)
		$Roads.add_child(road)
		road.apply_attributes()
		roads[road_id] = road
	
	roads_to_add.clear()
	roads_to_delete = roads.keys()
	debug_points.clear()



func _create_road(road_feature, road_instance_scene: PackedScene) -> void:
	var road_id: int = int(road_feature.get_attribute("edge_id"))
	# If road already exists, skip and remove it from to-delete
	if roads.has(road_id):
		roads_to_delete.erase(road_id)
		return
	
	# Create Road instance
	var road_instance = road_instance_scene.instance()
	# Set road curve
	var road_curve: Curve3D = road_feature.get_offset_curve3d(-center[0], 0, -center[1])
	var road_width = float(road_feature.get_attribute("width"))

	# Set initial road point heights
	for index in range(road_curve.get_point_count()):
		var point = road_curve.get_point_position(index)
		
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
	
	# Go through each road edge
	for i in range(curve_point_count - 1):
		var current_point = road_curve.get_point_position(current_point_index)
		var next_point = road_curve.get_point_position(current_point_index + 1)
	
		var x_grid_point = null
		var z_grid_point = null
		while true:
			
			# INTERSECTION WITH DIAGONAL
			var intersection_point = _get_diagonal_point(current_point, next_point, sample_rate)
			if intersection_point != null:
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
					x_grid_point = _move_to_ground_height(x_grid_point)
					
					# Get points on other axis
					_set_correction_heights_on_z_grid(x_grid_point, sample_rate, road_width)
			
			# Same for z
			if z_grid_point == null:
				z_grid_point = _get_z_grid_intersection(current_point, next_point, sample_rate)
				if z_grid_point != null:
					z_grid_point = _move_to_ground_height(z_grid_point)
					
					_set_correction_heights_on_x_grid(z_grid_point, sample_rate, road_width)
			
			
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
	
	roads_to_add[road_id] = road_instance


func _move_to_ground_height(vector :Vector3) -> Vector3:
	var ground_height: float = layer.render_info.ground_height_layer.get_value_at_position(center[0] + vector.x, center[1] - vector.z)
	return Vector3(vector.x, ground_height, vector.z)


func _triangularInterpolation(P, A, B, C) -> Vector3:
	var W1 = ((B.z - C.z) * (P.x - C.x) + (C.x - B.x) * (P.z - C.z)) / ((B.z - C.z) * (A.x - C.x) + (C.x - B.x) * (A.z - C.z))
	var W2 = ((C.z - A.z) * (P.x - C.x) + (A.x - C.x) * (P.z - C.z)) / ((B.z - C.z) * (A.x - C.x) + (C.x - B.x) * (A.z - C.z))
	var W3 = 1 - W1 - W2
	
	return Vector3(W1, W2, W3)


func _get_x_grid_intersection(from: Vector3, to: Vector3, step_size: float):
	var direction = to - from
	
	var offset = _get_grid_offset(from.x, to.x, step_size)
	if offset == null:
		return null
	
	var z = direction.z / direction.x * offset
	return Vector3(from.x + offset, 0, from.z + z)


func _get_z_grid_intersection(from: Vector3, to: Vector3, step_size: float):
	var direction = to - from
	
	var offset = _get_grid_offset(from.z, to.z, step_size)
	if offset == null:
		return null
	
	var x = direction.x / direction.z * offset
	return Vector3(from.x + x, 0, from.z + offset)


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


func _set_correction_heights_on_x_grid(point: Vector3, step_size: float, width: float) -> void:
	height_correction_image.lock()
	
	var required_points: int = width / step_size + 3
	
	var x_grid_point: Vector3 = _get_x_grid_point(point, step_size, 0)
	
	var x: int = x_grid_point.x + mesh_size / 2
	var z: int = x_grid_point.z + mesh_size / 2
	
	
	if x < mesh_size && z < mesh_size && x >= 0 && z >= 0:
		height_correction_image.set_pixel(x, z, Color(1, 0, 0))
	
	for i in range(1, required_points - 1, 1):
		x_grid_point = _get_x_grid_point(point, step_size, i)
		
		x = x_grid_point.x + mesh_size / 2
		z = x_grid_point.z + mesh_size / 2
		if x < mesh_size && z < mesh_size && x >= 0 && z >= 0:
			height_correction_image.set_pixel(x, z, Color(1, 0, 0))
		
		x_grid_point = _get_x_grid_point(point, step_size, -i)
		x = x_grid_point.x + mesh_size / 2
		z = x_grid_point.z + mesh_size / 2
		if x < mesh_size && z < mesh_size && x >= 0 && z >= 0:
			height_correction_image.set_pixel(x, z, Color(1, 0, 0))
	
	height_correction_image.unlock()


func _set_correction_heights_on_z_grid(point: Vector3, step_size: float, width: float) -> void:
	height_correction_image.lock()
	
	var required_points: int = width / step_size + 3
	
	var z_grid_point: Vector3 = _get_z_grid_point(point, step_size, 0)
	
	var x: int = z_grid_point.x + mesh_size / 2
	var z: int = z_grid_point.z + mesh_size / 2
	
	
	if x < mesh_size && z < mesh_size && x >= 0 && z >= 0:
		height_correction_image.set_pixel(x, z, Color(1, 0, 0))
	
	for i in range(1, required_points - 1, 1):
		z_grid_point = _get_z_grid_point(point, step_size, i)
		x = z_grid_point.x + mesh_size / 2
		z = z_grid_point.z + mesh_size / 2
		
		if x < mesh_size && z < mesh_size && x >= 0 && z >= 0:
			height_correction_image.set_pixel(x, z, Color(1, 0, 0))
		
		z_grid_point = _get_z_grid_point(point, step_size, -i)
		x = z_grid_point.x + mesh_size / 2
		z = z_grid_point.z + mesh_size / 2
		
		if x < mesh_size && z < mesh_size && x >= 0 && z >= 0:
			height_correction_image.set_pixel(x, z, Color(1, 0, 0))
	
	height_correction_image.unlock()


func _get_x_grid_point(point: Vector3, step_size: float, offset_count: int):
	return Vector3(
		(floor(point.x / step_size) + offset_count) * step_size,
		point.y,
		floor(point.z / step_size) * step_size)


func _get_z_grid_point(point: Vector3, step_size: float, offset_count: int):
	return Vector3(
		floor(point.x / step_size) * step_size,
		point.y,
		(floor(point.z / step_size) + offset_count) * step_size)

