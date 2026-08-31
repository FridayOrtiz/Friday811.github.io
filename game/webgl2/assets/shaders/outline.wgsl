// The hover rim: an inverted hull around whatever interactable the cursor is on.
//
// The pipeline (`outline::OutlineMaterial::specialize`) culls FRONT faces, so what draws is the
// far side of the shell this shader inflates -- and the object's own opaque surface, nearer
// everywhere it covers the shell, wins the stock depth test across the middle. What survives is
// a rim around the silhouette. Depth is left exactly stock (reverse-Z GreaterEqual, no write in
// the transparent pass): a wall in front of the object covers its rim like anything else.
//
// The inflation is along the STORED normal, in world units, taken through the mesh's own
// transform (inverse-transpose, via `mesh_normal_local_to_world`) -- so a unit cuboid scaled
// into a door slab still grows a rim of constant world thickness, and the rim is the same few
// centimetres whatever the mesh. Front-culling trusts the winding to agree with those normals;
// for the level's door nodes this is measured on the shipped glb (every triangle agrees), and
// bevy's primitives and the prop pipeline's re-exports generate agreeing normals -- see the
// module doc in outline.rs.
//
// NO SKINNED BRANCH, deliberately: actors are excluded at the system (`sync_hover_outline`), so
// this shader only ever inflates rigid meshes. A skinned twin would need the skinning path or
// it would draw the bind pose inside the animated body.

#import bevy_pbr::{
    mesh_functions,
    mesh_view_bindings::view,
    forward_io::Vertex,
}

struct OutlineUniform {
    color: vec4<f32>,
};

@group(#{MATERIAL_BIND_GROUP}) @binding(0)
var<uniform> outline: OutlineUniform;

// How far the shell stands off the surface, metres. A look constant, like the ghost's: thick
// enough to survive the map's orthographic zoom-out, thin enough not to read as a second door.
const RIM_M: f32 = 0.03;

struct OutlineOutput {
    @builtin(position) position: vec4<f32>,
};

@vertex
fn vertex(vertex: Vertex) -> OutlineOutput {
    var out: OutlineOutput;
    let world_from_local = mesh_functions::get_world_from_local(vertex.instance_index);
    let world =
        mesh_functions::mesh_position_local_to_world(world_from_local, vec4<f32>(vertex.position, 1.0));
#ifdef VERTEX_NORMALS
    let n = normalize(mesh_functions::mesh_normal_local_to_world(vertex.normal, vertex.instance_index));
    let inflated = world.xyz + n * RIM_M;
#else
    // A mesh with no normals cannot say which way "out" is; an uninflated shell front-culled
    // draws nothing, which is the honest answer for it.
    let inflated = world.xyz;
#endif
    out.position = view.clip_from_world * vec4<f32>(inflated, 1.0);
    return out;
}

@fragment
fn fragment(_in: OutlineOutput) -> @location(0) vec4<f32> {
    return outline.color;
}
