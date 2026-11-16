module ardot::c3spirv;

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
	VECTOR_EXTRACT_DYNAMIC = 77,
	VECTOR_INSERT_DYNAMIC = 78,
	COMPOSITE_CONSTRUCT = 80,
	COMPOSITE_EXTRACT = 81,
	COMPOSITE_INSERT = 82,
	U_CONVERT = 113,
	S_CONVERT = 114,
	BITCAST = 124,
	S_NEGATE = 126,
	F_NEGATE = 127,
	I_ADD = 128,
	F_ADD = 129,
	I_SUB = 130,
	F_SUB = 131,
	I_MUL = 132,
	F_MUL = 133,
	U_DIV = 134,
	S_DIV = 135,
	F_DIV = 136,
	U_MOD = 137,
	S_REM = 138,
	S_MOD = 139,
	F_REM = 140,
	F_MOD = 141,
	LOGICAL_EQUAL = 164,
	LOGICAL_NOT_EQUAL = 165,
	LOGICAL_OR = 166,
	LOGICAL_AND = 167,
	LOGICAL_NOT = 168,
	I_EQUAL = 170,
	I_NOT_EQUAL = 171,
	U_GREATER_THAN = 172,
	S_GREATER_THAN = 173,
	U_GREATER_THAN_EQUAL = 174,
	S_GREATER_THAN_EQUAL = 175,
	U_LESS_THAN = 176,
	S_LESS_THAN = 177,
	U_LESS_THAN_EQUAL = 178,
	S_LESS_THAN_EQUAL = 179,
	F_UNORD_EQUAL = 181,
	F_UNORD_NOT_EQUAL = 183,
	F_UNORD_LESS_THAN = 185,
	F_UNORD_GREATER_THAN = 187,
	F_UNORD_LESS_THAN_EQUAL = 189,
	F_UNORD_GREATER_THAN_EQUAL = 191,
	SHIFT_RIGHT_LOGICAL = 194,
	SHIFT_RIGHT_ARITHMETIC = 195,
	SHIFT_LEFT_LOGICAL = 196,
	BITWISE_OR = 197,
	BITWISE_XOR = 198,
	BITWISE_AND = 199,
	BITWISE_NOT = 200,
	PHI = 245,
	LOOP_MERGE = 246,
	SELECTION_MERGE = 247,
	LABEL = 248,
	BRANCH = 249,
	BRANCH_CONDITIONAL = 250,
	SWITCH = 251,
	RETURN = 253,
	RETURN_VALUE = 254,
	INVALID = ushort::max,
}

<*
 Returns the operand index which should contain the result ID of the op.
 Returns 0 if the op has no result.
*>
fn uint Opcode.result_index(self) {
	switch(self) {
		case EXTENSION:
		case MEMORY_MODEL:
		case ENTRY_POINT:
		case EXECUTION_MODE:
		case CAPABILITY:
		case TYPE_FORWARD_POINTER:
		case FUNCTION_END:
		case STORE:
		case DECORATE:
		case MEMBER_DECORATE:
		case LOOP_MERGE:
		case SELECTION_MERGE:
		case BRANCH:
		case BRANCH_CONDITIONAL:
		case SWITCH:
		case RETURN:
		case RETURN_VALUE:
			return 0;
		case TYPE_VOID:
		case TYPE_BOOL:
		case TYPE_INT:
		case TYPE_FLOAT:
		case TYPE_VECTOR:
		case TYPE_MATRIX:
		case TYPE_ARRAY:
		case TYPE_STRUCT:
		case TYPE_POINTER:
		case TYPE_FUNCTION:
		case LABEL:
			return 1;
		case CONSTANT_TRUE:
		case CONSTANT_FALSE:
		case CONSTANT:
		case FUNCTION:
		case FUNCTION_PARAMETER:
		case VARIABLE:
		case LOAD:
		case ACCESS_CHAIN:
		case PTR_ACCESS_CHAIN:
		case VECTOR_EXTRACT_DYNAMIC:
		case VECTOR_INSERT_DYNAMIC:
		case COMPOSITE_CONSTRUCT:
		case COMPOSITE_EXTRACT:
		case COMPOSITE_INSERT:
		case U_CONVERT:
		case S_CONVERT:
		case BITCAST:
		case S_NEGATE:
		case F_NEGATE:
		case I_ADD:
		case F_ADD:
		case I_SUB:
		case F_SUB:
		case I_MUL:
		case F_MUL:
		case U_DIV:
		case S_DIV:
		case F_DIV:
		case U_MOD:
		case S_REM:
		case S_MOD:
		case F_REM:
		case F_MOD:
		case LOGICAL_EQUAL:
		case LOGICAL_NOT_EQUAL:
		case LOGICAL_OR:
		case LOGICAL_AND:
		case LOGICAL_NOT:
		case I_EQUAL:
		case I_NOT_EQUAL:
		case U_GREATER_THAN:
		case S_GREATER_THAN:
		case U_GREATER_THAN_EQUAL:
		case S_GREATER_THAN_EQUAL:
		case U_LESS_THAN:
		case S_LESS_THAN:
		case U_LESS_THAN_EQUAL:
		case S_LESS_THAN_EQUAL:
		case F_UNORD_EQUAL:
		case F_UNORD_NOT_EQUAL:
		case F_UNORD_LESS_THAN:
		case F_UNORD_GREATER_THAN:
		case F_UNORD_LESS_THAN_EQUAL:
		case F_UNORD_GREATER_THAN_EQUAL:
		case SHIFT_RIGHT_LOGICAL:
		case SHIFT_RIGHT_ARITHMETIC:
		case SHIFT_LEFT_LOGICAL:
		case BITWISE_OR:
		case BITWISE_XOR:
		case BITWISE_AND:
		case BITWISE_NOT:
		case PHI:
			return 2;
	}

	unreachable("The opcode %s is missing from the result_index function", self);
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
	FUNCTION = 7,
	STORAGE_BUFFER = 12,
	PHYSICAL_STORAGE_BUFFER = 5349,
	INVALID = uint::max,
}

constdef Decoration : inline uint {
	BLOCK = 2,
	ARRAY_STRIDE = 6,
	BUILTIN = 11,
	BINDING = 33,
	DESCRIPTOR_SET = 34,
	OFFSET = 35,
}

constdef SelectionControl : inline uint {
	NONE = 0,
	FLATTEN = 1,
	DONT_FLATTEN = 2,
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

