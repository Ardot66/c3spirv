module ardot::c3spirv;
import ardot::c3c::ast;
import std::io, std::collections::map;

struct ArgContext {
	bool test_mode;
}

ArgContext arg_context;

Type* bool_type;
Type* int_type;
Type* uint_type;

fn void find_builtin_types() {
	Type*[] types = ast::vec(ast::gc().type);

	foreach(Type* type : types) {
		switch(type.type_kind) {
			case TYPE_BOOL: bool_type = type;
			case TYPE_I32: int_type = type;
			case TYPE_U32: uint_type = type;
		}
	}
}

fn int main(String[] args) @public
{
	// emit_sample_program();

	if(args.len == 2) {
		arg_context.test_mode = true;
		ast::load_ast({"c3cdev", "compile-only", "--ast-dump", "--no-obj", args[1], "src/lib.c3"})!!;
	} else {
		ast::load_ast({"c3cdev", "compile-only", "--ast-dump", "test/demo_shader.c3", "src/lib.c3"})!!;
	}

    defer ast::free_ast();

	GlobalContext context;
	const sz VMEM_SIZE = 1024 * 1024 * 64;
	context.init(VMEM_SIZE);
	defer context.free();

	find_builtin_types();
	if(catch sema::analyse(&context)) {
		return 1;
	}

	codegen::emit(&context);

	// context.gen_context.print();

	io::File out_file = file::open("output.spv", "w")!!;
	defer out_file.close();
	context.write(&out_file)!!;
	
	return 0;
}