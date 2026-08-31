// A WALL CROWDING THE LENS, drawn as an instrument reading instead of as a wall.
//
// One shader, worn by two materials over the same geometry, told apart by `holo_dial.y`:
//
//   * the SOLID one throws the band away and draws the rest exactly as bevy would, so a level
//     outside the band is pixel-for-pixel the level that shipped;
//   * the FILM draws only the band, and lerps -- from the surface's own lit colour at full
//     opacity where the band begins, to flat instrument blue at [`HOLO_ALPHA`] where it is fully
//     open.
//
// The lerp is what makes the seam invisible, and it is the whole reason the film shades through
// the standard PBR path rather than being a flat blue decal. At the band's edge the film IS the
// surface -- same albedo, same lights, same tonemapping -- so the two materials meet at a value
// they agree on, and the wall dissolves rather than switching. A flat blue that faded in from
// zero would put a hard step at the boundary in every channel but alpha.

#import bevy_pbr::{
    pbr_fragment::pbr_input_from_standard_material,
    pbr_functions::{alpha_discard, apply_pbr_lighting, main_pass_post_lighting_processing},
    forward_io::{VertexOutput, FragmentOutput},
}
#import near_hologram::band::{near_band, is_film}

// The instrument blue, linear. The hue `ghost.wgsl` paints the pilot's occluded silhouette in and
// `unknown_contact.wgsl` paints a sensor guess in: the client's one colour for "this is a reading,
// not a thing". Sharing it is the point -- a deck where the wall you can see through and the body
// you can see through it are the same blue reads as one instrument, not two effects.
const HOLO: vec3<f32> = vec3<f32>(0.42, 0.68, 0.95);

// How opaque the film is once the band is fully open.
//
// A LOOK constant, in the sense `ghost`'s colour and `fog_mask`'s radii are: the same number on
// every level by construction, because this pass knows nothing about levels. Low enough that the
// deck, the crates and the pilot behind the wall are all plainly readable through it; high enough
// that the wall is still a surface standing there rather than a hole in the station.
const HOLO_ALPHA: f32 = 0.12;

@fragment
fn fragment(in: VertexOutput, @builtin(front_facing) is_front: bool) -> FragmentOutput {
    let band = near_band(in.world_position);
    // Each material draws exactly what the other throws away, so the two together are the level
    // and neither can double up.
    if is_film() {
        if band <= 0.0 {
            discard;
        }
    } else if band > 0.0 {
        discard;
    }

    // Everything below here is bevy's own forward path, unchanged, so a surface outside the band
    // is shaded by the shader that would have shaded it.
    var pbr_input = pbr_input_from_standard_material(in, is_front);
    pbr_input.material.base_color =
        alpha_discard(pbr_input.material, pbr_input.material.base_color);
    let lit = apply_pbr_lighting(pbr_input);

    var out: FragmentOutput;
    out.color = vec4<f32>(mix(lit.rgb, HOLO, band), lit.a);
    // Fog, tonemapping and debanding BEFORE the alpha is set, and in that order for a reason: the
    // solid material's pixels go through this same call, so anything applied after it would be a
    // difference between the two sides of the seam.
    out.color = main_pass_post_lighting_processing(pbr_input, out.color);
    // From the SURFACE'S OWN alpha, not from 1.0, and never past it. A level ships blended glass as
    // well as opaque plate; starting the lerp at 1.0 would make a pane jump to fully opaque exactly
    // where the film meets the solid material, which is the one place the two have to agree. `min`
    // is the other half: a pane already thinner than the film must not be thickened by it.
    out.color.a = mix(lit.a, min(lit.a, HOLO_ALPHA), band);
    return out;
}
