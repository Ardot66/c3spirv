module ardot::c3spirv::sema @local;
import ardot::c3c::ast, ardot::c3spirv;

import std::io;

fn void? analyse_var(SemaContext* context, SpirvDecl* spirv_decl) {
	VarDecl* variable = &spirv_decl.declaration.var_field;

	ExprType type = expr_type(analyse_type(context, spirv_decl.declaration.type, spirv_decl.declaration.loc, UNRESOLVED))!;
	// If the type kind is a pointer, then we can't create a SPIR-V variable to it, so
	// we do nothing. If it isn't, then it must be a value type of some kind, so we
	// can safely create a variable, and the pointer to the variable must have the FUNCTION storage class.
	if(type.ref.kind != TYPE_POINTER) {
		type.real = create_type_pointer(context, null, FUNCTION, type.ref);
	}
	spirv_decl.variable.type = type;

	if(variable.init_expr) {
		SpirvExpr* init = analyse_expression(context, variable.init_expr)!;
		// Intentionally not using analyse_assignment here because we allow the special
		// case where we can't create a proper SPIR-V variable, but we can use a SSA ID
		// from the initializer.
		resolve_types(context, type.ref, init.type.ref, variable.init_expr.loc)!;
	} else if(!type.is_ref()) {
		return err::error(spirv_decl.declaration.loc, "Variables containing pointers must have an initializer.")~;
	}
}

fn void? analyse_declaration(SemaContext* context, Decl* declaration) @public {
	SpirvDecl* spirv_decl = alloc::new(&context.global.vmem, SpirvDecl, {
		.declaration = declaration,
	});
	declaration.backend_ref = spirv_decl;

	switch(declaration.decl_kind) {
		case DECL_VAR: analyse_var(context, spirv_decl)!;
		default: return err::error(declaration.loc, "Unsupported declaration kind: %s", ast::const_name(declaration.decl_kind))~;
	}
}

