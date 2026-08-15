// Surface detail for a station, generated rather than sampled.
//
// A station is one texture atlas over a five-kilometre structure, which measures 0.09 to 0.20
// TEXELS PER METRE of hull (`tools/fab-pipeline/texel_density.py` reads it off the shipped glb).
// One texel per five to ten metres is why the plating goes soft the moment a pilot flies along a
// berth: the pack was authored to be seen whole, and no source texture fixes it — 4096 buys 33%,
// and a texel per 10 cm would want an atlas thirty thousand pixels wide.
//
// So the detail is computed from the WORLD POSITION instead, at whatever density we ask for, and
// costs no texels at all. Triplanar, so it needs no second uv set and never stretches; procedural,
// so it needs no texture binding — which also keeps this inside WebGL2's sampler budget, the
// browser backend being the one that cannot afford another one.
//
// It is plating, not noise: a grid of plates a few metres across, each with its own roughness and
// its own slight tilt, with a bevel at the seams. That is the frequency a hull is missing.

#import bevy_pbr::{
    pbr_fragment::pbr_input_from_standard_material,
    pbr_functions::{alpha_discard, apply_pbr_lighting, main_pass_post_lighting_processing},
    pbr_types::STANDARD_MATERIAL_FLAGS_UNLIT_BIT,
    forward_io::{VertexOutput, FragmentOutput},
}

struct StationDetail {
    // x: metres across one plate, y: how hard the seams and tilts read,
    // z: how much the plate-to-plate roughness varies, w: unused.
    settings: vec4<f32>,
}

@group(#{MATERIAL_BIND_GROUP}) @binding(100)
var<uniform> detail: StationDetail;

// A hash with no texture behind it. Two dimensions in, one out, stable for a given cell — so a
// plate keeps its own finish frame to frame and from every angle, which a per-pixel random would
// not.
fn hash21(p: vec2<f32>) -> f32 {
    var h = fract(p * vec2<f32>(0.1031, 0.1030));
    h += dot(h, h.yx + 33.33);
    return fract((h.x + h.y) * h.x);
}

// The plating on one axis-aligned plane: how far into a seam this point is (0 at the middle of a
// plate, 1 in the groove) and the plate's own two random numbers.
struct Plate {
    seam: f32,
    tilt: vec2<f32>,
    finish: f32,
}

fn plate_at(uv: vec2<f32>, plate_m: f32) -> Plate {
    let g = uv / plate_m;
    let cell = floor(g);
    let f = fract(g);
    // Distance to the nearest edge of the cell, in cell units. `fwidth` keeps the seam a constant
    // width ON SCREEN rather than in metres, so it neither disappears at range nor swells into a
    // canyon up close.
    let edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
    let w = max(fwidth(g.x + g.y), 1e-5);
    var out: Plate;
    out.seam = 1.0 - smoothstep(0.0, w * 1.5, edge);
    // Which way this plate sits, a fraction of a degree off true. Enough to break a flat kilometre
    // of hull into panels the light catches differently.
    out.tilt = vec2<f32>(hash21(cell) - 0.5, hash21(cell + 37.0) - 0.5);
    out.finish = hash21(cell + 91.0);
    return out;
}

@fragment
fn fragment(in: VertexOutput, @builtin(front_facing) is_front: bool) -> FragmentOutput {
    var pbr_input = pbr_input_from_standard_material(in, is_front);
    pbr_input.material.base_color =
        alpha_discard(pbr_input.material, pbr_input.material.base_color);

    let plate_m = max(detail.settings.x, 0.01);
    let strength = detail.settings.y;
    let finish_var = detail.settings.z;

    let wp = in.world_position.xyz;
    let n = normalize(pbr_input.N);
    // Triplanar weights: whichever way this bit of hull faces decides which plane's plating it
    // wears. Squared and normalised so the three never sum to more than themselves at a corner.
    var w = abs(n);
    w = w * w;
    w = w / max(w.x + w.y + w.z, 1e-5);

    let px = plate_at(wp.yz, plate_m);
    let py = plate_at(wp.zx, plate_m);
    let pz = plate_at(wp.xy, plate_m);

    let seam = px.seam * w.x + py.seam * w.y + pz.seam * w.z;
    let finish = px.finish * w.x + py.finish * w.y + pz.finish * w.z;

    // The tilt of each plate, taken back into world space: each plane contributes its own two
    // axes, which is what makes this a normal perturbation rather than a pattern painted on.
    let tilt = vec3<f32>(0.0, px.tilt.x, px.tilt.y) * w.x
        + vec3<f32>(py.tilt.y, 0.0, py.tilt.x) * w.y
        + vec3<f32>(pz.tilt.x, pz.tilt.y, 0.0) * w.z;

    // A seam is a groove, so it pulls the normal toward the surface rather than tilting it: the
    // gradient of the seam field is not available cheaply, and a groove that merely darkens reads
    // correctly at every range a station is seen from.
    let perturbed = normalize(n + tilt * strength * 0.35);
    pbr_input.N = perturbed;
    pbr_input.world_normal = perturbed;

    // Plate to plate, the finish differs — the single roughness map over five kilometres is what
    // makes a hull read as one moulded object.
    let rough = pbr_input.material.perceptual_roughness
        + (finish - 0.5) * finish_var
        + seam * 0.25 * strength;
    pbr_input.material.perceptual_roughness = clamp(rough, 0.05, 1.0);
    // ...and a seam is a shadow line, which is the part that survives being a pixel wide.
    let shade = 1.0 - seam * 0.45 * strength;
    pbr_input.material.base_color = vec4<f32>(
        pbr_input.material.base_color.rgb * shade,
        pbr_input.material.base_color.a,
    );

    var out: FragmentOutput;
    if (pbr_input.material.flags & STANDARD_MATERIAL_FLAGS_UNLIT_BIT) == 0u {
        out.color = apply_pbr_lighting(pbr_input);
    } else {
        out.color = pbr_input.material.base_color;
    }
    out.color = main_pass_post_lighting_processing(pbr_input, out.color);
    return out;
}
