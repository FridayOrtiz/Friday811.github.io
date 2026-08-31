// THE NEAR BAND: one number per fragment, and the only thing this effect knows.
//
// Imported by both halves of the material (`near_hologram.wgsl` draws it, `near_hologram_prepass.wgsl`
// cuts the same fragments out of every depth buffer) so the two can never drift: a band the picture
// and the depth disagreed about is a wall you can see through that still hides the pilot behind it.
//
// The band is a WORLD-SPACE HALF-SPACE, handed down whole by `near_hologram::tend_band`. World space
// rather than the view's own depth on purpose, and it is the difference between working and looking
// like it works: this shader runs in four views -- the deck camera, its depth prepass, the ghost's
// scenery-depth camera and the deck lamp's shadow cube -- and `view` is a DIFFERENT camera in each.
// A depth measured from `view` would carve the room out of the lamp's shadow map, because every
// surface in a station is nearer to the lamp than the deck camera's band ever reaches.

#define_import_path near_hologram::band

// ONE binding, two lanes: `AsBindGroup` combines fields sharing an index into a single struct, and
// a struct is one thing to keep in step rather than two.
//
// `#{MATERIAL_BIND_GROUP}` and never a hardcoded number. The material group's index is a shader def
// bevy substitutes, it is not 2, and writing the digit compiles and links perfectly before failing
// at pipeline creation with "binding is missing from the pipeline layout" — which reads like the
// Rust side forgot to declare the uniform and is nothing of the sort.
struct NearBand {
    // xyz: the plane's unit normal, pointing from the room back toward the lens. w: its offset, so
    // `dot(p, xyz) - w` is how far in front of the plane a point is, in metres.
    plane: vec4<f32>,
    // x: how many metres in front of the plane the hologram reaches full strength. ZERO SHUTS THE
    // WHOLE EFFECT, which is what a wide framing and a grid room both look like from here.
    // y: 1 for the translucent film, 0 for the solid surface it is cut out of. zw: unused.
    dial: vec4<f32>,
    // x: the deck's own floor height in world metres. y: how far above it the film reaches full
    // strength. zw: unused.
    deck: vec4<f32>,
}

@group(#{MATERIAL_BIND_GROUP}) @binding(100) var<uniform> holo: NearBand;

// How far into the hologram a point is: 0 solid, 1 fully an instrument reading.
//
// Smoothstepped by hand rather than through `smoothstep`, the same way `fog_mask::fade` does it and
// for the same reason -- a hand-written curve is one the CPU side can test without a device.
fn near_band(world_position: vec4<f32>) -> f32 {
    let reach = holo.dial.x;
    if reach <= 0.0 {
        return 0.0;
    }
    let ahead = dot(world_position.xyz, holo.plane.xyz) - holo.plane.w;
    let t = clamp(ahead / reach, 0.0, 1.0);
    // AND ABOVE THE DECK. The band is a slab at a fixed view depth, so on an iso camera it cuts a
    // diagonal strip across the picture — and a strip takes the FLOOR with it, which is most of
    // what a leaned-in frame is looking at. A floor hides nothing: it is the thing being looked
    // at, so filming it turns the deck milky rather than revealing anything (reported from a live
    // client as "the level as a whole is milky"). The room's own deck height comes down in the
    // uniform, so this is the floor the server placed, not a tuned constant: plating stays solid,
    // a crate starts to answer at knee height, a wall answers whole.
    let above = clamp((world_position.y - holo.deck.x) / max(holo.deck.y, 0.0001), 0.0, 1.0);
    let lift = above * above * (3.0 - 2.0 * above);
    return t * t * (3.0 - 2.0 * t) * lift;
}

// Whether this material draws the film or the solid surface.
fn is_film() -> bool {
    return holo.dial.y > 0.5;
}
