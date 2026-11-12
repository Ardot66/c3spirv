module ardot::c3spirv::sema @local;
import ardot::c3c::ast, ardot::c3spirv;

fn bool can_write_variable(SpirvType* type) => type.type.type_kind != TYPE_POINTER;
fn void? analyse_set_var(EmissionContext* context, SpirvDecl* variable, SpirvType* value, SourceLocId loc) {
	if(variable.variable.type) {
		if(variable.variable.type != value) {
			err::error(loc, "Cannot set variable, conflicting pointer types!");
			return err::error_note(variable.declaration.loc, "The variable was declared here.")~;
		} else if(!variable.variable.writeable) {
			err::error(loc, "Cannot set the value of a pointer variable more than once.");
			return err::error_note(variable.declaration.loc, "The variable was declared here.")~;
		}

		return;
	}

	if(variable.declaration.type != value.type) {
		unreachable();
	}

	variable.variable.type = value;
	bool writeable = can_write_variable(value);
	variable.variable.writeable = writeable;

	if(writeable) {
		variable.variable.real_type = create_type_pointer(context, null, StorageClass.FUNCTION, value);
	} else {
		variable.variable.real_type = value;
	}
}

fn void? analyse_var(EmissionContext* context, SpirvDecl* spirv_decl) {
	VarDecl* variable = &spirv_decl.declaration.var_field;
	if(variable.init_expr) {
		SpirvType* initializer = analyse_expression(context, variable.init_expr).type.ref!;
		analyse_set_var(context, spirv_decl, initializer, variable.init_expr.loc)!;
	}
}

fn void? analyse_declaration(EmissionContext* context, Decl* declaration) @public {
	SpirvDecl* spirv_decl = alloc::new(&context.vmem, SpirvDecl, {
		.declaration = declaration,
	});
	declaration.backend_ref = spirv_decl;

	switch(declaration.decl_kind) {
		case DECL_VAR: analyse_var(context, spirv_decl)!;
		default: return err::error(declaration.loc, "Unsupported declaration kind: %s", ast::const_name(declaration.decl_kind))~;
	}
}

