module ardot::c3spirv::codegen;
import ardot::c3spirv, ardot::c3c::ast;

fn void emit_entry_point(GenContext* context, SpirvEntryPoint* entry) {
	Id void_type = context.type_op(TYPE_VOID);
	Id func_type = context.type_op(TYPE_FUNCTION, void_type);

	Id func = context.func_op(FUNCTION, void_type, (uint)(FunctionControl){}, func_type);
	entry.label = context.func_op(LABEL);
	Op* label_op = context.func_ops.last_op;

	OpStream body;
	@push_stream(context, &body) {
		emit_statement(context, ast::ast_ptr(entry.declaration.func_decl.body));
	};

	// Need to have all variable ops at the start of the function.
	append_stream(context, &context.func_var_ops);
	append_stream(context, &body);

	context.func_op(RETURN);
	context.func_op(FUNCTION_END);

	// TODO: should probably use fully qualified name here, or have the user specify it in the attribute.
	context.init_op_raw(
		ENTRY_POINT, 
		{entry.model, func}, 
		tstr_literal(ast::c_string(entry.declaration.name)), 
		// func_interfaces are added as builtin calls are emitted.
		(uint[])context.func_interfaces.array_view()
	);

	switch(entry.model) {
		case COMPUTE:
			context.init_op(EXECUTION_MODE, func, ExecutionMode.LOCAL_SIZE, ...entry.compute.group_size);
	}

	context.func_interfaces.clear();
}

fn void emit(GlobalContext* context) {
	GenContext* gen_context = alloc::new(&context.vmem, GenContext);
	gen_context.init(context);

	context.gen_context = gen_context;

	gen_context.init_op(CAPABILITY, Capability.SHADER);
	gen_context.init_op(CAPABILITY, Capability.PHYSICAL_STORAGE_BUFFER_ADDRESSES);
	gen_context.init_op(MEMORY_MODEL, AddressingModel.PHYSICAL_STORAGE_BUFFER_64, MemoryModel.GLSL450);

	foreach(SpirvEntryPoint* entry : context.entry_points) {
		emit_entry_point(gen_context, entry);
	}
}