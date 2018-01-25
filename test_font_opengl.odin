import "core:fmt.odin";
import "core:mem.odin";

import "shared:odin-glfw/glfw.odin";
import "shared:odin-gl/gl.odin";

import font_gl "font_opengl.odin";

Vec4 :: #type_alias font_gl.Vec4;

main :: proc() {

	resx, resy := 1280/2, 720/2;
    window := glfw.init_helper(resx, resy, "Odin Font Rendering", 4, 3, 0, false);
    if window == nil {
        glfw.Terminate();
        return;
    }
    defer glfw.Terminate();

    gl.load_up_to(4, 3, glfw.set_proc_address);

    //
	sizes := [...]int{72, 68, 64, 60, 56, 52, 48, 44, 40, 36, 32, 28, 24, 20, 16, 12};
	codepoints: [95]rune;
	for i in 0..95 do codepoints[i] = rune(32+i);

	font, success_font := font_gl.init_from_ttf_gl("consola.ttf", "Consola", true, sizes[...], codepoints[...]);
	if !success_font {
		return;
	}

	//
	font_gl.colors[0] = Vec4{248/255.0, 248/255.0, 242/255.0, 1.0}; // white/text
	font_gl.colors[1] = Vec4{166/255.0, 226/255.0, 46/255.0, 1.0}; // green/function
	font_gl.colors[2] = Vec4{102/255.0, 217/255.0, 239/255.0, 1.0}; // blue/function names
	font_gl.colors[3] = Vec4{174/255.0, 129/255.0, 255/255.0, 1.0}; // purple/numbers
	font_gl.colors[4] = Vec4{230/255.0, 219/255.0, 116/255.0, 1.0}; // yellow/strings
	font_gl.colors[5] = Vec4{249/255.0, 38/255.0, 114/255.0, 1.0}; // red/keywords
	font_gl.update_colors(0, 6);

	fmt.println(font.glyph_metrics[14*95+65]);

	//
    gl.ClearColor(39/255.0, 40/255.0, 34/255.0, 1.0);
    for !glfw.WindowShouldClose(window) {
    	glfw.PollEvents();
    	if glfw.GetKey(window, glfw.KEY_ESCAPE) do glfw.SetWindowShouldClose(window, true);

    	gl.Clear(gl.COLOR_BUFFER_BIT);

		font_gl.set_state();
		num, dx, dy := font_gl.parse_string(&font, "The quick brown fox jumps over the lazy dog", 16, nil, font_gl.glyph_instances);
		font_gl.draw_instances(font_gl.glyph_instances[0..num], [2]f32{0.0, 1.0});
		num, dx, dy  = font_gl.parse_string(&font, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", 16, nil, font_gl.glyph_instances);
		font_gl.draw_instances(font_gl.glyph_instances[0..num], [2]f32{0.0, 17.0});
		num, dx, dy  = font_gl.parse_string(&font, "[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[", 16, nil, font_gl.glyph_instances);
		font_gl.draw_instances(font_gl.glyph_instances[0..num], [2]f32{0.0, 33.0});
		num, dx, dy  = font_gl.parse_string(&font, "abcdefghijklmnopqrstuvwxyz0123456789!#¤%&/(", 16, nil, font_gl.glyph_instances);
		font_gl.draw_instances(font_gl.glyph_instances[0..num], [2]f32{0.0, 49.0});

    	glfw.SwapBuffers(window);
    }
} 