module demo_shader;
import ardot::c3spirv;

struct ComputeRoot @ShaderRoot {
	float* input;
	float* output;
	uint count;
}

// fn void compute(ComputeBuiltin *builtin, ComputeRoot* root) @ComputeShader({64, 1, 1}) {
// 	uint id = builtin.global_invocation_id.x;
// 	if(id < root.count) {
// 		root.output[id] = root.input[id] * 2f;
// 	}
// }

// Alternative syntax?

fn void subfunc(ComputeRoot* root) {
	// ...
}

fn void compute_alt() @ComputeShader({64, 1, 1}) {
	// Restrictions: get_root can only be used in an entry point function.
	// It should ideally be possible to use from within a macro, as long at it's properly
	// unfolded.

	// get_root will create the uniform variable behind the scenes. I think we should just dereference
	// it immediately and assign the result to the local variable here. For now I don't think that
	// any 'fetching' builtins like get_root should be allowed to appear multiple times.

	// c3c tracks whether a local variable is ever assigned to, so we can use that to determine whether
	// and OpVariable is necessary or not. (but it may be easier to just always use OpVariable as
	// apparently drivers don't really care)

	// Taking the address of a local variable should be allowed ideally, but it should never be
	// possible to modify the variable holding the local address, only the underlying data. This
	// is due to a SPIR-V restriction but I don't think it will impact much.

	// Theoretically it _could_ be possible to modify pointers to local variables, but I don't think
	// spirv-val would like this very much and I imagine it's a pretty niche case to begin with.
	ComputeRoot* root = c3spirv::get_root{ComputeRoot}();

	// Functions like get_global_invocation_id should also never be allowed outside an entry point.
	// They should work in macros to allow helper creation.
	uint[<3>] invocation_id = c3spirv::get_global_invocation_id();

	// Calling a function that takes pointer parameters will be a little complex on the whole,
	// but I think the simplest way to manage it is that the function will be emitted once
	// for every unique combination of storage classes that it gets called with.

	// I don't think void* parameters are going to be possible, but in an ideal world we could
	// either bitcast to a char* (preferred) or perform type inference for the whole function and emit
	// an extra version for each unique combination of types (less ideal). 

	// In the case of this particular function, the parameter should just be a ComputeRoot pointer,
	// nothing fancy. If it was a ** we would still be able to pass it, but there would need to
	// be restrictions on the other side that the local variable can't be modified.
	// subfunc(root);

	// This should just create an OpVariable and load from the invocation_id, pretty simple.
	uint id = invocation_id.x;

	// Branches are a little complex, but I think it should be possible to represent them well.
	// Will need to do some more experimentation here.
	if(id < root.count) {
		// As members of the root, output and input should implicitly be of the PhysicalStorageBuffer
		// storage class. Their array stride should just be equal to their size, and to make things
		// easier it may be best to always decorate pointers with array stride, even if it's never
		// used. The other option is to only decorate with array stride when necessary, which is
		// probably possible.

		// The constant 2f here should be unique (to make the SPIR-V smaller hopefully), and our type_op
		// system should handle that neatly. There is the matter of 64 bit floating point, but handling
		// that is a whole other can of worms.
		// root.output[id] = root.input[id] * 2f;
	}
}