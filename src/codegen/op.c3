module ardot::c3spirv::codegen;
import ardot::c3c::ast, std::io, std::collections::map, std::collections::list;

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

// Append a given stream to the context's func_ops stream.
fn void append_stream(GenContext* context, OpStream* stream) {
	if(stream.first_op == null) {
		return;
	}

	Op* last_op = context.func_ops.last_op;
	last_op.next = stream.first_op;
	context.func_ops.last_op = stream.last_op;

	*stream = {};
}

fn void Op.insert_stream(&self, OpStream* stream) {
	if(stream.first_op == null) {
		return;
	}

	Op* after = self.next;
	self.next = stream.first_op;
	stream.last_op.next = after;

	stream.first_op = null;
	stream.last_op = null;
}

fn uint HashOp.hash(self) => Op.hash(self);
fn bool HashOp.equals(a, HashOp b) @operator(==) => Op.equals(a, b);

fn Id GenContext.generate_id(&self) {

	defer self.id_count += 1;
	return (Id)self.id_count;
}

fn void GenContext.print(&self) {
	self.init_ops.print();
	self.decoration_ops.print();
	self.type_ops.print();
	self.func_ops.print();
}

fn void OpStream.print(&self) => @pool() {
	DString buffer;
	buffer.tinit(256);
	Op* op = self.first_op;
	while(op) {
		uint opsize = op.opsize();
		Opcode opcode = op.opcode();

		uint result_index = op.result_index();
		uint result_id = result_index == 0 ? 0 : op.operands[result_index];
		if(result_index) {
			buffer.appendf("%%%s = ", result_id);
		}
		buffer.appendf("%s ", ast::const_name(opcode));
		sz whitespace = 30 - buffer.len();
		for(sz i = 0; i < whitespace; i++) {
			io::print(" ");
		}
		io::print(buffer);
		for(sz i = 1; i < opsize; i++) {
			if(i == result_index) continue;
			io::printf("%s ", op.operands[i]);
		}
		io::print("\n");

		op = op.next;

		buffer.clear();
	}
}

fn void? GenContext.write(&self, OutStream stream) {
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
		io::write_all(stream, c3spirv::byte_view(&op.operands, opsize * uint::size))!;
		op = op.next;
	}
}

fn Op* GenContext.create_op(&self, Opcode opcode, Id* result, uint[]... operands) {
	uint result_index = opcode.result_index();

	sz opsize = 1 + (sz)(result_index > 0);
	for(sz i = 0; i < operands.len; i++) {
		opsize += operands[i].len;
	}

	assert(opsize <= ushort::max);

	Op* op = alloc::malloc(&self.global.vmem, Op::size + opsize * uint::size);
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

fn Id OpStream.unique_op_raw(&self, GenContext* context, Opcode opcode, uint[]... operands) {
	sz mark = context.global.vmem.mark();

	Id result @noinit;
	Op* op = context.create_op(opcode, &result, ... operands);

	Id? existing_type = context.op_map[(HashOp)op];
	if(try existing_type) {
		context.global.vmem.reset(mark);
		context.id_count -= 1;
		return existing_type;
	}

	context.op_map[(HashOp)op] = result;
	self.add_op(op);
	return result;
}

fn Id OpStream.op_raw(&self, GenContext* context, Opcode opcode, uint[]... operands) {
	Id result @noinit;
	self.add_op(context.create_op(opcode, &result, ...operands));
	return result;
}

fn Id OpStream.op(&self, GenContext* context, Opcode opcode, uint... operands) {
	return self.op_raw(context, opcode, operands);
}

fn Id GenContext.init_op_raw(&self, Opcode opcode, uint[]... operands) {
	return self.init_ops.op_raw(self, opcode, ...operands);
}

fn Id GenContext.init_op(&self, Opcode opcode, uint... operands) {
	return self.init_ops.op_raw(self, opcode, operands);
}

fn Id GenContext.type_op_raw(&self, Opcode opcode, uint[]... operands) {
	return self.type_ops.unique_op_raw(self, opcode, ...operands);
}

fn Id GenContext.type_op(&self, Opcode opcode, uint... operands) {
	return self.type_ops.unique_op_raw(self, opcode, operands);
}

fn Id GenContext.decoration_op_raw(&self, Opcode opcode, uint[]... operands) {
	return self.decoration_ops.unique_op_raw(self, opcode, ...operands);
}

fn Id GenContext.decoration_op(&self, Opcode opcode, uint... operands) {
	return self.decoration_ops.unique_op_raw(self, opcode, operands);
}

fn Id GenContext.func_op_raw(&self, Opcode opcode, uint[]... operands) {
	return self.func_ops.op_raw(self, opcode, ...operands);
}

fn Id GenContext.func_op(&self, Opcode opcode, uint... operands) {
	return self.func_ops.op_raw(self, opcode, operands);
}

fn Id GenContext.func_var_op_raw(&self, Opcode opcode, uint[]... operands) {
	return self.func_var_ops.op_raw(self, opcode, ...operands);
}

fn Id GenContext.func_var_op(&self, Opcode opcode, uint... operands) {
	return self.func_var_ops.op_raw(self, opcode, operands);
}

// Pushes an OpStream into the context's func_ops variable for the duration of the body.
macro void @push_stream(GenContext* context, OpStream* stream; @body) {
	OpStream* old_stream = context.func_ops;
	context.func_ops = stream;
	@body();
	context.func_ops = old_stream;
}