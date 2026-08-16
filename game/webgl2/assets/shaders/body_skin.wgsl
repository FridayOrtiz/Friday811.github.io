// What a world has that a shaded sphere does not: air around it, and grain on it.
//
// The CPU bake (`procgen::bodies`) draws a body's face into textures, and that is the right way to
// carry continents, bands and craters -- it is the same on every backend and it can be tested on a
// machine with no GPU. Two things it CANNOT carry, and both of them are why a world alongside you
// read as a beach ball:
//
//  - **Air.** A limb is not an edge. What separates a planet from a ball is that its edge is a band
//    of lit atmosphere and its terminator is a soft, warm gradient rather than a cosine falling off
//    a cliff. Every part of that depends on where the eye and the star are, so no texture can hold
//    it -- which is exactly why the design study's preview pictures had it and the shipped renderer
//    did not.
//  - **Grain.** The bake tops out at 512x256, and a body at the standoff fills the canopy, so a
//    texel lands about thirty pixels across. Magnified that far, bilinear filtering is smooth ramps
//    with hard kinks at the texel boundaries, and the generator's own coastline becomes a visibly
//    angular polyline. No bake size fixes it: even 4096x2048 is still magnified, and it costs
//    ninety seconds of a frame budget to make. Detail generated PER FRAGMENT has no resolution at
//    all, so it is the one thing here that stays sharp however close you get.
//
// Both are gated on `air.w` / `grain.w` being non-zero, and both are uniform-branched, so a chart
// full of specks pays nothing and only the world you are parked beside runs the expensive half.

#import bevy_pbr::{
    pbr_fragment::pbr_input_from_standard_material,
    forward_io::{VertexOutput, FragmentOutput},
    pbr_functions::{apply_pbr_lighting, main_pass_post_lighting_processing},
    pbr_types::STANDARD_MATERIAL_FLAGS_UNLIT_BIT,
}

struct BodyAir {
    /// rgb: what this body's air scatters. w: how much of it there is, 0 for a world with none.
    air: vec4<f32>,
    /// xyz: unit direction from this body toward its star, in render space. w: how hard the
    /// per-fragment grain pushes the normal around, 0 to switch it off.
    sun: vec4<f32>,
    /// x: grain frequency, in noise cells per radian of arc. y: the seed, as a float, because a
    /// uniform of mixed types is a struct nobody can lay out twice the same way. z: how much of a
    /// star's limb darkening to apply, 0 for anything that is not a star. w: spare.
    grain: vec4<f32>,
    /// x: crater lattice frequency, in cells per radian. y: how deeply they bite, fading in as the
    /// body gets close so they cross-fade with the baked ones rather than popping. zw: spare.
    pits: vec4<f32>,
}

@group(#{MATERIAL_BIND_GROUP}) @binding(100) var<uniform> body: BodyAir;

const TAU: f32 = 6.2831853;
const PI: f32 = 3.14159265;

/// How far apart the two grain samples are taken, IN NOISE CELLS.
///
/// Load-bearing that this is in cells and not in radians. The gradient below is divided by this
/// same number, so what comes out is a slope PER CELL -- a quantity of order one whatever the
/// frequency is. Divided by an offset in radians instead it came out of order `freq`, so the gain
/// beside it meant something different at every zoom and, at the frequency actually shipped, threw
/// the normal through more than forty-five degrees on every cell of the noise. That is what "it
/// just looks like random noise" was: not too much detail, one number out by a factor of the
/// frequency.
const GRAIN_STEP: f32 = 0.15;

/// The roughness a surface needs before it has any fine relief at all, and where it has all of it.
///
/// **Read off the roughness map the bake already wrote, rather than worked out again here.** Fine
/// relief and roughness are the same physical fact at two scales: chalk is rough because it is
/// pebbled all the way down, and open water is smooth because it is not. So the sea -- which the
/// bake marks at 0.22 -- gets none, ice and cloud at 0.62 get almost none, and land at 0.88 and
/// regolith at 1.0 get all of it. One channel, one answer, and no second opinion about where the
/// coastline is that could disagree with the one drawn in the albedo.
const GRAIN_ROUGH_FLOOR: f32 = 0.55;
const GRAIN_ROUGH_FULL: f32 = 0.90;

/// How near the terminator relief stops being applied, as a cosine of the angle to the star.
///
/// **Not a taste knob: it is the largest tilt the relief below ever applies.** A perturbation that
/// leans the normal by `t` can move `dot(N, L)` by about `t`, so anywhere the geometric `dot(N, L)`
/// is smaller than the largest tilt, the grain is deciding whether a fragment is lit AT ALL rather
/// than how brightly. Fading it out over exactly that band is what stops it doing so. Kept in step
/// with `body_skin::grain_of` and `pit_of` by a test that reads this file.
const GRAZE_BAND: f32 = 0.30;

// --- the same noise the CPU generator uses, so the grain is of a piece with the bake ---------
//
// Ported function for function from `procgen::bodies`, which is what the design study asked for:
// the two must not drift, or leaning in changes what a world is made of rather than how finely it
// is drawn. `bitcast` rather than `u32()` for the same reason the Rust side is all integer
// arithmetic until the final divide -- a value conversion of a negative number is not the bit
// pattern `as u32` gives, and the hash would then differ by platform.

fn hash3(x: i32, y: i32, z: i32, seed: u32) -> f32 {
    var h: u32 = seed
        ^ (bitcast<u32>(x) * 0x8da6b343u)
        ^ (bitcast<u32>(y) * 0xd8163841u)
        ^ (bitcast<u32>(z) * 0xcb1ab31fu);
    h ^= h >> 13u;
    h = h * 0x5bd1e995u;
    h ^= h >> 15u;
    h = h * 0x2545f491u;
    h ^= h >> 16u;
    return f32(h & 0x00ffffffu) / 16777215.0;
}

fn ease(t: f32) -> f32 {
    let c = clamp(t, 0.0, 1.0);
    return c * c * (3.0 - 2.0 * c);
}

fn vnoise(p: vec3<f32>, seed: u32) -> f32 {
    let fl = floor(p);
    let i = i32(fl.x);
    let j = i32(fl.y);
    let k = i32(fl.z);
    let f = vec3(ease(p.x - fl.x), ease(p.y - fl.y), ease(p.z - fl.z));
    let x00 = mix(hash3(i, j, k, seed), hash3(i + 1, j, k, seed), f.x);
    let x10 = mix(hash3(i, j + 1, k, seed), hash3(i + 1, j + 1, k, seed), f.x);
    let x01 = mix(hash3(i, j, k + 1, seed), hash3(i + 1, j, k + 1, seed), f.x);
    let x11 = mix(hash3(i, j + 1, k + 1, seed), hash3(i + 1, j + 1, k + 1, seed), f.x);
    return mix(mix(x00, x10, f.y), mix(x01, x11, f.y), f.z);
}

/// Two octaves, not five. This runs per fragment on a body filling the canopy, and its job is
/// GRAIN -- the frequencies above what a 512-wide bake can hold. The structure below that is the
/// bake's, and generating it twice would only disagree with it.
fn grain_at(p: vec3<f32>, seed: u32) -> f32 {
    return vnoise(p, seed) * 0.667 + vnoise(p * 2.03, seed + 7919u) * 0.333;
}

/// The steepest the crater profile below ever gets, in profile units per unit of `t`.
///
/// Worked out from the profile itself rather than measured: `d/dt` of
/// `-(1 - t^2) * 0.09 + smoothstep(0.72, 1, t) * 0.06` is `0.18t + 0.06 * S'(t)`, and `S'` peaks
/// at `6 * 0.25 / 0.28 = 5.36` halfway up the rim, giving about 0.48 there.
///
/// **It is here so the accumulated slope is bounded to about one per crater**, which makes the
/// strength knob beside it a real maximum tilt rather than a number whose scale depends on the
/// arithmetic above it. That is the exact mistake the grain shipped with, and this is the shape of
/// code that would have caught it.
const PIT_PEAK: f32 = 0.48;

/// Craters, evaluated where you are looking rather than baked into a texture.
///
/// **A moon needs these and a bake cannot give them.** Parked at the standoff a body shows about a
/// quarter radian of arc, which is four parts in a thousand of its surface — so the thirty-odd
/// craters a 512-wide map can resolve put, on average, *no craters at all* in the canopy. Baked
/// craters serve the mid distance. Up close the surface has to grow them.
///
/// One crater per lattice cell that the unit sphere passes through. The cell's own hash gives a
/// jittered point; the point is projected onto the sphere; cells whose point does not straddle the
/// sphere are rejected, which is what keeps the density a property of the SURFACE rather than of
/// the volume — without that test every cell in the lattice would contribute one and a moon would
/// be nothing but rim.
///
/// Returns the profile's slope directly and ANALYTICALLY. A crater is a function of angular
/// distance from its centre, so the gradient is that function's derivative pointing away from the
/// centre — no extra samples, unlike the grain, which has no closed form to differentiate.
fn crater_slope(dir: vec3<f32>, freq: f32, seed: u32) -> vec3<f32> {
    var slope = vec3(0.0, 0.0, 0.0);
    let base = floor(dir * freq);
    for (var dx: i32 = -1; dx <= 1; dx++) {
        for (var dy: i32 = -1; dy <= 1; dy++) {
            for (var dz: i32 = -1; dz <= 1; dz++) {
                let i = i32(base.x) + dx;
                let j = i32(base.y) + dy;
                let k = i32(base.z) + dz;
                let jitter = vec3(
                    hash3(i, j, k, seed),
                    hash3(i, j, k, seed ^ 0x9e3779b9u),
                    hash3(i, j, k, seed ^ 0x85ebca6bu),
                );
                let at = (vec3(f32(i), f32(j), f32(k)) + jitter) / freq;
                let len = length(at);
                // Does the unit sphere actually pass through this cell? If not, this cell has no
                // crater, and projecting its point onto the sphere anyway is how a lattice full of
                // empty space turns into a surface full of craters that are not there.
                if abs(len - 1.0) > 0.87 / freq {
                    continue;
                }
                let centre = at / len;
                // Up to most of a cell, so neighbours can touch but rarely swallow each other.
                let rad = (0.30 + 0.55 * hash3(i, j, k, seed ^ 0x2545f491u)) / freq;
                let cosang = dot(dir, centre);
                if cosang <= cos(rad) {
                    continue;
                }
                let ang = acos(clamp(cosang, -1.0, 1.0));
                let t = ang / rad;
                // Straight down the middle of a crater there is no direction to lean, and
                // normalizing a zero vector to find one gives NaN across the whole floor.
                let radial = dir - centre * cosang;
                let reach = length(radial);
                if reach < 1e-6 {
                    continue;
                }
                // `d/dt` of the same bowl-and-rim profile the bake uses. Depth is proportional to
                // radius there, which makes the SLOPE independent of radius — so it cancels here
                // and a small crater bites exactly as hard as a large one, which is what lets one
                // lattice serve every size.
                let u = clamp((t - 0.72) / 0.28, 0.0, 1.0);
                let d_profile = 0.18 * t + 0.06 * (6.0 * u * (1.0 - u)) / 0.28;
                slope += (radial / reach) * (d_profile / PIT_PEAK);
            }
        }
    }
    // Overlapping rims can stack; bounded so a chance pile-up cannot throw a normal round
    // backwards. Three craters deep is already more than a real field manages.
    let heap = length(slope);
    if heap > 3.0 {
        slope *= 3.0 / heap;
    }
    return slope;
}

/// Where on the unit sphere, in the BODY's own frame, this fragment is.
///
/// Reconstructed from the mesh's own uv rather than from the world normal, and that is
/// load-bearing: a world turns, so anything derived from a world-space direction is a noise field
/// the planet slides underneath. The uv is nailed to the mesh and turns with it.
fn body_dir(uv: vec2<f32>) -> vec3<f32> {
    let theta = uv.x * TAU;
    let phi = (0.5 - uv.y) * PI;
    let cp = cos(phi);
    return vec3(cp * cos(theta), sin(phi), cp * sin(theta));
}

@fragment
fn fragment(in: VertexOutput, @builtin(front_facing) is_front: bool) -> FragmentOutput {
    var pbr_input = pbr_input_from_standard_material(in, is_front);

    // The sphere's own normal, before the normal map bent it, and the view vector -- both
    // already worked out and normalized by `pbr_input_from_standard_material`, so this reads
    // them rather than deriving a second opinion.
    //
    // `world_normal` and NOT `N`: the limb and the terminator are facts about the BODY, about
    // where it curves away and where its star is. Taken off the normal-mapped `N` a mountain
    // range would read as a hole in the atmosphere, and the grain below would put a sparkle of
    // sunset all over the disc.
    let sphere_n = pbr_input.world_normal;
    let facing = clamp(dot(sphere_n, pbr_input.V), 0.0, 1.0);
    let sun_dot = dot(sphere_n, body.sun.xyz);

    // --- grain: the detail no bake is large enough to hold ---------------------------------
#ifdef VERTEX_UVS_A
    // Uniform for the whole body, so a world too far off to want relief -- or one with no
    // surface to put it on -- skips the whole thing rather than computing it and multiplying by
    // zero. The two halves have their own gates INSIDE this one, because they come and go at
    // different ranges: grain switches on with the detail rung, craters fade in over a stretch of
    // their own.
    if body.sun.w > 0.0 || body.pits.y > 0.0 {
        // ...and how much of it THIS point may have. See `GRAIN_ROUGH_FLOOR`: the sea is flat, so
        // it stays flat, and the land is not.
        let ground = smoothstep(
            GRAIN_ROUGH_FLOOR,
            GRAIN_ROUGH_FULL,
            pbr_input.material.perceptual_roughness,
        );
        let seed = u32(body.grain.y);
        let dir = body_dir(in.uv);
        var lean = vec3(0.0, 0.0, 0.0);
        var shade = 0.0;

        // --- grain: fine, isotropic, and sized in pixels ---
        if body.sun.w > 0.0 {
            let freq = body.grain.x;
            // A tangent frame to take the two derivatives in. Built off whichever axis the point
            // is least aligned with, so the cross product never collapses -- including at the
            // poles, which is where a fixed `up` vector would have produced a ring of NaNs.
            var seam = vec3(0.0, 1.0, 0.0);
            if abs(dir.y) > 0.9 {
                seam = vec3(1.0, 0.0, 0.0);
            }
            let t1 = normalize(cross(dir, seam));
            let t2 = cross(dir, t1);
            // A fraction of a CELL either way, so what the difference measures is this noise's own
            // steepness and not the frequency it happens to be drawn at.
            let e = GRAIN_STEP / freq;
            let h0 = grain_at(dir * freq, seed);
            let h1 = grain_at((dir + t1 * e) * freq, seed);
            let h2 = grain_at((dir + t2 * e) * freq, seed);
            lean += ((t1 * (h1 - h0) + t2 * (h2 - h0)) / GRAIN_STEP) * body.sun.w;
            // ...and a whisper of it in the colour too. Relief alone leaves the washes between the
            // bake's own features flat, and those are what read as painted.
            shade = (h0 - 0.5) * 0.07;
        }

        // --- craters: a real angular size, faded in by range ---
        if body.pits.y > 0.0 {
            lean += crater_slope(dir, body.pits.x, seed ^ 0x9e37u) * body.pits.y;
        }

        // **Relief goes away where the light grazes, and that is a fix rather than a fudge.**
        //
        // Diffuse lighting is `max(dot(N, L), 0)`, which has a KINK at zero. On the day side a
        // small tilt of the normal changes the shading a little; along the day/night line the same
        // tilt decides whether the fragment is lit at all. So grain that is invisible at noon
        // becomes a hard binary flicker at the terminator, and any sub-pixel movement of the
        // camera makes the whole band crawl like static -- which is exactly how it was reported.
        //
        // Softening the terminator would hide it rather than fix it. The reason the relief has to
        // GO is that what makes real terrain dramatic at a terminator is that it shadows itself,
        // and nothing here casts a shadow. Without that, a bumped normal under grazing light is
        // not information: it is the noise being read at the one angle where the lighting has
        // unbounded gain on it. Microfacet shading does the same thing at a smaller scale, for the
        // same geometry, and calls it a shadowing term.
        let graze = smoothstep(0.0, GRAZE_BAND, sun_dot);
        pbr_input.N = normalize(pbr_input.N - lean * ground * graze);
        pbr_input.material.base_color = vec4(
            pbr_input.material.base_color.rgb * (1.0 + shade * ground),
            pbr_input.material.base_color.a,
        );
    }
#endif

    var out: FragmentOutput;
    if (pbr_input.material.flags & STANDARD_MATERIAL_FLAGS_UNLIT_BIT) == 0u {
        out.color = apply_pbr_lighting(pbr_input);
    } else {
        // A star. It makes its own light, so there is no terminator on it -- but it is still a
        // SPHERE, and the thing that says so is limb darkening: the edge of a star's disc is
        // cooler and dimmer than its middle, because you are looking through more of it at a
        // shallower angle. Without this a star is a flat coin with granulation printed on it.
        let limb = mix(1.0, 0.42 + 0.58 * pow(facing, 0.45), body.grain.z);
        out.color = vec4(pbr_input.material.base_color.rgb * limb, pbr_input.material.base_color.a);
    }

    // --- air ---------------------------------------------------------------------------------
    if body.air.w > 0.0 {
        // Out-scatter toward the limb. A broad power rather than a sharp one: what reads as
        // atmosphere is a band a good fraction of the disc wide, not a hairline round the edge.
        let rim = pow(1.0 - facing, 2.6);
        // Lit air only, with a little wrap so the band does not stop dead at the terminator --
        // air is lit round the curve, which is the whole reason a dawn happens before sunrise.
        let day = clamp(sun_dot * 1.6 + 0.25, 0.0, 1.0);
        // Sunset: at grazing angles the short wavelengths have scattered out on the way in, so
        // what is left over the terminator is the warm end of the body's own air colour.
        let dusk = clamp(1.0 - abs(sun_dot) * 3.5, 0.0, 1.0);
        let tint = mix(body.air.rgb, body.air.rgb * vec3(1.6, 0.72, 0.42), dusk * 0.85);
        out.color = vec4(out.color.rgb + tint * rim * day * body.air.w, out.color.a);
    }

    out.color = main_pass_post_lighting_processing(pbr_input, out.color);
    return out;
}
