module ardot::c3spirv::sema;
import ardot::c3c::ast, ardot::c3spirv;

import std::io;

fn ExprType expr_type(SpirvType* value) {
	return {.ref = value, .real = value};
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

fn bool SpirvType.can_make_variable(&self) {
	switch(self.kind) {
		case TYPE_POINTER: 
			assert(self.resolved);
			return self.pointer.class == PHYSICAL_STORAGE_BUFFER;
		default: return true;
	}
}

fn bool types_equal(SpirvType* a, SpirvType* b) {
	// SpirvType.original is set to be a circular reference for original types,
	// so this check works.
	return a.original == b.original;
}

fn bool ExprType.is_ref(self) => !types_equal(self.real, self.ref);

fn void? analyse_assignment(SemaContext* context, ExprType variable, ExprType value, SourceLocId loc) {
	if(!variable.is_ref()) {
		return err::error(loc, "Cannot assign to this value, it is not a reference.")~;
	}

	resolve_type(context, variable.ref, value.ref, loc)!;
}

fn ExprType expr_deref(ExprType type) {
	SpirvType* real_inner = inner_type(type.real);

	if(!type.is_ref()) {
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
	assert(type.is_ref());
	return {
		.real = type.real,
		.ref = type.real,
	};
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

fn void SemaContext.add_type(&self, SpirvType* type) {
	if(!self.first_type) {
		self.first_type = type;
		self.last_type = type;
		return;
	}

	self.last_type.next = type;
	self.last_type = type;
}

macro void SemaContext.@push_frame(&self, SemaStackFrame* frame, SemaStackFrameKind kind, Id* label; @body()) {
	frame.kind = kind;
	frame.label = label;

	frame.parent = self.frame;
	self.frame = frame;

	@body();

	self.frame = frame.parent;
}

fn bool SpirvAst.is_flow(&self) {
	switch(self.statement.ast_kind) {
		case AST_IF_STMT:
		case AST_SWITCH_STMT:
		case AST_FOR_STMT:
		case AST_FOREACH_STMT:
			return true;
		default: return false;
	}
}

fn SemaStackFrame* SemaStackFrame.find_function(&frame) {
	while(frame) {
		if(frame.kind == FUNCTION) {
			return frame;
		}
		frame = frame.parent;
	}

	unreachable();
}