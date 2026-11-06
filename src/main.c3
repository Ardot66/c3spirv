module ardot::c3spirv @private;
import ardot::c3c::ast;
import std::io, std::collections::map;

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
			if(string != TAG) {
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

fn void? eval_entry_func(EmissionContext* context, Decl* decl) {
	assert(decl.decl_kind == DECL_FUNC);
	Expr*[]? params = get_attribute(decl, SHADER);
	if(catch params) {
		return;
	}

	ExecutionModel execution_model = (ExecutionModel)eval_const_int(params[0]);

	uint[<3>] group_size;
	{
		ExprConst* const_value = &params[1].const_expr;
		ConstInitializer*[] initializers = ast::vec(const_value.initializer.init_array_full);
		group_size.x = (uint)eval_const_int(initializers[0].init_value);
		group_size.y = (uint)eval_const_int(initializers[1].init_value);
		group_size.z = (uint)eval_const_int(initializers[2].init_value);
	}

	Id void_type = context.type_op(TYPE_VOID);
	Id func_type = context.type_op(TYPE_FUNCTION, void_type);

	Id func = context.func_op(FUNCTION, void_type, (uint)(FunctionControl){}, func_type);
	Id label = context.func_op(LABEL);

	// context.get_type_id(decl.type, decl.loc)!;
	// Id id = context.generate_id();
	// context.func_ops.op(context, FUNCTION, );
	// context.init_ops.op(context, ENTRY_POINT, );
}

fn uint[] str_literal(String string) {
	// + 4 here because if the string perfectly fits into the literal that leaves no space
	// for the null terminator!
	sz elements = (string.len + 4) / 4; 

	uint[] literal = mem::talloc_array(uint, elements);
	literal[^1] = 0;
	mem::copy(literal, string, string.len);
	return literal;
}

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

	context.init_ops.op(&context, CAPABILITY, Capability.SHADER);
	context.init_ops.op(&context, CAPABILITY, Capability.PHYSICAL_STORAGE_BUFFER_ADDRESSES);
	context.init_ops.op(&context, MEMORY_MODEL, AddressingModel.PHYSICAL_STORAGE_BUFFER_64, MemoryModel.GLSL450);

	ast::@vec_foreach(gc.module_list; Module* mod) {
		ast::@vec_foreach(mod.units; CompilationUnit* unit) {
			ast::@vec_foreach(unit.functions; Decl* function) {
				if(catch eval_entry_func(&context, function)) {
					return 1;
				}
			};
		};
	};

	context.write(&out_file)!!;
	return 0;
}
