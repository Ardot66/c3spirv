module ardot::c3spirv @private;

constdef Opcode : ushort {
	EXTENSION = 10,
	MEMORY_MODEL = 14,
	ENTRY_POINT = 15,
	EXECUTION_MODE = 16,
	CAPABILITY = 17,
	TYPE_VOID = 19,
	TYPE_BOOL = 20,
	TYPE_INT = 21,
	TYPE_FLOAT = 22,
	TYPE_VECTOR = 23,
	TYPE_MATRIX = 24,
	TYPE_ARRAY = 28,
	TYPE_STRUCT = 30,
	TYPE_POINTER = 32,
	TYPE_FUNCTION = 33,
	TYPE_FORWARD_POINTER = 39,
	CONSTANT_TRUE = 41,
	CONSTANT_FALSE = 42,
	CONSTANT = 43,
	FUNCTION = 54,
	FUNCTION_PARAMETER = 55,
	FUNCTION_END = 56,
	VARIABLE = 59,
	LOAD = 61,
	STORE = 62,
	ACCESS_CHAIN = 65,
	PTR_ACCESS_CHAIN = 67,
	DECORATE = 71,
	MEMBER_DECORATE = 72,
	I_MUL = 132,
	F_MUL = 133,
	LABEL = 248,
	RETURN = 253,
	TYPE_UNTYPED_POINTER = 4417,
	UNTYPED_VARIABLE = 4418,
	UNTYPED_ACCESS_CHAIN = 4419,
	UNTYPED_IN_BOUNDS_ACCESS_CHAIN = 4420,
}

constdef Capability : inline uint {
	SHADER = 1,
	ADDRESSES = 4,
	KERNEL = 6,
	UNTYPED_POINTERS = 4473,
	VULKAN_MEMORY_MODEL = 5345,
	PHYSICAL_STORAGE_BUFFER_ADDRESSES = 5347,
}

constdef AddressingModel : inline uint {
	LOGICAL = 0,
	PHYSICAL_32 = 1,
	PHYSICAL_64 = 2,
	PHYSICAL_STORAGE_BUFFER_64 = 5348,
}

constdef MemoryModel : inline uint {
	GLSL450 = 1,
	OPENCL = 2,
	VULKAN = 3,
}

constdef ExecutionMode : inline uint {
	LOCAL_SIZE = 17,
}

constdef StorageClass : inline uint {
	INPUT = 1,
	UNIFORM = 2,
	OUTPUT = 3,
	PHYSICAL_STORAGE_BUFFER = 5349,
}

constdef Decoration : inline uint {
	BLOCK = 2,
	ARRAY_STRIDE = 6,
	BUILTIN = 11,
	BINDING = 33,
	DESCRIPTOR_SET = 34,
	OFFSET = 35,
}

constdef Builtin : inline uint {
	GLOBAL_INVOCATION_ID = 28,
}

bitstruct FunctionControl : uint {
	bool force_inline : 0;
	bool no_inline : 1;
	bool pure : 2;
	bool constant : 3;
}

bitstruct MemoryOperands : uint {
	bool volatile : 0;
	bool aligned : 1;
	bool non_temporal : 2;
}

