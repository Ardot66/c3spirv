module ardot::c3spirv;
import ardot::c3c::ast, std::io, std::collections::map, std::collections::list;

fn uint Expr.hash(Expr* self) => void*.hash(self);

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
	self.entry_points.init(&self.vmem);
	self.types.init(&self.vmem);
	// self.global_ids.init(&self.vmem);
	self.id_count = 1;
}

fn void EmissionContext.free(&self) {
	self.vmem.free();
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

fn Id EmissionContext.init_op_raw(&self, Opcode opcode, uint[]... operands) {
	return self.init_ops.op_raw(self, opcode, ...operands);
}

fn Id EmissionContext.init_op(&self, Opcode opcode, uint... operands) {
	return self.init_ops.op(self, opcode, ...operands);
}

fn Id EmissionContext.type_op_raw(&self, Opcode opcode, uint[]... operands) {
	sz mark = self.vmem.mark();

	Id result @noinit;
	Op* op = self.create_op(opcode, &result, ... operands);

	Id? existing_type = self.type_op_map[(HashOp)op];
	if(try existing_type) {
		self.vmem.reset(mark);
		self.id_count -= 1;
		return existing_type;
	}

	self.type_op_map[(HashOp)op] = result;
	self.type_ops.add_op(op);
	return result;
}

fn Id EmissionContext.type_op(&self, Opcode opcode, uint... operands) {
	return self.type_op_raw(opcode, operands);
}

fn Id EmissionContext.decoration_op_raw(&self, Opcode opcode, uint[]... operands) {
	return self.decoration_ops.op_raw(self, opcode, ...operands);
}

fn Id EmissionContext.decoration_op(&self, Opcode opcode, uint... operands) {
	return self.decoration_ops.op(self, opcode, ...operands);
}

fn Id EmissionContext.func_op_raw(&self, Opcode opcode, uint[]... operands) {
	return self.func_ops.op_raw(self, opcode, ...operands);
}

fn Id EmissionContext.func_op(&self, Opcode opcode, uint... operands) {
	return self.func_ops.op(self, opcode, ...operands);
}

// fn SpirvType*? spirv_type(EmissionContext* context, Type* type, SourceLocId reference_loc, TypeContext type_context = {}) {
// 	SpirvTypeInfo* info = type_info(context, type);
// 	SpirvType* stype;
// 	switch(type.type_kind) {
// 		case TYPE_VOID: stype = context.type_op(TYPE_VOID);
// 		case TYPE_BOOL: stype = context.type_op(TYPE_BOOL);
// 		case TYPE_I8: stype = context.type_op(TYPE_INT, 8, 1);
// 		case TYPE_I16: stype = context.type_op(TYPE_INT, 16, 1);
// 		case TYPE_I32: stype = context.type_op(TYPE_INT, 32, 1);
// 		case TYPE_I64: stype = context.type_op(TYPE_INT, 64, 1);
// 		// case TYPE_I128: // unsupported for now.
// 		case TYPE_U8: stype = context.type_op(TYPE_INT, 8, 0);
// 		case TYPE_U16: stype = context.type_op(TYPE_INT, 16, 0);
// 		case TYPE_U32: stype = context.type_op(TYPE_INT, 32, 0);
// 		case TYPE_U64: stype = context.type_op(TYPE_INT, 64, 0);
// 		// case TYPE_U128: // unsupported for now.
// 		case TYPE_F16: stype = context.type_op(TYPE_FLOAT, 16);
// 		// case TYPE_BF16: // unsupported for now.
// 		case TYPE_F32: stype = context.type_op(TYPE_FLOAT, 32);
// 		case TYPE_F64: stype = context.type_op(TYPE_FLOAT, 64);
// 		// case TYPE_F128: // unsupported for now.

// 		case TYPE_POINTER:
// 			Type* inner = type.pointer;
// 			StorageClass class = FUNCTION;
// 			if(type_context.uniform_ptr) {
// 				class = UNIFORM;
// 				type_context.uniform_ptr = false;
// 			} else if(type_context.in_root) {
// 				class = PHYSICAL_STORAGE_BUFFER;
// 			}

// 			SpirvType* inner_type = spirv_type(context, inner, reference_loc, type_context)!;
// 			stype = context.type_op(TYPE_POINTER, class, inner_type.id);
// 			stype.pointer = {
// 				.inner = inner_type,
// 				.class = class,
// 			};
// 		case TYPE_STRUCT: @pool() {
// 			if(info.root) {
// 				type_context.in_root = true;
// 			}

// 			StructDecl* struct_decl = &type.decl.strukt;
// 			Decl*[] members = ast::vec(struct_decl.members);

// 			SpirvType*[] member_types = alloc::alloc_array(&context.vmem, SpirvType*, members.len);
// 			Id[] member_ids = mem::talloc_array(Id, members.len);

// 			foreach(sz i, Decl* member : members) {
// 				SpirvType* member_type = spirv_type(context, member.type, member.loc, type_context)!;
// 				member_types[i] = member_type;
// 				member_ids[i] = member_type.id;
// 			};

// 			SpirvType* struct_type = context.type_op_raw(TYPE_STRUCT, (uint[])member_ids);
// 			if(!struct_type.type) {
// 				if(info.root) {
// 					context.decoration_op(DECORATE, struct_type.id, Decoration.BLOCK);
// 				}
// 				foreach(sz i, Decl* member : members) {
// 					context.decoration_op(MEMBER_DECORATE, struct_type.id, (uint)i, Decoration.OFFSET, (uint)member.offset);
// 				}

// 				struct_type.members = member_types;
// 			}

// 			stype = struct_type;
// 		};
// 		default:
// 			return err::error(reference_loc, "Unsupported type: %s", ast::const_name(type.type_kind))~;
// 	}

// 	assert(stype);
// 	if(stype.type == null) {
// 		stype.type = type;
// 	}

// 	return stype;
// }

// fn Id? EmissionContext.decl_id(&self, Decl* decl) {
// 	assert(decl.decl_kind == DECL_VAR);

// 	if(decl.backend_ref) {
// 		return (Id)(uptr)decl.backend_ref;
// 	}

// 	Type* type = decl.type;
// 	return {};
// }