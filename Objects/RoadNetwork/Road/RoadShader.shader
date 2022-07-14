shader_type spatial;

const float outer_line_width = 0.03;
const float outer_line_offset = 0.05;

const float inner_line_width = 0.04;
const float inner_line_length = 12.0;
const float inner_line_frequency = 40.0;

const float inner_lines = 1.0;

uniform int number_of_lanes = 9;
uniform int lane_type_0 = 4;
uniform int lane_type_1 = -1;
uniform int lane_type_2 = 10;
uniform int lane_type_3 = 10;
uniform int lane_type_4 = 0;
uniform int lane_type_5 = 10;
uniform int lane_type_6 = 10;
uniform int lane_type_7 = -1;
uniform int lane_type_8 = 4;
uniform int lane_type_9 = -1;
uniform int lane_type_10 = -1;
uniform int lane_type_11 = -1;
uniform int lane_type_12 = -1;
uniform int lane_type_13 = -1;
uniform int lane_type_14 = -1;


float map_to_range(float value, float old_from, float old_to, float new_from, float new_to){
	return new_from + ((new_to - new_from) / (old_to - old_from)) * (value - old_from);
}

bool inside_line(float value, float width , float position){
	return value > position - width / 2.0 && value < position + width / 2.0;
}

vec3 road_lane(vec2 uv, vec3 color) {
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
	
	return color;
}

vec3 bike_lane(vec2 uv, vec3 color){
	// Left outer line
	if (inside_line(uv.y, outer_line_width, outer_line_offset)){
		color = vec3(1.0);
	}
	// Right outer line
	if (inside_line(uv.y, outer_line_width, 1.0 - outer_line_offset)){
		color = vec3(1.0);
	}
	
	return color;
}


void fragment() {
	vec3 color = vec3(0.01);
	
	int types[] = 
	{
		lane_type_0, lane_type_1, lane_type_2, lane_type_3, lane_type_4, 
		lane_type_5, lane_type_6, lane_type_7, lane_type_8, lane_type_9,
		lane_type_10, lane_type_11, lane_type_12, lane_type_13, lane_type_14
	};
	
	for(int i = 0; i < number_of_lanes; i++){
		vec2 uv = UV * (float(number_of_lanes) * 2.0 + 6.0) - float(i);
		// Car
		if(types[i] == 0){
			color = road_lane(uv, color);
		}
		// Bike on Car
		else if(types[i] == 1){
			if(uv.y > 0.0 && uv.y < 1.0){
				color = vec3(0.4, 0.1, 0.1);
			}
		}
		// Parking
		else if(types[i] == 2){
			if(uv.y > 0.0 && uv.y < 1.0){
				color = vec3(0.1, 0.1, 0.4);
			}
		}
		// Pedestrian
		else if(types[i] == 3){
			if(uv.y > 0.0 && uv.y < 1.0){
				color = vec3(0.2);
			}
		}
		// Bike
		else if(types[i] == 4){
			color = bike_lane(uv, color);
		}
		// Curbside
		else if(types[i] == 10){
			if(uv.y > 0.0 && uv.y < 1.0){
				color = vec3(0.4);
			}
		}
		
	}
	
	
	ALBEDO = color;

}
