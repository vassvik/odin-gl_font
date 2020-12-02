package gl_font_example

import "core:runtime"
import "core:fmt"

import glfw "shared:odin-glfw";
import gl "shared:odin-gl";
import gl_font "shared:odin-gl_font";

Font_Color :: enum {
	Black = 0,
	Red,
	Green,
	Blue,
	Yellow,
	Purple,
	Cyan,
	White
};

font_colors := [Font_Color]gl_font.Vec4 {
	.Black  = {0.0, 0.0, 0.0, 1.0},
	.Red    = {1.0, 0.0, 0.0, 1.0},
	.Green  = {0.0, 1.0, 0.0, 1.0},
	.Blue   = {0.0, 0.0, 1.0, 1.0},
	.Yellow = {1.0, 1.0, 0.0, 1.0},
	.Purple = {1.0, 0.0, 1.0, 1.0},
	.Cyan   = {0.0, 1.0, 1.0, 1.0},
	.White  = {1.0, 1.0, 1.0, 1.0},
};

Window :: struct{
	handle: glfw.Window_Handle,
	vao: u32,

	key_went_down: Key_Set,
	key_is_down:   Key_Set,
	key_went_up:   Key_Set,

	cached_time: f64,
	cached_min_time: f64,
	cached_max_time: f64,
	accumulated_time: f64,
	accumulated_count: int,
	average_time: f64,
	min_time: f64,
	max_time: f64,
}

main :: proc() {
	error_callback :: proc"c"(error: i32, desc: cstring) {
		context = runtime.default_context();
		fmt.printf("Error code %d: %s\n", error, desc);
	}
	glfw.set_error_callback(error_callback);

	if !glfw.init() do panic("Failed to init GLFW.");
	defer glfw.terminate();

	
	attribute_map := map[glfw.Window_Attribute]int{
		.CONTEXT_VERSION_MAJOR = 4,
		.CONTEXT_VERSION_MINOR = 4,
		.OPENGL_PROFILE = int(glfw.OpenGL_Profile.OPENGL_CORE_PROFILE),
		.SAMPLES = 8,
	};

	default_window_size := [2]int{1280, 720};
	main_window := new_window(default_window_size, "Main Window", attribute_map, 0, nil);
	
	gl.load_up_to(attribute_map[.CONTEXT_VERSION_MAJOR], attribute_map[.CONTEXT_VERSION_MINOR], glfw.set_proc_address); 

	fmt.println(gl.GetString(gl.VENDOR));
	fmt.println(gl.GetString(gl.RENDERER));

	sizes := [?]int{72, 68, 64, 60, 56, 52, 48, 44, 40, 36, 32, 28, 24, 20, 16, 12};
	codepoints: [95]rune;
	for i in 0..<95 do codepoints[i] = rune(32+i);
	font, font_success := gl_font.init_from_ttf_gl("C:/Windows/Fonts/consola.ttf", "Consola", false, sizes[:], codepoints[:]);
	if !font_success do panic("Failed to load font.");

	for v in Font_Color do gl_font.colors[v] = font_colors[v];
	gl_font.update_colors(0, len(Font_Color));

	init_key_map();
	init_window(main_window);

	for !glfw.window_should_close(main_window.handle) {
		time := glfw.get_time();
		glfw.poll_events();
		defer {
			main_window.key_went_down = {};
			main_window.key_went_up = {};
			if main_window.accumulated_time >= 1.0 {
				main_window.average_time = main_window.accumulated_time / f64(main_window.accumulated_count);
				main_window.min_time = main_window.cached_min_time;
				main_window.max_time = main_window.cached_max_time;
				main_window.accumulated_count = 0;
				main_window.accumulated_time = 0.0;
				main_window.cached_min_time = max(f64);
				main_window.cached_max_time = min(f64);
			}
			dt := time - main_window.cached_time;
			main_window.accumulated_time += dt;
			main_window.accumulated_count += 1;
			main_window.cached_time = time;
			main_window.cached_max_time = max(main_window.cached_max_time, dt);
			main_window.cached_min_time = min(main_window.cached_min_time, dt);
		}

		if .ESC in main_window.key_went_down {
			glfw.set_window_should_close(main_window.handle, true);
		}

		glfw.make_context_current(main_window.handle);
		if .KEY_1 in main_window.key_went_down do gl.ClearColor(1.0, 0.7, 0.4, 1.0);
		if .KEY_2 in main_window.key_went_down do gl.ClearColor(1.0, 0.4, 0.7, 1.0);
		if .KEY_3 in main_window.key_went_down do gl.ClearColor(0.7, 1.0, 0.4, 1.0);
		if .KEY_4 in main_window.key_went_down do gl.ClearColor(0.4, 1.0, 0.7, 1.0);
		if .KEY_5 in main_window.key_went_down do gl.ClearColor(0.7, 0.4, 1.0, 1.0);
		if .KEY_6 in main_window.key_went_down do gl.ClearColor(0.4, 0.7, 1.0, 1.0);
		if .KEY_0 in main_window.key_went_down do gl.ClearColor(0.5, 0.5, 0.5, 1.0);

		gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
		gl_font.set_state(main_window.vao);
		gl_font.draw_string(&font, 16, {10, 10},  0, "Window: %p", main_window.handle);
		gl_font.draw_string(&font, 16, {10, 30},  1, "Keys Went Down: %v", main_window.key_went_down);
		gl_font.draw_string(&font, 16, {10, 50},  2, "Keys Is Down:   %v", main_window.key_is_down);
		gl_font.draw_string(&font, 16, {10, 70},  3, "Keys Went Up:   %v", main_window.key_went_up);
		gl_font.draw_string(&font, 16, {10, 90},  4, "Previous frame time: %.3f ms", 1000*(time - main_window.cached_time));
		gl_font.draw_string(&font, 16, {10, 110}, 5, "Average frame time:  %.3f ms", 1000*main_window.average_time);
		gl_font.draw_string(&font, 16, {10, 130}, 6, "Minimum frame time:  %.3f ms", 1000*main_window.min_time);
		gl_font.draw_string(&font, 16, {10, 150}, 7, "Maximum frame time:  %.3f ms", 1000*main_window.max_time);
		glfw.swap_buffers(main_window.handle);
	}

	delete_window(main_window);
}

init_window :: proc(window: ^Window) {
	glfw.make_context_current(window.handle);
	window.cached_time = glfw.get_time();
	gl.GenVertexArrays(1, &window.vao);
	gl.ClearColor(0.5, 0.5, 0.5, 1.0);
}

delete_window :: proc(window: ^Window) {
	glfw.make_context_current(window.handle);
	gl.DeleteVertexArrays(1, &window.vao);
	glfw.destroy_window(window.handle);
	free(window);
}

new_window :: proc(window_size: [2]int, title: string, attribute_map: map[glfw.Window_Attribute]int, swap_interval: int = 1, share: glfw.Window_Handle = nil) -> ^Window {
	for k, v in attribute_map do glfw.window_hint(k, v);

	handle := glfw.create_window(window_size[0], window_size[1], title, nil, share);
	if handle == nil do return nil;

	glfw.make_context_current(handle);
	glfw.swap_interval(swap_interval);
	glfw.set_key_callback(handle, key_callback);

	window := new(Window);
	window.handle = handle;
	glfw.set_window_user_pointer(handle, window);
	return window;
}
	





key_callback :: proc "c" (handle: glfw.Window_Handle, key, scancode, action, kmods: i32) {
    context = runtime.default_context();
    window := cast(^Window)glfw.get_window_user_pointer(handle);
    assert(window != nil);
    assert(window.handle == handle);

    if action == 2 do return;
    if action == 1 {
        incl(&window.key_went_down, key_map[glfw.Key(key)]);
        incl(&window.key_is_down, key_map[glfw.Key(key)]);
    }
    if action == 0 {
        incl(&window.key_went_up, key_map[glfw.Key(key)]);
        excl(&window.key_is_down, key_map[glfw.Key(key)]);
    }
}

Key :: enum u16 {
    INVALID,

    LEFT_CTRL,
    LEFT_SHIFT,
    LEFT_ALT,
    LEFT_SUPER,
    RIGHT_CTRL,
    RIGHT_SHIFT,
    RIGHT_ALT,
    RIGHT_SUPER,

    ESC,
    ENTER,
    TAB,
    BACKSPACE,
    SPACE,
    DELETE,

    APOSTROPHE,
    COMMA,
    MINUS,
    PERIOD,
    SLASH,
    SEMICOLON,
    EQUAL,
    BACKSLASH,
    LEFT_BRACKET,
    RIGHT_BRACKET,
    GRAVE_ACCENT,
    HOME,
    END,

    A, B, C, D,
    E, F, G, H,
    I, J, K, L,
    M, N, O, P,
    Q, R, S, T,
    U, V, W, X,
    Y, Z,

    KEY_1, KEY_2, KEY_3, KEY_4, KEY_5,
    KEY_6, KEY_7, KEY_8, KEY_9, KEY_0,

    KP_0, KP_1, KP_2, KP_3, KP_4,
    KP_5, KP_6, KP_7, KP_8, KP_9,
    KP_DIVIDE, KP_MULTIPLY, KP_SUBTRACT,
    KP_ADD, KP_ENTER, KP_DECIMAL,

    F1, F2, F3, F4,
    F5, F6, F7, F8,
    F9, F10, F11, F12,

    RIGHT,
    UP,
    LEFT,
    DOWN,
}
#assert(len(Key) <= 128);
Key_Set :: bit_set[Key; u128];

key_map: map[glfw.Key]Key;
init_key_map :: proc() {
    key_map[.KEY_A] = .A;
    key_map[.KEY_B] = .B;
    key_map[.KEY_C] = .C;
    key_map[.KEY_D] = .D;
    key_map[.KEY_E] = .E;
    key_map[.KEY_F] = .F;
    key_map[.KEY_G] = .G;
    key_map[.KEY_H] = .H;
    key_map[.KEY_I] = .I;
    key_map[.KEY_J] = .J;
    key_map[.KEY_K] = .K;
    key_map[.KEY_L] = .L;
    key_map[.KEY_M] = .M;
    key_map[.KEY_N] = .N;
    key_map[.KEY_O] = .O;
    key_map[.KEY_P] = .P;
    key_map[.KEY_Q] = .Q;
    key_map[.KEY_R] = .R;
    key_map[.KEY_S] = .S;
    key_map[.KEY_T] = .T;
    key_map[.KEY_U] = .U;
    key_map[.KEY_V] = .V;
    key_map[.KEY_W] = .W;
    key_map[.KEY_X] = .X;
    key_map[.KEY_Y] = .Y;
    key_map[.KEY_Z] = .Z;

    key_map[.KEY_1] = .KEY_1;
    key_map[.KEY_2] = .KEY_2;
    key_map[.KEY_3] = .KEY_3;
    key_map[.KEY_4] = .KEY_4;
    key_map[.KEY_5] = .KEY_5;
    key_map[.KEY_6] = .KEY_6;
    key_map[.KEY_7] = .KEY_7;
    key_map[.KEY_8] = .KEY_8;
    key_map[.KEY_9] = .KEY_9;
    key_map[.KEY_0] = .KEY_0;

    key_map[.KEY_F1] = .F1;
    key_map[.KEY_F2] = .F2;
    key_map[.KEY_F3] = .F3;
    key_map[.KEY_F4] = .F4;
    key_map[.KEY_F5] = .F5;
    key_map[.KEY_F6] = .F6;
    key_map[.KEY_F7] = .F7;
    key_map[.KEY_F8] = .F8;
    key_map[.KEY_F9] = .F9;
    key_map[.KEY_F10] = .F10;
    key_map[.KEY_F11] = .F11;
    key_map[.KEY_F12] = .F12;

    key_map[.KEY_APOSTROPHE]    = .APOSTROPHE;
    key_map[.KEY_COMMA]         = .COMMA;
    key_map[.KEY_MINUS]         = .MINUS;
    key_map[.KEY_PERIOD]        = .PERIOD;
    key_map[.KEY_SLASH]         = .SLASH;
    key_map[.KEY_SEMICOLON]     = .SEMICOLON;
    key_map[.KEY_EQUAL]         = .EQUAL;
    key_map[.KEY_BACKSLASH]     = .BACKSLASH;
    key_map[.KEY_LEFT_BRACKET]  = .LEFT_BRACKET;
    key_map[.KEY_RIGHT_BRACKET] = .RIGHT_BRACKET;
    key_map[.KEY_GRAVE_ACCENT]  = .GRAVE_ACCENT;
    key_map[.KEY_HOME]          = .HOME;
    key_map[.KEY_END]           = .END;

    key_map[.KEY_KP_0] = .KP_0;
    key_map[.KEY_KP_1] = .KP_1;
    key_map[.KEY_KP_2] = .KP_2;
    key_map[.KEY_KP_3] = .KP_3;
    key_map[.KEY_KP_4] = .KP_4;

    key_map[.KEY_KP_5] = .KP_5;
    key_map[.KEY_KP_6] = .KP_6;
    key_map[.KEY_KP_7] = .KP_7;
    key_map[.KEY_KP_8] = .KP_8;
    key_map[.KEY_KP_9] = .KP_9;

    key_map[.KEY_KP_DIVIDE]   = .KP_DIVIDE;
    key_map[.KEY_KP_MULTIPLY] = .KP_MULTIPLY;
    key_map[.KEY_KP_SUBTRACT] = .KP_SUBTRACT;

    key_map[.KEY_KP_ADD]      = .KP_ADD;
    key_map[.KEY_KP_ENTER]    = .KP_ENTER;
    key_map[.KEY_KP_DECIMAL]  = .KP_DECIMAL;

    key_map[.KEY_ESCAPE]        = .ESC;
    key_map[.KEY_SPACE]         = .SPACE;
    key_map[.KEY_TAB]           = .TAB;
    key_map[.KEY_KP_ENTER]      = .ENTER;
    key_map[.KEY_ENTER]         = .ENTER;
    key_map[.KEY_BACKSPACE]     = .BACKSPACE;
    key_map[.KEY_DELETE]        = .DELETE;

    key_map[.KEY_LEFT_CONTROL]  = .LEFT_CTRL;
    key_map[.KEY_LEFT_CONTROL]  = .LEFT_CTRL;
    key_map[.KEY_LEFT_SHIFT]    = .LEFT_SHIFT;
    key_map[.KEY_LEFT_ALT]      = .LEFT_ALT;
    key_map[.KEY_LEFT_SUPER]    = .LEFT_SUPER;
    key_map[.KEY_RIGHT_CONTROL] = .RIGHT_CTRL;
    key_map[.KEY_RIGHT_SHIFT]   = .RIGHT_SHIFT;
    key_map[.KEY_RIGHT_ALT]     = .RIGHT_ALT;
    key_map[.KEY_RIGHT_SUPER]   = .RIGHT_SUPER;

    key_map[.KEY_RIGHT] = .RIGHT;
    key_map[.KEY_UP]    = .UP;
    key_map[.KEY_LEFT]  = .LEFT;
    key_map[.KEY_DOWN]  = .DOWN;

}