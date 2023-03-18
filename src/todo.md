# TODO

~~1. Make vertex buffer update able. Just create large buffer for now, maybe later make it so that you can create larger buffer if current one is filled up, later tho, later.~~

~~2. Make some sort of abstraction, we should be able to call `drawRect(x, y, width, height)` or something for some time and it should draw those rects.~~

3. Move the rendering API to it own file.
    ~~1. Clear up the buffer after a frame is finished, so that if rect if drawn when a button is pressed, it should only render when button is pressed.~~
    2. Add some `setColor(R<Int>, G<Int>, B<Int>)` function for setting color. Whatever rendered after setting color should use that color.

4. Add Triangles.

5. Add Textures.

6. Add Texts.

Ofc, we build up batch system while we complete above.