module ardot::c3spirv::codegen @local;
import ardot::c3spirv, ardot::c3c::ast;

fn void emit_var(EmissionContext* context, SpirvDecl* spirv_decl) {
	VarDecl* var_decl = &spirv_decl.declaration.var_field;

	Id type = type_id(context, spirv_decl.variable.type);
	Id initializer;
	if(var_decl.init_expr) {
		initializer = expr_value(context, emit_expression(context, var_decl.init_expr));
	}

	if(!spirv_decl.variable.writeable) {
		spirv_decl.variable.id = initializer;
	} else {
		Id pointer = context.type_op(TYPE_POINTER, StorageClass.FUNCTION, type);

		Id variable = context.func_var_op(VARIABLE, pointer, StorageClass.FUNCTION);
		if(initializer) {
			context.func_op(STORE, variable, initializer);
		}

		spirv_decl.variable.pointer_type_id = pointer;
		spirv_decl.variable.id = variable;
	}
}

fn void emit_declaration(EmissionContext* context, Decl* declaration) @public {
	SpirvDecl *spirv_decl = declaration.backend_ref;

	switch(declaration.decl_kind) {
		case DECL_VAR: emit_var(context, spirv_decl);
		default: unreachable("Unsupported codegen declaration: %s", ast::const_name(declaration.decl_kind));
	}
}