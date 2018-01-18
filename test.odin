import "core:fmt.odin";
import "core:os.odin";
import "core:math.odin";
import "core:strings.odin";

import "shared:odin-glfw/glfw.odin";
import "shared:odin-gl/gl.odin";

import stbtt "shared:odin-stb/stb_truetype.odin"
import stbi "shared:odin-stb/stb_image_write.odin";

using import "font_base.odin";


main :: proc() {
	sizes := [...]int{72, 68, 64, 60, 56, 52, 48, 44, 40, 36, 32, 28, 24, 20, 16, 12};
	codepoints: [95]rune;
	for i in 0..95 do codepoints[i] = rune(32+i);

	font, success := get_font_from_ttf("consola.ttf", "Consola", [2]int{1, 1}, sizes[...], codepoints[...]);
	save_as_png(&font);
}