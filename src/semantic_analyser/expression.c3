module ardot::c3spirv::sema;
import ardot::c3c::ast, ardot::c3spirv;

fn SpirvType*? analyse_builtin_call(EmissionContext* context, SpirvExpr* spirv_expression, Expr*[] attribute_params) {
	Expr* expression = spirv_expression.expression;
	ExprCall* call = &expression.call_expr;
	ShaderBuiltin builtin = (ShaderBuiltin)eval_const_enum(attribute_params[0]);
	Type* rtype = expression.type;

	spirv_expression.call = {
		.is_builtin = true,
		.builtin = builtin,
	};

	switch(builtin) {
		case GET_ROOT:
			Type* inner = rtype.pointer;
			if(inner.type_kind != TYPE_STRUCT) {
				return err::error(expression.loc, "The root type must be a struct.")~;
			}

			SpirvType* spirv_inner = analyse_physical_type(context, inner, expression.loc)!;
			return create_type_pointer(context, rtype, UNIFORM, spirv_inner);
		case GET_GLOBAL_INVOCATION_ID:
			return analyse_logical_type(context, rtype, expression.loc)!;
		default: return err::error(expression.loc, "Unsupported builtin.")~;
	}
}

fn SpirvExpr*? analyse_expression(EmissionContext* context, Expr* expression, bool allow_null = false) {
	SpirvExpr* spirv_expression = alloc::new(&context.vmem, SpirvExpr, {
		.expression = expression,
	});
	context.spirv_expressions[expression] = spirv_expression;

	ExprType type;
	switch(expression.expr_kind) {
		case EXPR_ACCESS_RESOLVED:
			ExprResolvedAccess* resolved = &expression.access_resolved_expr;
			SpirvExpr* parent = analyse_expression(context, resolved.parent)!;

			uint member_index;
			foreach(uint i, Decl* member : ast::vec(parent.type.ref.type.decl.strukt.members)) {
				if(member == resolved.ref) {
					member_index = i;
					break;
				}
			}

			spirv_expression.access.index = member_index;

			SpirvType* member_type = parent.type.ref.structure.members[member_index];
			type.ref = member_type;
			if(parent.type.ref != parent.type.real) {
				type.real = create_type_pointer(context, null, parent.type.real.pointer.class, member_type);
			} else {
				type.real = member_type;
			}
		case EXPR_BINARY:
			ExprBinary* binary = &expression.binary_expr;
			analyse_expression(context, ast::expr_ptr(binary.left), true)!;
			SpirvExpr* right = analyse_expression(context, ast::expr_ptr(binary.right), true)!;
			switch(binary.operator) {
				case BINARYOP_GT:
				case BINARYOP_GE:
				case BINARYOP_LT:
				case BINARYOP_LE:
				case BINARYOP_NE:
				case BINARYOP_EQ:
					type = expr_type(create_type_primitive(context, c3spirv::bool_type));
				default: type = expr_deref(right.type);
			}
		case EXPR_CALL:
			ExprCall* call = &expression.call_expr;
			Decl* declaration = ast::decl_ptr(call.func_ref);

			Expr*[]? builtin_params = get_attribute(declaration, SHADER_BUILTIN);
			if(try builtin_params) {
				type = expr_type(analyse_builtin_call(context, spirv_expression, builtin_params))!;
			} else {
				return err::error(expression.loc, "Non-builtin calls are not currently supported.")~;
			}
		case EXPR_COND:
			Expr*[] expressions = ast::vec(expression.cond_expr);
			foreach(cond : expressions[..^2]) {
				analyse_expression(context, cond)!;
			}
			type = analyse_expression(context, expressions[^1]).type!;
		case EXPR_CONST:
			type = expr_type(analyse_logical_type(context, expression.type, expression.loc))!;
		case EXPR_EXT_TRUNC:
			ExprExtTrunc* trunc = &expression.ext_trunc_expr;
			type = analyse_expression(context, trunc.inner).type!;
			// type = expr_type(analyse_logical_type(context, expression.type, expression.loc))!;
		case EXPR_IDENTIFIER:
			SpirvDecl* declaration = expression.ident_expr.backend_ref;
			type = {
				.real = declaration.variable.real_type,
				.ref = declaration.variable.type
			};
		case EXPR_SUBSCRIPT:
			ExprSubscript* subscript = &expression.subscript_expr;

			SpirvExpr* expr = analyse_expression(context, ast::expr_ptr(subscript.expr))!;
			analyse_expression(context, ast::expr_ptr(subscript.index.expr))!;

			SpirvType* result;
			switch(expr.type.ref.type.type_kind) {
				case TYPE_VECTOR:
					type = expr_type(expr.type.ref.vector.member);
					if(expr.type.ref != expr.type.real) {
						type.real = create_type_pointer(context, null, expr.type.real.pointer.class, type.ref);
					}
				case TYPE_POINTER: type = expr_deref(expr_type(expr.type.ref));
				default: return err::error(expression.loc, "Unsupported subscript type kind: %s", ast::const_name(expr.type.ref.type.type_kind))~;
			}
		case EXPR_UNARY:
			ExprUnary* unary = &expression.unary_expr;
			SpirvExpr* inner = analyse_expression(context, unary.expr)!;
			switch(unary.operator) {
				case UNARYOP_DEREF:
					type = expr_deref(inner.type);
				default: 
					return err::error(expression.loc, "Unsupported unary kind: %s", ast::const_name(unary.operator))~;
			}
		default: return err::error(expression.loc, "Unsupported expression kind: %s", ast::const_name(expression.expr_kind))~;
	}

	if(!allow_null) {
		assert(type.real);
		assert(type.ref);
	}

	spirv_expression.type = type;
	return spirv_expression;
}

