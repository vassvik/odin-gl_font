package font_gl 

import "core:fmt";
import "core:mem";

import gl "shared:odin-gl";


MAX_COLORS :: 65536;
colors: []Vec4;

program: u32;
vao: u32;
texture: u32;
all_buffer: u32;

MAX_INSTANCES :: 1000000;
glyph_instances: []Glyph_Instance;

size_instances: int;
size_metrics: int;
size_colors: int;
offset_instances: int;
offset_metrics: int;
offset_colors: int;

destroy_gl :: proc(font: Font) {
	if colors != nil do delete(colors);
	if glyph_instances != nil do delete(glyph_instances);

	destroy(font);
}

init_from_ttf_gl :: proc(ttf_name, identifier: string, use_subpixels: bool, sizes: []int, codepoints: []rune) -> (Font, bool) {
	
	// check for opengl function pointers.
	if gl.loaded_up_to_major*10 + gl.loaded_up_to_minor < 43 {
		fmt.println("Error: Function pointers for OpenGL version 4.3 not loaded. Got '%d.%d' instead.", gl.loaded_up_to_major, gl.loaded_up_to_minor);
		return Font{}, false;
	}

	// load shaders from source
	_program, success_program := gl.load_shaders_source(vertex_shader_source, fragment_shader_source);
    if !success_program {
    	fmt.println("Error: Could not load font shaders.");
    	return Font{}, false;
	}
	program = _program;
    gl.UseProgram(program);

	// init the base font stuff
	font, success := init_from_ttf(ttf_name, identifier, use_subpixels ? [2]int{3, 1} : [2]int{1,1}, sizes, codepoints);
	if !success {
		return Font{}, false;
	}

	//
	colors = make([]Vec4, 65536);

    //
    glyph_instances = make([]Glyph_Instance, MAX_INSTANCES);

	//
    gl.GenVertexArrays(1, &vao);
    gl.BindVertexArray(vao);

    //
    gl.GenTextures(1, &texture);
    gl.ActiveTexture(gl.TEXTURE0);
    gl.BindTexture(gl.TEXTURE_2D, texture);

    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, i32(font.width), i32(font.height), 0, gl.RED, gl.UNSIGNED_BYTE, &font.bitmap[0]);

	// SSBO's for general gpu storage, used for indirect lookup using instance ID
	gl.GenBuffers(1, &all_buffer);

	//
	round_up_power_of_two :: proc(value: int, pot: int) -> int {
		return (value + pot/2) & ~int(pot-1);
	}

	//
	size_instances = size_of(Glyph_Instance)*MAX_INSTANCES;
	size_metrics   = size_of(Glyph_Metric)*len(font.size_metrics)*len(font.codepoints);
	size_colors    = size_of(Vec4)*len(colors);
	
	//offset: i32;
	//gl.GetIntegerv(gl.SHADER_STORAGE_BUFFER_OFFSET_ALIGNMENT, &offset);
	// @NOTE: just assume the offset is 64

	// @WARNING: must round to nearest multiple of `offset` to satisfy opengl's alignment requirements
	size_instances_rounded := round_up_power_of_two(size_instances, 64);
	size_metrics_rounded   := round_up_power_of_two(size_metrics,   64);
	size_colors_rounded    := round_up_power_of_two(size_colors,    64);
	size_total_rounded     := size_instances_rounded + size_metrics_rounded + size_colors_rounded;
	
	offset_instances = 0;
	offset_metrics   = offset_instances + size_instances_rounded;
	offset_colors    = offset_metrics   + size_metrics;

	//
	all_data := make([]byte, size_total_rounded);
	mem.copy(&all_data[offset_metrics], &font.glyph_metrics[0], size_metrics);
	mem.copy(&all_data[offset_colors],  &colors[0],             size_colors);

	// 
	gl.BindBuffer(gl.SHADER_STORAGE_BUFFER, all_buffer);
	gl.BufferData(gl.SHADER_STORAGE_BUFFER, size_total_rounded, &all_data[0], gl.DYNAMIC_DRAW); // @WARNING: Performance concerns?

	//
	gl.BindBufferRange(gl.SHADER_STORAGE_BUFFER, 0, all_buffer, offset_instances, size_instances);
	gl.BindBufferRange(gl.SHADER_STORAGE_BUFFER, 1, all_buffer, offset_metrics,   size_metrics);
	gl.BindBufferRange(gl.SHADER_STORAGE_BUFFER, 2, all_buffer, offset_colors,    size_colors);

	// 
	gl.UseProgram(program);
    gl.Uniform2f(gl.get_uniform_location(program, "bitmap_resolution"), f32(font.width), f32(font.height)); 
    gl.Uniform1i(gl.get_uniform_location(program, "sampler_bitmap"), 0);
    gl.Uniform1i(gl.get_uniform_location(program, "use_subpixels"), i32(use_subpixels));

	return font, true;
}



update_colors :: proc(start, num: int) {
	gl.BindBuffer(gl.SHADER_STORAGE_BUFFER, all_buffer);
 	gl.BufferSubData(gl.SHADER_STORAGE_BUFFER, offset_colors, num*size_of(Vec4), &colors[start]);
}

set_state :: proc() {
	//
	gl.Disable(gl.CULL_FACE);
	gl.Disable(gl.DEPTH_TEST);
    gl.Enable(gl.BLEND);
    gl.BlendEquation(gl.FUNC_ADD);
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

	//
	gl.BindVertexArray(vao);
	gl.BindBuffer(gl.SHADER_STORAGE_BUFFER, all_buffer);

    //
    gl.BindBufferRange(gl.SHADER_STORAGE_BUFFER, 0, all_buffer, offset_instances, size_instances);
    gl.BindBufferRange(gl.SHADER_STORAGE_BUFFER, 1, all_buffer, offset_metrics,   size_metrics);
    gl.BindBufferRange(gl.SHADER_STORAGE_BUFFER, 2, all_buffer, offset_colors,    size_colors);

    //
    gl.ActiveTexture(gl.TEXTURE0);
    gl.BindTexture(gl.TEXTURE_2D, texture);

    //
    dims: [4]i32;
    gl.GetIntegerv(gl.VIEWPORT, &dims[0]);

    //
	gl.UseProgram(program);
    gl.Uniform2f(gl.get_uniform_location(program, "window_resolution"), f32(dims[2] - dims[0]), f32(dims[3]-dims[1]));

}

draw_instances :: proc(instances: []Glyph_Instance, offset: [2]f32) {
	if len(instances) == 0 do return;

	//
	gl.BindBuffer(gl.SHADER_STORAGE_BUFFER, all_buffer);
 	gl.BufferSubData(gl.SHADER_STORAGE_BUFFER, 0, len(instances)*size_of(Glyph_Instance), &instances[0]);
	
	gl.Uniform2f(gl.get_uniform_location(program, "string_offset"), offset.x, offset.y); 
 	
	//
	gl.DrawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, cast(i32)len(instances));
}

str_backing: [1024]u8;

draw_string_nopalette :: inline proc(font: ^Font, size: int, at: [2]f32, palette: u16, format: string, args: ..any) -> (int, f32, f32) {
	return draw_string_palette(font, size, at, []u16{palette}, format, ..args);
}

draw_string_palette :: inline proc(font: ^Font, size: int, at: [2]f32, palette: []u16, format: string, args: ..any) -> (int, f32, f32) {
	str: string;
	if len(args) > 0 {
		str = fmt.bprintf(str_backing[:], format, ..args);
	} else {
		str = format;
	}

	num, dx, dy := parse_string(font, str, size, palette, glyph_instances);
	draw_instances(glyph_instances[0:num], at);

	return num, dx, dy;
}

draw_string :: proc{draw_string_palette, draw_string_nopalette};

vertex_shader_source := `
#version 430 core

// glyph data types and buffers
struct GlyphInstance {
    uint x_y;
    uint index_palette;
};

struct GlyphMetric {
    uint x0_y0, x1_y1;
    float xoff, yoff, xadvance;
    float xoff2, yoff2;
};

layout (std430, binding = 0) buffer glyph_instance_buffer {
    GlyphInstance glyph_instances[];
};

layout (std430, binding = 1) buffer glyph_metric_buffer {
    GlyphMetric glyph_metrics[];
};

uint get_lower(uint val) { return val & uint(0xFFFF); }
uint get_upper(uint val) { return val >> 16 & uint(0xFFFF); }
float fixed_to_float(uint val) { return float(val)/32.0; }
vec2 fixed2_to_vec2(uint val) { return vec2(fixed_to_float(get_lower(val)), fixed_to_float(get_upper(val))); }
vec2 uint_to_vec2(uint val) { return vec2(get_lower(val), get_upper(val)); }

uniform vec2 window_resolution;
uniform vec2 bitmap_resolution;

uniform vec2 string_offset = vec2(0.0);

out vec2 uv;
flat out uint palette_index;

void main() {
    // grab the relevant metadata from the buffers using the instance ID.
    GlyphInstance glyph_instance = glyph_instances[gl_InstanceID];
    GlyphMetric metric = glyph_metrics[get_lower(glyph_instance.index_palette)];
    palette_index = get_upper(glyph_instance.index_palette);

    // expand vertex ID to quad positions:
    vec2 p = vec2(gl_VertexID % 2, gl_VertexID/ 2); // unit square

    // grab the texture coordinates
    vec2 p0 = uint_to_vec2(metric.x0_y0);
    vec2 p1 = uint_to_vec2(metric.x1_y1);
    uv = (p0 + (p1 - p0)*p)/bitmap_resolution;

    // transform the vertex, starting from unit square
    p *= vec2(metric.xoff2 - metric.xoff, metric.yoff2 - metric.yoff); // scale
    p += vec2(metric.xoff, metric.yoff);                               // correct position relative to baseline
    p += fixed2_to_vec2(glyph_instance.x_y);                           // per-glyph positioning
    p += string_offset;                                                // move string
    p *= vec2(1.0, -1.0);                                              // invert y
    p *= 2.0/window_resolution;                                        // correct for aspect ratio and transform to NDC
    p += vec2(-1.0, 1.0);                                              // move to the upper left corner
    gl_Position = vec4(p, 0.0, 1.0);
    
}
`;

fragment_shader_source := `
#version 430 core

layout (std430, binding = 2) buffer color_buffer {
    vec4 palette[];
};

flat in uint palette_index;
in vec2 uv;

uniform sampler2D sampler_bitmap;
uniform vec2 bitmap_resolution;
uniform bool use_subpixels;

out vec4 color;

void main() {
	if (use_subpixels) {
	    float r = textureOffset(sampler_bitmap, uv, ivec2(-1, 0)).r;
	    float g = textureOffset(sampler_bitmap, uv, ivec2(0, 0)).r;
	    float b = textureOffset(sampler_bitmap, uv, ivec2(1, 0)).r;
	    vec4 c = palette[palette_index];
	    vec4 bg_color = vec4(255.0/255.0, 255.0/255.0, 255.0/255.0, 1.0);

	   	color = mix(bg_color, c, vec4(r, g, b, 1.0));
    } else {
    	float a = texture(sampler_bitmap, uv).r;
    	vec4 c = palette[palette_index];
    	color = vec4(c.xyz, a*c.w);
    }
}
`;