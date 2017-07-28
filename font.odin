import (
    gl_font "gl.odin";
    os_font "os.odin";
    mem_font "mem.odin";
);

// wrapper to use GetUniformLocation with an Odin string
// @NOTE: str has to be zero-terminated, so add a \x00 at the end
GetUniformLocation_ :: proc(program: u32, str: string) -> i32 {
    return gl_font.GetUniformLocation(program, &str[0]);;
}

GlyphMetrics :: struct #ordered {
    x0, y0, x1, y1: u16; 
    xoff, yoff, xadvance: f32;
    xoff2, yoff2: f32;
};
GlyphInstance :: struct #ordered {
    x, y: u16;
    index, palette: u16;
};

FontMetrics :: struct #ordered {
    size, ascent, descent, linegap: f32;
};

Vec4 :: struct #ordered {
    x, y, z, w: f32;
};

// f32 to 11.5 fixed point, round to nearest fractional part
// `val` between 0.0 and 2047.0
float_to_fixed :: proc(val: f32) -> u16 {
    return u16(32.0*val + 0.5);
}
// 11.5 fixed point to f32
fixed_to_float :: proc(val: u16) -> f32 {
    return f32(val)/32.0;
}




max_instances :: 1000000;
num_colors :: 4;

glyph_instances: []GlyphInstance;
glyph_metrics: []GlyphMetrics;
font_metrics: []FontMetrics;

colors: [num_colors]Vec4;

last_program, last_vertex_array: i32;
last_texture: i32;
last_blend_src, last_blend_dst: i32;
last_blend_equation_rgb, last_blend_equation_alpha: i32;
last_enable_blend, last_enable_depth_test: u8;

glyph_instance_buffer, glyph_metric_buffer, color_buffer: u32;
vao: u32;
program: u32;
texture_bitmap: u32;

width, height: int;


save_state :: proc() {
    using gl_font;
    // save state
    GetIntegerv(CURRENT_PROGRAM, &last_program);
    GetIntegerv(VERTEX_ARRAY_BINDING, &last_vertex_array);

    ActiveTexture(TEXTURE0); 
    GetIntegerv(TEXTURE_BINDING_2D, &last_texture);

    GetIntegerv(BLEND_SRC, &last_blend_src);
    GetIntegerv(BLEND_DST, &last_blend_dst);
    
    GetIntegerv(BLEND_EQUATION_RGB, &last_blend_equation_rgb);
    GetIntegerv(BLEND_EQUATION_ALPHA, &last_blend_equation_alpha);

    last_enable_blend = IsEnabled(BLEND);
    last_enable_depth_test = IsEnabled(DEPTH_TEST);
}

restore_state :: proc() {
    using gl_font;
    // restore state
    UseProgram(cast(u32)last_program);
    BindTexture(TEXTURE_2D, cast(u32)last_texture);
    BindVertexArray(cast(u32)last_vertex_array);

    BlendEquationSeparate(cast(u32)last_blend_equation_rgb, cast(u32)last_blend_equation_alpha);
    BlendFunc(cast(u32)last_blend_src, cast(u32)last_blend_dst);
    
    if last_enable_depth_test == TRUE do Enable(DEPTH_TEST);
    else do Disable(DEPTH_TEST);
    
    if last_enable_blend == TRUE do Enable(BLEND);
    else do Disable(BLEND);
}

draw_string :: proc(str: string, offset_x, offset_y: f32, size: f32) {
    idx := -1;
    for font_metric, i in font_metrics {
        if font_metric.size == size {
            idx = i;
        }
    }
    if idx == -1 do return;

    cursor_x := f32(4.0);
    cursor_y := f32(4.0 + int(1.0*font_metrics[idx].ascent + 0.5));

    num_instances := 0;
    for c, i in str {
        if c == '\n' {
            cursor_x = f32(4.0);
            cursor_y += f32(int(font_metrics[idx].size + 0.5));
        }
        glyph_instances[i].x = float_to_fixed(cursor_x);
        glyph_instances[i].y = float_to_fixed(cursor_y);
        glyph_instances[i].index = u16(idx)*95 + (u16(c) - 32);
        glyph_instances[i].palette = u16(num_instances&3);

        cursor_x += glyph_metrics[u16(idx)*95+(u16(c) - 32)].xadvance;
        num_instances += 1;
    }

    using gl_font;

    NamedBufferSubData(glyph_instance_buffer, 0, size_of(GlyphInstance)*int(num_instances), &glyph_instances[0]);

    save_state();

    // Change state
    Disable(DEPTH_TEST);
    Enable(BLEND);
    BlendEquation(FUNC_ADD);
    BlendFunc(SRC_ALPHA, ONE_MINUS_SRC_ALPHA);

    BindTexture(TEXTURE_2D, texture_bitmap);
    UseProgram(program);

    dims: [4]i32;
    GetIntegerv(VIEWPORT, &dims[0]);
    Uniform2f(GetUniformLocation_(program, "window_resolution"), f32(dims[2] - dims[0]), f32(dims[3]-dims[1]));
    
    Uniform2f(GetUniformLocation_(program, "string_offset"), f32(offset_x), f32(offset_y)); 
    Uniform2f(GetUniformLocation_(program, "bitmap_resolution"), f32(width), f32(height)); 
    Uniform1i(GetUniformLocation_(program, "sampler_bitmap"), 0);

    BindVertexArray(vao);
    DrawArraysInstanced(TRIANGLE_STRIP, 0, 4, cast(i32)num_instances);

    restore_state();
}

cleanup_font :: proc() {
    using gl_font;
    DeleteProgram(program);
    DeleteVertexArrays(1, &vao);
    DeleteTextures(1, &texture_bitmap);

    DeleteBuffers(1, &glyph_instance_buffer);
    DeleteBuffers(1, &glyph_metric_buffer);
    DeleteBuffers(1, &color_buffer);

    free(glyph_instances);
    free(glyph_metrics);
    free(font_metrics);
}

init_font :: proc() -> bool {
    using gl_font;

    // grab the binary font data
    data_3x1, success_3x1 := os_font.read_entire_file("font_3x1.bin");
    if !success_3x1 do return false;
    defer free(data_3x1);

    // grab the shaders
    success_shaders: bool;
    program, success_shaders = load_shaders("vertex_shader.vs", "fragment_shader.fs");
    if !success_shaders do return false;

    // the first 4 bytes is the number of font sizes
    num_sizes := cast(int)mem_font.slice_ptr(cast(^i32)&data_3x1[0], 1)[0];

    // allocate slices/arrays
    font_metrics    = make([]FontMetrics,   num_sizes);
    glyph_metrics   = make([]GlyphMetrics,  num_sizes*95);
    glyph_instances = make([]GlyphInstance, max_instances);
    colors = [num_colors]Vec4{
        {0.0, 0.0, 0.0, 1.0}, 
        {1.0, 0.0, 0.0, 1.0}, 
        {0.0, 1.0, 0.0, 1.0}, 
        {0.0, 0.0, 1.0, 1.0}
    };

    // parse the remaining data
    rest := data_3x1[4..];
    for i in 0..num_sizes {
        font_metrics[i] = mem_font.slice_ptr(cast(^FontMetrics)&rest[0], 1)[0];
        rest = rest[16..];

        for j in 0..95 do glyph_metrics[i*95 + j] = mem_font.slice_ptr(cast(^GlyphMetrics)&rest[0], 95)[j];
        
        rest = rest[size_of(GlyphMetrics)*95..];
    }

    bitmap := rest;
    
    width = 2048;
    height = len(bitmap)/2048;

    // create and initialize opengl objects
    CreateVertexArrays(1, &vao);

    // @TODO: update to bindless textures?
    GenTextures(1, &texture_bitmap);
    ActiveTexture(TEXTURE0);
    BindTexture(TEXTURE_2D, texture_bitmap);

    TexParameteri(TEXTURE_2D, TEXTURE_MIN_FILTER, LINEAR);
    TexParameteri(TEXTURE_2D, TEXTURE_MAG_FILTER, LINEAR);
    TexImage2D(TEXTURE_2D, 0, RED, i32(width), i32(height), 0, RED, UNSIGNED_BYTE, &bitmap[0]);
    
    // SSBO's for general gpu storage, used for indirect lookup using instance ID
    CreateBuffers(1, &glyph_instance_buffer);
    CreateBuffers(1, &glyph_metric_buffer);
    CreateBuffers(1, &color_buffer);

    BindBufferBase(SHADER_STORAGE_BUFFER, 0, glyph_instance_buffer);
    BindBufferBase(SHADER_STORAGE_BUFFER, 1, glyph_metric_buffer);
    BindBufferBase(SHADER_STORAGE_BUFFER, 2, color_buffer);

    NamedBufferData(glyph_instance_buffer, size_of(GlyphInstance)*max_instances, nil,               DYNAMIC_READ);
    NamedBufferData(glyph_metric_buffer,   size_of(GlyphMetrics)*num_sizes*95,   &glyph_metrics[0], DYNAMIC_READ);
    NamedBufferData(color_buffer,          size_of(colors),                      &colors[0],        DYNAMIC_READ);

    return true;
}