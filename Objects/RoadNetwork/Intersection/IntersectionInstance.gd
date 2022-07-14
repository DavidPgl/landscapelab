extends Spatial
class_name IntersectionInstance


func set_points(points: PoolVector2Array) -> void:
	$CSGPolygon.polygon = points
