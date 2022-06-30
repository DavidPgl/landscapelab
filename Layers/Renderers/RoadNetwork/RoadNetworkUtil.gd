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


static func clockwise_angle(a: Vector2, b: Vector2) -> float:
	var angle = atan2(a.y, a.x) - atan2(b.y, b.x)
	return angle if angle >= 0 else angle + 2.0 * PI
