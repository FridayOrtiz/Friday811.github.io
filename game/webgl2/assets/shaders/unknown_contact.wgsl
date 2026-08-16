// A contact nobody has identified: the sensor suite's GUESS at what is out there, drawn as a
// guess.
//
// The client is not told what an unidentified hull is. It is told how big the return is, and it
// picks the modelled hull nearest that size (`ship_art::guess_for`) — so the shape on screen is
// plausible and quite possibly wrong. That is a lie unless the picture says so, and this is what
// says so: the hull arrives as a cold reconstruction rather than as a ship somebody painted.
//
// Three things do the talking, and each answers a different way the plain material lied:
//
//   1. **No paint.** The pack's albedo is thrown away and replaced with one flat instrument
//      colour. A Reaver's black and a Halcyon's grey are the yards' own liveries, and wearing one
//      would claim exactly the thing that has not been established.
//   2. **A fresnel rim.** The edges light and the faces stay dim, which is what a reconstruction
//      looks like everywhere it has ever been drawn — the silhouette is what the return actually
//      resolved, and the middle is filled in by inference.
//   3. **Scan bands.** Slow horizontal courses in the hull's own frame, so the surface reads as
//      swept rather than lit. In the HULL's frame on purpose: banded in world space they would
//      slide along a ship that is holding station, which reads as the ship moving.
//
// It is deliberately NOT transparent. A see-through contact reads as a phantom the guns will pass
// through, and this thing is solid, dangerous and about to shoot at somebody.

#import bevy_pbr::{
    pbr_fragment::pbr_input_from_standard_material,
    pbr_functions::{alpha_discard, apply_pbr_lighting, main_pass_post_lighting_processing},
    forward_io::{VertexOutput, FragmentOutput},
    mesh_view_bindings::{view, globals},
}

// The instrument's own colour, and the one every unidentified contact is drawn in. A cold
// desaturated blue-grey: it belongs to no yard's livery (`hulls::Yard::plate` runs warm greys and
// off-whites) and it matches the neutral the contact list already paints an unidentified role in
// (`draw::contact_color`'s fallback grey), so the roster and the sky agree about which one this is.
const COLD: vec3<f32> = vec3<f32>(0.26, 0.34, 0.46);

// How hard the rim lights, and how sharply it falls off the silhouette. The exponent is what makes
// it a rim rather than a wash: at 1.0 the whole hull glows and the shape stops reading.
const RIM_GAIN: f32 = 1.05;
const RIM_FALLOFF: f32 = 2.6;

// How much of the lit result survives, against the flat instrument colour. Some real lighting is
// kept so the hull still has a form a pilot can read the orientation off; too much and it is
// simply a grey ship.
const LIT_MIX: f32 = 0.18;

// Scan bands: how many courses across the hull's own length, how deep they cut, and how fast they
// travel. Slow on purpose. A fast sweep reads as a warning light, and this is not an alarm, it is
// the sensor working.
const BAND_COURSES: f32 = 18.0;
const BAND_DEPTH: f32 = 0.10;
const BAND_SPEED: f32 = 0.35;

@fragment
fn fragment(in: VertexOutput, @builtin(front_facing) is_front: bool) -> FragmentOutput {
    // The standard input, so the geometry, the normals and the shadow work are bevy's own. What
    // this shader replaces is only what the surface LOOKS like.
    var pbr_input = pbr_input_from_standard_material(in, is_front);
    pbr_input.material.base_color =
        alpha_discard(pbr_input.material, pbr_input.material.base_color);

    // Lit once, honestly, so the hull keeps a form a pilot can read an attitude off...
    let lit = apply_pbr_lighting(pbr_input);

    // ...then almost all of it is thrown away for the instrument colour. `lit` carries the pack's
    // own albedo, which is the one thing that must not survive: a reconstruction wearing a yard's
    // paint claims a manufacturer nobody has read off this contact.
    let to_eye = normalize(view.world_position.xyz - in.world_position.xyz);
    let shade = clamp(dot(normalize(pbr_input.world_normal), to_eye), 0.0, 1.0);
    var col = mix(COLD * (0.35 + 0.65 * shade), lit.rgb, LIT_MIX);

    // The rim: bright where the surface turns away from the eye, which is the silhouette.
    let rim = pow(1.0 - shade, RIM_FALLOFF) * RIM_GAIN;
    col += COLD * rim;

    // Scan bands along the hull. Off the world position rather than the pack's uv, which is an
    // atlas and lays out nothing in particular, and drifting on the clock so the surface reads as
    // swept rather than painted.
    let band = sin((in.world_position.z + globals.time * BAND_SPEED) * BAND_COURSES);
    col *= 1.0 - BAND_DEPTH * (0.5 + 0.5 * band);

    var out: FragmentOutput;
    out.color = vec4<f32>(col, 1.0);
    out.color = main_pass_post_lighting_processing(pbr_input, out.color);
    return out;
}
