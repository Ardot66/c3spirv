module ardot::c3spirv;
import ardot::c3c::ast;
import std::io, std::collections::map;

typedef Id = inline uint;

// fn void? emit_declaration(EmissionContext* context, Decl* declaration) {
// 	switch(declaration.decl_kind) {
// 		case DECL_VAR:
// 			VarDecl* variable = &declaration.var_field;
// 			SpirvValue initializer;
// 			if(!variable.no_init) {
// 				initializer = emit_expression(context, variable.init_expr)!;
// 			}

// 			// Id type = spirv_type(context, declaration.type, declaration.loc)!;
// 			// Id type_ptr = context.type_op(TYPE_POINTER, StorageClass.FUNCTION, type);

// 			// Id id = context.func_op_raw(VARIABLE, {type_ptr, StorageClass.FUNCTION}, initializer ? {initializer} : {});
// 			// declaration.backend_ref = id;
// 		default: return error(declaration.loc, "Unsupported declaration kind: %s", ast::const_name(declaration.decl_kind))~;
// 	}
// }

// fn SpirvValue? emit_expression(EmissionContext* context, Expr* expression) {
// 	switch(expression.expr_kind) {
// 		case EXPR_COND:
// 			Expr*[] expressions = ast::vec(expression.cond_expr);
// 			foreach(cond : expressions) {
// 				emit_expression(context, cond)!;
// 			}
// 			return {};
// 		case EXPR_BINARY:
// 			ExprBinary* binary = &expression.binary_expr;
// 			emit_expression(context, ast::expr_ptr(binary.left))!;
// 			emit_expression(context, ast::expr_ptr(binary.right))!;
// 			return {};
// 		case EXPR_IDENTIFIER:
// 			Decl* ident = expression.ident_expr;
// 			return {};
// 		default: return error(expression.loc, "Unsupported expression kind: %s", ast::const_name(expression.expr_kind))~;
// 	}
// }

// fn void? emit_statement(EmissionContext* context, Ast* statement) {
// 	while(statement) {
// 		switch(statement.ast_kind) {
// 			case AST_COMPOUND_STMT:
// 				emit_statement(context, ast::ast_ptr(statement.compound_stmt.first_stmt))!;
// 			case AST_DECLARE_STMT:
// 				emit_declaration(context, statement.declare_stmt)!;
// 			case AST_IF_STMT:
// 				AstIfStmt* specific = &statement.if_stmt;
// 				emit_expression(context, ast::expr_ptr(specific.cond))!;
// 				emit_statement(context, ast::ast_ptr(specific.then_body))!;
// 				emit_statement(context, ast::ast_ptr(specific.else_body))!;
// 			default: return error(statement.loc, "Unsupported statement kind: %s", ast::const_name(statement.ast_kind))~;
// 		}

// 		statement = ast::ast_ptr(statement.next);
// 	}
// }

// fn void? eval_entry_func(EmissionContext* context, Decl* decl) {
// 	assert(decl.decl_kind == DECL_FUNC);
// 	Expr*[]? attribute_params = get_attribute(decl, SHADER);
// 	if(catch attribute_params) {
// 		return;
// 	}

// 	ExecutionModel execution_model = (ExecutionModel)eval_const_int(attribute_params[0]);

// 	uint[<3>] group_size;
// 	{
// 		ExprConst* const_value = &attribute_params[1].const_expr;
// 		ConstInitializer*[] initializers = ast::vec(const_value.initializer.init_array_full);
// 		group_size.x = (uint)eval_const_int(initializers[0].init_value);
// 		group_size.y = (uint)eval_const_int(initializers[1].init_value);
// 		group_size.z = (uint)eval_const_int(initializers[2].init_value);
// 	}

// 	FuncDecl* func_decl = &decl.func_decl;
// 	Signature* signature = &func_decl.signature;
// 	Decl*[] params = ast::vec(signature.params);

// 	Id void_type = context.type_op(TYPE_VOID).id;
// 	Id func_type = context.type_op(TYPE_FUNCTION, void_type).id;

// 	Id func = context.func_op(FUNCTION, void_type, (uint)(FunctionControl){}, func_type);
// 	Id label = context.func_op(LABEL);

// 	emit_statement(context, ast::ast_ptr(func_decl.body))!;
// 	// AstCompoundStmt* body = &ast::ast_ptr(decl.func_decl.body).compound_stmt;
// 	// Ast* current = ast::ast_ptr(body.first_stmt);
// 	// while(current) {
// 	// 	io::printn(ast::const_name(current.ast_kind));
// 	// 	current = ast::ast_ptr(current.next);
// 	// }
// 	// stuff

// 	context.func_op(RETURN);
// 	context.func_op(FUNCTION_END);

// 	// TODO: should probably use fully qualified name here, or have the user specify it in the attribute.
// 	context.init_op_raw(ENTRY_POINT, {execution_model, func}, str_literal(ast::c_string(decl.name)));
// }

fn uint[] str_literal(String string) {
	// + 4 here because if the string perfectly fits into the literal that leaves no space
	// for the null terminator!
	sz elements = (string.len + 4) / 4; 

	uint[] literal = mem::talloc_array(uint, elements);
	literal[^1] = 0;
	mem::copy(literal, string, string.len);
	return literal;
}

fn int? test() => 1;

fn int main(String[] args) @public
{
	// emit_sample_program();

	GlobalContext* gc = ast::load_ast({"c3cdev", "build", "--ast-dump"})!!;
    defer ast::free_ast();

	io::File out_file = file::open("output.spv", "w")!!;
	defer out_file.close();

	EmissionContext context;
	const sz VMEM_SIZE = 1024 * 1024 * 64;
	context.init(VMEM_SIZE);
	defer context.free();

	if(catch sema::analyse(&context)) {
		return 1;
	}
	// context.init_ops.op(&context, CAPABILITY, Capability.SHADER);
	// context.init_ops.op(&context, CAPABILITY, Capability.PHYSICAL_STORAGE_BUFFER_ADDRESSES);
	// context.init_ops.op(&context, MEMORY_MODEL, AddressingModel.PHYSICAL_STORAGE_BUFFER_64, MemoryModel.GLSL450);

	// ast::@vec_foreach(gc.module_list; Module* mod) {
	// 	ast::@vec_foreach(mod.units; CompilationUnit* unit) {
	// 		ast::@vec_foreach(unit.functions; Decl* function) {
	// 			if(catch eval_entry_func(&context, function)) {
	// 				return 1;
	// 			}
	// 		};
	// 	};
	// };

	context.write(&out_file)!!;
	return 0;
}
