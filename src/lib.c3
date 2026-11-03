module ardot::c3spirv;

struct ComputeBuiltin {
	uint[<3>] global_invocation_id;
	uint[<3>] local_invocation_id;
}

enum ExecutionModel {
	VERTEX,
	FRAGMENT,
	COMPUTE,
}

enum Attribute @private {
	SHADER
}

const String C3SPIRV_TAG = "c3spirv_builtin";
attrdef @Shader(ExecutionModel model) = @tag(C3SPIRV_TAG, Attribute.SHADER, model);