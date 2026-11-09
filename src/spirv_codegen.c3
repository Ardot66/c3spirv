module ardot::c3spirv::codegen;
import ardot::c3spirv, ardot::c3c::ast;

import std::io;

fn Id type_id(EmissionContext* context, SpirvType* type) {
	if(type.id) {
		return type.id;
	}

	Id id;
	switch(type.type.type_kind) {
		case TYPE_VOID: id = context.type_op(TYPE_VOID);
		case TYPE_BOOL: id = context.type_op(TYPE_BOOL);
		case TYPE_I8: id = context.type_op(TYPE_INT, 8, 1);
		case TYPE_I16: id = context.type_op(TYPE_INT, 16, 1);
		case TYPE_I32: id = context.type_op(TYPE_INT, 32, 1);
		case TYPE_I64: id = context.type_op(TYPE_INT, 64, 1);
		// case TYPE_I128: // unsupported for now.
		case TYPE_U8: id = context.type_op(TYPE_INT, 8, 0);
		case TYPE_U16: id = context.type_op(TYPE_INT, 16, 0);
		case TYPE_U32: id = context.type_op(TYPE_INT, 32, 0);
		case TYPE_U64: id = context.type_op(TYPE_INT, 64, 0);
		// case TYPE_U128: // unsupported for now.
		case TYPE_F16: id = context.type_op(TYPE_FLOAT, 16);
		// case TYPE_BF16: // unsupported for now.
		case TYPE_F32: id = context.type_op(TYPE_FLOAT, 32);
		case TYPE_F64: id = context.type_op(TYPE_FLOAT, 64);
		// case TYPE_F128: // unsupported for now.

		case TYPE_POINTER:
			SpirvType* inner = type.pointer.inner;
			Id inner_id = type_id(context, inner);
			id = context.type_op(TYPE_POINTER, type.pointer.class, inner_id);
		case TYPE_STRUCT: @pool() {
			StructDecl* struct_decl = &type.type.decl.strukt;

			Id[] member_ids = mem::talloc_array(Id, type.structure.members.len);
			foreach(sz i, SpirvType* member : type.structure.members) {
				member_ids[i] = type_id(context, member);
			};

			id = context.type_op_raw(TYPE_STRUCT, (uint[])member_ids);
			context.decoration_op(DECORATE, id, Decoration.BLOCK);
			foreach(sz i, Decl* member : ast::vec(struct_decl.members)) {
				context.decoration_op(MEMBER_DECORATE, id, (uint)i, Decoration.OFFSET, (uint)member.offset);
			}
		};
		case TYPE_VECTOR:
			Id inner = type_id(context, type.vector.member);
			id = context.type_op(TYPE_VECTOR, inner, (uint)type.vector.length);
		default:
			unreachable("Unsupported codegen type: %s", ast::const_name(type.type.type_kind));
	}

	assert(id);
	type.id = id;
	return id;
}

fn void add_func_interface(EmissionContext* context, Id interface_id) {
	if(!context.func_interfaces.contains(interface_id)) {
		context.func_interfaces.push(interface_id);
	}
}

fn Id emit_builtin_call(EmissionContext* context, SpirvExpr* spirv_expr) {
	ShaderBuiltin builtin = spirv_expr.call.builtin;
	Expr* expression = spirv_expr.expression;
	Id expr_type = type_id(context, spirv_expr.type);

	Id id;
	switch(builtin) {
		case GET_ROOT:
			id = context.type_op(VARIABLE, expr_type, StorageClass.UNIFORM);
			add_func_interface(context, id);
			context.decoration_op(DECORATE, id, Decoration.BINDING, 0);
			context.decoration_op(DECORATE, id, Decoration.DESCRIPTOR_SET, 0);
		case GET_GLOBAL_INVOCATION_ID:
			Id expr_pointer = context.type_op(TYPE_POINTER, StorageClass.INPUT, expr_type);
			Id var_id = context.type_op(VARIABLE, expr_pointer, StorageClass.INPUT);
			add_func_interface(context, var_id);
			context.decoration_op(DECORATE, var_id, Decoration.BUILTIN, Builtin.GLOBAL_INVOCATION_ID);

			id = context.func_op(LOAD, expr_type, var_id);
	}

	assert(id);
	return id;
}

fn Id emit_expression(EmissionContext* context, Expr* expression) {
	SpirvExpr* spirv_expr = context.spirv_expressions.get(expression)!!;

	Id id;
	switch(expression.expr_kind) {
		case EXPR_CALL:
			if(spirv_expr.call.is_builtin) {
				id = emit_builtin_call(context, spirv_expr);
				break;
			}
		// case EXPR_COND:
		// 	Expr*[] expressions = ast::vec(expression.cond_expr);
		// 	foreach(cond : expressions) {
		// 		emit_expression(context, cond)!;
		// 	}
		// 	return {};
		// case EXPR_BINARY:
		// 	ExprBinary* binary = &expression.binary_expr;
		// 	emit_expression(context, ast::expr_ptr(binary.left))!;
		// 	emit_expression(context, ast::expr_ptr(binary.right))!;
		// 	return {};
		// case EXPR_IDENTIFIER:
		// 	Decl* ident = expression.ident_expr;
		// 	return {};
		default: unreachable("Unsupported codegen expression: %s", ast::const_name(expression.expr_kind));
	}

	assert(id);
	return id;
}

fn void emit_declaration(EmissionContext* context, Decl* declaration) {
	SpirvDecl *spirv_decl = declaration.backend_ref;

	switch(declaration.decl_kind) {
		case DECL_VAR:
			VarDecl* var_decl = &declaration.var_field;

			Id type = type_id(context, spirv_decl.variable.type);
			Id initializer;
			if(var_decl.init_expr) {
				initializer = emit_expression(context, var_decl.init_expr);
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
		default: unreachable("Unsupported codegen declaration: %s", ast::const_name(declaration.decl_kind));
	}
}

fn void emit_statement(EmissionContext* context, Ast* statement) {
	while(statement) {
		switch(statement.ast_kind) {
			case AST_COMPOUND_STMT:
				emit_statement(context, ast::ast_ptr(statement.compound_stmt.first_stmt));
			case AST_DECLARE_STMT:
				emit_declaration(context, statement.declare_stmt);
			// case AST_IF_STMT:
			// 	AstIfStmt* specific = &statement.if_stmt;
			// 	emit_expression(context, ast::expr_ptr(specific.cond))!;
			// 	emit_statement(context, ast::ast_ptr(specific.then_body))!;
			// 	emit_statement(context, ast::ast_ptr(specific.else_body))!;
			default: unreachable("Unsupported codegen statement: %s", ast::const_name(statement.ast_kind));
		}

		statement = ast::ast_ptr(statement.next);
	}
}

fn void emit_entry_point(EmissionContext* context, SpirvEntryPoint* entry) {
	Id void_type = context.type_op(TYPE_VOID);
	Id func_type = context.type_op(TYPE_FUNCTION, void_type);

	Id func = context.func_op(FUNCTION, void_type, (uint)(FunctionControl){}, func_type);
	Id label = context.func_op(LABEL);
	Op* label_op = context.func_ops.last_op;

	emit_statement(context, ast::ast_ptr(entry.declaration.func_decl.body));

	label_op.insert_stream(&context.func_var_ops);
	context.func_op(RETURN);
	context.func_op(FUNCTION_END);

	// TODO: should probably use fully qualified name here, or have the user specify it in the attribute.
	context.init_op_raw(
		ENTRY_POINT, 
		{entry.model, func}, 
		tstr_literal(ast::c_string(entry.declaration.name)), 
		// func_interfaces are added as builtin calls are emitted.
		(uint[])context.func_interfaces.array_view()
	);

	switch(entry.model) {
		case COMPUTE:
			context.init_op(EXECUTION_MODE, func, ExecutionMode.LOCAL_SIZE, ...entry.compute.group_size);
	}

	context.func_interfaces.clear();
}

fn void emit(EmissionContext* context) {
	context.init_op(CAPABILITY, Capability.SHADER);
	context.init_op(CAPABILITY, Capability.PHYSICAL_STORAGE_BUFFER_ADDRESSES);
	context.init_op(MEMORY_MODEL, AddressingModel.PHYSICAL_STORAGE_BUFFER_64, MemoryModel.GLSL450);

	foreach(SpirvEntryPoint* entry : context.entry_points) {
		emit_entry_point(context, entry);
	}
}