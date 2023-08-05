# TODO

1. Some assest managment system.
    - For now, just load some pngs and some function that spit out texture buffer.
2. Figure out how should texture, texture batching should work and how will user specific which texture to draw with draw__Image() functions (api).
    - For now, we just draw whatever is given parameter to draw__Image(some_texture)
3. Add transformation (rotate, scale and translate)
4. Add Texts.


## Not now, but something to look at
- Move vertex position calculation to gpu.
- Do CPU side calculation using SIMD.
- Some sort of ECS/DOD type renderer?

Ofc, we build up batch system while we complete above.