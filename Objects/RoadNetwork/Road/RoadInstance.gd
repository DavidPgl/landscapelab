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

const road_type_to_names: Dictionary = {
	"U":	"Bike and Pedestrian Lane",
	"RW":	"Bike Lane",
	"FW":	"Pedestrian",
	"PS":	"Private Road",
	"G":	"Municipal Road",
	"L":	"Country Road"
}

const road_physical_type_to_names: Dictionary = {
	-1:		"Unknown",
	1:		"Autobahn",
	2:		"Divided Roadway",
	3:		"Undivided Roadway",
	4:		"Roundabout",
	15:		"Footpath",
	504:	"Bike and Pedestrian Lane",
	505:	"Bike Lane"
}

var default_road_material: Material = load("res://Objects/RoadNetwork/Road/DefaultRoad.tres")
var car_road_material: ShaderMaterial = RoadNetworkUtil.shadermaterial_from_shader(load("res://Objects/RoadNetwork/Road/RoadShader.shader"))
var road_materials: Dictionary = {
	# Bike and Pedestrian
	"U":	default_road_material,
	# Bike
	"RW":	default_road_material,
	# Pedestrian
	"FW":	default_road_material,
	# Private road
	"PS":	default_road_material,
	# Municipal road
	"G":	car_road_material,
	# Country road
	"L":	car_road_material
}


# Road Information
var id: int
var road_name: String
var from_intersection: int
var to_intersection: int
var width: float
var left_width: float
var right_width: float
var speed_forward: float
var speed_backwards: float
var lanes_forward: int
var lanes_backwards: int
var direction: int
# A = Autobahn | B = Landesstraße | FW = Fußweg | H = Hauptstraße
var type: String
# See: https://www.gip.gv.at/assets/downloads/2112_dokumentation_gipat_ogd.pdf#page=13
# 1 = Autobahn | 2 = Splitted road | 3 = unsplitted road | 4 = Roundabout
var physical_type: int
var lane_uses: String

# The id of the intersection this road comes from
var intersection_id: int

class RoadLane:
	var type: int
	var width: float
	var offset: float

var road_lanes: Array = []


func _ready():
	_apply_attributes()


func set_polygon_from_lane_uses() -> void:
	# Default road if no lanes are defined
	if lane_uses == null:
		road_polygon.polygon[0].x = -width / 2.0
		road_polygon.polygon[1].x = width / 2.0
		road_polygon.polygon[2].x = width / 2.0
		road_polygon.polygon[3].x = -width / 2.0
	
	var lanes: PoolStringArray = lane_uses.split(';', false)
	for lane in lanes:
		var lane_infos: PoolStringArray = lane.split(',', false)
		var road_lane: RoadLane = RoadLane.new()
		road_lane.type = int(lane_infos[0])
		road_lane.width = float(lane_infos[1])
		road_lane.offset = float(lane_infos[2])
		
		road_lanes.append(road_lane)
	
	
	road_lanes.sort_custom(self, "custom_compare")
	
	var points: PoolVector2Array
	var number_of_lanes: int = 0
	var last_lane_end: float = 10000.0
	for road_lane in road_lanes:
		var current_lane_begin = road_lane.offset - road_lane.width / 2.0
		# Add additional points if there is space in-between lanes
		if last_lane_end < current_lane_begin:
			points.insert(number_of_lanes, Vector2(last_lane_end, 0.2))
			points.insert(points.size() - number_of_lanes, Vector2(last_lane_end, 0.0))
		
		# Set point as upper and lower vertex
		var point = Vector2(current_lane_begin, 0.2)
		points.insert(number_of_lanes, point)
		points.insert(points.size() - number_of_lanes, Vector2(point.x, 0.0))
		last_lane_end = road_lane.offset + road_lane.width / 2.0
		
		number_of_lanes += 1
	
	var road_lane: RoadLane = road_lanes[road_lanes.size() - 1]
	var lane_end = road_lane.offset + road_lane.width / 2.0
	points.insert(number_of_lanes, Vector2(lane_end, 0.2))
	points.insert(points.size() - number_of_lanes, Vector2(lane_end, 0.0))
	number_of_lanes += 1
	
	width = points[points.size() - number_of_lanes].x - points[0].x
	left_width = abs(points[0].x)
	right_width = abs(points[points.size() - number_of_lanes].x)
	
	$RoadPolygon.polygon = points


func custom_compare(a, b):
	return a.offset < b.offset


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
		"Type": road_type_to_names[type] + (" (%s)" % type) \
		if road_type_to_names.has(type) \
		else "Unknown Type: " + type,
		"Physical Type": road_physical_type_to_names[physical_type] + (" (%s)" % physical_type) \
		if road_physical_type_to_names.has(physical_type) \
		else "Unknown Physical Type: " + String(physical_type)
	}


func _apply_attributes() -> void:
	pass
