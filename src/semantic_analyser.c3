module ardot::c3spirv::sema;
import ardot::c3c::ast, ardot::c3spirv;
import std::collections::list;

import std::io;

fn SpirvType* create_type(EmissionContext* context, SpirvType* type) {
	SpirvType*? existing = context.types[c3spirv::byte_view(type, SpirvType::size)];
	if(try existing) {
		return existing;
	}

	SpirvType* new = alloc::alloc(&context.vmem, SpirvType);
	mem::copy(new, type, SpirvType::size);
	return new;
}

fn SpirvType* create_type_primitive(EmissionContext* context, Type* type) {
	return create_type(context, &&{
		.type = type
	});
}

fn SpirvType* create_type_struct(EmissionContext* context, Type* type, SpirvType*[] members) {
	SpirvType struct_type = {
		.type = type,
		.structure = {
			.members = alloc::alloc_array(&context.vmem, SpirvType*, members.len),
		}
	};
	mem::copy(struct_type.structure.members, members, members.len * SpirvType*::size);
	return create_type(context, &struct_type);
}

fn SpirvType* create_type_vector(EmissionContext* context, Type* type, SpirvType* member, int length) {
	return create_type(context, &&{
		.type = type,
		.vector = {
			.member = member,
			.length = length,
		}
	});
}

fn SpirvType* create_type_pointer(EmissionContext* context, Type* type, StorageClass class, SpirvType* inner) {
	return create_type(context, &&{
		.type = type,
		.pointer = {
			.class = class,
			.inner = inner,
		}
	});
}

fn Expr*[] eval_untyped_list(Expr *expr) {
	ExprConst* const_values = &expr.const_expr;
	assert(const_values.const_kind == CONST_UNTYPED_LIST);

	Expr** values = const_values.untyped_list;
	return ast::vec(values);
}

fn long eval_const_enum(Expr* expr) {
	ExprConst* enum_const = &expr.const_expr;
	assert(enum_const.const_kind == CONST_ENUM);

	EnumConstantDecl* enum_decl = &enum_const.enum_val.enum_constant;
	assert(!enum_decl.is_raw);

	return enum_decl.inner_ordinal;
}

fn long eval_const_int(Expr* expr) {
	ExprConst* const_value = &expr.const_expr;
	assert(const_value.const_kind == CONST_INTEGER);

	return (long)const_value.ixx.i.low;
}

fn Expr*[]? get_attribute(Decl* decl, Attribute attribute) {
	if(!decl.has_tag) {
		return NOT_FOUND~;
	}

	ResolvedAttrData *attrs = decl.attrs_resolved;
	ast::@vec_foreach(attrs.tags; Attr* tag) {
		do {
			if(ast::vec_size(tag.exprs) < 2) {
				break;
			}

			ExprConst* name = &tag.exprs[0].const_expr;
			if(name.bytes.len == 0) {
				break;
			}
			
			String string = (String)((char*)name.bytes.ptr)[..name.bytes.len - 1];
			if(string != c3spirv::TAG) {
				break;
			}

			Expr*[] values = eval_untyped_list(tag.exprs[1]);
			long enum_value = eval_const_enum(values[0]);
			if(attribute.ordinal != enum_value) {
				break;
			}

			return values[1..];
		};
	};

	return NOT_FOUND~;
}

fn SpirvType*? analyse_logical_type(EmissionContext* context, Type* type, SourceLocId loc) {
	bool is_primitive = false;
	is_primitive |= type.type_kind >= TYPE_NUM_FIRST && type.type_kind <= TYPE_NUM_LAST;
	is_primitive |= type.type_kind == TYPE_VOID || type.type_kind == TYPE_BOOL;
	if(is_primitive) {
		return create_type_primitive(context, type);
	}

	switch(type.type_kind) {
		case TYPE_ALIAS:
			return analyse_logical_type(context, type.canonical, loc);
		case TYPE_STRUCT: @pool() {
			StructDecl* struct_decl = &type.decl.strukt;
			Decl*[] members = ast::vec(struct_decl.members);

			SpirvType*[] member_types = mem::talloc_array(SpirvType*, members.len);
			foreach(sz i, Decl* member : members) {
				member_types[i] = analyse_logical_type(context, member.type, member.loc)!;
			}

			return create_type_struct(context, type, member_types);
		};
		case TYPE_VECTOR:
			return create_type_vector(context, type, analyse_logical_type(context, type.array.base, loc), type.array.len);
		default: return err::error(loc, "Unsupported logical memory type kind: %s", ast::const_name(type.type_kind))~;
	}
}

fn SpirvType*? analyse_physical_type(EmissionContext* context, Type* type, SourceLocId loc) {
	bool is_primitive = false;
	is_primitive |= type.type_kind >= TYPE_NUM_FIRST && type.type_kind <= TYPE_NUM_LAST;
	is_primitive |= type.type_kind == TYPE_VOID || type.type_kind == TYPE_BOOL;
	if(is_primitive) {
		return create_type_primitive(context, type);
	}

	switch(type.type_kind) {
		case TYPE_STRUCT: @pool() {
			StructDecl* struct_decl = &type.decl.strukt;
			Decl*[] members = ast::vec(struct_decl.members);

			SpirvType*[] member_types = mem::talloc_array(SpirvType*, members.len);
			foreach(sz i, Decl* member : members) {
				member_types[i] = analyse_physical_type(context, member.type, member.loc)!;
			}

			return create_type_struct(context, type, member_types);
		};
		case TYPE_POINTER:
			return create_type_pointer(context, type, PHYSICAL_STORAGE_BUFFER, analyse_physical_type(context, type.pointer, loc))!;
		default: return err::error(loc, "Unsupported physical memory type kind: %s", ast::const_name(type.type_kind))~;
	}
}

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

fn ExprType expr_type(SpirvType* value) {
	return {value, value};
}

fn SpirvType* inner_type(SpirvType* type) {
	if(type.type == null) {
		return type.pointer.inner;
	}

	switch(type.type.type_kind) {
		case TYPE_POINTER: return type.pointer.inner;
		case TYPE_VECTOR: return type.vector.member;
		default: return type;
	}
}

fn ExprType expr_deref(ExprType type) {
	SpirvType* real_inner = inner_type(type.real);

	if(type.real == type.ref) {
		return {
			.real = type.real,
			.ref = inner_type(type.ref),
		};
	}

	return {
		.real = inner_type(type.real),
		.ref = inner_type(type.ref),
	};
}

fn ExprType expr_addr(ExprType type) {
	assert(type.real != type.ref);
	return {
		.real = type.real,
		.ref = type.real,
	};
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

fn void? analyse_declaration(EmissionContext* context, Decl* declaration) {
	SpirvDecl* spirv_declaration = alloc::new(&context.vmem, SpirvDecl, {
		.declaration = declaration,
	});
	declaration.backend_ref = spirv_declaration;

	switch(declaration.decl_kind) {
		case DECL_VAR:
			VarDecl* variable = &declaration.var_field;
			if(variable.init_expr) {
				SpirvType* initializer = analyse_expression(context, variable.init_expr).type.ref!;
				analyse_set_var(context, spirv_declaration, initializer, variable.init_expr.loc)!;
			}
		default: return err::error(declaration.loc, "Unsupported declaration kind: %s", ast::const_name(declaration.decl_kind))~;
	}
}

fn void? analyse_statement(EmissionContext* context, Ast* statement) {
	while(statement) {
		switch(statement.ast_kind) {
			case AST_COMPOUND_STMT: 
				analyse_statement(context, ast::ast_ptr(statement.compound_stmt.first_stmt))!;
			case AST_DECLARE_STMT:
				analyse_declaration(context, statement.declare_stmt)!;
			case AST_EXPR_STMT:
				analyse_expression(context, statement.expr_stmt)!;
			case AST_IF_STMT:
				AstIfStmt* if_statement = &statement.if_stmt;
				analyse_expression(context, ast::expr_ptr(if_statement.cond))!;
				analyse_statement(context, ast::ast_ptr(if_statement.then_body))!;
				analyse_statement(context, ast::ast_ptr(if_statement.else_body))!;
			default: return err::error(statement.loc, "Unsupported statement kind: %s", ast::const_name(statement.ast_kind))~;
		}

		statement = ast::ast_ptr(statement.next);
	}
}

fn void? analyse_entry_point(EmissionContext* context, Decl* decl) {
	Expr*[]? attribute_params = get_attribute(decl, SHADER);
	if(catch attribute_params) {
		return;
	}

	SpirvEntryPoint* entry_point = alloc::new(&context.vmem, SpirvEntryPoint, {
		.declaration = decl,
	});
	context.entry_points.push(entry_point);

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

fn void? analyse(EmissionContext* context) {
	foreach(Module* mod : ast::vec(ast::gc().module_list)) {
		foreach(CompilationUnit* unit : ast::vec(mod.units)) {
			foreach(Decl* function : ast::vec(unit.functions)) {
				analyse_entry_point(context, function)!;
			}
		}
	}
}