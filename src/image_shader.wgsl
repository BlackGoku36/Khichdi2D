struct VertexOut{
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
    @location(1) col: vec4<f32>,
}

@vertex 
fn vert_main(@location(0) position : vec4<f32>, @location(1) uv: vec2<f32>, @location(2) col: vec4<f32>) -> VertexOut{
    var output: VertexOut;
    output.position = position;
    output.uv = uv;
    output.col = col;
    return output;
}

@group(0) @binding(0) var texture_sampler: sampler;
@group(0) @binding(1) var texture: texture_2d<f32>;

@fragment 
fn frag_main(@location(0) uv: vec2<f32>, @location(1) col: vec4<f32>) -> @location(0) vec4<f32> {
    return textureSample(texture, texture_sampler, uv) * col;
}