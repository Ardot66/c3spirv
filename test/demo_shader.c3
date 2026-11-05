module demo_shader;
import ardot::c3spirv;

struct ComputeRoot {
	float* input;
	float* output;
	uint count;
}

fn void compute(ComputeBuiltin *builtin, ComputeRoot* root) @Shader(COMPUTE) {
	uint id = builtin.global_invocation_id.x;
	if(id < root.count) {
		root.output[id] = root.input[id] * 2f;
	}
}