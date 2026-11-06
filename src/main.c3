module ardot::c3spirv;
import ardot::c3c::ast;
import std::io, std::collections::map;

typedef Id = inline uint;

struct EmissionContext {
	Vmem vmem;
	uint id_count;
	HashMap{HashOp, Id} type_ids;

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

fn Id EmissionContext.type_op_raw(&self, Opcode opcode, uint[]... operands) {
	sz mark = self.vmem.mark();

	Id result @noinit;
	Op* op = self.create_op(opcode, &result, ... operands);

	Id? existing_id = self.type_ids[(HashOp)op];
	if(try existing_id) {
		self.vmem.reset(mark);
		self.id_count -= 1;
		return existing_id;
	}

	self.type_ids[(HashOp)op] = result;
	self.type_ops.add_op(op);
	return result;
}

fn Id EmissionContext.type_op(&self, Opcode opcode, uint... operands) {
	return self.type_op_raw(opcode, operands);
}

fn Id? EmissionContext.get_type_id(&self, Type* type, SourceLocId reference_loc) {
	// Id? id = self.type_ids[type];
	// if(try id) {
	// 	return id;
	// }

	// Id new_id = self.generate_id();
	// switch(type.type_kind) {
	// 	case TYPE_VOID: self.type_ops.op(self, TYPE_VOID, new_id);
	// 	case TYPE_BOOL: self.type_ops.op(self, TYPE_BOOL, new_id);
	// 	case TYPE_I8: self.type_ops.op(self, TYPE_INT, new_id, 8, 1);
	// 	case TYPE_I16: self.type_ops.op(self, TYPE_INT, new_id, 16, 1);
	// 	case TYPE_I32: self.type_ops.op(self, TYPE_INT, new_id, 32, 1);
	// 	case TYPE_I64: self.type_ops.op(self, TYPE_INT, new_id, 64, 1);
	// 	// case TYPE_I128: // unsupported for now.
	// 	case TYPE_U8: self.type_ops.op(self, TYPE_INT, new_id, 8, 0);
	// 	case TYPE_U16: self.type_ops.op(self, TYPE_INT, new_id, 16, 0);
	// 	case TYPE_U32: self.type_ops.op(self, TYPE_INT, new_id, 32, 0);
	// 	case TYPE_U64: self.type_ops.op(self, TYPE_INT, new_id, 64, 0);
	// 	// case TYPE_U128: // unsupported for now.
	// 	case TYPE_F16: self.type_ops.op(self, TYPE_FLOAT, new_id, 16);
	// 	// case TYPE_BF16: // unsupported for now.
	// 	case TYPE_F32: self.type_ops.op(self, TYPE_FLOAT, new_id, 32);
	// 	case TYPE_F64: self.type_ops.op(self, TYPE_FLOAT, new_id, 64);
	// 	// case TYPE_F128: // unsupported for now.
	// 	// case TYPE_ANY: // runtime reflection in shaders is probably unnecessary.
	// 	// case TYPE_TYPEID:

	// 	case TYPE_FUNC_PTR:
	// 		nextcase default;
	// 	case TYPE_POINTER:
	// 		Type* inner = type.pointer;
	// 		Id inner_id = self.get_type_id(inner, reference_loc)!;
	// 		self.type_ops.op(self, TYPE_UNTYPED_POINTER, new_id, StorageClass.PHYSICAL_STORAGE_BUFFER);
	// 	case TYPE_TYPEDEF:
	// 	case TYPE_CONSTSET:
	// 	case TYPE_ENUM:
	// 		nextcase default;
	// 	case TYPE_FUNC_RAW: @pool() {
	// 		TypeFunction *func = &type.function;

	// 		Decl*[] params = ast::vec(func.signature.params);
	// 		Id[] param_ids = mem::talloc_array(Id, params.len);

	// 		for(sz i = 0; i < params.len; i++) {
	// 			param_ids[i] = self.get_type_id(params[i].type, params[i].loc)!;
	// 		}

	// 		TypeInfo* ret_type = ast::type_info_ptr(func.signature.rtype);
	// 		Id ret_id = self.get_type_id(ret_type.type, ret_type.loc)!;
	// 		self.type_ops.op_raw(self, TYPE_FUNCTION, {new_id, ret_id}, (uint[])param_ids);
	// 	};
	// 	case TYPE_STRUCT:
	// 	case TYPE_UNION:
	// 	case TYPE_BITSTRUCT:
	// 	case TYPE_ALIAS:
	// 	case TYPE_UNTYPEDLIST:
	// 	case TYPE_SLICE:
	// 	case TYPE_ARRAY:
	// 	case TYPE_FLEXIBLE_ARRAY:
	// 	case TYPE_INFERRED_ARRAY:
	// 	case TYPE_VECTOR:
	// 	case TYPE_SIMD_VECTOR:
	// 	case TYPE_INFERRED_VECTOR:
	// 	case TYPE_OPTIONAL:
	// 		return error(reference_loc, "Unsupported type: %s", ast::const_name(type.type_kind))~;
	// 	default:
	// 		return error(reference_loc, "Unsupported type: %s", ast::const_name(type.type_kind))~;
	// }

	// self.type_ids[type] = new_id;
	// return new_id;
	unreachable();
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

fn uint Op.opsize(&self) {
	return self.operands[0] >> 16;
}

fn Opcode Op.opcode(&self) {
	return (Opcode)(self.operands[0] & 0xFFFF);
}

fn uint Op.result_index(&self) => self.opcode().result_index();

fn uint Op.hash(&self) {
	uint hash = builtin::@generic_hash(self.operands[0]);
	uint opsize = self.opsize();
	uint result_index = self.result_index();
	for(sz i = 1; i < opsize; i++) {
		if(i == result_index) {
			continue;
		}
		hash = builtin::@generic_hash_core(hash, self.operands[i]);
	}
	return hash;
}

fn bool Op.equals(&a, Op* b) {
	if(b.operands[0] != a.operands[0]) {
		return false;
	}

	uint opsize_a = a.opsize();
	uint opsize_b = b.opsize();
	if(opsize_a != opsize_b) {
		return false;
	}

	uint result_index = a.result_index();
	for(sz i = 1; i < opsize_a; i++) {
		if(i == result_index) {
			continue;
		} else if(a.operands[i] != b.operands[i]) {
			return false;
		}
	}

	return true;
}

typedef HashOp = inline Op*;

fn uint HashOp.hash(self) => Op.hash(self);
fn bool HashOp.equals(a, HashOp b) @operator(==) => Op.equals(a, b);

fn Op* EmissionContext.create_op(&self, Opcode opcode, Id* result, uint[]... operands) {
	uint result_index = opcode.result_index();

	sz opsize = 1 + (sz)(result_index > 0);
	for(sz i = 0; i < operands.len; i++) {
		opsize += operands[i].len;
	}

	assert(opsize <= ushort::max);

	Op* op = alloc::malloc(&self.vmem, Op::size + opsize * uint::size);
	op.next = null;

	Id id = self.generate_id();
	op.operands[result_index] = id;
	*result = id;

	op.operands[0] = (uint)opsize << 16 + (ushort)opcode;
	for(sz x = 0, sz p = 1; x < operands.len; x++) {
		for(sz y = 0; y < operands[x].len; y++, p++) {
			if(result_index != 0 && result_index == p) {
				p += 1;
			}

			op.operands[p] = operands[x][y];
		}
	}
	return op;
}

fn void OpStream.add_op(&self, Op* op) {
	if(self.first_op == null) {
		self.first_op = op;
		self.last_op = op;
	}

	self.last_op.next = op;
	self.last_op = op;
}

fn Id OpStream.op_raw(&self, EmissionContext* context, Opcode opcode, uint[]... operands) {
	Id result @noinit;
	self.add_op(context.create_op(opcode, &result, ...operands));
	return result;
}

fn Id OpStream.op(&self, EmissionContext* context, Opcode opcode, uint... operands) {
	return self.op_raw(context, opcode, operands);
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

	Id func = context.generate_id();
	context.func_ops.op(context, FUNCTION, void_type, func, (uint)(FunctionControl){}, func_type);
	Id label = context.generate_id();
	// context.func_ops.op(context, LABEL, );

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

fn int main(String[] args)
{
	emit_sample_program();

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
