// THE SAME CUT, made in every depth buffer the level appears in.
//
// This is the half that keeps the effect honest. A wall the pilot can see through must not be a
// wall anything MEASURES, and three passes measure the level without drawing it: the deck camera's
// own depth prepass, the ghost's scenery-depth camera (`ghost::SceneryDepthCam` -- the silhouette
// and the fog-of-war mask both read that texture), and the deck lamp's shadow cube. Left out of
// this file, the near wall would go translucent in the picture and stay solid in all three: the
// pilot standing behind it would be drawn as a blue GHOST through a wall you can already see
// through, and the fog would measure its distance to a surface nobody can see.
//
// It runs at all only because the solid material is `AlphaMode::Mask`. bevy builds a prepass
// fragment stage for a material only when its pipeline key carries `MAY_DISCARD`, which
// `alpha_mode_pipeline_key` sets for `Mask` and for nothing else an opaque level could wear
// (`bevy_pbr/src/prepass/mod.rs`, `fragment_required`). An `Opaque` level would silently get
// bevy's vertex-only depth pipeline and this file would never be compiled.

#import bevy_pbr::{
    pbr_prepass_functions,
    prepass_io,
}
#import near_hologram::band::near_band

#ifdef PREPASS_FRAGMENT
@fragment
fn fragment(in: prepass_io::VertexOutput) -> prepass_io::FragmentOutput {
    pbr_prepass_functions::prepass_alpha_discard(in);
    if near_band(in.world_position) > 0.0 {
        discard;
    }
    var out: prepass_io::FragmentOutput;
#ifdef UNCLIPPED_DEPTH_ORTHO_EMULATION
    out.frag_depth = in.unclipped_depth;
#endif
#ifdef NORMAL_PREPASS
    out.normal = vec4(in.world_normal * 0.5 + vec3(0.5), 1.0);
#endif
#ifdef MOTION_VECTOR_PREPASS
    out.motion_vector =
        pbr_prepass_functions::calculate_motion_vector(in.world_position, in.previous_world_position);
#endif
    return out;
}
#else
// The client's only prepasses are depth-only, so this is the branch that actually ships: no
// targets at all, and the whole job is deciding whether the fragment exists.
@fragment
fn fragment(in: prepass_io::VertexOutput) {
    pbr_prepass_functions::prepass_alpha_discard(in);
    if near_band(in.world_position) > 0.0 {
        discard;
    }
}
#endif
