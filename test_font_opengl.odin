import "core:fmt.odin";
import "core:math.odin";

import "shared:odin-glfw/glfw.odin";
import "shared:odin-gl/gl.odin";

import font_gl "font_opengl.odin";

Vec4 :: #type_alias font_gl.Vec4;

main :: proc() {

	resx, resy := 800, 320;
	window := glfw.init_helper(resx, resy, "Odin Font Rendering", 4, 3, 0, false);
	if window == nil {
		glfw.Terminate();
		return;
	}
	defer glfw.Terminate();

	gl.load_up_to(4, 3, glfw.set_proc_address);

	//
	sizes := [...]int{72, 68, 64, 60, 56, 52, 48, 44, 40, 36, 32, 28, 24, 20, 16, 12};
	codepoints: [96]rune;
	for i in 0..95 {
		codepoints[i] = rune(32+i);
	}
	codepoints[95] = rune('π');



	font, success_font := font_gl.init_from_ttf_gl("consola.ttf", "Consola", true, sizes[...], codepoints[...]);
	if !success_font {
		return;
	}
	defer font_gl.destroy_gl(font);

	//
	font_gl.colors[0] = Vec4{248/255.0, 248/255.0, 242/255.0, 1.0}; // white/text
	font_gl.colors[1] = Vec4{166/255.0, 226/255.0, 46/255.0,  1.0}; // green/function
	font_gl.colors[2] = Vec4{102/255.0, 217/255.0, 239/255.0, 1.0}; // blue/function names
	font_gl.colors[3] = Vec4{174/255.0, 129/255.0, 255/255.0, 1.0}; // purple/numbers
	font_gl.colors[4] = Vec4{230/255.0, 219/255.0, 116/255.0, 1.0}; // yellow/strings
	font_gl.colors[5] = Vec4{249/255.0, 38/255.0,  114/255.0, 1.0}; // red/keywords
	font_gl.update_colors(0, 6);

	//
	gl.ClearColor(39/255.0, 40/255.0, 34/255.0, 1.0);
	for !glfw.WindowShouldClose(window) {
		glfw.PollEvents();
		if glfw.GetKey(window, glfw.KEY_ESCAPE) do glfw.SetWindowShouldClose(window, true);

		gl.Clear(gl.COLOR_BUFFER_BIT);

		font_gl.set_state();

		str := "The quick brown fox jumps over the lazy dog";
		palette := [...]u16{
			1, 1, 1, // the
			0, 
			2, 2, 2, 2, 2, // quick
			0, 
			3, 3, 3, 3, 3, // brown
			0, 
			4, 4, 4, // fox
			0, 
			5, 5, 5, 5, 5, //jumps
			0, 
			1, 1, 1, 1, //over
			0, 
			2, 2, 2, // the
			0, 
			3, 3, 3, 3, //lazy
			0, 
			4, 4, 4  // dog
		};

		at := [2]f32{0.0, 1.0};
		num, dx, dy := font_gl.draw_string(&font, 16, at, 0,            str);              at.y += dy;
		num, dx, dy  = font_gl.draw_string(&font, 12, at, 1,            str);              at.y += dy;
		num, dx, dy  = font_gl.draw_string(&font, 16, at, 2,            str);              at.y += dy;
		num, dx, dy  = font_gl.draw_string(&font, 20, at, 3,            str);              at.y += dy;
		num, dx, dy  = font_gl.draw_string(&font, 24, at, 4,            str);              at.y += dy;
		num, dx, dy  = font_gl.draw_string(&font, 28, at, 5,            str);              at.y += dy;
		num, dx, dy  = font_gl.draw_string(&font, 32, at, palette[...], str);              at.y += dy;
		num, dx, dy  = font_gl.draw_string(&font, 16, at, 0,            "π = %f", math.π); at.y += dy;


		glfw.SwapBuffers(window);
	}
}  