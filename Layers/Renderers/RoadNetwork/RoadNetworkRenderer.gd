extends Node
class_name RoadNetworkRenderer


export(bool) var debug_draw_points: bool = false


const radius = 500
const max_features = 50000

const lod_sample_rates: Array = [
	1.0,
	3.0,
	9.0,
	27.0,
	27.0
]

var road_layer
var intersection_layer
var road_instance_scene: PackedScene
var intersection_instance_scene: PackedScene

var center: Array = [0,0]

var roads_parent: Spatial
var intersection_parent: Spatial

# Road id to road instance
var roads: Dictionary = {}
var debug_points: Array = []

var height_correction_texture: HeightCorrectionTexture = HeightCorrectionTexture.new(300, 1.0)

onready var road_network_ui: RoadNetworkUI = self.get_node("RoadNetworkUI")


func load_data():
	var road_features = road_layer.get_features_near_position(center[0], center[1], radius, max_features)
	var intersection_features = intersection_layer.get_features_near_position(center[0], center[1], radius, max_features)
	
	# Reset height correction textures
	height_correction_texture.reset()
	
	roads_parent = Spatial.new()
	roads_parent.name = "Roads"
	
	intersection_parent = Spatial.new()
	intersection_parent.name = "Intersections"
	
	_create_roads(road_features)
	_create_intersections(intersection_features)
	_refine_roads()
	
	height_correction_texture.update_texture()
	get_parent().set_height_correction_texture(height_correction_texture)


func apply_data():
	if debug_draw_points:
		for child in $Debug.get_children():
			child.queue_free()
		for point in debug_points:
			$Debug.add_child(point)
		debug_points.clear()
	
	# Remove old objects
	$Roads.free()
	$Intersections.free()
	roads.clear()
	
	add_child(roads_parent)
	add_child(intersection_parent)


# Creates the road instances with basic information
func _create_roads(road_features) -> void:
	for road_feature in road_features:
		var road_type: String = road_feature.get_attribute("type")
		
		# Skip all rail-roads
		if road_type.begins_with('E'):
			continue
		
		var road_id: int = int(road_feature.get_attribute("edge_id"))
		var road_curve: Curve3D = road_feature.get_offset_curve3d(-center[0], 0, -center[1])
		var road_width = float(road_feature.get_attribute("width"))
		
		# Create Road instance
		var road_instance: RoadInstance = road_instance_scene.instance()
		# Set road information
		road_instance.id = road_id
		road_instance.width = road_width
		road_instance.road_name = road_feature.get_attribute("name")
		road_instance.from_intersection = road_feature.get_attribute("from_node")
		road_instance.to_intersection = road_feature.get_attribute("to_node")
		road_instance.speed_forward = road_feature.get_attribute("speed_forward")
		road_instance.speed_backwards = road_feature.get_attribute("speed_backwards")
		road_instance.lanes_forward = road_feature.get_attribute("lanes_forward")
		road_instance.lanes_backwards = road_feature.get_attribute("lanes_backwards")
		road_instance.direction = road_feature.get_attribute("direction")
		road_instance.type = road_type
		road_instance.physical_type = road_feature.get_attribute("physical_type")
		road_instance.lane_uses = road_feature.get_attribute("linear_uses")
		
		
		# TODO: Define this width depending on road type and number of lanes
		# If the road has no width (usually defined as -1), give it a default width
		if road_width <= 0:
			road_width = 3
		
		# INITIAL POINTS
		for index in range(road_curve.get_point_count()):
			# Make sure all roads are facing up
			road_curve.set_point_tilt(index, 0)
			
			var point = road_curve.get_point_position(index)
			point = _get_ground_point(point)
			road_curve.set_point_position(index, point)
			
			height_correction_texture.set_correction_heights(point, 1.0, road_width)
			
			if debug_draw_points:
				var debug_point: MeshInstance = $Debug_Point.duplicate() if index > 0 else $Debug_Point_Start.duplicate()
				debug_point.transform.origin = point
				debug_points.append(debug_point)
		
		
		road_instance.curve = road_curve
		road_instance.width = road_width
		road_instance.intersection_id = int(road_feature.get_attribute("from_node"))
		road_instance.set_polygon_from_lane_uses()
		roads_parent.add_child(road_instance)
		
		roads[road_id] = road_instance


func _create_intersections(intersection_features) -> void:
	for intersection_feature in intersection_features:
		var intersection: IntersectionInstance = intersection_instance_scene.instance()
		var vertices: PoolVector2Array = PoolVector2Array()
		var road_attributes: Array = []
		
		var intersection_id: int = int(intersection_feature.get_attribute("node_id"))
		
		var edge_ids: PoolStringArray = intersection_feature.get_attribute("edges").split(';')
		
		if edge_ids.size() < 3:
			continue
		
		var current_edge_id: int = int(edge_ids[0])
		var next_edge_id: int = current_edge_id
		for i in range(edge_ids.size()):
			# Abort if any road is missing
			if not roads.has(next_edge_id):
				break
			
			var road_a: RoadInstance = roads[next_edge_id]
			current_edge_id = next_edge_id
			
			var edge_a = _get_road_point_and_direction(intersection_id, road_a)
			var edge_a_point = edge_a[0]
			var edge_a_direction = edge_a[2]
			
			var edge_b
			var smallest_angle: float = 2 * PI
			var road_b: RoadInstance
			# Find closest angle clockwise
			for id in edge_ids:
				var other_edge_id: int = int(id)
				# Skip itself
				if other_edge_id == current_edge_id:
					continue
				
				var road: RoadInstance = roads[other_edge_id]
				var edge = _get_road_point_and_direction(intersection_id, road)
				var edge_direction = edge[2]
				
				var angle = RoadNetworkUtil.clockwise_angle(edge_a_direction, edge_direction)
				if angle < smallest_angle:
					edge_b = edge
					smallest_angle = angle
					road_b = road
					# Use this road as the next road -> Clockwise
					next_edge_id = other_edge_id
			
			# Use left side of road for intersection
			var edge_a_shift = Vector2(-edge_a[2].y, edge_a[2].x).normalized() * (road_a.left_width)
			edge_a[0] += edge_a_shift
			# Use right side
			var edge_b_shift = Vector2(edge_b[2].y, -edge_b[2].x).normalized() * (road_b.right_width)
			edge_b[0] += edge_b_shift
			var point = Geometry.line_intersects_line_2d(edge_a[0], edge_a[2], edge_b[0], edge_b[2])
			if point != null:
				vertices.push_back(Vector2(point.x, point.y))
			# Safe some attributes for additional point generation
			road_attributes.append([edge_a_shift, edge_b_shift, smallest_angle, road_a, road_b])
			intersection.transform.origin.y = edge_a[1].y
			
		# Add additional points to match road angles
		var temp: PoolVector2Array = PoolVector2Array()
		temp.append_array(vertices)
		var added_point_count: int = 0
		var index: int = 0
		var number_of_vertices: int = vertices.size()
		
		for vertex in temp:
			var angle_to_left: float = road_attributes[(index - 1) if index > 0 else number_of_vertices - 1][2]
			var angle_to_right: float = road_attributes[(index + 1) % number_of_vertices][2]
			var angle = road_attributes[index][2]
			
			# Only add left point if own angle is smaller
			if angle < angle_to_left:
				var left_shift = road_attributes[index][0]
				vertices.insert(index + added_point_count, vertex - left_shift * 2.0)
				added_point_count += 1
				
				# Move road to edge of intersection
				var road: RoadInstance = road_attributes[index][3]
				var point_count: int = road.curve.get_point_count()
				var shifted_point: Vector2 = vertex - left_shift
				if road.intersection_id == intersection_id:
					var point = road.curve.get_point_position(0)
					road.curve.set_point_position(0, Vector3(shifted_point.x, point.y, shifted_point.y))
				else:
					var point = road.curve.get_point_position(point_count - 1)
					road.curve.set_point_position(point_count - 1, Vector3(shifted_point.x, point.y, shifted_point.y))
			# Only add right point if own angle is smaller
			if angle < angle_to_right:
				var right_sift = road_attributes[index][1]
				vertices.insert(index + added_point_count + 1, vertex - right_sift * 2.0)
				added_point_count += 1
				# Move road to edge of intersection
				var road: RoadInstance = road_attributes[index][4]
				var point_count: int = road.curve.get_point_count()
				var shifted_point: Vector2 = vertex - right_sift
				if road.intersection_id == intersection_id:
					var point = road.curve.get_point_position(0)
					road.curve.set_point_position(0, Vector3(shifted_point.x, point.y, shifted_point.y))
				else:
					var point = road.curve.get_point_position(point_count - 1)
					road.curve.set_point_position(point_count - 1, Vector3(shifted_point.x, point.y, shifted_point.y))
			
			index += 1
		
		# Create mesh from points
		intersection.set_points(vertices)
		intersection_parent.add_child(intersection)

# Returns the last edge as a starting point (VECTOR2), end point (VECTOR3) and direction (VECTOR2)
func _get_road_point_and_direction(intersection_id: int, road: RoadInstance) -> Array:
	var point_a: Vector3
	var point_b: Vector3
	# Either use first two points or last two points
	if road.intersection_id == intersection_id:
		point_a = road.curve.get_point_position(1)
		point_b = road.curve.get_point_position(0)
	else:
		var point_count: int = road.curve.get_point_count()
		point_a = road.curve.get_point_position(point_count - 2)
		point_b = road.curve.get_point_position(point_count - 1)
	
	return [Vector2(point_a.x, point_a.z), point_b, Vector2(point_b.x - point_a.x, point_b.z - point_a.z)]


# Adds additional curve points depending on the underlying terrain and sets their height
func _refine_roads() -> void:
	for road_instance in roads.values():
		var road_curve: Curve3D = road_instance.curve
		var road_width: float = road_instance.width
		
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
			
			# LOD INTERSECTIONS
			# Get the LOD
			var current_lod: int = 0
			var lod_size: float = 0
			for j in range(4):
				lod_size = pow(3, j) * 300
				# If the point is smaller than the current LOD size
				if abs(current_point.x) <= lod_size / 2 and abs(current_point.z) <= lod_size / 2:
					# If FROM is the LOD-edge and we're going away, use next LOD
					if (current_point == lod_x_grid_point or current_point == lod_z_grid_point) and\
					(abs(next_point.x) > lod_size / 2 or abs(next_point.z) > lod_size / 2):
						current_lod += 1
						break
					# Otherwise use previous LOD size
					lod_size = pow(3, max(0, j - 1)) * 300
					break
				current_lod += 1
			
			
			var sample_rate = lod_sample_rates[current_lod]
			var shift = Vector3(lod_size / 2, 0, lod_size / 2)
			# Get intersections with LOD grid
			lod_x_grid_point = QuadUtil.get_horizontal_intersection(current_point - shift, next_point - shift, lod_size)
			lod_z_grid_point = QuadUtil.get_vertical_intersection(current_point - shift, next_point - shift, lod_size)
			
			var lod_point: Vector3
			# Add LOD grid intersection as point
			if lod_x_grid_point != null or lod_z_grid_point != null:
				if lod_z_grid_point == null || (lod_x_grid_point != null && current_point.distance_squared_to(lod_x_grid_point + shift) <= current_point.distance_squared_to(lod_z_grid_point + shift)):
					lod_point = lod_x_grid_point + shift
				else:
					lod_point = lod_z_grid_point + shift
				
				lod_point = _get_ground_point(lod_point)
				
				_add_point_to_curve(road_curve, lod_point, current_point_index + 1, road_width)
				next_point = lod_point
				
				if debug_draw_points:
					var debug_point: MeshInstance = $Debug_Point_Intersect_LOD.duplicate()
					debug_point.transform.origin = lod_point
					debug_points.append(debug_point)
				
				i -= 1
			
			i += 1
			
			var x_grid_point = null
			var z_grid_point = null
			while true:
				# INTERSECTION WITH DIAGONAL
				var intersection_point = QuadUtil.get_diagonal_intersection(current_point, next_point, sample_rate)
				if intersection_point != null:
					intersection_point = _get_ground_point(intersection_point)
					
					# Add intersection to curve
					_add_point_to_curve(road_curve, intersection_point, current_point_index + 1, road_width)
					current_point_index += 1
					
					if debug_draw_points:
						var debug_point: MeshInstance = $Debug_Point_Intersect.duplicate()
						debug_point.transform.origin = intersection_point
						debug_points.append(debug_point)
				
				# INTERSECTION WITH GRID AXES
				# Only calculate grid point if we don't have one from last calculation
				if x_grid_point == null:
					x_grid_point = QuadUtil.get_horizontal_intersection(current_point, next_point, sample_rate)
				
				# Same for z
				if z_grid_point == null:
					z_grid_point = QuadUtil.get_vertical_intersection(current_point, next_point, sample_rate)
				
				# If no grid points, done with this curve edge
				if x_grid_point == null && z_grid_point == null:
					# Move to next points
					current_point_index += 1
					break
				
				# Add closest one
				if z_grid_point == null || (x_grid_point != null && current_point.distance_squared_to(x_grid_point) <= current_point.distance_squared_to(z_grid_point)):
					x_grid_point = _get_ground_point(x_grid_point)
					_add_point_to_curve(road_curve, x_grid_point, current_point_index + 1, road_width)
					current_point = x_grid_point
					x_grid_point = null
				else:
					z_grid_point = _get_ground_point(z_grid_point)
					_add_point_to_curve(road_curve, z_grid_point, current_point_index + 1, road_width)
					current_point = z_grid_point
					z_grid_point = null
				
				# Move to newly added point and start from there again
				current_point_index += 1
				
				if debug_draw_points:
					var debug_point: MeshInstance = $Debug_Point_Grid.duplicate()
					debug_point.transform.origin = current_point
					debug_points.append(debug_point)
		
		
		road_instance.curve = road_curve


func _add_point_to_curve(curve: Curve3D, point: Vector3, point_index: int, width: float):
	curve.add_point(point, Vector3.ZERO, Vector3.ZERO, point_index)
	height_correction_texture.set_correction_heights(point, 1.0, width)


# Moves the given vector to the ground and returns it
func _get_ground_point(vector: Vector3) -> Vector3:
	return Vector3(vector.x, _get_ground_height(vector), vector.z)


# Gets the ground height at the given position
func _get_ground_height(vector: Vector3) -> float:
	var space_state = get_parent().get_world().direct_space_state
	var result = space_state.intersect_ray(Vector3(vector.x, 6000, vector.z),Vector3(vector.x, -1000, vector.z), [], 1048576)

	if not result.empty():
		return result.position.y
	else:
		# If nothing was hit (e.g. border between LODs has a gap) try again with offset
		result = space_state.intersect_ray(Vector3(vector.x + 0.01, 6000, vector.z + 0.01),Vector3(vector.x + 0.01, -1000, vector.z + 0.01), [], 1048576)
		if not result.empty():
			return result.position.y
		else:
			return 0.0
