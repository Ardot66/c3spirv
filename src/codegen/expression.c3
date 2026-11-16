module ardot::c3spirv::codegen @local;
import ardot::c3spirv, ardot::c3c::ast;

import std::io;

fn Id emit_access(GenContext* context, SpirvExpr* spirv_expr) {
	ExprResolvedAccess* resolved = &spirv_expr.expression.access_resolved_expr;
	SpirvExpr* parent = emit_expression(context, resolved.parent);

	uint index = spirv_expr.access.index;

	Id result_type = type_id(context, spirv_expr.type.real);
	if(parent.type.ref != parent.type.real) {
		Id index_type = context.type_op(TYPE_INT, 32, 0);
		Id index_id = context.type_op(CONSTANT, index_type, index);
		return context.func_op(ACCESS_CHAIN, result_type, parent.id, index_id);
	} else {
		return context.func_op(COMPOSITE_EXTRACT, result_type, parent.id, index);
	}
}

fn Id emit_binary_assign(GenContext* context, SpirvExpr* spirv_expr) {
	ExprBinary* binary = &spirv_expr.expression.binary_expr;
	SpirvExpr* left = emit_expression(context, ast::expr_ptr(binary.left));
	SpirvExpr* right = emit_expression(context, ast::expr_ptr(binary.right));
	context.func_op(STORE, left.id, expr_value(context, right), (uint)(MemoryOperands){.aligned}, 4);
	return right.id;
}

fn Opcode num_op(TypeKind kind, Opcode floating, Opcode unsigned, Opcode signed = INVALID) {
	if(kind >= TYPE_FLOAT_FIRST && kind <= TYPE_FLOAT_LAST) {
		return floating;
	} else if(kind >= TYPE_UINT_FIRST && kind <= TYPE_UINT_LAST) {
		return unsigned;
	} else if(kind >= TYPE_INT_FIRST && kind <= TYPE_INT_LAST) {
		if(signed == INVALID) {
			return unsigned;
		}
		return signed;
	}

	unreachable();
}

enum BinaryMode {
	START,
	MATH,
	ASSIGN,
}

fn Id emit_binary(GenContext* context, SpirvExpr* spirv_expr) {
	ExprBinary* binary = &spirv_expr.expression.binary_expr;

	SpirvExpr* right = emit_expression(context, ast::expr_ptr(binary.right));
	SpirvExpr* left = emit_expression(context, ast::expr_ptr(binary.left));

	TypeKind kind = right.type.ref.kind;
	Opcode op;
	bool assign;
	Id id;
	switch OUTER: (BinaryMode.START) {
		case START:
			switch(binary.operator) {
				case BINARYOP_MULT: op = num_op(kind, F_MUL, I_MUL); nextcase OUTER:MATH;
				case BINARYOP_SUB: op = num_op(kind, F_SUB, I_SUB); nextcase OUTER:MATH;
				case BINARYOP_ADD: op = num_op(kind, F_ADD, I_ADD); nextcase OUTER:MATH;
				case BINARYOP_DIV: op = num_op(kind, F_DIV, U_DIV, S_DIV); nextcase OUTER:MATH;
				case BINARYOP_MOD: op = num_op(kind, F_MOD, U_MOD, S_MOD); nextcase OUTER:MATH;
				case BINARYOP_SHR: op = num_op(kind, INVALID, SHIFT_RIGHT_LOGICAL); nextcase OUTER:MATH;
				case BINARYOP_SHL: op = num_op(kind, INVALID, SHIFT_LEFT_LOGICAL); nextcase OUTER:MATH;
				case BINARYOP_BIT_OR: op = num_op(kind, INVALID, BITWISE_OR); nextcase OUTER:MATH;
				case BINARYOP_BIT_XOR: op = num_op(kind, INVALID, BITWISE_XOR); nextcase OUTER:MATH;
				case BINARYOP_BIT_AND: op = num_op(kind, INVALID, BITWISE_AND); nextcase OUTER:MATH;
				case BINARYOP_AND: op = num_op(kind, INVALID, LOGICAL_AND); nextcase OUTER:MATH;
				case BINARYOP_OR: op = num_op(kind, INVALID, LOGICAL_OR); nextcase OUTER:MATH;
				case BINARYOP_EQ: op = num_op(kind, F_UNORD_EQUAL, I_EQUAL); nextcase OUTER:MATH;
				case BINARYOP_NE: op = num_op(kind, F_UNORD_NOT_EQUAL, I_NOT_EQUAL); nextcase OUTER:MATH;
				case BINARYOP_LT: op = num_op(kind, F_UNORD_LESS_THAN, U_LESS_THAN, S_LESS_THAN); nextcase OUTER:MATH;
				case BINARYOP_GT: op = num_op(kind, F_UNORD_GREATER_THAN, U_GREATER_THAN, S_GREATER_THAN); nextcase OUTER:MATH;
				case BINARYOP_LE: op = num_op(kind, F_UNORD_LESS_THAN_EQUAL, U_LESS_THAN_EQUAL, S_LESS_THAN_EQUAL); nextcase OUTER:MATH;
				case BINARYOP_GE: op = num_op(kind, F_UNORD_GREATER_THAN_EQUAL, U_GREATER_THAN_EQUAL, S_GREATER_THAN_EQUAL); nextcase OUTER:MATH;

				case BINARYOP_VEC_EQ: op = num_op(kind, F_UNORD_EQUAL, I_EQUAL); nextcase OUTER:MATH;
				case BINARYOP_VEC_NE: op = num_op(kind, F_UNORD_NOT_EQUAL, I_NOT_EQUAL); nextcase OUTER:MATH;
				case BINARYOP_VEC_LT: op = num_op(kind, F_UNORD_LESS_THAN, U_LESS_THAN, S_LESS_THAN); nextcase OUTER:MATH;
				case BINARYOP_VEC_GT: op = num_op(kind, F_UNORD_GREATER_THAN, U_GREATER_THAN, S_GREATER_THAN); nextcase OUTER:MATH;
				case BINARYOP_VEC_LE: op = num_op(kind, F_UNORD_LESS_THAN_EQUAL, U_LESS_THAN_EQUAL, S_LESS_THAN_EQUAL); nextcase OUTER:MATH;
				case BINARYOP_VEC_GE: op = num_op(kind, F_UNORD_GREATER_THAN_EQUAL, U_GREATER_THAN_EQUAL, S_GREATER_THAN_EQUAL); nextcase OUTER:MATH;

				case BINARYOP_ADD_ASSIGN: assign = true; nextcase BINARYOP_ADD;
				case BINARYOP_BIT_AND_ASSIGN: assign = true; nextcase BINARYOP_BIT_AND;
				case BINARYOP_BIT_OR_ASSIGN: assign = true; nextcase BINARYOP_BIT_OR;
				case BINARYOP_BIT_XOR_ASSIGN: assign = true; nextcase BINARYOP_BIT_XOR;
				case BINARYOP_DIV_ASSIGN: assign = true; nextcase BINARYOP_DIV;
				case BINARYOP_MOD_ASSIGN: assign = true; nextcase BINARYOP_MOD;
				case BINARYOP_MULT_ASSIGN: assign = true; nextcase BINARYOP_MULT;
				case BINARYOP_SHR_ASSIGN: assign = true; nextcase BINARYOP_SHR;
				case BINARYOP_SHL_ASSIGN: assign = true; nextcase BINARYOP_SHL;
				case BINARYOP_SUB_ASSIGN: assign = true; nextcase BINARYOP_SUB;

				case BINARYOP_ASSIGN: 
					id = expr_value(context, right);
					nextcase OUTER:ASSIGN;
				default: unreachable("Unsupported binary op kind: %s", ast::const_name(binary.operator));
			}
		case MATH:	
			id = context.func_op(
				op, 
				type_id(context, spirv_expr.type.ref), 
				expr_value(context, left), 
				expr_value(context, right
			));
			if(assign) {
				nextcase ASSIGN;
			}
		case ASSIGN:
			context.func_op(STORE, left.id, id, (uint)(MemoryOperands){.aligned}, 4);
	}

	return id;
}

fn void add_func_interface(GenContext* context, Id interface_id) {
	if(!context.func_interfaces.contains(interface_id)) {
		context.func_interfaces.push(interface_id);
	}
}

fn Id emit_builtin_call(GenContext* context, SpirvExpr* spirv_expr) {
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

fn Id emit_call(GenContext* context, SpirvExpr* spirv_expr) {
	if(spirv_expr.call.is_builtin) {
		return emit_builtin_call(context, spirv_expr);
	}
	unreachable();
}

fn Id emit_cond(GenContext* context, SpirvExpr* spirv_expr) {
	Expr*[] expressions = ast::vec(spirv_expr.expression.cond_expr);
	foreach(cond : expressions[..^2]) {
		emit_expression(context, cond);
	}
	return emit_expression(context, expressions[^1]).id;
}

fn Id emit_const(GenContext* context, SpirvExpr* spirv_expr) {
	ExprConst* const_expr = &spirv_expr.expression.const_expr;
	Id type = type_id(context, spirv_expr.type.ref);
	switch(const_expr.const_kind) {
		case CONST_FLOAT:
			return context.type_op(CONSTANT, type, bitcast((float)const_expr.fxx.f, uint));
		case CONST_INTEGER:
			return context.type_op(CONSTANT, type, (uint)const_expr.ixx.i.low);
		case CONST_BOOL:
			Opcode op = const_expr.b ? CONSTANT_TRUE : CONSTANT_FALSE;
			return context.type_op(op);
		default: unreachable("Unsupported codegen const %s", ast::const_name(const_expr.const_kind));
	}
}

fn Id emit_trunc(GenContext* context, SpirvExpr* spirv_expr) {
	ExprExtTrunc* trunc = &spirv_expr.expression.ext_trunc_expr;
	SpirvExpr* inner = emit_expression(context, trunc.inner);
	if(inner.type.ref == spirv_expr.type.ref) {
		return expr_value(context, inner);
	} else {
		Opcode op = trunc.is_signed ? S_CONVERT : U_CONVERT;
		return context.func_op(op, type_id(context, spirv_expr.type.ref), expr_value(context, inner));
	}
}

fn Id emit_identifier(GenContext* context, SpirvExpr* spirv_expr) {
	SpirvDecl* spirv_decl = spirv_expr.expression.ident_expr.backend_ref;
	return spirv_decl.variable.id;
}

fn Id emit_macro_block(GenContext* context, SpirvExpr* spirv_expr) {
	ExprMacroBlock* block = &spirv_expr.expression.macro_block;

	OpStream return_stream;
	@push_stream(context, &return_stream) {
		spirv_expr.macro_block.return_label = context.func_op(LABEL);
	};

	foreach(Decl* param : ast::vec(block.params)) {
		emit_declaration(context, param);
	}

	emit_statement(context, ast::ast_ptr(block.first_stmt));

	// This marks the return block where all control flow will reconverge.
	context.func_op(BRANCH, spirv_expr.macro_block.return_label);
	append_stream(context, &return_stream);

	SpirvType* rtype = spirv_expr.type.ref;
	if(rtype.kind == TYPE_VOID)	{
		// No need to return anything in this case.
		return {};
	} else {
		sz return_count = spirv_expr.macro_block.returns.len();
		if(return_count == 1) {
			return spirv_expr.macro_block.returns.first.block_return.value;
		}

		@pool() {
			uint[] params = mem::talloc_array(uint, return_count * 2);
			sz i = 0;
			spirv_expr.macro_block.returns.@enumerate(; SpirvAst* return_stmt) {
				params[i] = return_stmt.block_return.value;
				params[i + 1] = *return_stmt.block_return.label;
				i += 2;
			};

			return context.func_op_raw(PHI, {type_id(context, rtype)}, params);
		};
	}
}

fn Id emit_subscript(GenContext* context, SpirvExpr* spirv_expr) {
	ExprSubscript* subscript = &spirv_expr.expression.subscript_expr;

	SpirvExpr* left = emit_expression(context, ast::expr_ptr(subscript.expr));
	SpirvExpr* index = emit_spirv_expression(context, spirv_expr.subscript.index);

	switch(left.type.ref.type.type_kind) {
		case TYPE_VECTOR:
			if(left.type.ref != left.type.real) {
				return context.func_op(ACCESS_CHAIN, type_id(context, spirv_expr.type.real), left.id, expr_value(context, index));
			} else {
				return context.func_op(VECTOR_EXTRACT_DYNAMIC, type_id(context, spirv_expr.type.real), left.id, expr_value(context, index));
			}
		case TYPE_POINTER: 
			return context.func_op(PTR_ACCESS_CHAIN, type_id(context, spirv_expr.type.real), expr_value(context, left), expr_value(context, index));
		default: unreachable("Unsupported subscript kind: %s", ast::const_name(left.type.ref.type.type_kind));
	}
}

fn Id emit_unary(GenContext* context, SpirvExpr* spirv_expr) {
	ExprUnary* unary = &spirv_expr.expression.unary_expr;
	SpirvExpr* inner = emit_expression(context, unary.expr);
	TypeKind kind = inner.type.ref.kind;
	switch(unary.operator) {
		case UNARYOP_DEREF: return expr_value(context, inner);
		case UNARYOP_ADDR: return inner.id;
		case UNARYOP_NEG: return context.func_op(num_op(kind, F_NEGATE, S_NEGATE), expr_value(context, inner));
		case UNARYOP_PLUS: return expr_value(context, inner);
		case UNARYOP_BITNEG: return context.func_op(BITWISE_NOT, expr_value(context, inner));
		case UNARYOP_NOT: return context.func_op(LOGICAL_NOT, expr_value(context, inner));
		// Will support these later, for now they're a bit complex.
		// case UNARYOP_INC:
		// case UNARYOP_DEC:
		case UNARYOP_TADDR:
			return context.func_var_op(
				VARIABLE, 
				type_id(context, inner.type.real), 
				StorageClass.FUNCTION, 
				expr_value(context, inner
			));
		default: unreachable("Unsupported unary kind: %s", ast::const_name(unary.operator));
	}
}

fn SpirvExpr* emit_spirv_expression(GenContext* context, SpirvExpr* spirv_expr) @public {
	Id id;
	switch(spirv_expr.expression.expr_kind) {
		case EXPR_ACCESS_RESOLVED: id = emit_access(context, spirv_expr);
		case EXPR_BINARY: id = emit_binary(context, spirv_expr);
		case EXPR_CALL: id = emit_call(context, spirv_expr);
		case EXPR_COND: id = emit_cond(context, spirv_expr);
		case EXPR_CONST: id = emit_const(context, spirv_expr);
		case EXPR_EXT_TRUNC: id = emit_trunc(context, spirv_expr);
		case EXPR_IDENTIFIER: id = emit_identifier(context, spirv_expr);
		case EXPR_MACRO_BLOCK: id = emit_macro_block(context, spirv_expr);
		case EXPR_SUBSCRIPT: id = emit_subscript(context, spirv_expr);
		case EXPR_UNARY: id = emit_unary(context, spirv_expr);
		default: unreachable("Unsupported codegen expression: %s", ast::const_name(spirv_expr.expression.expr_kind));
	}

	// assert(id);
	spirv_expr.id = id;
	return spirv_expr;
}

fn SpirvExpr* emit_expression(GenContext* context, Expr* expression) @public {
	return emit_spirv_expression(context, context.global.spirv_expressions.get(expression))!!;
}