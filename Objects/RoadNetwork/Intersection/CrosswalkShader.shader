shader_type spatial;

const float width = 0.05;
const float frequency = 0.2;
const float border = 0.1;


void fragment() {
	vec3 color = vec3(0.01);
	vec2 uv = UV;
	
	if(NORMAL.y > 0.0 && uv.y > border && uv.y < 1.0 - border) {
		if (mod(uv.x, frequency) < width){
				color = vec3(1.0);
			}
	}
	
	ALBEDO = color;

}