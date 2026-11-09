module ardot::c3spirv;
import ardot::c3c::ast;
import std::io, std::collections::map;

fn uint[] str_literal(String string) {
	// + 4 here because if the string perfectly fits into the literal that leaves no space
	// for the null terminator!
	sz elements = (string.len + 4) / 4; 

	uint[] literal = mem::talloc_array(uint, elements);
	literal[^1] = 0;
	mem::copy(literal, string, string.len);
	return literal;
}

Type* bool_type;

fn void find_builtin_types() {
	Type*[] types = ast::vec(ast::gc().type);

	foreach(Type* type : types) {
		switch(type.type_kind) {
			case TYPE_BOOL: bool_type = type;
		}
	}
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

	find_builtin_types();
	if(catch sema::analyse(&context)) {
		return 1;
	}
	// context.init_ops.op(&context, CAPABILITY, Capability.SHADER);
	// context.init_ops.op(&context, CAPABILITY, Capability.PHYSICAL_STORAGE_BUFFER_ADDRESSES);
	// context.init_ops.op(&context, MEMORY_MODEL, AddressingModel.PHYSICAL_STORAGE_BUFFER_64, MemoryModel.GLSL450);

	// ast::@vec_foreach(gc.module_list; Module* mod) {
	// 	ast::@vec_foreach(mod.units; CompilationUnit* unit) {
	// 		ast::@vec_foreach(unit.functions; Decl* function) {
	// 			if(catch eval_entry_func(&context, function)) {
	// 				return 1;
	// 			}
	// 		};
	// 	};
	// };

	context.write(&out_file)!!;
	return 0;
}
