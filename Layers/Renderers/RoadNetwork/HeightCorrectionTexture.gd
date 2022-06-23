extends Node
class_name HeightCorrectionTexture

var texture: ImageTexture = ImageTexture.new()

var _data: PoolByteArray
var _image: Image = Image.new()
var _size: int = 0


func _init(size: int):
	_size = size
	_image.create(_size, _size, false, Image.FORMAT_RF)
	texture.storage = ImageTexture.STORAGE_RAW
	texture.create_from_image(_image, Image.FORMAT_RF)
	
	_data.resize(_size * _size * 4)


func reset() -> void:
	# Reset corrections
	for i in range(_size * _size * 4):
		_data[i] = 0


func update_texture() -> void:
	_image.create_from_data(_size, _size, false, Image.FORMAT_RF, _data)
	texture.set_data(_image)


func set_height(x: float, z: float, new_height: float, old_height: float, interpolation_factor: float) -> void:
	# Outside of texture
	if x >= _size || z >= _size || x < 0 || z < 0:
		return
	
	# Wrap 64-bit float into Vector2 to cast it to 32-bit
	var correction: Vector2 = Vector2(lerp(old_height, new_height, interpolation_factor), 0.0)
	var position: int = (z * _size + x) * 4
	
	# Check previous correction
	var old_bytes: PoolByteArray
	# Vector2 header
	old_bytes.append(5)
	old_bytes.append(0)
	old_bytes.append(0)
	old_bytes.append(0)
	# height as 32-bit float
	old_bytes.append_array(_data.subarray(position, position + 3))
	# zero as 32-bit float
	old_bytes.append(0)
	old_bytes.append(0)
	old_bytes.append(0)
	old_bytes.append(0)
	# Reconstruct vector from bytes
	var old_correction: Vector2 = bytes2var(old_bytes)
	
	if old_correction.x != 0.0 and old_correction.x < correction.x:
		return
	
	# Convert Vector2 to bytes
	var bytes: PoolByteArray = var2bytes(correction)
	# Read only 4 bytes from x (Byte 4 to 7)
	for i in range(4):
		_data[position + i] = bytes[i + 4]







