class_name RoadNetworkUtil


static func inverse_lerp_vector(a: Vector3, b: Vector3, value: Vector3) -> float:
	var ab = b - a
	var av = value - a
	return av.dot(ab) / ab.dot(ab)


static func inverse_lerp_vector2(a: Vector2, b: Vector2, value: Vector2) -> float:
	var ab = b - a
	var av = value - a
	return av.dot(ab) / ab.dot(ab)


# Triangular interpolation with barycentric coordinates. Returns weights as Vector3
static func triangularInterpolation(P, A, B, C) -> Vector3:
	var W1 = ((B.z - C.z) * (P.x - C.x) + (C.x - B.x) * (P.z - C.z)) / ((B.z - C.z) * (A.x - C.x) + (C.x - B.x) * (A.z - C.z))
	var W2 = ((C.z - A.z) * (P.x - C.x) + (A.x - C.x) * (P.z - C.z)) / ((B.z - C.z) * (A.x - C.x) + (C.x - B.x) * (A.z - C.z))
	var W3 = 1 - W1 - W2
	
	return Vector3(W1, W2, W3)


# Calculates the grid point in x direction with the given grid offset
static func get_x_grid_point(point: Vector3, step_size: float, offset_count: int) -> Vector3:
	return Vector3(
		(floor(point.x / step_size) + offset_count) * step_size,
		point.y,
		floor(point.z / step_size) * step_size)


# Calculates the grid point in z direction with the given grid offset
static func get_z_grid_point(point: Vector3, step_size: float, offset_count: int) -> Vector3:
	return Vector3(
		floor(point.x / step_size) * step_size,
		point.y,
		(floor(point.z / step_size) + offset_count) * step_size)
