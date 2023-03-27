# TODO

~~1. Make vertex buffer update able. Just create large buffer for now, maybe later make it so that you can create larger buffer if current one is filled up, later tho, later.~~

~~2. Make some sort of abstraction, we should be able to call `drawRect(x, y, width, height)` or something for some time and it should draw those rects.~~

~~3. Move the rendering API to it own file.
    1. Clear up the buffer after a frame is finished, so that if rect if drawn when a button is pressed, it should only render when button is pressed.
    2. Add some `setColor(R<Int>, G<Int>, B<Int>)` function for setting color. Whatever rendered after setting color should use that color.~~

~~4. Add Triangles.~~

~~5. Add Textures.
    1. Add basics texture rendering.
    2. Add functions like:
        - drawImage: parameter is x & y post and width/height should be image size.
        - drawScaledImage: parameter is x, y, width and height.
        - drawSubImage: parameter is x, y, x1, y1, width1, height1.
            - x1, y1, width1 and height1 are sub-image section area.
            - image width and height will be same as image size.
        - drawScaledSubImage: all parameters.
    3. Clean it up (naming, sizes, etc).
    4. Make up a main renderer (batch system) and expose all the draw functions from there (colored, images, etc).~~

6. Decide if setColor should effect textures or not.
7. Figure out how should texture, texture batching should work and how will user specific which texture to draw with draw__Image() functions (api).

8. Add Texts.

Ofc, we build up batch system while we complete above.