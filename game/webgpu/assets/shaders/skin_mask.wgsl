// Hide the skin a worn garment covers, per PIXEL, instead of cutting it out of the mesh.
//
// Each mask is written by `tools/fab-pipeline/mh_gameready.py`, one PER GARMENT, over two tiles of
// the character's UV atlas -- the face's then the body's. The client binds the map of whatever is
// worn in each slot, so a second shirt is a second file rather than a channel to find room for:
// which garment hides a texel is a wardrobe choice, and no texture baked per BODY can state it.
//
// This is what the engine the outfit came from does. Cutting the same decision into geometry is
// what forced `COVER_ERODE` -- a triangle boundary has to be pulled back under the cloth, which
// leaves a rim of skin, which is what came through the trousers in a stride.

#import bevy_pbr::{
    pbr_fragment::pbr_input_from_standard_material,
    forward_io::{VertexOutput, FragmentOutput},
    pbr_functions::{apply_pbr_lighting, main_pass_post_lighting_processing},
}

@group(#{MATERIAL_BIND_GROUP}) @binding(100) var<uniform> worn: vec4<f32>;
@group(#{MATERIAL_BIND_GROUP}) @binding(101) var body_texture: texture_2d<f32>;
@group(#{MATERIAL_BIND_GROUP}) @binding(102) var body_sampler: sampler;
@group(#{MATERIAL_BIND_GROUP}) @binding(103) var legs_texture: texture_2d<f32>;
@group(#{MATERIAL_BIND_GROUP}) @binding(104) var legs_sampler: sampler;
@group(#{MATERIAL_BIND_GROUP}) @binding(105) var feet_texture: texture_2d<f32>;
@group(#{MATERIAL_BIND_GROUP}) @binding(106) var feet_sampler: sampler;

@fragment
fn fragment(in: VertexOutput, @builtin(front_facing) is_front: bool) -> FragmentOutput {
    // `VertexOutput::uv` only EXISTS behind this def, so reading it unguarded makes the shader
    // fail to compile for any mesh without UVs -- at pipeline creation, on the machine drawing
    // the pilot, not at build time. Every skin mesh has them; the guard is what stops a mesh that
    // does not from taking the whole body's pipeline down with it. Without UVs there is no mask
    // to read, so it simply draws, which is what a body with no mask beside it should do.
#ifdef VERTEX_UVS_A
    // HALVED, not folded. The MetaHuman atlas puts the face's tile at u < 1 and the body's at u in
    // [1, 2], and the mask is baked TWO TILES WIDE to match -- face on the left, body on the
    // right -- so `u * 0.5` lands each mesh on its own half.
    //
    // It used to fold the body's tile down onto the face's, which meant the face could never be
    // masked: its texels landed on the body's coverage, and a pilot's cheeks came off in the
    // shape of somebody's arms. So the face was left drawn whatever was worn, and its YOKE -- the
    // sheet of skin over the clavicles that fills the hole in the body mesh -- came through the
    // jacket's shoulder. Both halves are addressable now and both are masked.
    //
    // Sampled, not fetched: the boundary wants the filtering, since that is the whole point of
    // moving it off the triangle edges.
    let spot = vec2(in.uv.x * 0.5, in.uv.y);
    // One map per WORN SLOT, each belonging to the garment actually in it, unioned -- the same
    // thing `GeometryRemoval::TryCombineHiddenFaceMaps` does in the engine these outfits come
    // from. Red channel: the maps are greyscale.
    //
    // `worn` is what says a slot has a real map. An unbound texture falls back to bevy's WHITE
    // image, which reads as covered, so an ungated sample would undress a pilot down to nothing.
    let covered = vec3(
        textureSample(body_texture, body_sampler, spot).r,
        textureSample(legs_texture, legs_sampler, spot).r,
        textureSample(feet_texture, feet_sampler, spot).r,
    );
    if dot(covered, worn.xyz) > 0.5 {
        discard;
    }
#endif
    var pbr_input = pbr_input_from_standard_material(in, is_front);
    var out: FragmentOutput;
    out.color = apply_pbr_lighting(pbr_input);
    out.color = main_pass_post_lighting_processing(pbr_input, out.color);
    return out;
}
