module ardot::c3spirv;
import ardot::c3c::ast;
import std::io, std::os;

fn void emit_sample_program() {
	io::File out_file = file::open("sample.spv", "w")!!;
	defer out_file.close();

	GlobalContext global_context;
	const sz VMEM_SIZE = 1024 * 1024 * 64;
	global_context.init(VMEM_SIZE);
	defer global_context.free();

	GenContext context;
	context.init(&global_context);

	// Declare the capabilities needed for this shader.
	context.init_ops.op(&context, CAPABILITY, Capability.SHADER);
	context.init_ops.op(&context, CAPABILITY, Capability.PHYSICAL_STORAGE_BUFFER_ADDRESSES);
	context.init_ops.op(&context, MEMORY_MODEL, AddressingModel.PHYSICAL_STORAGE_BUFFER_64, MemoryModel.GLSL450);

	// Declare primitives types.
	Id void_type = context.type_ops.op(&context, TYPE_VOID);

	// Declare type for function.
	Id function_type = context.type_ops.op(&context, TYPE_FUNCTION, void_type);
	Id float_type = context.type_ops.op(&context, TYPE_FLOAT, 32);
	Id uint_type = context.type_ops.op(&context, TYPE_INT, 32, 0);

	// Physical float pointer types for input and output arrays. 
	// Needs ARRAY_STRIDE decoration for indexing
	Id float_physical_ptr_type = context.type_ops.op(&context, TYPE_POINTER, StorageClass.PHYSICAL_STORAGE_BUFFER, float_type);
	context.decoration_ops.op(&context, DECORATE, float_physical_ptr_type, Decoration.ARRAY_STRIDE, float::size);

	// Root struct, members must be explicitly offset because it's a uniform. 
	// It needs the BLOCK decoration because it's a uniform.
	Id root_type = context.type_ops.op(&context, TYPE_STRUCT, float_physical_ptr_type, float_physical_ptr_type, uint_type);
	context.decoration_ops.op(&context, DECORATE, root_type, Decoration.BLOCK);
	context.decoration_ops.op(&context, MEMBER_DECORATE, root_type, 0, Decoration.OFFSET, 0);
	context.decoration_ops.op(&context, MEMBER_DECORATE, root_type, 1, Decoration.OFFSET, 8);
	context.decoration_ops.op(&context, MEMBER_DECORATE, root_type, 2, Decoration.OFFSET, 16);

	// Pointer to the root, needed for variable declaration.
	Id root_uniform_ptr_type = context.type_ops.op(&context, TYPE_POINTER, StorageClass.UNIFORM, root_type);

	// Root variable, this links our root in so that entry points can use it.
	// BINDING and DESCRIPTOR_SET are zero because that's what nogfx requires for roots.
	// This variable is just a pointer to the root, and is used as such.
	Id root_variable = context.type_ops.op(&context, VARIABLE, root_uniform_ptr_type, StorageClass.UNIFORM);
	context.decoration_ops.op(&context, DECORATE, root_variable, Decoration.BINDING, 0);
	context.decoration_ops.op(&context, DECORATE, root_variable, Decoration.DESCRIPTOR_SET, 0);

	// Vector3 uint type for global invocation id.
	Id vector3_type = context.type_ops.op(&context, TYPE_VECTOR, uint_type, 3);
	Id vector3_input_ptr_type = context.type_ops.op(&context, TYPE_POINTER, StorageClass.INPUT, vector3_type);

	// Global invocation id element pointer type, needed for loading later.
	Id uint_input_ptr_type = context.type_ops.op(&context, TYPE_POINTER, StorageClass.INPUT, uint_type);

	// Declare builtin global invocation id. The decoration is necessary, 
	// otherwise it's just a plain variable with no special properties.
	Id invocation_id = context.type_ops.op(&context, VARIABLE, vector3_input_ptr_type, StorageClass.INPUT);
	context.decoration_ops.op(&context, DECORATE, invocation_id, Decoration.BUILTIN, Builtin.GLOBAL_INVOCATION_ID);

	// Compute shader function body.
	Id function = context.func_ops.op(&context, FUNCTION, void_type, (uint)(FunctionControl){}, function_type);
	// Functions must start with a label, even if it's never used.
	Id label = context.func_ops.op(&context, LABEL);

	// Constant values for use later. These aren't function specific, and so could be shared with
	// another function.
	Id const_0 = context.type_ops.op(&context, CONSTANT, uint_type, 0);
	Id const_1 = context.type_ops.op(&context, CONSTANT, uint_type, 1);
	Id const_2f = context.type_ops.op(&context, CONSTANT, float_type, bitcast(2f, uint));

	// When we use ACCESS_CHAIN on the root, we get a pointer to a element of the root.
	// In this case, that pointer is a pointer to the physical pointer in the root that points to the
	// input or output buffer, hence this type.
	// The storage class is UNIFORM because the root struct is in uniform memory, thus this pointer
	// points to uniform memory.
	Id ptr_uniform_float_physical_ptr_type = context.type_ops.op(&context, TYPE_POINTER, StorageClass.UNIFORM, float_physical_ptr_type);

	// Access chain basically performs an offset into the global invocation id, getting the 
	// pointer to the x value.
	Id index_ptr = context.func_ops.op(&context, ACCESS_CHAIN, uint_input_ptr_type, invocation_id, const_0);
	// Load the global invocation id x value itself into a local variable.
	Id index = context.func_ops.op(&context, LOAD, uint_type, index_ptr);

	// Offset into the root struct to get a pointer to an element, in this case the element
	// is the physical pointer to our input buffer.
	Id in_buf_ref_ref = context.func_ops.op(&context, ACCESS_CHAIN, ptr_uniform_float_physical_ptr_type, root_variable, const_0);

	// Load the in buffer physical pointer into a local variable.
	Id in_buf_ref = context.func_ops.op(&context, LOAD, float_physical_ptr_type, in_buf_ref_ref);

	// Offset from the buffer physical pointer to get the physical pointer to the element at the loaded index.
	Id in_element_ref = context.func_ops.op(&context, PTR_ACCESS_CHAIN, float_physical_ptr_type, in_buf_ref, index);

	// Finally, load the element into a local variable. This is our input for this particular invocation.
	Id in_element = context.func_ops.op(&context, LOAD, float_type, in_element_ref, (uint)(MemoryOperands){.aligned}, 4);

	// Multiply the input value by the constant 2f.
	Id result = context.func_ops.op(&context, F_MUL, float_type, in_element, const_2f);

	// Do all the same stuff we just did with the input buffer, but for the output buffer.
	Id out_buf_ref_ref = context.func_ops.op(&context, ACCESS_CHAIN, ptr_uniform_float_physical_ptr_type, root_variable, const_1);
	Id out_buf_ref = context.func_ops.op(&context, LOAD, float_physical_ptr_type, out_buf_ref_ref);
	Id out_element_ref = context.func_ops.op(&context, PTR_ACCESS_CHAIN, float_physical_ptr_type, out_buf_ref, index);

	// Store the result we calculated into the correct slot in the output buffer.
	context.func_ops.op(&context, STORE, out_element_ref, result, (uint)(MemoryOperands){.aligned}, 4);

	// Return from the function and end.
	context.func_ops.op(&context, RETURN);
	context.func_ops.op(&context, FUNCTION_END);

	// Mark the function as the entry point "main". root_variable and invocation_id need to 
	// be referenced here, as they are the external inputs for this entry point.
	context.init_ops.op_raw(&context, ENTRY_POINT, {ExecutionModel.COMPUTE, function}, codegen::tstr_literal("main"), {root_variable, invocation_id});
	// Compute shaders need to have their LOCAL_SIZE specified. The LOCAL_SIZE is the size
	// of each workgroups that will be dispatched. 
	// (Think of it like a cube of workers with the given dimentions.)
	context.init_ops.op(&context, EXECUTION_MODE, function, ExecutionMode.LOCAL_SIZE, 64, 1, 1);

	context.write(&out_file)!!;
	os::exit(0);
}