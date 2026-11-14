module ardot::c3spirv::sema;
import ardot::c3c::ast, ardot::c3spirv;

import std::io;

fn void? analyse_entry_point(SemaContext* context, Decl* decl) {
	Expr*[]? attribute_params = get_attribute(decl, SHADER);
	if(catch attribute_params) {
		return;
	}

	SpirvEntryPoint* entry_point = alloc::new(&context.global.vmem, SpirvEntryPoint, {
		.declaration = decl,
	});
	context.global.entry_points.push(entry_point);

	FuncDecl* func_decl = &decl.func_decl;
	Signature* signature = &func_decl.signature;

	TypeInfo* rtype_info = ast::type_info_ptr(signature.rtype);
	if(rtype_info.type.type_kind != TYPE_VOID) {
		return err::error(rtype_info.loc, "Shader entry point must have return type of void.")~;
	} else if(ast::vec_size(signature.params) > 0) {
		return err::error(decl.loc, "Shader entry point must have no parameters.")~;
	}

	ExecutionModel execution_model = (ExecutionModel)eval_const_int(attribute_params[0]);
	entry_point.model = execution_model;
	switch(execution_model) {
		case COMPUTE:
			uint[<3>] group_size;
			ExprConst* const_value = &attribute_params[1].const_expr;
			ConstInitializer*[] initializers = ast::vec(const_value.initializer.init_array_full);
			group_size.x = (uint)eval_const_int(initializers[0].init_value);
			group_size.y = (uint)eval_const_int(initializers[1].init_value);
			group_size.z = (uint)eval_const_int(initializers[2].init_value);
			entry_point.compute.group_size = group_size;
	}

	analyse_statement(context, ast::ast_ptr(func_decl.body))!;
}

fn void? analyse(GlobalContext* context) {
	SemaContext sema_context;
	sema_context.init(context);
	
	foreach(Module* mod : ast::vec(ast::gc().module_list)) {
		foreach(CompilationUnit* unit : ast::vec(mod.units)) {
			foreach(Decl* function : ast::vec(unit.functions)) {
				analyse_entry_point(&sema_context, function)!;
			}
		}
	}

	SpirvType* type = sema_context.first_type;
	while(type) {
		resolve_type_final(&sema_context, type);
		type = type.next;
	}
}