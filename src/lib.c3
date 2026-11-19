module ardot::c3spirv;

constdef ExecutionModel : inline uint {
	VERTEX = 0,
	FRAGMENT = 4,
	COMPUTE = 5,
}

enum Attribute {
	SHADER,
	SHADER_ROOT,
	SHADER_BUILTIN,
}

constdef Builtin : inline uint {
	POSITION = 0,
	POINT_SIZE = 1,
	VERTEX_ID = 5,
	INSTANCE_ID = 6,
	GLOBAL_INVOCATION_ID = 28,
}

enum ShaderBuiltin {
	GET_ROOT,
	GET_GLOBAL_INVOCATION_ID,
	UNIFORM_INPUT,
	BUILTIN_INPUT,
	BUILTIN_OUTPUT,
	PIPELINE_INPUT,
	PIPELINE_OUTPUT,
}

const String TAG = "c3spirv_builtin";

attrmacro @ComputeShader(uint[<3>] group_size) = @tag(TAG, {
	Attribute.SHADER, 
	ExecutionModel.COMPUTE, 
	group_size
});

attrmacro @VertexShader = @tag(TAG, {
	Attribute.SHADER, 
	ExecutionModel.VERTEX,
});

attrmacro @ShaderRoot = @tag(TAG, {Attribute.SHADER_ROOT});
attrmacro @ShaderBuiltin(ShaderBuiltin kind) = @tag(TAG, {Attribute.SHADER_BUILTIN, kind});

fn Type* uniform_input(uint layout_index, uint binding_index) <Type> @ShaderBuiltin(UNIFORM_INPUT) => {};

fn Type* builtin_input(Builtin builtin) <Type> @ShaderBuiltin(BUILTIN_INPUT) => {};
fn Type* builtin_output(Builtin builtin) <Type> @ShaderBuiltin(BUILTIN_OUTPUT) => {};

fn Type* pipeline_input(uint layout_index) <Type> @ShaderBuiltin(PIPELINE_INPUT) => {};
fn Type* pipeline_output(uint layout_index) <Type> @ShaderBuiltin(PIPELINE_OUTPUT) => {};

// struct VertexBuiltin {
// 	// Input
// 	int* vertex_id;
// 	int* instance_id;

// 	// Output
// 	float[<4>]* position;
// 	float* point_size;
// }

// macro VertexBuiltin vertex_builtin() {
// 	VertexBuiltin builtin;
// 	builtin.vertex_id = builtin_input{int}(VERTEX_ID);
// 	builtin.instance_id = builtin_input{int}(INSTANCE_ID);

// 	builtin.position = builtin_output{float[<4>]}(POSITION);
// 	builtin.point_size = builtin_output{float}(POINT_SIZE);
// 	return builtin;
// }