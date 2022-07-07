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
	// The road surface UVs are only between 0 and 0.125
	vec2 uv = UV / 0.125;
	
	vec3 color = vec3(0.01);
	
	// Left outer line
	if (inside_line(uv.y, outer_line_width, outer_line_offset)){
		color = vec3(1.0);
	}
	// Right outer line
	if (inside_line(uv.y, outer_line_width, 1.0 - outer_line_offset)){
		color = vec3(1.0);
	}
	
	float offset = outer_line_width + outer_line_offset / 2.0;
	float lane_width = ((1.0 - 2.0 * offset) - inner_line_width * inner_lines) / (inner_lines + 1.0);
	
	
	offset += lane_width / 2.0;
	if (uv.y > offset && uv.y < 1.0 - offset){
		// TODO: Mapping uv here results in different line widths returned from `inside_line()` 
		uv.y = map_to_range(uv.y, offset, 1.0 - offset, 0.0, 1.0);
		uv.y *= inner_lines;
		if (inside_line(fract(uv.y), inner_line_width * inner_lines, 0.5)) {
			if (mod(uv.x, inner_line_frequency) < inner_line_length){
				color = vec3(1.0);
			}
		}
	}
	
	ALBEDO = color;

}
