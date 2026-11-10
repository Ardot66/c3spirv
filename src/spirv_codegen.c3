module ardot::c3spirv::codegen;
import ardot::c3spirv, ardot::c3c::ast;

import std::io;

fn Id pointer_type_id(EmissionContext* context, SpirvType* type) {
	SpirvType* inner = type.pointer.inner;
	Id inner_id = type_id(context, inner);
	return context.type_op(TYPE_POINTER, type.pointer.class, inner_id);
}

fn Id type_id(EmissionContext* context, SpirvType* type) {
	if(type.id) {
		return type.id;
	} else if(!type.type) {
		return pointer_type_id(context, type);
	}

	Id id;
	switch(type.type.type_kind) {
		case TYPE_VOID: id = context.type_op(TYPE_VOID);
		case TYPE_BOOL: id = context.type_op(TYPE_BOOL);
		case TYPE_I8: id = context.type_op(TYPE_INT, 8, 1);
		case TYPE_I16: id = context.type_op(TYPE_INT, 16, 1);
		case TYPE_I32: id = context.type_op(TYPE_INT, 32, 1);
		case TYPE_I64: id = context.type_op(TYPE_INT, 32, 1);
		// case TYPE_I64: id = context.type_op(TYPE_INT, 64, 1); // Limiting 64 bit constants for now.
		// case TYPE_I128: // unsupported for now.
		case TYPE_U8: id = context.type_op(TYPE_INT, 8, 0);
		case TYPE_U16: id = context.type_op(TYPE_INT, 16, 0);
		case TYPE_U32: id = context.type_op(TYPE_INT, 32, 0);
		case TYPE_U64: id = context.type_op(TYPE_INT, 32, 0);
		// case TYPE_U64: id = context.type_op(TYPE_INT, 64, 0); // Limiting 64 bit constants for now.
		// case TYPE_U128: // unsupported for now.
		case TYPE_F16: id = context.type_op(TYPE_FLOAT, 16);
		// case TYPE_BF16: // unsupported for now.
		case TYPE_F32: id = context.type_op(TYPE_FLOAT, 32);
		case TYPE_F64: id = context.type_op(TYPE_FLOAT, 64);
		// case TYPE_F128: // unsupported for now.

		case TYPE_POINTER: id = pointer_type_id(context, type);
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
	Id expr_type = type_id(context, spirv_expr.type.ref);

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

// fn Id emit_variable_load(EmissionContext* context, SpirvDecl* spirv_decl) {
// 	assert(spirv_decl.declaration.decl_kind == DECL_VAR);
// 	if(spirv_decl.variable.writeable) {
// 		return context.func_op(LOAD, type_id(context, spirv_decl.variable.type), spirv_decl.variable.id);
// 	} else {
// 		return spirv_decl.variable.id;
// 	}
// }

fn SpirvExpr* emit_expression(EmissionContext* context, Expr* expression) {
	SpirvExpr* spirv_expr = context.spirv_expressions.get(expression)!!;

	Id id;
	switch(expression.expr_kind) {
		case EXPR_ACCESS_RESOLVED:
			ExprResolvedAccess* resolved = &expression.access_resolved_expr;
			SpirvExpr* parent = emit_expression(context, resolved.parent);

			uint index = spirv_expr.access.index;

			Id result_type = type_id(context, spirv_expr.type.real);
			if(parent.type.ref != parent.type.real) {
				Id index_type = context.type_op(TYPE_INT, 32, 0);
				Id index_id = context.type_op(CONSTANT, index_type, index);
				id = context.func_op(ACCESS_CHAIN, result_type, parent.id, index_id);
			} else {
				id = context.func_op(COMPOSITE_EXTRACT, result_type, parent.id, index);
			}
		case EXPR_BINARY:
			ExprBinary* binary = &expression.binary_expr;
			Opcode op;
			// Will need to specialize this to handle signed, unsigned, and floats.
			switch(binary.operator) {
				case BINARYOP_LT: op = U_LESS_THAN;
				default: unreachable("Unsupported binary op kind: %s", ast::const_name(binary.operator));
			}
			SpirvExpr* left = emit_expression(context, ast::expr_ptr(binary.left));
			SpirvExpr* right = emit_expression(context, ast::expr_ptr(binary.right));
			id = context.func_op(op, type_id(context, spirv_expr.type.ref), expr_value(context, left), expr_value(context, right));
		case EXPR_CALL:
			if(spirv_expr.call.is_builtin) {
				id = emit_builtin_call(context, spirv_expr);
				break;
			}
		case EXPR_COND:
			Expr*[] expressions = ast::vec(expression.cond_expr);
			foreach(cond : expressions[..^2]) {
				emit_expression(context, cond);
			}
			id = emit_expression(context, expressions[^1]).id;
		case EXPR_CONST:
			ExprConst* const_expr = &expression.const_expr;
			Id type = type_id(context, spirv_expr.type.ref);
			switch(const_expr.const_kind) {
				case CONST_FLOAT:
					id = context.type_op(CONSTANT, type, bitcast((float)const_expr.fxx.f, uint));
				case CONST_INTEGER:
					id = context.type_op(CONSTANT, type, (uint)const_expr.ixx.i.low);
				case CONST_BOOL:
					Opcode op = const_expr.b ? CONSTANT_TRUE : CONSTANT_FALSE;
					id = context.type_op(op);
				default: unreachable("Unsupported codegen const %s", ast::const_name(const_expr.const_kind));
			}
		case EXPR_IDENTIFIER:
			SpirvDecl* spirv_decl = expression.ident_expr.backend_ref;
			id = spirv_decl.variable.id;
		case EXPR_SUBSCRIPT:
			ExprSubscript* subscript = &expression.subscript_expr;

			SpirvExpr* left = emit_expression(context, ast::expr_ptr(subscript.expr));
			SpirvExpr* right = emit_expression(context, ast::expr_ptr(subscript.index.expr));

			switch(left.type.ref.type.type_kind) {
				case TYPE_VECTOR:
					if(left.type.ref != left.type.real) {
						id = context.func_op(ACCESS_CHAIN, type_id(context, spirv_expr.type.real), left.id, right.id);
					} else {
						id = context.func_op(VECTOR_EXTRACT_DYNAMIC, type_id(context, spirv_expr.type.real), left.id, right.id);
					}
				// case TYPE_POINTER: return left.pointer.inner;
				default: unreachable("Unsupported subscript kind: %s", ast::const_name(left.type.ref.type.type_kind));
			}
		case EXPR_UNARY:
			ExprUnary* unary = &expression.unary_expr;
			SpirvExpr* inner = emit_expression(context, unary.expr);
			switch(unary.operator) {
				case UNARYOP_DEREF:
					id = expr_value(context, inner);
				default: unreachable("Unsupported unary kind: %s", ast::const_name(unary.operator));
			}
		default: unreachable("Unsupported codegen expression: %s", ast::const_name(expression.expr_kind));
	}

	assert(id);
	spirv_expr.id = id;
	return spirv_expr;
}

fn Id expr_value(EmissionContext* context, SpirvExpr* expression) {
	if(expression.type.ref != expression.type.real) {
		return context.func_op(LOAD, type_id(context, expression.type.ref), expression.id);
	} else {
		return expression.id;
	}
}

fn void emit_declaration(EmissionContext* context, Decl* declaration) {
	SpirvDecl *spirv_decl = declaration.backend_ref;

	switch(declaration.decl_kind) {
		case DECL_VAR:
			VarDecl* var_decl = &declaration.var_field;

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
		default: unreachable("Unsupported codegen declaration: %s", ast::const_name(declaration.decl_kind));
	}
}

// Pushes an OpStream into the context's func_ops variable for the duration of the body.
macro void @push_stream(EmissionContext* context, OpStream* stream; @body) {
	OpStream* old_stream = context.func_ops;
	context.func_ops = stream;
	@body();
	context.func_ops = old_stream;
}

fn void emit_statement(EmissionContext* context, Ast* statement) {
	while(statement) {
		switch(statement.ast_kind) {
			case AST_COMPOUND_STMT:
				emit_statement(context, ast::ast_ptr(statement.compound_stmt.first_stmt));
			case AST_DECLARE_STMT:
				emit_declaration(context, statement.declare_stmt);
			case AST_EXPR_STMT:
				emit_expression(context, statement.expr_stmt);
			case AST_IF_STMT:
				AstIfStmt* if_statement = &statement.if_stmt;
				SpirvExpr* condition = emit_expression(context, ast::expr_ptr(if_statement.cond));

				assert(!if_statement.else_body);

				OpStream merge_stream;
				Id merge_label;
				@push_stream(context, &merge_stream) {
					merge_label = context.func_op(LABEL);
				};

				OpStream then_stream;
				Id then_label;
				@push_stream(context, &then_stream) {
					then_label = context.func_op(LABEL);
					emit_statement(context, ast::ast_ptr(if_statement.then_body));
					context.func_op(BRANCH, merge_label);
				};

				context.func_op(SELECTION_MERGE, merge_label, SelectionControl.NONE);
				context.func_op(BRANCH_CONDITIONAL, expr_value(context, condition), then_label, merge_label);

				append_stream(context, &then_stream);
				append_stream(context, &merge_stream);
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

	OpStream body;
	@push_stream(context, &body) {
		emit_statement(context, ast::ast_ptr(entry.declaration.func_decl.body));
	};

	// Need to have all variable ops at the start of the function.
	append_stream(context, &context.func_var_ops);
	append_stream(context, &body);

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