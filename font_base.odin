package font_gl

import "core:fmt";
import "core:math";
import "core:os";
import "core:strings";

import "shared:odin-stb/stbtt";
import "shared:odin-stb/stbi";


Glyph_Metric :: stbtt.Packed_Char;

Size_Metric :: struct {
	size: f32,
	ascent, descent, linegap: f32,
}

Font :: struct {
	identifier: string,

	codepoints_are_sorted: bool,
	codepoints_are_dense: bool,
	codepoints: []rune,

	glyph_metrics: []Glyph_Metric,
	size_metrics: []Size_Metric,

	width, height: int,
	bitmap: []byte,

	oversample: [2]int,
}

destroy :: proc(using font: Font) {
	if identifier != "" do delete(identifier);
	if codepoints != nil do delete(codepoints);
	if glyph_metrics != nil do delete(glyph_metrics);
	if size_metrics != nil do delete(size_metrics);
	if bitmap != nil do delete(bitmap);
}

init_from_ttf :: proc(ttf_name, identifier: string, oversample: [2]int, sizes: []int, codepoints: []rune, width := 2048) -> (Font, bool) {
	using stbtt;

	// check input
	if ttf_name == "" {
		fmt.println("Error: No font file provided.");
		return Font{}, false;
	}

	if codepoints == nil {
		fmt.println("Error: No Unicode codepoints provided.");
		return Font{}, false;
	}

	if sizes == nil {
		fmt.println("Error: No font sizes provided.");
		return Font{}, false;
	}

	if oversample[0] <= 0 || oversample[1] <= 0 {
		fmt.printf("Error: Invalid oversampling '%v' provided.\n", oversample);
		return Font{}, false;
	}

	for size, i in sizes {
		if size <= 0 {
			fmt.printf("Error: Invalid size '%d' at index '%d' detected.\n", size, i);
			return Font{}, false;		
		}
	}

	for codepoint, i in codepoints {
		if codepoint <= 0 {
			fmt.printf("Error: Invalid codepoint '%c' = %d at index '%d' detected.\n", codepoint, codepoint, i);
			return Font{}, false;		
		}
	}

	// grab the data from the ttf file
	ttf_data, ttf_success := os.read_entire_file(ttf_name);
	if !ttf_success {
		fmt.println("Error: could not read font file.");
		return Font{}, false;
	}
	defer delete(ttf_data);

	// Calculate the maximum number of pixels used, 
	// assuming all glyphs are squares and equal to the font size in pixels.
	// This *will* overestimate the pixel count by *a lot*, 
	// so we will not bother counting the padding
	total_size := 0;
	for size, i in sizes {
		total_size += size*size;
	}
	total_size *= oversample[0]*oversample[1]*len(codepoints);

	// By the end we will crop the bitmap and copy it to a new bitmap
	// to preserve storage space.
	height := total_size / width;

	// make a temporary raster bitmap to be used by stb_truetype
	bitmap_raster := make([]byte, width*height);
	defer delete(bitmap_raster);

	// pre-allocate glyph metric storage
	glyph_metrics := make([]Glyph_Metric, len(sizes)*len(codepoints));

	// setup the pack ranges
	pack_ranges := make([]Pack_Range, len(sizes));
	for _, i in sizes {
		pack_ranges[i] = Pack_Range{f32(sizes[i]), 0, cast(^i32)&codepoints[0], i32(len(codepoints)), &glyph_metrics[i*len(codepoints)+0],  0, 0};
	}

	// do the actual packing of the glyphs
	pc, success_pack := pack_begin(bitmap_raster, width, height, 0, 1);   
	pack_set_oversampling(&pc, oversample[0], oversample[1]); 
	pack_font_ranges(&pc, ttf_data, 0, pack_ranges);
	pack_end(&pc);

	// get global font metrics for each size
	size_metrics := make([]Size_Metric, len(sizes));

	info: Font_Info;
	init_font(&info, ttf_data, get_font_offset_for_index(ttf_data, 0));
	for _, i in sizes {
		using size_metric := &size_metrics[i];

		scale := scale_for_pixel_height(&info, f32(sizes[i]));
		a, d, l := get_font_v_metrics(&info);
		
		ascent  = f32(a)*scale;
		descent = f32(d)*scale;
		linegap = f32(l)*scale;
		size = f32(sizes[i]);
	};

	// get the tight bounds of the bitmap
	max_y := 0;
	for _, i in sizes {
		for _, j in codepoints {
			max_y = max(max_y, int(glyph_metrics[i*len(codepoints)+j].y1));
		}
	}
	max_y += 1;

	// make Font object. we'll make copies of the input sizes and codepoints
	font: Font;
	font.width = width;
	font.height = max_y;
	font.glyph_metrics = glyph_metrics;
	font.size_metrics = size_metrics;
	font.oversample = oversample;
	
	// copy the identifier name
	font.identifier = strings.clone(identifier);

	// make a copy of the unicode codepoints
	// also check if the codepoints are sorted
	font.codepoints = make([]rune, len(codepoints));
	font.codepoints_are_sorted = true;
	font.codepoints_are_dense = true;
	for _, i in codepoints {
		font.codepoints[i] = codepoints[i];
		if i > 0 && codepoints[i] < codepoints[i-1] do font.codepoints_are_sorted = false;
		if i > 0 && codepoints[i] != codepoints[i-1] + 1 do font.codepoints_are_dense = false;
	}

	// make a copy of the bitmap, but truncate it
	font.bitmap = make([]byte, width*max_y);
	for k in 0..width*max_y-1 do font.bitmap[k] = bitmap_raster[k];

	return font, true;
}


// Helpers
Vec4 :: [4]f32;

Glyph_Instance :: struct {
    x, y: u16,
    index, palette: u16,
};

// 11.5 fixed function helpers, usefull for rendering in shaders while packing vertex data
float_to_fixed :: proc(val: f32) -> u16 {
	return u16(32.0*val + 0.5);
}

fixed_to_float :: proc(val: u16) -> f32 {
	return f32(val/32.0);
}

bisect :: proc(data: []rune, value: rune) -> int {
	start := 0;
	stop := len(data)-1;
	
	// test for invalid data
	if len(data) == 0 do return -1;
	if value < data[start] do return -1;      // out of bounds
	if value > data[stop] do return -1;       // out of bounds
	if data[stop] < data[start] do return -1; // definitely not sorted

	// special cases
	if value == data[start] do return start;
	if value == data[stop] do return stop;

	// iterate
	for start <= stop {
		mid := (start + stop)/2;
		if value == data[mid] {
			return mid;
		} else if value < data[mid] {
			stop = mid - 1;
		} else {
			start = mid + 1;
		}
	}

	// not found
	return -1;
}

// routines for parsing a string, returning data that can be used for 
// returns the number of drawn glyphs (ignoring newlines), and the size of the bounding box of the string
parse_string_allocate :: proc(using font: ^Font, str: string, ask_size: int, palette: []u16) -> ([]Glyph_Instance, int, f32, f32) {
	instances := make([]Glyph_Instance, len(str));
	num, dx, dy := parse_string_provided(font, str, ask_size, palette, instances);
	return instances, num, dx, dy;
}

parse_string_noallocate :: proc(using font: ^Font, str: string, ask_size: int, palette: []u16) -> (int, f32, f32) {
	num, dx, dy := parse_string_provided(font, str, ask_size, palette, nil);
	return num, dx, dy;
}

parse_string_provided :: proc(using font: ^Font, str: string, ask_size: int, palette: []u16, instances: []Glyph_Instance) -> (int, f32, f32) {
	// see if we can find the requested font size
	idx := -1;
	for _, i in font.size_metrics {
		if int(font.size_metrics[i].size+0.5) == ask_size {
			idx = i;
			break;
		}
	}
	if idx == -1 do return -1, 0.0, 0.0;
	
	if len(palette) > 1 && len(str) != len(palette) do return -1, 0.0, 0.0;

	using m := &font.size_metrics[idx];

	// step through the string, and advance the cursor
	cursor_x := f32(0.0);
    cursor_y := f32(int(ascent)); // assume Y increase downwards, which means that the cursor does not start at the top of the bounding box
    max_cursor_x := cursor_x;

    num := 0;
    for c, i in str {
        if c == '\n' {
            cursor_x  = 0.0;
            cursor_y += ascent - descent + linegap;
            max_cursor_x = max(max_cursor_x, cursor_x);
            continue;
        }

        if instances != nil do instances[num].x = float_to_fixed(cursor_x);
        if instances != nil do instances[num].y = float_to_fixed(cursor_y);
        if instances != nil do instances[num].palette = palette == nil ? 0 : len(palette) == 1 ? palette[0] : palette[i];

        index := -1;
        if codepoints_are_dense {
        	if int(c - codepoints[0]) >= 0 && int(c - codepoints[0]) < len(codepoints) {
        		index = idx*len(codepoints) + int(c - codepoints[0]);
        	}
        } else if codepoints_are_sorted {
        	// bisection
        	if i := bisect(codepoints, c); i != -1 {
        		index = idx*len(codepoints) + i;
        	}
        } else {
        	// linear search
        	for C, i in codepoints {
        		if C == c {
        			index = idx*len(codepoints) + i;
        			break;
        		}
        	}
        }
        if index == -1 do break;
        if instances != nil do instances[num].index = u16(index);

        //cursor_x += cast(f32)int(glyph_metrics[index].xadvance);
        //cursor_x += glyph_metrics[index].xadvance;
        cursor_x += glyph_metrics[index].xadvance; 
        //fmt.println(num, cursor_y);
        num += 1;
    }

    max_cursor_x = max(max_cursor_x, cursor_x);
    //if cursor_x > 0.0 do cursor_y += size;
    cursor_y += -descent + linegap;


    return num, max_cursor_x, cursor_y;
}

parse_string :: proc{parse_string_provided, parse_string_allocate};


save_as_png :: proc(using font: ^Font) {
	// output the bitmap to a file, where each font size is coloured differently
	color_image := make([]u8, 3*width*height);
	defer delete(color_image);

	// color each size differently:
	for _, i in size_metrics {
		R := 0.5 + 0.5*math.cos(2.0*f64(i));
		G := 0.5 + 0.5*math.cos(3.0*f64(i));
		B := 0.5 + 0.5*math.cos(5.0*f64(i));
		for _, j in codepoints {
			using m := &glyph_metrics[i*len(codepoints)+j];
			for y in y0..y1 {
				for x in x0..x1 {
					id := int(y)*width + int(x);

					p := bitmap[id];
					color_image[3*id+0] = u8(R*f64(p));
					color_image[3*id+1] = u8(G*f64(p));
					color_image[3*id+2] = u8(B*f64(p));
				}
			}
		}
	}

	backing: [64]byte;
	output_filename := fmt.bprintf(backing[:], "%s.png", identifier);
	stbi.write_png(output_filename, width, height, 3, color_image, 0);
}

