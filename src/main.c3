module ardot::c3spirv;
import ardot::c3c::ast;
import std::io, std::collections::map;

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
	DECORATE = 71,
	MEMBER_DECORATE = 72,
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
	UNIFORM = 2,
	PHYSICAL_STORAGE_BUFFER = 5349,
}

constdef Decoration : inline uint {
	BLOCK = 2,
	BINDING = 33,
	DESCRIPTOR_SET = 34,
	OFFSET = 35,
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

typedef Id = inline uint;

struct EmissionContext {
	Vmem vmem;
	uint id_count;
	HashMap{void*, Id} type_ids;

	OpStream init_ops;
	OpStream decoration_ops;
	OpStream type_ops;
	OpStream func_ops;
}

struct LineInfo {
	String content;
	sz line;
}

<*
 @require before + after + 1 == dest.len : "Dest length is incompatible with the given parameters"
*>
fn void ast::File.get_lines(&self, sz offset, LineInfo[] dest, sz before = 0, sz after = 0) {
	String contents = (String)((char*)self.contents)[.. self.content_len - 1];
	sz lines = before + after + 1;

	sz start = offset;	
	while(start >= 0) {
		if(contents[start] == '\n') {
			if(before <= 0) {
				start += 1;
				break;
			}
			before -= 1;
		}
		start -= 1;
	}

	sz line_no = 1;	
	for(sz i = start; i >= 0; i--) {
		if(contents[i] == '\n') {
			line_no += 1;
		}
	}

	sz output_idx = before;
	for(sz i = start, sz line_start = i; i < contents.len && output_idx < dest.len; i++) {
		if(contents[i] == '\n') {
			dest[output_idx] = {
				.content = contents[line_start..i - 1],
				.line = line_no,
			};

			line_start = i + 1;
			line_no += 1;
			output_idx += 1;
		}
	}
}

excuse {COMPILE_ERROR}
fn void error_msg(SourceLocId loc_id, String error_kind, String format, args...) {
	SourceLoc* loc = ast::source_loc_ptr(loc_id);
	ast::File* file = ast::gc().loaded_sources[loc.file_id];

	LineInfo[4] lines;
	file.get_lines(loc.offset, &lines, before: 3);

	io::eprintf("\n");
	foreach(LineInfo line : lines) {
		io::eprintf("%6d: %s\n", line.line, line.content);
	}

	for(sz i = 0; i < (sz)loc.col - 1 + 8; i++) {
		io::eprintf(" ");
	}

	for(sz i = 0; i < loc.length; i++) {
		io::eprintf("^");
	}

	io::eprintf("\n%s:%s:%s: %s: ", (ZString)file.full_path, loc.row, loc.col, error_kind);
	io::eprintf(format, ...args);
	io::eprintf("\n\n");
}

fn fault error_note(SourceLocId loc, String format, args...) {
	error_msg(loc, "note", format, ...args);
	return COMPILE_ERROR;
}

fn fault error(SourceLocId loc, String format, args...) {
	error_msg(loc, "error", format, ...args);
	return COMPILE_ERROR;
}

fn void EmissionContext.init(&self, sz vmem_size) {
	self.vmem.init(vmem_size)!!;
	self.type_ids.init(mem);
	self.id_count = 1;
}

fn void EmissionContext.free(&self) {
	self.vmem.free();
	self.type_ids.free();
}

fn Id? EmissionContext.get_type_id(&self, Type* type, SourceLocId reference_loc) {
	Id? id = self.type_ids[type];
	if(try id) {
		return id;
	}

	Id new_id = self.generate_id();
	switch(type.type_kind) {
		case TYPE_VOID: self.type_ops.op(self, TYPE_VOID, new_id);
		case TYPE_BOOL: self.type_ops.op(self, TYPE_BOOL, new_id);
		case TYPE_I8: self.type_ops.op(self, TYPE_INT, new_id, 8, 1);
		case TYPE_I16: self.type_ops.op(self, TYPE_INT, new_id, 16, 1);
		case TYPE_I32: self.type_ops.op(self, TYPE_INT, new_id, 32, 1);
		case TYPE_I64: self.type_ops.op(self, TYPE_INT, new_id, 64, 1);
		// case TYPE_I128: // unsupported for now.
		case TYPE_U8: self.type_ops.op(self, TYPE_INT, new_id, 8, 0);
		case TYPE_U16: self.type_ops.op(self, TYPE_INT, new_id, 16, 0);
		case TYPE_U32: self.type_ops.op(self, TYPE_INT, new_id, 32, 0);
		case TYPE_U64: self.type_ops.op(self, TYPE_INT, new_id, 64, 0);
		// case TYPE_U128: // unsupported for now.
		case TYPE_F16: self.type_ops.op(self, TYPE_FLOAT, new_id, 16);
		// case TYPE_BF16: // unsupported for now.
		case TYPE_F32: self.type_ops.op(self, TYPE_FLOAT, new_id, 32);
		case TYPE_F64: self.type_ops.op(self, TYPE_FLOAT, new_id, 64);
		// case TYPE_F128: // unsupported for now.
		// case TYPE_ANY: // runtime reflection in shaders is probably unnecessary.
		// case TYPE_TYPEID:

		case TYPE_FUNC_PTR:
			nextcase default;
		case TYPE_POINTER:
			Type* inner = type.pointer;
			Id inner_id = self.get_type_id(inner, reference_loc)!;
			self.type_ops.op(self, TYPE_UNTYPED_POINTER, new_id, StorageClass.PHYSICAL_STORAGE_BUFFER);
		case TYPE_TYPEDEF:
		case TYPE_CONSTSET:
		case TYPE_ENUM:
			nextcase default;
		case TYPE_FUNC_RAW: @pool() {
			TypeFunction *func = &type.function;

			Decl*[] params = ast::vec(func.signature.params);
			Id[] param_ids = mem::talloc_array(Id, params.len);

			for(sz i = 0; i < params.len; i++) {
				param_ids[i] = self.get_type_id(params[i].type, params[i].loc)!;
			}

			TypeInfo* ret_type = ast::type_info_ptr(func.signature.rtype);
			Id ret_id = self.get_type_id(ret_type.type, ret_type.loc)!;
			self.type_ops.op_raw(self, TYPE_FUNCTION, {new_id, ret_id}, (uint[])param_ids);
		};
		case TYPE_STRUCT:
		case TYPE_UNION:
		case TYPE_BITSTRUCT:
		case TYPE_ALIAS:
		case TYPE_UNTYPEDLIST:
		case TYPE_SLICE:
		case TYPE_ARRAY:
		case TYPE_FLEXIBLE_ARRAY:
		case TYPE_INFERRED_ARRAY:
		case TYPE_VECTOR:
		case TYPE_SIMD_VECTOR:
		case TYPE_INFERRED_VECTOR:
		case TYPE_OPTIONAL:
			return error(reference_loc, "Unsupported type: %s", ast::const_name(type.type_kind))~;
		default:
			return error(reference_loc, "Unsupported type: %s", ast::const_name(type.type_kind))~;
	}

	self.type_ids[type] = new_id;
	return new_id;
}

fn Id EmissionContext.generate_id(&self) {
	defer self.id_count += 1;
	return (Id)self.id_count;
}

macro char[] byte_view(void* ptr, sz size) => ((char*)ptr)[..size - 1];

fn void? EmissionContext.write(&self, OutStream stream) {
	uint[5] header = {
		0x07230203, // SPIR-V magic number.
		1 << 16 + 6 << 8, // SPIR-V target version number (1.6)
		0x3654597F, // Generator magic number, randomly generated.
		self.id_count, // ID bound, specifies that no IDs will be greater than this number.
		0, // Reserved for future use.
	};

	io::write_any(stream, &header)!;
	self.init_ops.write(stream)!;
	self.decoration_ops.write(stream)!;
	self.type_ops.write(stream)!;
	self.func_ops.write(stream)!;
}

fn void? OpStream.write(&self, OutStream stream) {
	Op* op = self.first_op;
	while(op) {
		uint opsize = op.operands[0] >> 16;
		io::write_all(stream, byte_view(&op.operands, opsize * uint::size))!;
		op = op.next;
	}
}

struct OpStream {
	Op* first_op;
	Op* last_op;
}

struct Op {
	Op* next;
	uint[*] operands;
}

fn void OpStream.op_raw(&self, EmissionContext* context, Opcode opcode, uint[]... operands) {
	sz opsize = 1;
	for(sz i = 0; i < operands.len; i++) {
		opsize += operands[i].len;
	}

	assert(opsize <= ushort::max);

	Op* op = alloc::malloc(&context.vmem, Op::size + opsize * uint::size);
	op.next = null;

	op.operands[0] = (uint)opsize << 16 + (ushort)opcode;
	for(sz x = 0, sz p = 1; x < operands.len; x++) {
		for(sz y = 0; y < operands[x].len; y++, p++) {
			op.operands[p] = operands[x][y];
		}
	}

	if(self.first_op == null) {
		self.first_op = op;
		self.last_op = op;
	}

	self.last_op.next = op;
	self.last_op = op;
}

fn void OpStream.op(&self, EmissionContext* context, Opcode opcode, uint... operands) {
	self.op_raw(context, opcode, operands);
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
			if(string != C3SPIRV_TAG) {
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

fn void? eval_func(EmissionContext* context, Decl* decl) {
	assert(decl.decl_kind == DECL_FUNC);
	Expr*[]? params = get_attribute(decl, SHADER);
	if(catch params) {
		return;
	}

	ExecutionModel execution_model = (ExecutionModel)eval_const_enum(params[0]);

	context.get_type_id(decl.type, decl.loc)!;
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

struct Root {
	float* in_buf;
	float* out_buf;
	uint count;
}

fn int main(String[] args)
{
	GlobalContext* gc = ast::load_ast({"c3cdev", "build", "--ast-dump"})!!;
	defer ast::free_ast();

	io::File out_file = file::open("output.spv", "w")!!;
	defer out_file.close();

	EmissionContext context;
	const sz VMEM_SIZE = 1024 * 1024 * 64;
	context.init(VMEM_SIZE);
	defer context.free();

	context.init_ops.op(&context, CAPABILITY, Capability.SHADER);
	context.init_ops.op(&context, CAPABILITY, Capability.UNTYPED_POINTERS);
	context.init_ops.op(&context, CAPABILITY, Capability.PHYSICAL_STORAGE_BUFFER_ADDRESSES);
	context.init_ops.op_raw(&context, EXTENSION, str_literal("SPV_KHR_untyped_pointers"));
	context.init_ops.op(&context, MEMORY_MODEL, AddressingModel.PHYSICAL_STORAGE_BUFFER_64, MemoryModel.GLSL450);

	Id void_type = context.generate_id();
	context.type_ops.op(&context, TYPE_VOID, void_type);

	Id function_type = context.generate_id();
	context.type_ops.op(&context, TYPE_FUNCTION, function_type, void_type);

	Id float_type = context.generate_id();
	context.type_ops.op(&context, TYPE_FLOAT, float_type, 32);

	Id uint_type = context.generate_id();
	context.type_ops.op(&context, TYPE_INT, uint_type, 32, 0);

	Id physical_ptr_type = context.generate_id();
	context.type_ops.op(&context, TYPE_UNTYPED_POINTER, physical_ptr_type, StorageClass.PHYSICAL_STORAGE_BUFFER);

	Id root_type = context.generate_id();
	context.type_ops.op(&context, TYPE_STRUCT, root_type, physical_ptr_type, physical_ptr_type, uint_type);
	context.decoration_ops.op(&context, DECORATE, root_type, Decoration.BLOCK);
	context.decoration_ops.op(&context, MEMBER_DECORATE, root_type, 0, Decoration.OFFSET, 0);
	context.decoration_ops.op(&context, MEMBER_DECORATE, root_type, 1, Decoration.OFFSET, 8);
	context.decoration_ops.op(&context, MEMBER_DECORATE, root_type, 2, Decoration.OFFSET, 16);

	Id uniform_ptr_type = context.generate_id();
	context.type_ops.op(&context, TYPE_UNTYPED_POINTER, uniform_ptr_type, StorageClass.UNIFORM);

	Id root_variable = context.generate_id();
	context.type_ops.op(&context, UNTYPED_VARIABLE, uniform_ptr_type, root_variable, StorageClass.UNIFORM, root_type);
	context.decoration_ops.op(&context, DECORATE, root_variable, Decoration.BINDING, 0);
	context.decoration_ops.op(&context, DECORATE, root_variable, Decoration.DESCRIPTOR_SET, 0);

	Id function = context.generate_id();
	context.func_ops.op(&context, FUNCTION, void_type, function, (uint)(FunctionControl){}, function_type);
	Id label = context.generate_id();
	context.func_ops.op(&context, LABEL, label);

	Id const_1 = context.generate_id();
	context.type_ops.op(&context, CONSTANT, uint_type, const_1, 1);

	Id out_buf_ref_ref = context.generate_id();
	context.func_ops.op(&context, UNTYPED_IN_BOUNDS_ACCESS_CHAIN, uniform_ptr_type, out_buf_ref_ref, root_type, root_variable, const_1);

	Id out_buf_ref = context.generate_id();
	context.func_ops.op(&context, LOAD, physical_ptr_type, out_buf_ref, out_buf_ref_ref);

	Id const_2f = context.generate_id();
	context.type_ops.op(&context, CONSTANT, float_type, const_2f, bitcast(2f, uint));
	context.func_ops.op(&context, STORE, out_buf_ref, const_2f, (uint)(MemoryOperands){.aligned}, 4);

	context.func_ops.op(&context, RETURN);
	context.func_ops.op(&context, FUNCTION_END);

	context.init_ops.op_raw(&context, ENTRY_POINT, {ExecutionModel.COMPUTE, function}, str_literal("main"), {root_variable});
	context.init_ops.op(&context, EXECUTION_MODE, function, ExecutionMode.LOCAL_SIZE, 64, 1, 1);

	// ast::@vec_foreach(gc.module_list; Module* mod) {
	// 	ast::@vec_foreach(mod.units; CompilationUnit* unit) {
	// 		ast::@vec_foreach(unit.functions; Decl* function) {
	// 			if(catch eval_func(&context, function)) {
	// 				return 1;
	// 			}
	// 		};
	// 	};
	// };

	context.write(&out_file)!!;
	return 0;
}
