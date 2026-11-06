module ardot::c3spirv;

struct ComputeBuiltin {
	uint[<3>] global_invocation_id;
	uint[<3>] local_invocation_id;
}

constdef ExecutionModel : inline uint @private {
	VERTEX = 0,
	FRAGMENT = 4,
	COMPUTE = 5,
}

enum Attribute @private {
	SHADER,
	SHADER_ROOT,
}

const String TAG @private = "c3spirv_builtin";

attrmacro @ComputeShader(uint[<3>] group_size) = @tag(TAG, {
	Attribute.SHADER, 
	ExecutionModel.COMPUTE, 
	group_size
});

attrmacro @ShaderRoot = @tag(TAG, {Attribute.SHADER_ROOT});