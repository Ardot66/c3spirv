module ardot::c3spirv::codegen @local;
import ardot::c3spirv, ardot::c3c::ast;

fn Id emit_access(EmissionContext* context, SpirvExpr* spirv_expr) {
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

fn Id emit_binary_math(EmissionContext* context, SpirvExpr* spirv_expr, Opcode op) {
	ExprBinary* binary = &spirv_expr.expression.binary_expr;
	SpirvExpr* left = emit_expression(context, ast::expr_ptr(binary.left));
	SpirvExpr* right = emit_expression(context, ast::expr_ptr(binary.right));
	return context.func_op(
		op, 
		type_id(context, spirv_expr.type.ref), 
		expr_value(context, left), 
		expr_value(context, right
	));
}

fn Id emit_binary_assign(EmissionContext* context, SpirvExpr* spirv_expr) {
	ExprBinary* binary = &spirv_expr.expression.binary_expr;
	SpirvExpr* left = emit_expression(context, ast::expr_ptr(binary.left));
	SpirvExpr* right = emit_expression(context, ast::expr_ptr(binary.right));
	context.func_op(STORE, left.id, expr_value(context, right), (uint)(MemoryOperands){.aligned}, 4);
	return right.id;
}

fn Id emit_binary(EmissionContext* context, SpirvExpr* spirv_expr) {
	ExprBinary* binary = &spirv_expr.expression.binary_expr;

	// Will need to specialize this to handle signed, unsigned, and floats.
	switch(binary.operator) {
		case BINARYOP_LT: return emit_binary_math(context, spirv_expr, U_LESS_THAN);
		case BINARYOP_MULT: return emit_binary_math(context, spirv_expr, F_MUL);
		case BINARYOP_ASSIGN: return emit_binary_assign(context, spirv_expr);
		default: unreachable("Unsupported binary op kind: %s", ast::const_name(binary.operator));
	}
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

fn Id emit_call(EmissionContext* context, SpirvExpr* spirv_expr) {
	if(spirv_expr.call.is_builtin) {
		return emit_builtin_call(context, spirv_expr);
	}
	unreachable();
}

fn Id emit_cond(EmissionContext* context, SpirvExpr* spirv_expr) {
	Expr*[] expressions = ast::vec(spirv_expr.expression.cond_expr);
	foreach(cond : expressions[..^2]) {
		emit_expression(context, cond);
	}
	return emit_expression(context, expressions[^1]).id;
}

fn Id emit_const(EmissionContext* context, SpirvExpr* spirv_expr) {
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

fn Id emit_trunc(EmissionContext* context, SpirvExpr* spirv_expr) {
	ExprExtTrunc* trunc = &spirv_expr.expression.ext_trunc_expr;
	return emit_expression(context, trunc.inner).id;
	// if(inner.type.ref == spirv_expr.type.ref) {
	// 	id = expr_value(context, inner);
	// } else {
	// 	Opcode op = trunc.is_signed ? S_CONVERT : U_CONVERT;
	// 	id = context.func_op(op, type_id(context, spirv_expr.type.ref), expr_value(context, inner));
	// }
}

fn Id emit_identifier(EmissionContext* context, SpirvExpr* spirv_expr) {
	SpirvDecl* spirv_decl = spirv_expr.expression.ident_expr.backend_ref;
	return spirv_decl.variable.id;
}

fn Id emit_subscript(EmissionContext* context, SpirvExpr* spirv_expr) {
	ExprSubscript* subscript = &spirv_expr.expression.subscript_expr;

	SpirvExpr* left = emit_expression(context, ast::expr_ptr(subscript.expr));
	SpirvExpr* right = emit_expression(context, ast::expr_ptr(subscript.index.expr));

	switch(left.type.ref.type.type_kind) {
		case TYPE_VECTOR:
			if(left.type.ref != left.type.real) {
				return context.func_op(ACCESS_CHAIN, type_id(context, spirv_expr.type.real), left.id, expr_value(context, right));
			} else {
				return context.func_op(VECTOR_EXTRACT_DYNAMIC, type_id(context, spirv_expr.type.real), left.id, expr_value(context, right));
			}
		case TYPE_POINTER: 
			return context.func_op(PTR_ACCESS_CHAIN, type_id(context, spirv_expr.type.real), expr_value(context, left), expr_value(context, right));
		default: unreachable("Unsupported subscript kind: %s", ast::const_name(left.type.ref.type.type_kind));
	}
}

fn Id emit_unary(EmissionContext* context, SpirvExpr* spirv_expr) {
	ExprUnary* unary = &spirv_expr.expression.unary_expr;
	SpirvExpr* inner = emit_expression(context, unary.expr);
	switch(unary.operator) {
		case UNARYOP_DEREF: return expr_value(context, inner);
		default: unreachable("Unsupported unary kind: %s", ast::const_name(unary.operator));
	}
}

fn SpirvExpr* emit_expression(EmissionContext* context, Expr* expression) @public {
	SpirvExpr* spirv_expr = context.spirv_expressions.get(expression)!!;

	Id id;
	switch(expression.expr_kind) {
		case EXPR_ACCESS_RESOLVED: id = emit_access(context, spirv_expr);
		case EXPR_BINARY: id = emit_binary(context, spirv_expr);
		case EXPR_CALL: id = emit_call(context, spirv_expr);
		case EXPR_COND: id = emit_cond(context, spirv_expr);
		case EXPR_CONST: id = emit_const(context, spirv_expr);
		case EXPR_EXT_TRUNC: id = emit_trunc(context, spirv_expr);
		case EXPR_IDENTIFIER: id = emit_identifier(context, spirv_expr);
		case EXPR_SUBSCRIPT: id = emit_subscript(context, spirv_expr);
		case EXPR_UNARY: id = emit_unary(context, spirv_expr);
		default: unreachable("Unsupported codegen expression: %s", ast::const_name(expression.expr_kind));
	}

	assert(id);
	spirv_expr.id = id;
	return spirv_expr;
}