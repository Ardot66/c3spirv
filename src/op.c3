module ardot::c3spirv @private;
import ardot::c3c::ast, std::io, std::collections::map;

typedef Id = inline uint;

struct OpStream {
	Op* first_op;
	Op* last_op;
}

struct Op {
	Op* next;
	uint[*] operands;
}

// Needed so that Op* works correctly in hashmaps.
typedef HashOp = inline Op*;

struct EmissionContext {
	Vmem vmem;
	uint id_count;
	HashMap{HashOp, Id} type_ids;

	OpStream init_ops;
	OpStream decoration_ops;
	OpStream type_ops;
	OpStream func_ops;
}

fn uint Op.opsize(&self) => self.operands[0] >> 16;
fn Opcode Op.opcode(&self) => (Opcode)(self.operands[0] & 0xFFFF);
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

fn uint HashOp.hash(self) => Op.hash(self);
fn bool HashOp.equals(a, HashOp b) @operator(==) => Op.equals(a, b);

fn void EmissionContext.init(&self, sz vmem_size) {
	self.vmem.init(vmem_size)!!;
	self.type_ids.init(mem);
	self.id_count = 1;
}

fn void EmissionContext.free(&self) {
	self.vmem.free();
	self.type_ids.free();
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

