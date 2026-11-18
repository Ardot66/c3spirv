module demo_shader;
import ardot::c3spirv;

struct ComputeRoot @ShaderRoot {
	float* input;
	float* output;
	uint count;
}

fn void compute_alt() @ComputeShader({64, 1, 1}) {
	ComputeRoot* root = c3spirv::get_root{ComputeRoot}();
	ComputeRoot a;
	*root = a; // #error: Cannot assign an unresolved type.
}