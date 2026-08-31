// The ghost: the flat colour a body reads as THROUGH the scenery covering it.
//
// TWO depth tests decide a fragment, and they answer different questions. The pipeline's
// (`ghost::GhostMaterial::specialize`: test LESS -- bevy's depth is reversed, so "behind what is
// drawn" is the smaller value -- write nothing) asks "is ANYTHING nearer than the body's
// plane?", which is what keeps the twin off the pilot's own visible skin. The fragment shader
// then asks WHO: it samples a SCENERY-ONLY depth -- the `SceneryDepthCam`'s buffer, walls and
// props and fixtures with every body excluded by render layer -- and discards unless scenery is
// strictly nearer. A wall in front of the pilot ghosts; an NPC walking between the camera and
// the pilot does not, because the NPC never wrote into this buffer and whatever scenery sits
// behind them is farther than the pilot. Where no scenery camera has rendered yet the binding
// is a 1x1 white fallback -- 1.0, the nearest reverse-Z depth -- so the gate passes everywhere
// and the ghost degrades to the old whole-scene behaviour rather than to nothing.
//
// The sample is an unfiltered float read through a NEAREST sampler -- not a `textureLoad`, and
// not a comparison sampler. The sampler is what makes it work on WebGL2 at all: GLES calls a
// depth texture with non-NEAREST filters INCOMPLETE and hands back 0.0 for every read, and a
// `textureLoad` binds no sampler to override the defaults it was created with. `ghost.rs`'s
// `scenery_depth_sampler` has the whole story. NEAREST costs nothing here -- there is no
// meaningful value between two depth texels, and the coordinate is the fragment's own screen
// position over the viewport, which is texel-for-texel with this texture in steady state
// (clamp-to-edge carries the one resize frame where it is not, and the 1x1 fallback).
//
// THE BODY CANNOT OCCLUDE ITSELF, BY CONSTRUCTION. There is one depth buffer per view and it
// holds everything, so the fragment cannot ask WHOSE pixel is in front of it -- and every
// version of this that tried to outrun self-occlusion with a bias lost to some pose (a stride
// puts one leg half a metre behind the other, which is deeper than any garment gap). So the
// twin keeps the body's true skinned SILHOUETTE in x and y, and throws the body's depth relief
// away entirely: every vertex takes the depth of ONE point, the body's own anchor pushed toward
// the lens far enough to clear its nearest surface. A flat thing has no parts behind other
// parts. What is nearer than that plane -- a wall, a doorframe, a crate -- still occludes it,
// and is exactly what the silhouette should show through.
//
// The flattening leans on this camera being ORTHOGRAPHIC: with w = 1 everywhere, splicing one
// vertex's clip z under another's clip x/y is exact, and moving a point along the view axis
// changes its depth and nothing else.

#import bevy_pbr::{
    mesh_functions,
    mesh_view_bindings::view,
    skinning,
    forward_io::Vertex,
}

struct GhostUniform {
    color: vec4<f32>,
};

@group(#{MATERIAL_BIND_GROUP}) @binding(0)
var<uniform> ghost: GhostUniform;

// The scenery-only depth (reverse-Z), rendered by `ghost::SceneryDepthCam` over the lamp's
// scenery layer -- or the 1x1 white fallback before that camera exists. Declared as a float
// texture, not texture_depth_2d: the raw value is what the comparison below wants, not a
// comparison verdict.
@group(#{MATERIAL_BIND_GROUP}) @binding(1)
var scenery_depth: texture_2d<f32>;
// NEAREST, non-comparison, and load-bearing on the web: see the header.
@group(#{MATERIAL_BIND_GROUP}) @binding(2)
var scenery_sampler: sampler;

// Where the body's depth plane sits: its anchor (the mesh node's own origin, at the feet),
// lifted to the chest, then brought toward the lens by more than any part of a standing body
// reaches from its own chest -- at this camera's flattest rake, a head 1.8 up leans about 1.3
// toward the lens from the feet, which is under 1.0 from the chest. Facts about bodies and the
// shipped rake ladder, not about any level.
const CHEST: f32 = 0.9;
const NEAR_BODY: f32 = 1.05;

struct GhostOutput {
    @builtin(position) position: vec4<f32>,
};

@vertex
fn vertex(vertex: Vertex) -> GhostOutput {
    var out: GhostOutput;
    let world_from_local = mesh_functions::get_world_from_local(vertex.instance_index);
#ifdef SKINNED
    let skin_from_local = skinning::skin_model(
        vertex.joint_indices,
        vertex.joint_weights,
        vertex.instance_index
    );
    let world =
        mesh_functions::mesh_position_local_to_world(skin_from_local, vec4<f32>(vertex.position, 1.0));
#else
    let world =
        mesh_functions::mesh_position_local_to_world(world_from_local, vec4<f32>(vertex.position, 1.0));
#endif
    // The silhouette's screen position: the real skinned vertex.
    let clip = view.clip_from_world * vec4<f32>(world.xyz, 1.0);
    // The body's one depth: its anchor, chest-high, stepped toward the lens.
    let toward_lens = normalize(view.world_from_view[2].xyz);
    let anchor = world_from_local[3].xyz + vec3<f32>(0.0, CHEST, 0.0) + toward_lens * NEAR_BODY;
    let flat = view.clip_from_world * vec4<f32>(anchor, 1.0);
    out.position = vec4<f32>(clip.x, clip.y, flat.z, clip.w);
    return out;
}

@fragment
fn fragment(in: GhostOutput) -> @location(0) vec4<f32> {
    // Only SCENERY triggers the ghost: sample the scenery-only depth at this fragment's screen
    // position and draw only where scenery is strictly NEARER than the body's flat plane
    // (reverse-Z: nearer is larger). A body in front writes nothing into this texture, so the
    // floor behind it answers, and the floor is farther: no ghost.
    let uv = in.position.xy / view.viewport.zw;
    let scenery = textureSampleLevel(scenery_depth, scenery_sampler, uv, 0.0).x;
    if scenery <= in.position.z {
        discard;
    }
    return ghost.color;
}
