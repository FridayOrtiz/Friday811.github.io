// Surface detail for a station, generated rather than sampled.
//
// A station is one texture atlas over a five-kilometre structure, which measures 0.09 to 0.20
// TEXELS PER METRE of hull (`tools/fab-pipeline/texel_density.py` reads it off the shipped glb).
// One texel per five to ten metres is why the plating goes soft the moment a pilot flies along a
// berth: the pack was authored to be seen whole, and no source texture fixes it — 4096 buys 33%,
// and a texel per 10 cm would want an atlas thirty thousand pixels wide.
//
// So the detail is computed from POSITION instead, at whatever density we ask for, and costs no
// texels at all. Triplanar, so it needs no second uv set and never stretches; procedural, so it
// needs no texture binding — which also keeps this inside WebGL2's sampler budget, the browser
// backend being the one that cannot afford another one.
//
// It is plating, not noise: courses of rectangular plates laid in running bond, each with its own
// roughness and its own slight tilt, with a groove at the seams — and three of those, each five
// times finer than the last, because a pilot sees a berth from four hundred metres and from forty
// and the same single frequency cannot serve both.
//
// Three things here are less obvious than they look, and all three shipped wrong once:
//
//   1. **Which frame the pattern lives in.** Not the world's — see the fragment entry.
//   2. **What happens when a plate falls under a pixel.** Not "draw it anyway" — see `plate_at`.
//   3. **Whether the seams line up.** They must not — see the running bond in `plate_at`.

#import bevy_pbr::{
    mesh_functions,
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

// How many scales of plating, how much finer each is than the one above it, and how much less it
// counts. Three because that is what covers the range a berth is actually looked at from: the
// coarse octave is the structure seen from a warp-in, the middle one is what a pilot flies along,
// and the fine one is what is left to look at while the clamps are closing. With one octave, a
// hull has exactly one interesting distance and is bare glass at every other.
const OCTAVES: i32 = 3;
const OCTAVE_SPLIT: f32 = 5.0;
const OCTAVE_FALLOFF: f32 = 0.5;

// A plate is longer than it is wide, because rolled plate comes off the mill that way.
const PLATE_ASPECT: f32 = 2.5;

// How wide the groove between two plates is, as a fraction of the plate. A fraction rather than a
// width in metres so the fine octaves get fine grooves: a fixed 5 cm seam is a third of the way
// across a 16 cm plate, which is not a seam, it is a trench.
const SEAM_FRACTION: f32 = 0.012;

// How far the cell ids are allowed to wander before they wrap. `hash21` is fract-based, so it
// loses its decorrelation once its input runs into the thousands — and the fine octave of a
// kilometre of hull is tens of thousands of cells out. Wrapping repeats the pattern every 512
// plates, which at the coarsest octave is further than any station is long.
const HASH_WRAP: f32 = 512.0;

// A hash with no texture behind it. Two dimensions in, one out, stable for a given cell — so a
// plate keeps its own finish frame to frame and from every angle, which a per-pixel random would
// not.
fn hash21(p: vec2<f32>) -> f32 {
    let q = p - floor(p / HASH_WRAP) * HASH_WRAP;
    var h = fract(q * vec2<f32>(0.1031, 0.1030));
    h += dot(h, h.yx + 33.33);
    return fract((h.x + h.y) * h.x);
}

// The plating on one axis-aligned plane: how far into a seam this point is (0 in the middle of a
// plate, 1 in the groove) and the plate's own random numbers.
struct Plate {
    seam: f32,
    tilt: vec2<f32>,
    finish: f32,
}

/// One course of plating on one plane, at one scale.
///
/// `uv` is **metres in the hull's own frame** and `px_m` is how many of those metres a screen
/// pixel covers, handed in rather than measured here — `fwidth` has to be called in uniform
/// control flow, and the octave loop below is a loop.
fn plate_at(uv: vec2<f32>, plate_m: f32, px_m: f32) -> Plate {
    let cell = vec2<f32>(plate_m * PLATE_ASPECT, plate_m);
    // Running bond: each course is shifted along its own length by its own random fraction of a
    // plate, so no seam runs unbroken across the hull. This is the difference between plating and
    // graph paper, and it is the whole reason a berth used to read as a grid drawn over a shape
    // rather than a thing built out of parts. Every real hull, wall and pavement is laid this way.
    let course = floor(uv.y / cell.y);
    let g = vec2<f32>(uv.x / cell.x + hash21(vec2<f32>(course, 5.0)), uv.y / cell.y);
    let id = floor(g);
    let f = fract(g);
    // How far this point is from the nearest edge of its plate, in METRES, so a groove is a
    // physical width on both axes of a cell that is not square.
    let edge_m = min(min(f.x, 1.0 - f.x) * cell.x, min(f.y, 1.0 - f.y) * cell.y);
    // A groove is a fixed fraction of the plate, floored at about a pixel so the line is
    // anti-aliased rather than crawling.
    let half = max(plate_m * SEAM_FRACTION, px_m * 0.75);

    // Under about a pixel per plate there is no pattern left to draw, and the two obvious things
    // to do are both wrong: drawn sharp it aliases, and drawn with a seam wide enough to survive
    // it floods — `smoothstep(0, w, edge)` with `w` past half a cell reports SEAM EVERYWHERE, so
    // a berth at four kilometres was being uniformly darkened by nearly half and roughened with
    // it. Nobody spotted that, because a slightly dark station still looks like a station.
    //
    // So each octave converges on its own average instead: the fraction of the hull a groove
    // actually covers, which is a couple of percent. The tilt and the finish go the same way,
    // toward flat and toward the middle, which is what filtering a random field means.
    let blur = smoothstep(0.15, 0.5, px_m / min(cell.x, cell.y));
    let covered =
        1.0 - max(0.0, 1.0 - 2.0 * half / cell.x) * max(0.0, 1.0 - 2.0 * half / cell.y);

    var out: Plate;
    out.seam = mix(1.0 - smoothstep(0.0, half, edge_m), covered * 0.5, blur);
    // Which way this plate sits, a fraction of a degree off true. Enough to break a flat kilometre
    // of hull into panels the light catches differently.
    out.tilt = vec2<f32>(hash21(id) - 0.5, hash21(id + 37.0) - 0.5) * (1.0 - blur);
    out.finish = mix(hash21(id + 91.0) - 0.5, 0.0, blur);
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

    let n = normalize(pbr_input.N);

    // **The plating belongs to the hull, not to space.**
    //
    // This map has a floating origin: every transform in the sky is rewritten each frame as
    // `where it is - what the camera is looking at` (`system_map_3d::render_of`), and what the
    // camera looks at is the pilot. So a station's bevy world position changes whenever the pilot
    // moves, while the camera's own barely does — which means a pattern keyed on world position is
    // pinned to the CAMERA. Flying along a berth, the hull slid through a lattice that stood still
    // on screen. It looked like exactly what it was: a grid projected onto the station rather than
    // built into it. The belt learned this same lesson one level up — see the note on the rubble
    // in `sync_system_map`.
    //
    // So the pattern is worked out in the mesh's own frame: undo the model matrix's translation
    // and rotation, keep its scale, and the result is metres of hull, welded to the plate it is
    // supposed to be part of. It costs two matrix reads and survives the origin moving, the
    // station being anywhere, and anything that ever decides to turn one.
    let model = mesh_functions::get_world_from_local(in.instance_index);
    let axes = mat3x3<f32>(
        normalize(model[0].xyz),
        normalize(model[1].xyz),
        normalize(model[2].xyz),
    );
    let to_hull = transpose(axes);
    let hp = to_hull * (in.world_position.xyz - model[3].xyz);
    let hn = normalize(to_hull * n);

    // Triplanar weights: whichever way this bit of hull faces decides which plane's plating it
    // wears. Squared and normalised so the three never sum to more than themselves at a corner.
    var w = abs(hn);
    w = w * w;
    w = w / max(w.x + w.y + w.z, 1e-5);

    // The screen footprint of each plane's coordinates, measured once, outside the loop.
    let dx = max(fwidth(hp.y + hp.z), 1e-5);
    let dy = max(fwidth(hp.z + hp.x), 1e-5);
    let dz = max(fwidth(hp.x + hp.y), 1e-5);

    var seam = 0.0;
    var finish = 0.0;
    var tilt = vec3<f32>(0.0);
    var amp = 1.0;
    var total = 0.0;
    var size = plate_m;
    for (var i = 0; i < OCTAVES; i = i + 1) {
        let px = plate_at(hp.yz, size, dx);
        let py = plate_at(hp.zx, size, dy);
        let pz = plate_at(hp.xy, size, dz);
        seam += (px.seam * w.x + py.seam * w.y + pz.seam * w.z) * amp;
        finish += (px.finish * w.x + py.finish * w.y + pz.finish * w.z) * amp;
        // The tilt of each plate, taken back into the hull's axes: each plane contributes its own
        // two, which is what makes this a normal perturbation rather than a pattern painted on.
        tilt += (vec3<f32>(0.0, px.tilt.x, px.tilt.y) * w.x
            + vec3<f32>(py.tilt.y, 0.0, py.tilt.x) * w.y
            + vec3<f32>(pz.tilt.x, pz.tilt.y, 0.0) * w.z)
            * amp;
        total += amp;
        amp *= OCTAVE_FALLOFF;
        size /= OCTAVE_SPLIT;
    }
    seam /= total;
    finish /= total;
    tilt /= total;

    // A seam is a groove, so it pulls the normal toward the surface rather than tilting it: the
    // gradient of the seam field is not available cheaply, and a groove that merely darkens reads
    // correctly at every range a station is seen from. The tilt goes back into world space first —
    // it was worked out in the hull's axes along with everything else.
    let perturbed = normalize(n + (axes * tilt) * strength * 0.35);
    pbr_input.N = perturbed;
    pbr_input.world_normal = perturbed;

    // Plate to plate, the finish differs — the single roughness map over five kilometres is what
    // makes a hull read as one moulded object.
    let rough = pbr_input.material.perceptual_roughness
        + finish * finish_var
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
