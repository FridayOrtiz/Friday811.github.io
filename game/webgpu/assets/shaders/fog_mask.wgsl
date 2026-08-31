// THE VISIBILITY MASK: the deck's finished picture, multiplied down by how far each pixel is
// from the pilot.
//
// Not a light. A light shades by surface angle and by inverse square, so it rims whatever it
// stands near and blows out whatever stands close to it; this pass never touches shading at all.
// It reads the composed frame, works out WHERE IN THE WORLD each pixel is, and multiplies by one
// number that depends on nothing but distance. Two surfaces the same distance from the pilot come
// out equally dimmed however they are turned, and a body dims exactly as the floor it stands on
// does -- which is the whole point, and the thing a light cannot do.
//
// The distance is WORLD distance from the pilot, reconstructed per pixel: the scenery camera's
// depth (which by the time this runs holds scenery AND the bodies the overlay pass drew into it)
// unprojected through `view.world_from_clip`. Not screen distance -- that would be a vignette,
// and a corridor running away from the camera would fade across its width instead of its length.
// Not distance from the CAMERA -- that is what `DistanceFog` already does, and an orthographic
// lens sixty metres up the diagonal makes it very nearly a constant.
//
// Both textures are read with `textureLoad`: no sampler, no filtering, nothing WebGL2 has to be
// asked twice for. The colour is 1:1 with the destination, and the depth is an unfilterable float
// -- GLES will not sample a depth texture any other way (see `ghost.wgsl`, which pays the same
// price for the same texture).

#import bevy_render::view::View
#import bevy_core_pipeline::fullscreen_vertex_shader::FullscreenVertexOutput

struct DeckFog {
    // xyz: the world point the fade is measured from -- the pilot, at chest height. w unused.
    pilot: vec4<f32>,
    // x: the radius held at full brightness. y: the radius the floor is reached at. zw unused.
    curve: vec4<f32>,
    // rgb: what the picture is multiplied by at `curve.y` and beyond. a unused.
    floor: vec4<f32>,
}

@group(0) @binding(0) var<uniform> view: View;
@group(0) @binding(1) var source: texture_2d<f32>;
@group(0) @binding(2) var scenery_depth: texture_2d<f32>;
@group(0) @binding(3) var<uniform> fog: DeckFog;
// The depth's sampler: NEAREST, no comparison, and the only reason the depth reads at all on
// WebGL2 -- `ghost::scenery_depth_sampler` has the story. Last, so the numbering above held.
@group(0) @binding(4) var scenery_sampler: sampler;

fn texel_at(dims: vec2<u32>, uv: vec2<f32>) -> vec2<u32> {
    // Scaled through the texture's own size rather than taken as raw pixels: the colour target and
    // the scenery depth are the same size in steady state and one frame apart on a resize, and a
    // mask that is a few texels stale for one frame is nothing while a load out of bounds is not.
    return min(vec2<u32>(uv * vec2<f32>(dims)), dims - vec2(1u));
}

@fragment
fn fragment(in: FullscreenVertexOutput) -> @location(0) vec4<f32> {
    let colour = textureLoad(source, texel_at(textureDimensions(source), in.uv), 0);
    // Through the sampler, not a `textureLoad`: a depth texture with no sampler bound is
    // INCOMPLETE under GLES and reads 0.0 for ever, which this pass would take for the void past
    // the deck and answer by flooring the whole picture. NEAREST, so the value is the texel's.
    let depth = textureSampleLevel(scenery_depth, scenery_sampler, in.uv, 0.0).x;

    // How far past the pilot this pixel is, in metres. Reverse-Z: the clear is 0.0, which is the
    // far plane -- and past the level's last wall there is nothing to unproject, so that case is
    // answered directly rather than by reconstructing a point on the far plane. It is the void
    // beyond the deck, which is as far away as anything gets.
    var t = 1.0;
    if depth > 0.0 {
        let ndc = vec3<f32>(in.uv.x * 2.0 - 1.0, 1.0 - in.uv.y * 2.0, depth);
        let homogeneous = view.world_from_clip * vec4<f32>(ndc, 1.0);
        let world = homogeneous.xyz / homogeneous.w;
        t = smoothstep(fog.curve.x, fog.curve.y, distance(world, fog.pilot.xyz));
    }

    // The curve is ours, not physics: flat out to the near radius, eased down to the floor by the
    // far one. The floor is not black on purpose -- the deck has to go on reading as station
    // carrying on into the dark rather than as a hole cut in the picture.
    let veil = mix(vec3<f32>(1.0), fog.floor.rgb, t);
    return vec4<f32>(colour.rgb * veil, colour.a);
}
