import ardot::c3spirv;

struct ComputeRoot {
	uint variable;
}

fn void compute() @ComputeShader({64, 1, 1}) {
	ComputeRoot* root = c3spirv::get_root{ComputeRoot}();
	*root = {}; // #error: It is not possible to write to a pointer with the uniform storage class
}