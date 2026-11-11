module ardot::c3spirv;
import ardot::c3c::ast;
import std::io, std::collections::map;

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

	EmissionContext context;
	const sz VMEM_SIZE = 1024 * 1024 * 64;
	context.init(VMEM_SIZE);
	defer context.free();

	find_builtin_types();
	if(catch sema::analyse(&context)) {
		return 1;
	}

	codegen::emit(&context);

	// context.print();

	io::File out_file = file::open("output.spv", "w")!!;
	defer out_file.close();
	context.write(&out_file)!!;
	
	return 0;
}