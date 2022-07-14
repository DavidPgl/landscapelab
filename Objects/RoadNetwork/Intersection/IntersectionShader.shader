shader_type spatial;

const float outer_line_width = 0.03;
const float outer_line_offset = 0.05;

const float inner_line_width = 0.04;
const float inner_line_length = 12.0;
const float inner_line_frequency = 40.0;

const float inner_lines = 1.0;


float map_to_range(float value, float old_from, float old_to, float new_from, float new_to){
	return new_from + ((new_to - new_from) / (old_to - old_from)) * (value - old_from);
}

bool inside_line(float value, float width , float position){
	return value > position - width / 2.0 && value < position + width / 2.0;
}


void fragment() {
	vec3 color = vec3(0.01);
	
	ALBEDO = color;

}
