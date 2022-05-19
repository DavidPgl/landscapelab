class_name RoadNetworkUtil


static func inverse_lerp_vector(a: Vector3, b: Vector3, value: Vector3) -> float:
	var ab = b - a
	var av = value - a
	var test = av.dot(ab) / ab.dot(ab)
	return test


static func inverse_lerp_vector2(a: Vector2, b: Vector2, value: Vector2) -> float:
	var ab = b - a
	var av = value - a
	return av.dot(ab) / ab.dot(ab)
