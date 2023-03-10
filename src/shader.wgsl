struct VertexOut{
    @builtin(position) position: vec4<f32>,
    @location(0) color: vec4<f32>,
}

@vertex 
fn vert_main(@location(0) position : vec4<f32>, @location(1) color: vec4<f32>) -> VertexOut{
    var output: VertexOut;
    output.position = position;
    output.color = color;
    return output;
}

@fragment 
fn frag_main(@location(0) color: vec4<f32>) -> @location(0) vec4<f32> {
    return color;
}