extends Path
class_name RoadInstance

onready var road_polygon: CSGPolygon = get_node("RoadPolygon")

# TODO: Convert to internal types in pre-processing
const road_type_to_names: Dictionary = {
	"U":	"Bike and Pedestrian Lane",
	"RW":	"Bike Lane",
	"FW":	"Pedestrian",
	"PS":	"Private Road",
	"G":	"Municipal Road",
	"L":	"Country Road"
}

# TODO: Convert to internal types in pre-processing
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


const road_lane_type_to_name: Dictionary = {
	0: "Car",
	1: "Bike on Car",
	2: "Parking",
	3: "Pedestrian",
	4: "Bike",
	10: "Curbside"
}

class RoadLane:
	var type: int
	var width: float
	var offset: float
	var height: float

const road_height = 0.2
const curbside_width = 0.2
const curbside_height = 0.1


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
		road_lane.offset = float(lane_infos[2]) * direction
		
		road_lanes.append(road_lane)
	
	road_lanes.sort_custom(self, "custom_compare")
	
	var height = road_height
	var points: PoolVector2Array
	var number_of_lanes: int = 0
	var last_lane_end: float = 10000.0
	var last_lane_type: int = -1
	# Set upper points, defining road surface
	for road_lane in road_lanes:
		var current_lane_begin = road_lane.offset - road_lane.width / 2.0
		
		# Add curbside if going from sidewalk (bike or pedestrian) to road
		if road_lane.type == 0 or road_lane.type == 1 or road_lane.type == 2:
			if last_lane_type == 3 or last_lane_type == 4:
				points.insert(number_of_lanes, Vector2(current_lane_begin - curbside_width, height))
				# Flag this lane as curbside in shader
				$RoadPolygon.material.set_shader_param("lane_type_%d" % number_of_lanes, 10)
				number_of_lanes += 1
				
				points.insert(number_of_lanes, Vector2(current_lane_begin, height))
				$RoadPolygon.material.set_shader_param("lane_type_%d" % number_of_lanes, 10)
				number_of_lanes += 1
				
				# Correct road height as we are now lower due to curbside
				height -= curbside_height
		
		# Add additional point if there is space in-between lanes
		if last_lane_end < current_lane_begin:
			points.insert(number_of_lanes, Vector2(last_lane_end, 0.2))
			number_of_lanes += 1
		
		# Add curbside if going from road to sidewalk (bike or pedestrian) 
		if road_lane.type == 3 or road_lane.type == 4:
			if last_lane_type == 0 or last_lane_type == 1 or last_lane_type == 2:
				# Correct road height as we are now lower due to curbside
				height += curbside_height
				
				points.insert(number_of_lanes, Vector2(last_lane_end, height))
				$RoadPolygon.material.set_shader_param("lane_type_%d" % number_of_lanes, 10)
				number_of_lanes += 1
				
				points.insert(number_of_lanes, Vector2(last_lane_end + curbside_width, height))
				$RoadPolygon.material.set_shader_param("lane_type_%d" % number_of_lanes, 10)
				number_of_lanes += 1
		
		# Add current lane point
		points.insert(number_of_lanes, Vector2(current_lane_begin, 0.2))
		$RoadPolygon.material.set_shader_param("lane_type_%d" % number_of_lanes, road_lane.type)
		last_lane_end = road_lane.offset + road_lane.width / 2.0
		last_lane_type = road_lane.type
		
		number_of_lanes += 1
	
	var road_lane: RoadLane = road_lanes[road_lanes.size() - 1]
	var lane_end = road_lane.offset + road_lane.width / 2.0
	# Insert end points
	points.append(Vector2(lane_end, height))
	points.append(Vector2(lane_end, 0.0))
	
	# Insert point below first point as last point
	points.append(Vector2(points[0].x, 0.0))
	
	width = points[points.size() - number_of_lanes].x - points[0].x
	left_width = abs(points[0].x)
	right_width = abs(points[points.size() - number_of_lanes].x)
	
	$RoadPolygon.polygon = points
	
	# Set number of lanes in Shader
	$RoadPolygon.material.set_shader_param("number_of_lanes", number_of_lanes)
	


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
