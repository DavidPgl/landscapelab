extends Object
class_name GameObject

var id := -1
var collection: GameObjectCollection
var geo_feature


func _init(initial_id: int, initial_geo_feature):
	id = initial_id
	geo_feature = initial_geo_feature


func get_attribute(attribute_name):
	if not collection.attributes.has(attribute_name):
		logger.error("Invalid attribute with name {}".format(attribute_name), "GAMESYSTEM")
		return null
	
	return collection.attributes[attribute_name].get_value(self)


func set_position(new_position: Vector3):
	geo_feature.set_vector3(new_position)


func get_position():
	return geo_feature.get_vector3()
