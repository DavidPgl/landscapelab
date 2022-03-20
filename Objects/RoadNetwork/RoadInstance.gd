extends Path
class_name RoadInstance

onready var road_polygon: CSGPolygon = get_node("RoadPolygon")

var width: float

func apply_attributes() -> void:
	pass
	#_set_width(width)


func _set_width(width: float) -> void:
	road_polygon.polygon[0].x = -width / 2.0
	road_polygon.polygon[1].x = width / 2.0
	road_polygon.polygon[2].x = width / 2.0
	road_polygon.polygon[3].x = -width / 2.0

func _set_height(height: float) -> void:
	road_polygon.polygon[2].y = height / 2.0
	road_polygon.polygon[3].y = height / 2.0
