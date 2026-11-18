module ardot::c3spirv::sema @local;
import ardot::c3c::ast, ardot::c3spirv;

import std::io;

fn ExprType? analyse_access(SemaContext* context, SpirvExpr* spirv_expr) {
	ExprResolvedAccess* resolved = &spirv_expr.expression.access_resolved_expr;
	SpirvExpr* parent = analyse_expression(context, resolved.parent)!;

	uint member_index;
	foreach(uint i, Decl* member : ast::vec(parent.type.ref.type.decl.strukt.members)) {
		if(member == resolved.ref) {
			member_index = i;
			break;
		}
	}

	spirv_expr.access.index = member_index;
	SpirvType* member_type = parent.type.ref.structure.members[member_index];

	// TODO: figure out a better way to express this pattern.
	ExprType type = expr_type(member_type);
	if(parent.type.ref != parent.type.real) {
		type.real = create_type_pointer(context, null, parent.type.real.pointer.class, member_type);
	}
	return type;
}

fn ExprType? analyse_binary(SemaContext* context, SpirvExpr* spirv_expr) {
	ExprBinary* binary = &spirv_expr.expression.binary_expr;
	SpirvExpr* left = analyse_expression(context, ast::expr_ptr(binary.left))!;
	SpirvExpr* right = analyse_expression(context, ast::expr_ptr(binary.right))!;

	switch(binary.operator) {
		case BINARYOP_MULT:
		case BINARYOP_SUB:
		case BINARYOP_ADD:
		case BINARYOP_DIV:
		case BINARYOP_MOD:
		case BINARYOP_SHR:
		case BINARYOP_SHL:
		case BINARYOP_BIT_OR:
		case BINARYOP_BIT_XOR:
		case BINARYOP_BIT_AND:
			return expr_deref(right.type);
		case BINARYOP_AND:
		case BINARYOP_OR:
		case BINARYOP_EQ:
		case BINARYOP_NE:
		case BINARYOP_LT:
		case BINARYOP_GT:
		case BINARYOP_LE:
		case BINARYOP_GE:
			return expr_type(create_type_primitive(context, c3spirv::bool_type));
		case BINARYOP_VEC_EQ:
		case BINARYOP_VEC_NE:
		case BINARYOP_VEC_LT:
		case BINARYOP_VEC_GT:
		case BINARYOP_VEC_LE:
		case BINARYOP_VEC_GE:
			return expr_type(analyse_type(context, spirv_expr.expression.type, spirv_expr.expression.loc, LOGICAL));
		case BINARYOP_ADD_ASSIGN:
		case BINARYOP_BIT_AND_ASSIGN:
		case BINARYOP_BIT_OR_ASSIGN:
		case BINARYOP_BIT_XOR_ASSIGN:
		case BINARYOP_DIV_ASSIGN:
		case BINARYOP_MOD_ASSIGN:
		case BINARYOP_MULT_ASSIGN:
		case BINARYOP_SHR_ASSIGN:
		case BINARYOP_SHL_ASSIGN:
		case BINARYOP_SUB_ASSIGN:
		case BINARYOP_ASSIGN: 
			analyse_assignment(context, left.type, right.type, spirv_expr.expression.loc)!;
			return expr_deref(right.type);
		default: return err::error(spirv_expr.expression.loc, "Unsupported binary op kind: %s", ast::const_name(binary.operator))~;
	}
}

fn ExprType? analyse_cond(SemaContext* context, SpirvExpr* spirv_expr) {
	Expr*[] expressions = ast::vec(spirv_expr.expression.cond_expr);
	foreach(cond : expressions[..^2]) {
		analyse_expression(context, cond)!;
	}
	return analyse_expression(context, expressions[^1]).type!;
}

fn void? analyse_const_initializer_vec(SemaContext* context, ConstInitializer** vec, SourceLocId loc) {
	foreach(ConstInitializer* member : ast::vec(vec)) {
		analyse_const_initializer(context, member, loc)!;
	}
}

fn void? analyse_const_initializer(SemaContext* context, ConstInitializer* init, SourceLocId loc) {
	switch(init.kind) {
		case CONST_INIT_ZERO: break;
		case CONST_INIT_STRUCT: analyse_const_initializer_vec(context, init.init_struct, loc)!;
		case CONST_INIT_VALUE:
			// Don't need to bother with types here, because constant stuff is guaranteed
			// to be nicely logical.
	 		analyse_expression(context, init.init_value)!;
		case CONST_INIT_ARRAY: analyse_const_initializer_vec(context, init.init_array.elements, loc)!;
		case CONST_INIT_ARRAY_FULL: analyse_const_initializer_vec(context, init.init_struct, loc)!;
		case CONST_INIT_ARRAY_VALUE: analyse_const_initializer(context, init.init_array_value.element, loc)!;
		default: return err::error(loc, "Unsupported const initializer kind: %s", ast::const_name(init.kind))~;
	}
}

fn ExprType? analyse_const(SemaContext* context, SpirvExpr* spirv_expr) {
	ExprConst* const_e = &spirv_expr.expression.const_expr;
	Type* type = spirv_expr.expression.type.canonical;

	bool truncate;
	if(context.frame.kind == INFO) {
		truncate = context.frame.info.truncate_64_bit_constants;
	}

	TypeKind kind = type.type_kind;
	switch(const_e.const_kind) {
		case CONST_FLOAT:
		case CONST_INTEGER:
			switch(kind) {
				// This is a bit cursed, but handles cases where c3c really wants to
				// use 64 bit integer constants, like in subscripts.
				case TYPE_I64:
					if(truncate) {
						type = c3spirv::int_type;
					} else {
						return err::error(spirv_expr.expression.loc, "64 bit types are not allowed in shaders.")~;
					}
				case TYPE_U64:
					if(truncate) {
						type = c3spirv::uint_type;
					} else {
						return err::error(spirv_expr.expression.loc, "64 bit types are not allowed in shaders.")~;
					}
				case TYPE_F64:
					return err::error(spirv_expr.expression.loc, "64 bit types are not allowed in shaders.")~;
				case TYPE_I128:
				case TYPE_U128:
				case TYPE_F128:
					return err::error(spirv_expr.expression.loc, "128 bit types are not allowed in shaders.")~;
				default: break;
			}
		case CONST_INITIALIZER: analyse_const_initializer(context, const_e.initializer, spirv_expr.expression.loc)!;
		default: return err::error(spirv_expr.expression.loc, "Unsupported const kind: %s", ast::const_name(const_e.const_kind))~;
	}


	// Override the type kind here in case we need to truncate it.
	return expr_type(analyse_type(context, type, spirv_expr.expression.loc, UNRESOLVED))!;
}

fn ExprType? analyse_ext_trunc(SemaContext* context, SpirvExpr* spirv_expr) {
	ExprExtTrunc* trunc = &spirv_expr.expression.ext_trunc_expr;
	return expr_type(analyse_type(context, spirv_expr.expression.type, spirv_expr.expression.loc, LOGICAL))!;
}

fn ExprType? analyse_identifier(SemaContext* context, SpirvExpr* spirv_expr) {
	SpirvDecl* declaration = spirv_expr.expression.ident_expr.backend_ref;
	return declaration.variable.type;
}

fn ExprType? analyse_macro_block(SemaContext* context, SpirvExpr* spirv_expr) {
	ExprMacroBlock* block = &spirv_expr.expression.macro_block;

	SpirvType* type = analyse_type(context, spirv_expr.expression.type, spirv_expr.expression.loc, UNRESOLVED)!;
	SemaStackFrame frame = {
		.macro_frame = {
			.block = spirv_expr,
			.return_type = type,
		}
	};

	context.@push_frame(&frame, MACRO, context.frame.label) {
		foreach(Decl* param : ast::vec(block.params)) {
			analyse_declaration(context, param)!;
		}
		analyse_statement(context, ast::ast_ptr(block.first_stmt))!;
	};

	sz return_count = spirv_expr.macro_block.returns.len();
	if(return_count > 1 && !type.can_make_variable()) {
		return err::error(spirv_expr.expression.loc, "Cannot return a logical pointer from more than one place in a macro.")~;
	}

	return expr_type(type);
}

fn ExprType? analyse_subscript(SemaContext* context, SpirvExpr* spirv_expr) {
	ExprSubscript* subscript = &spirv_expr.expression.subscript_expr;

	SpirvExpr* left = analyse_expression(context, ast::expr_ptr(subscript.expr))!;

	// c3c wants to expand all int types to 64 bit when indexing,
	// but this isn't ideal for shaders so we ignore it here.
	Expr* index_expr = ast::expr_ptr(subscript.index.expr);
	while(index_expr.expr_kind == EXPR_EXT_TRUNC) {
		index_expr = index_expr.ext_trunc_expr.inner;
	}

	SemaStackFrame frame = {
		.info = {
			.truncate_64_bit_constants = true,
		}
	};
	context.@push_frame(&frame, INFO, context.frame.label) {
		spirv_expr.subscript.index = analyse_expression(context, index_expr)!;
	};

	ExprType type;
	switch(left.type.ref.kind) {
		case TYPE_VECTOR:
			type = expr_type(left.type.ref.vector.member);
			if(left.type.ref != left.type.real) {
				type.real = create_type_pointer(context, null, left.type.real.pointer.class, type.ref);
			}
		case TYPE_POINTER: type = expr_deref(expr_type(left.type.ref));
		default: return err::error(spirv_expr.expression.loc, "Unsupported subscript type kind: %s", ast::const_name(left.type.ref.kind))~;
	}
	return type;
}

fn ExprType? analyse_unary(SemaContext* context, SpirvExpr* spirv_expr) {
	ExprUnary* unary = &spirv_expr.expression.unary_expr;
	SpirvExpr* inner = analyse_expression(context, unary.expr)!;
	switch(unary.operator) {
		case UNARYOP_DEREF: return expr_deref(inner.type);
		case UNARYOP_ADDR: return expr_addr(inner.type);
		case UNARYOP_NEG: 
		case UNARYOP_PLUS:
		case UNARYOP_BITNEG:
		case UNARYOP_NOT:
			return expr_deref(inner.type);
		// Unsupported for now because setting up the constants would be pretty complex.
		case UNARYOP_INC:
		case UNARYOP_DEC:
			nextcase default;
		case UNARYOP_TADDR:
			return expr_type(create_type_pointer(context, null, FUNCTION, inner.type.ref));
		default: return err::error(spirv_expr.expression.loc, "Unsupported unary kind: %s", ast::const_name(unary.operator))~;
	}
}

fn SpirvType*? analyse_builtin_call(SemaContext* context, SpirvExpr* spirv_expression, Expr*[] attribute_params) {
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

			SpirvType* spirv_inner = analyse_type(context, inner, expression.loc, PHYSICAL)!;
			return create_type_pointer(context, rtype, UNIFORM, spirv_inner);
		case GET_GLOBAL_INVOCATION_ID:
			return analyse_type(context, rtype, expression.loc, LOGICAL)!;
		default: return err::error(expression.loc, "Unsupported builtin.")~;
	}
}

fn ExprType? analyse_call(SemaContext* context, SpirvExpr* spirv_expr) {
	ExprCall* call = &spirv_expr.expression.call_expr;
	Decl* declaration = ast::decl_ptr(call.func_ref);

	Expr*[]? builtin_params = get_attribute(declaration, SHADER_BUILTIN);
	if(try builtin_params) {
		return expr_type(analyse_builtin_call(context, spirv_expr, builtin_params))!;
	} else {
		return err::error(spirv_expr.expression.loc, "Non-builtin calls are not currently supported.")~;
	}
}

fn SpirvExpr*? analyse_expression(SemaContext* context, Expr* expression) @public {
	SpirvExpr* spirv_expr = alloc::new(&context.global.vmem, SpirvExpr, {
		.expression = expression,
	});
	context.global.spirv_data[expression] = spirv_expr;

	ExprType type;
	switch(expression.expr_kind) {
		case EXPR_ACCESS_RESOLVED: type = analyse_access(context, spirv_expr)!;
		case EXPR_BINARY: type = analyse_binary(context, spirv_expr)!;
		case EXPR_CALL: type = analyse_call(context, spirv_expr)!;
		case EXPR_COND: type = analyse_cond(context, spirv_expr)!;
		case EXPR_CONST: type = analyse_const(context, spirv_expr)!;
		case EXPR_EXT_TRUNC: type = analyse_ext_trunc(context, spirv_expr)!;
		case EXPR_IDENTIFIER: type = analyse_identifier(context, spirv_expr)!;
		case EXPR_MACRO_BLOCK: type = analyse_macro_block(context, spirv_expr)!;
		case EXPR_SUBSCRIPT: type = analyse_subscript(context, spirv_expr)!;
		case EXPR_UNARY: type = analyse_unary(context, spirv_expr)!;
		default: return err::error(expression.loc, "Unsupported expression kind: %s", ast::const_name(expression.expr_kind))~;
	}

	assert(type.real);
	assert(type.ref);

	spirv_expr.type = type;
	return spirv_expr;
}

