module ardot::c3spirv;

struct ComputeBuiltin {
	uint[<3>] global_invocation_id;
	uint[<3>] local_invocation_id;
}

constdef ExecutionModel : inline uint {
	VERTEX = 0,
	FRAGMENT = 4,
	COMPUTE = 5,
}

enum Attribute @private {
	SHADER
}

const String C3SPIRV_TAG = "c3spirv_builtin";
attrdef @Shader(ExecutionModel model) = @tag(C3SPIRV_TAG, {Attribute.SHADER, model});