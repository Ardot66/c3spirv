module ardot::c3spirv::sema;
import ardot::c3c::ast, ardot::c3spirv;
import std::collections::list;

import std::io;

struct SpirvEntryPoint {
	Decl* declaration;
	ExecutionModel model;
	union {
		struct compute {
			uint[<3>] group_size;
		}
	}
}

struct SpirvType {
	Id id;
	Type* type;
	union {
		struct pointer {
			SpirvType* inner;
			StorageClass class;
		}
		SpirvType*[] members;
	}
}

struct SpirvDecl {
	Decl* declaration;
	union {
		struct variable {
			SpirvType* type;
		}
	}
}

struct SpirvExpr {
	Expr* expression;
	SpirvType* type;
}

// struct SpirvTypeInfo {
// 	SpirvType* associated_type;
// 	bitstruct : uint {
// 		bool explicit_class;
// 		bool builtin;
// 		bool root;
// 	}
// 	StorageClass class;
// }

// fn SpirvTypeInfo* type_info(EmissionContext* context, Type* type) {
// 	if(type.backend_type) {
// 		return type.backend_type;
// 	}

// 	SpirvTypeInfo* info = alloc::new(&context.vmem, SpirvTypeInfo);

// 	bool 
// 	if(type.type_kind >= TYPE_NUM_FIRST &&type.type_kind <= TYPE_NUM_LAST) {

// 	}

// 	switch(type.type_kind) {
// 		case TYPE_STRUCT:
// 			Decl* decl = type.decl;
// 			if(try get_attribute(decl, SHADER_ROOT)) {
// 				info.explicit_class = true;
// 				info.root = true;
// 				info.class = UNIFORM;	
// 			}  else {
// 				info.explicit_class = true;
// 				info.class = INPUT;
// 			}
// 		default: break;
// 	}

// 	type.backend_type = info;
// 	return info;
// }

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
		.members = alloc::alloc_array(&context.vmem, SpirvType*, members.len),
	};
	mem::copy(struct_type.members, members, members.len * SpirvType*::size);
	return create_type(context, &struct_type);
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

// enum TypeEvalMode {
// 	IO,
// 	PHYSICAL_STRUCT,
// 	MATCH
// }

// struct TypeContext {
// 	TypeEvalMode mode;

// 	SourceLocId loc;
// 	union {
// 		struct io {
// 			StorageClass class;
// 		}
// 		struct match {
// 			SpirvType* a;
// 			SpirvType* b;
// 		}
// 	}
// }

// fn SpirvType*? analyse_type(EmissionContext* context, Type* type, TypeContext tc = {}) {
// 	switch(tc.mode) {
// 		case IO:
// 			switch (type.type_kind) {
// 				case TYPE_POINTER:
// 					Type* inner = type.pointer;
// 					SpirvType* inner_type = analyse_type(context, inner, tc)!;
// 					SpirvType* new_type = alloc::new(&context.vmem, SpirvType, {
// 						.pointer = {
// 							.inner = inner_type,
// 							.class = tc.io.class,
// 						}
// 					});
// 				default:
// 					tc.mode = PHYSICAL_STRUCT;
// 					return analyse_type(context, type, tc);
// 			}
// 		case PHYSICAL_STRUCT:
// 			switch (type.type_kind) {

// 			}
// 	}

// 	SpirvType* stype;
// 	switch(type.type_kind) {
// 		case TYPE_VOID: stype = context.type_op(TYPE_VOID);
// 		case TYPE_BOOL: stype = context.type_op(TYPE_BOOL);
// 		case TYPE_I8: stype = context.type_op(TYPE_INT, 8, 1);
// 		case TYPE_I16: stype = context.type_op(TYPE_INT, 16, 1);
// 		case TYPE_I32: stype = context.type_op(TYPE_INT, 32, 1);
// 		case TYPE_I64: stype = context.type_op(TYPE_INT, 64, 1);
// 		// case TYPE_I128: // unsupported for now.
// 		case TYPE_U8: stype = context.type_op(TYPE_INT, 8, 0);
// 		case TYPE_U16: stype = context.type_op(TYPE_INT, 16, 0);
// 		case TYPE_U32: stype = context.type_op(TYPE_INT, 32, 0);
// 		case TYPE_U64: stype = context.type_op(TYPE_INT, 64, 0);
// 		// case TYPE_U128: // unsupported for now.
// 		case TYPE_F16: stype = context.type_op(TYPE_FLOAT, 16);
// 		// case TYPE_BF16: // unsupported for now.
// 		case TYPE_F32: stype = context.type_op(TYPE_FLOAT, 32);
// 		case TYPE_F64: stype = context.type_op(TYPE_FLOAT, 64);
// 		// case TYPE_F128: // unsupported for now.

// 		case TYPE_POINTER:
// 			Type* inner = type.pointer;
// 			StorageClass class = FUNCTION;
// 			if(type_context.uniform_ptr) {
// 				class = UNIFORM;
// 				type_context.uniform_ptr = false;
// 			} else if(type_context.in_root) {
// 				class = PHYSICAL_STORAGE_BUFFER;
// 			}

// 			SpirvType* inner_type = analyse_type(context, inner, reference_loc, type_context)!;
// 			stype.pointer = {
// 				.inner = inner_type,
// 				.class = class,
// 			};
// 		case TYPE_STRUCT: @pool() {
// 			if(info.root) {
// 				type_context.in_root = true;
// 			}

// 			StructDecl* struct_decl = &type.decl.strukt;
// 			Decl*[] members = ast::vec(struct_decl.members);

// 			SpirvType*[] member_types = alloc::alloc_array(&context.vmem, SpirvType*, members.len);
// 			Id[] member_ids = mem::talloc_array(Id, members.len);

// 			foreach(sz i, Decl* member : members) {
// 				SpirvType* member_type = analyse_type(context, member.type, member.loc, type_context)!;
// 				member_types[i] = member_type;
// 				member_ids[i] = member_type.id;
// 			};

// 			SpirvType* struct_type = context.type_op_raw(TYPE_STRUCT, (uint[])member_ids);
// 			if(!struct_type.type) {
// 				if(info.root) {
// 					context.decoration_op(DECORATE, struct_type.id, Decoration.BLOCK);
// 				}
// 				foreach(sz i, Decl* member : members) {
// 					context.decoration_op(MEMBER_DECORATE, struct_type.id, (uint)i, Decoration.OFFSET, (uint)member.offset);
// 				}

// 				struct_type.members = member_types;
// 			}

// 			stype = struct_type;
// 		};
// 		default:
// 			return err::error(reference_loc, "Unsupported type: %s", ast::const_name(type.type_kind))~;
// 	}

// 	assert(stype);
// 	if(stype.type == null) {
// 		stype.type = type;
// 	}

// 	return stype;
// }

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

fn void? analyse_set_var(EmissionContext* context, SpirvDecl* variable, SpirvType* value, SourceLocId loc) {
	if(variable.variable.type) {
		if(variable.variable.type == value) {
			return;
		}

		err::error(loc, "Cannot set variable, conflicting pointer types!");
		return err::error_note(variable.declaration.loc, "The variable was declared here.")~;
	}

	if(variable.declaration.type != value.type) {
		unreachable();
	}

	variable.variable.type = value;
}

fn void? analyse_declaration(EmissionContext* context, Decl* declaration) {
	SpirvDecl* spirv_declaration = alloc::new(&context.vmem, SpirvDecl, {
		.declaration = declaration,
	});
	declaration.backend_ref = spirv_declaration;

	switch(declaration.decl_kind) {
		case DECL_VAR:
			VarDecl* variable = &declaration.var_field;
			if(!variable.no_init) {
				SpirvType* initializer = analyse_expression(context, variable.init_expr)!;
				analyse_set_var(context, spirv_declaration, initializer, variable.init_expr.loc)!;
			}
		default: return err::error(declaration.loc, "Unsupported declaration kind: %s", ast::const_name(declaration.decl_kind))~;
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

fn SpirvType*? analyse_builtin_call(EmissionContext* context, Expr* expression, Expr*[] attribute_params) {
	ExprCall* call = &expression.call_expr;
	ShaderBuiltin builtin = (ShaderBuiltin)eval_const_enum(attribute_params[0]);
	Type* rtype = expression.type;

	switch(builtin) {
		case GET_ROOT:
			Type* inner = rtype.pointer;
			if(inner.type_kind != TYPE_STRUCT) {
				return err::error(expression.loc, "The root type must be a struct.")~;
			}

			SpirvType* spirv_inner = analyse_physical_type(context, inner, expression.loc)!;
			return create_type_pointer(context, rtype, UNIFORM, spirv_inner);
		case GET_GLOBAL_INVOCATION_ID:
			return create_type_primitive(context, rtype);
		default: return err::error(expression.loc, "Unsupported builtin.")~;
	}
}

fn SpirvType*? analyse_expression(EmissionContext* context, Expr* expression) {
	SpirvExpr* spirv_expression = alloc::new(&context.vmem, SpirvExpr, {
		.expression = expression,
	});
	context.spirv_expressions[expression] = spirv_expression;

	SpirvType* type;
	switch(expression.expr_kind) {
		case EXPR_CALL:
			ExprCall* call = &expression.call_expr;
			Decl* declaration = ast::decl_ptr(call.func_ref);

			Expr*[]? builtin_params = get_attribute(declaration, SHADER_BUILTIN);
			if(try builtin_params) {
				type = analyse_builtin_call(context, expression, builtin_params)!;
			} else {
				return err::error(expression.loc, "Non-builtin calls are not currently supported.")~;
			}
		case EXPR_COND:
			// Expr*[] expressions = ast::vec(expression.cond_expr);
			// foreach(cond : expressions) {
			// 	emit_expression(context, cond)!;
			// }
			break;
		case EXPR_BINARY:
			// ExprBinary* binary = &expression.binary_expr;
			// emit_expression(context, ast::expr_ptr(binary.left))!;
			// emit_expression(context, ast::expr_ptr(binary.right))!;
			break;
		case EXPR_IDENTIFIER:
			// Decl* ident = expression.ident_expr;
			break;
		default: return err::error(expression.loc, "Unsupported expression kind: %s", ast::const_name(expression.expr_kind))~;
	}

	assert(type);

	spirv_expression.type = type;
	return type;
}

fn void? analyse_statement(EmissionContext* context, Ast* statement) {
	while(statement) {
		switch(statement.ast_kind) {
			case AST_COMPOUND_STMT: 
				analyse_statement(context, ast::ast_ptr(statement.compound_stmt.first_stmt))!;
			case AST_EXPR_STMT:
				analyse_expression(context, statement.expr_stmt)!;
			case AST_DECLARE_STMT:
				analyse_declaration(context, statement.declare_stmt)!;
			case AST_IF_STMT:
				break;
				// AstIfStmt* specific = &statement.if_stmt;
				// emit_expression(context, ast::expr_ptr(specific.cond))!;
				// emit_statement(context, ast::ast_ptr(specific.then_body))!;
				// emit_statement(context, ast::ast_ptr(specific.else_body))!;
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

	SpirvEntryPoint* entry_point = alloc::new(&context.vmem, SpirvEntryPoint);

	FuncDecl* func_decl = &decl.func_decl;
	Signature* signature = &func_decl.signature;
	Decl*[] params = ast::vec(signature.params);

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