shader_type spatial;

uniform sampler2D bike_icon;
uniform sampler2D bike_road_icon;
uniform sampler2D pedestrian_icon;
uniform float icon_frequency = 200.0;

const float outer_line_width = 0.03;
const float outer_line_offset = 0.05;
const float outer_line_length = 40.0;
const float outer_line_frequency = 60.0;

const float inner_line_width = 0.04;
const float inner_line_length = 12.0;
const float inner_line_frequency = 40.0;

const float inner_lines = 1.0;

uniform int number_of_lanes = 9;
uniform int lane_type_0 = 4;
uniform int lane_type_1 = 3;
uniform int lane_type_2 = 10;
uniform int lane_type_3 = 10;
uniform int lane_type_4 = 0;
uniform int lane_type_5 = 10;
uniform int lane_type_6 = 10;
uniform int lane_type_7 = 1;
uniform int lane_type_8 = 4;
uniform int lane_type_9 = -1;
uniform int lane_type_10 = -1;
uniform int lane_type_11 = -1;

uniform float lane_width_0 = 2.0;
uniform float lane_width_1 = 1.8;
uniform float lane_width_2 = 3.0;
uniform float lane_width_3 = 3.0;
uniform float lane_width_4 = 3.0;
uniform float lane_width_5 = 3.0;
uniform float lane_width_6 = 3.0;
uniform float lane_width_7 = 3.0;
uniform float lane_width_8 = 3.0;
uniform float lane_width_9 = 3.0;
uniform float lane_width_10 = 3.0;
uniform float lane_width_11 = 3.0;

uniform float road_length = 800.0;

uniform bool left_bike_on_road = false;
uniform bool right_bike_on_road = false;


float map_to_range(float value, float old_from, float old_to, float new_from, float new_to){
	return new_from + ((new_to - new_from) / (old_to - old_from)) * (value - old_from);
}

bool inside_line(float value, float width , float position){
	return value > position - width / 2.0 && value < position + width / 2.0;
}

vec3 read_icon(sampler2D icon, vec2 uv, float width, vec3 color, int lane) {
	if (uv.x < road_length * 8.0 && road_length >= 10.0){
		if (uv.y > 0.1 && uv.y < 0.9){
			float x = mod(uv.x, icon_frequency);
			if (x <= (width * 10.0)){
				x = x / (width * 10.0);
				x *= ((number_of_lanes / 2) <= lane) ? -1.0 : 1.0;
				float y = map_to_range(uv.y, 0.1, 0.9, 0, 1);
				vec4 pixel = texture(icon, vec2(y, x));
				return (pixel.a > 0.1) ? pixel.rgb : color;
			}
		}
	}
	return color;
}

vec3 road_lane(vec2 uv, vec3 color) {
	// Left outer line
	if (inside_line(uv.y, outer_line_width, outer_line_offset)){
		if (left_bike_on_road){
			if (mod(uv.x, outer_line_frequency) < outer_line_length){
				color = vec3(1.0);
			}
		}
		else {
			color = vec3(1.0);
		}
	}
	// Right outer line
	if (inside_line(uv.y, outer_line_width, 1.0 - outer_line_offset)){
		if (right_bike_on_road){
			if (mod(uv.x, outer_line_frequency) < outer_line_length){
				color = vec3(1.0);
			}
		}
		else {
			color = vec3(1.0);
		}
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

vec3 bike_lane(vec2 uv, float width, vec3 color, int lane){
	color = read_icon(bike_icon, uv, width, color, lane);
	
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

vec3 pedestrian_lane(vec2 uv, float width, vec3 color, int lane){
	return read_icon(pedestrian_icon, uv, width, color, lane);
}

vec3 bike_on_road(vec2 uv, float width, vec3 color, int lane){
	if(uv.y > 0.0 && uv.y < 1.0){
		color = vec3(214.0 / 255.0, 118.0 / 255.0, 118.0 / 255.0);
		color = read_icon(bike_road_icon, uv, width, color, lane);
	}
	return color;
}


void fragment() {
	vec3 color = vec3(40.0 / 255.0);
	
	int types[] = 
	{
		lane_type_0, lane_type_1, lane_type_2, lane_type_3, lane_type_4, 
		lane_type_5, lane_type_6, lane_type_7, lane_type_8, lane_type_9,
		lane_type_10, lane_type_11
	};
	
	float widths[] = 
	{
		lane_width_0, lane_width_1, lane_width_2, lane_width_3, lane_width_4,
		lane_width_5, lane_width_6, lane_width_7, lane_width_8, lane_width_9,
		lane_width_10, lane_width_11
	};
	
	for(int i = 0; i < number_of_lanes; i++){
		vec2 uv = UV * (float(number_of_lanes) * 2.0 + 6.0) - float(i);
		// Car
		if(types[i] == 0){
			color = road_lane(uv, color);
		}
		// Bike on Road
		else if(types[i] == 1){
			color = bike_on_road(uv, widths[i], color, i);
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
				color = pedestrian_lane(uv, widths[i], color, i);
			}
		}
		// Bike
		else if(types[i] == 4){
			color = bike_lane(uv, widths[i], color, i);
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
