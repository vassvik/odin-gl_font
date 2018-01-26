# odin-font

Work-in-progress font rendering library in Odin. The one and only dependency is OpenGL 4.3.

The file `font.odin` is the old file, and is deprecated. Consider using `font_opengl.odin` (see test_font_opengl.odin for an example), or use `font_base.odin` directly and setup your own renderer. 

The `font_base.odin` file is relies on `stb_truetype` from [https://github.com/vassvik/odin-stb](https://github.com/vassvik/odin-stb/), while `font_opengl.odin` relies on [https://github.com/vassvik/odin-gl/](https://github.com/vassvik/odin-gl/), and `test_font_opengl.odin` also relies on [https://github.com/vassvik/odin-glfw/](https://github.com/vassvik/odin-glfw/).

#### NOTE: It is recommended to put this into the shared collection:
```
cd Odin/shared
git clone https://github.com/vassvik/odin-gl_font.git
```
