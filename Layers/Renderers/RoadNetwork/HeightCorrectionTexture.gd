extends Node
class_name HeightCorrectionTexture

var texture: ImageTexture = ImageTexture.new()
var weights: ImageTexture = ImageTexture.new()
var size: int = 0
var resolution: float = 0

var _data: PoolByteArray
var _image: Image = Image.new()

var _weights_data: PoolByteArray
var _weights_image: Image = Image.new()

var _debug_image: Image = Image.new()


func _init(size: int, resolution: float):
	self.size = size
	self.resolution = resolution
	
	_image.create(size, size, false, Image.FORMAT_RF)
	texture.storage = ImageTexture.STORAGE_RAW
	texture.create_from_image(_image, 0)
	_data.resize(size * size * 4)
	
	_weights_image.create(size, size, false, Image.FORMAT_RF)
	weights.storage = ImageTexture.STORAGE_RAW
	weights.create_from_image(_weights_image, 0)
	_weights_data.resize(size * size * 4)
	
	_debug_image.create(size, size, false, Image.FORMAT_RGB8)


func reset() -> void:
	# Reset corrections
	for i in range(size * size * 4):
		_data[i] = 0
	
	for i in range(size * size * 4):
		_weights_data[i] = 0
	
	_debug_image = Image.new()
	_debug_image.create(size, size, false, Image.FORMAT_RGB8)

func update_texture() -> void:
	_image.data["data"] = _data
	texture.set_data(_image)
	
	_weights_image.data["data"] = _weights_data
	weights.set_data(_weights_image)
	
	_debug_image.save_png("Weights.png")


# Calculates neighboring points and adds height difference to the correction texture
func set_correction_heights(point: Vector3, step_size: float, width: float) -> void:
	var required_points: int = width / step_size
	var smooth_points: int = 10
	
	var x_grid_point: Vector3
	var z_grid_point: Vector3
	var x: int
	var z: int
	
	# Set required points depending on width, going left/right and up/down
	for i in range(required_points):
		x_grid_point = QuadUtil.get_lower_right_point(point, step_size, i)
		x = x_grid_point.x + size / 2
		z = x_grid_point.z + size / 2
		_set_height(x, z, point.y, 1.0)
		
		x_grid_point = QuadUtil.get_lower_left_point(point, step_size, -i)
		x = x_grid_point.x + size / 2
		z = x_grid_point.z + size / 2
		_set_height(x, z, point.y, 1.0)
		
		z_grid_point = QuadUtil.get_upper_left_point(point, step_size, 0, i)
		x = z_grid_point.x + size / 2
		z = z_grid_point.z + size / 2
		_set_height(x, z, point.y, 1.0)
		
		z_grid_point = QuadUtil.get_lower_left_point(point, step_size, 0, -i)
		x = z_grid_point.x + size / 2
		z = z_grid_point.z + size / 2
		_set_height(x, z, point.y, 1.0)
	
	# Interpolate between correction height and original height to smooth out
	for i in range(smooth_points):
		x_grid_point = QuadUtil.get_lower_right_point(point, step_size, i + required_points)
		x = x_grid_point.x + size / 2
		z = x_grid_point.z + size / 2
		# E.g. 5: 1.0 | 0.8 | 0.6 | 0.4 | 0.2
		_set_height(x, z, point.y, 1.0 - ((1.0 / smooth_points) * i))
		
		x_grid_point = QuadUtil.get_lower_left_point(point, step_size, -i - required_points)
		x = x_grid_point.x + size / 2
		z = x_grid_point.z + size / 2
		_set_height(x, z, point.y, 1.0 - ((1.0 / smooth_points) * i))
		
		z_grid_point = QuadUtil.get_upper_left_point(point, step_size, 0, i + required_points)
		x = z_grid_point.x + size / 2
		z = z_grid_point.z + size / 2
		_set_height(x, z, point.y, 1.0 - ((1.0 / smooth_points) * i))
		
		z_grid_point = QuadUtil.get_lower_left_point(point, step_size, 0, -i - required_points)
		x = z_grid_point.x + size / 2
		z = z_grid_point.z + size / 2
		_set_height(x, z, point.y, 1.0 - ((1.0 / smooth_points) * i))


func _set_height(x: float, z: float, height: float, weight: float) -> void:
	# Outside of texture
	if x >= size || z >= size || x < 0 || z < 0:
		return
	
	# Wrap 64-bit float into Vector2 to cast it to 32-bit
	var correction: Vector2 = Vector2(height, 0.0)
	var position: int = (z * size + x) * 4
	
	# Check previous correction
	var old_correction: Vector2 = bytes2vector(_data.subarray(position, position + 3))
	if old_correction.x == 0.0 or old_correction.x > height:
		# Convert Vector2 to bytes
		var bytes: PoolByteArray = var2bytes(correction)
		# Read only 4 bytes from x (Byte 4 to 7)
		for i in range(4):
			_data[position + i] = bytes[i + 4]
	
	
	var old_weight: Vector2 = bytes2vector(_weights_data.subarray(position, position + 3))
	if old_weight.x > weight:
		return
	
	# Write interpolation factor
	var bytes = var2bytes(Vector2(weight, 0.0))
	for i in range(4):
		_weights_data[position + i] = bytes[i + 4]
	
	_debug_image.lock()
	_debug_image.set_pixel(x, z, Color(weight + 0.5, weight, weight))
	_debug_image.unlock()


static func bytes2vector(bytes: PoolByteArray) -> Vector2:
	var vector_bytes: PoolByteArray
	# Vector2 header
	vector_bytes.append(5)
	vector_bytes.append(0)
	vector_bytes.append(0)
	vector_bytes.append(0)
	# height as 32-bit float
	vector_bytes.append_array(bytes)
	# zero as 32-bit float
	vector_bytes.append(0)
	vector_bytes.append(0)
	vector_bytes.append(0)
	vector_bytes.append(0)
	# Reconstruct vector from bytes
	return bytes2var(vector_bytes)

