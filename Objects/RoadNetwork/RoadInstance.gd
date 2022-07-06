extends Path
class_name RoadInstance

onready var road_polygon: CSGPolygon = get_node("RoadPolygon")

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

# Road Information
var id: int
var road_name: String
var from_intersection: int
var to_intersection: int
var width: float
var speed_forward: float
var speed_backwards: float
var lanes_forward: int
var lanes_backwards: int
var direction: int
# A = Autobahn | B = Landesstraße | FW = Fußweg | H = Hauptstraße
var type: String
# See: https://www.gip.gv.at/assets/downloads/2112_dokumentation_gipat_ogd.pdf#page=13
# 1 = Autobahn | 2 = Splitted road | 3 = unsplitted road | 4 = Roundabout
var physical_type: String



# The id of the intersection this road comes from
var intersection_id: int


func _ready():
	apply_attributes()


func apply_attributes() -> void:
	_set_width(width)
	_set_height(0.2)


func get_info() -> Dictionary:
	return {
		"ID": id,
		"Name": road_name,
		"From Intersection": from_intersection,
		"To Intersection": to_intersection,
		"Width": width,
		"Speed Forward": speed_forward,
		"Speed Backwards": speed_backwards,
		"Lanes Forward": lanes_forward,
		"Lanes Backwards": lanes_backwards,
		"Direction": direction,
		"Type": type,
		"Physical Type": direction
	}


func _set_width(width: float) -> void:
	road_polygon.polygon[0].x = -width / 2.0
	road_polygon.polygon[1].x = width / 2.0
	road_polygon.polygon[2].x = width / 2.0
	road_polygon.polygon[3].x = -width / 2.0

func _set_height(height: float) -> void:
	road_polygon.polygon[2].y = height / 2.0
	road_polygon.polygon[3].y = height / 2.0



