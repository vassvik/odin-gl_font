import "core:fmt.odin";
import "core:mem.odin";

import "shared:odin-glfw/glfw.odin";
import "shared:odin-gl/gl.odin";

export "font_base.odin";


main :: proc() {
	sizes := [...]int{72, 68, 64, 60, 56, 52, 48, 44, 40, 36, 32, 28, 24, 20, 16, 12};
	codepoints: [95]rune;
	for i in 0..95 do codepoints[i] = rune(32+i);

	font, success_font := get_font_from_ttf("consola.ttf", "Consola", [2]int{1, 1}, sizes[...], codepoints[...]);
	if !success_font {
		return;
	}
	save_as_png(&font);

	resx, resy := 1600, 900;
    window := glfw.init_helper(resx, resy, "Odin Font Rendering", 4, 3, 0, true);
    if window == nil {
        glfw.Terminate();
        return;
    }
    defer glfw.Terminate();

    gl.load_up_to(4, 3, glfw.set_proc_address);


    program, success_program := gl.load_shaders_source(vertex_shader, fragment_shader);
    if !success_program do return;
    gl.UseProgram(program);

    MAX_INSTANCES :: 10000;
    colors := make([]Vec4, 65536);
    defer free(colors);

    //asd
    vao: u32;
    gl.GenVertexArrays(1, &vao);
    gl.BindVertexArray(vao);

    // @TODO: update to bindless textures?
    texture: u32;
    gl.GenTextures(1, &texture);
    gl.ActiveTexture(gl.TEXTURE0);
    gl.BindTexture(gl.TEXTURE_2D, texture);

    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, i32(font.width), i32(font.height), 0, gl.RED, gl.UNSIGNED_BYTE, &font.bitmap[0]);
    
// SSBO's for general gpu storage, used for indirect lookup using instance ID
all_buffer: u32;
gl.GenBuffers(1, &all_buffer);

offset: i32;
gl.GetIntegerv(gl.SHADER_STORAGE_BUFFER_OFFSET_ALIGNMENT, &offset);

size_instances := size_of(Glyph_Instance)*MAX_INSTANCES;
size_glyph_metrics := size_of(Glyph_Metric)*len(font.size_metrics)*len(font.codepoints);
size_colors := size_of(Vec4)*len(colors);

// @WARNING: must round to nearest multiple of `offset` to satisfy opengl's alignment requirements
size_instances_rounded := int(size_instances+0x20)&(~int(0x3f));
size_glyph_metrics_rounded := int(size_glyph_metrics+0x20)&(~int(0x3f));
size_colors_rounded := int(size_colors+0x20)&(~int(0x3f));

fmt.println(len(font.size_metrics), len(font.codepoints), len(font.size_metrics)*len(font.codepoints));

all_data := make([]byte, size_instances_rounded+size_glyph_metrics_rounded+size_colors_rounded);
mem.copy(&all_data[size_instances_rounded], &font.glyph_metrics[0], size_glyph_metrics);
mem.copy(&all_data[size_instances_rounded+size_glyph_metrics_rounded], &colors[0], size_colors);

gl.BindBuffer(gl.SHADER_STORAGE_BUFFER, all_buffer);
gl.BufferData(gl.SHADER_STORAGE_BUFFER, size_instances_rounded+size_colors_rounded+size_glyph_metrics_rounded, &all_data[0], gl.DYNAMIC_DRAW); // @WARNING: Performance concerns?

gl.BindBufferRange(gl.SHADER_STORAGE_BUFFER, 0, all_buffer, 0, size_instances);
gl.BindBufferRange(gl.SHADER_STORAGE_BUFFER, 1, all_buffer, size_instances_rounded, size_glyph_metrics);
gl.BindBufferRange(gl.SHADER_STORAGE_BUFFER, 2, all_buffer, size_instances_rounded+size_glyph_metrics_rounded, size_colors);

    gl.Uniform2f(gl.get_uniform_location(program, "bitmap_resolution"), f32(font.width), f32(font.height)); 
    gl.Uniform1i(gl.get_uniform_location(program, "sampler_bitmap"), 0);

    //
    glyph_instances := make([]Glyph_Instance, MAX_INSTANCES);


    gl.Disable(gl.DEPTH_TEST);
    gl.Enable(gl.BLEND);
    gl.BlendEquation(gl.FUNC_ADD);
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

    gl.ClearColor(0.9, 0.9, 0.9, 1.0);
    for !glfw.WindowShouldClose(window) {
    	glfw.PollEvents();
    	if glfw.GetKey(window, glfw.KEY_ESCAPE) do glfw.SetWindowShouldClose(window, true);

    	gl.Clear(gl.COLOR_BUFFER_BIT);

    	gl.UseProgram(program);


    	num, dx, dy := parse_string(&font, "this is\nall in a single\n    drawcall", 72, nil, glyph_instances);

    	gl.BindVertexArray(vao);	 
    	gl.BindBuffer(gl.SHADER_STORAGE_BUFFER, all_buffer);   
	    gl.BindBufferRange(gl.SHADER_STORAGE_BUFFER, 0, all_buffer, 0, size_instances);
	    gl.BindBufferRange(gl.SHADER_STORAGE_BUFFER, 1, all_buffer, size_instances_rounded, size_glyph_metrics);
	    gl.BindBufferRange(gl.SHADER_STORAGE_BUFFER, 2, all_buffer, size_instances_rounded+size_glyph_metrics_rounded, size_colors);
	    gl.BufferSubData(gl.SHADER_STORAGE_BUFFER, 0, num*size_of(Glyph_Instance), &glyph_instances[0]);


	    gl.ActiveTexture(gl.TEXTURE0);
	    gl.BindTexture(gl.TEXTURE_2D, texture);
	    gl.Uniform2f(gl.get_uniform_location(program, "window_resolution"), f32(resx), f32(resy));
    	gl.Uniform2f(gl.get_uniform_location(program, "string_offset"), f32(0.0), f32(0.0)); 

    	gl.DrawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, cast(i32)num);

    	glfw.SwapBuffers(window);
    }
}



vertex_shader := `
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

fragment_shader := `
#version 430 core

layout (std430, binding = 2) buffer color_buffer {
    vec3 palette[];
};

flat in uint palette_index;
in vec2 uv;

uniform sampler2D sampler_bitmap;

out vec4 color;

void main() {
     float a = texture(sampler_bitmap, uv).r;
     vec3 c = palette[palette_index];
     color = vec4(c, a);
}
`;