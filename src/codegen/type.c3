module ardot::c3spirv::codegen;
import ardot::c3spirv, ardot::c3c::ast;

fn Id pointer_type_id(GenContext* context, SpirvType* type) {
	SpirvType* inner = type.pointer.inner;
	Id inner_id = type_id(context, inner);
	Id pointer_id = context.type_op(TYPE_POINTER, type.pointer.class, inner_id);
	if(inner.type.size > 0) {
		context.decoration_op(DECORATE, pointer_id, Decoration.ARRAY_STRIDE, (uint)inner.type.size);
	}
	return pointer_id;
}

fn Id type_id(GenContext* context, SpirvType* type) {
	assert(type.resolved);

	// Make sure we're working with the original type to make things more efficient.
	type = type.original;

	if(type.id) {
		return type.id;
	} else if(!type.type) {
		return pointer_type_id(context, type);
	}

	Id id;
	switch(type.type.type_kind) {
		case TYPE_VOID: id = context.type_op(TYPE_VOID);
		case TYPE_BOOL: id = context.type_op(TYPE_BOOL);
		case TYPE_I8: id = context.type_op(TYPE_INT, 8, 1);
		case TYPE_I16: id = context.type_op(TYPE_INT, 16, 1);
		case TYPE_I32: id = context.type_op(TYPE_INT, 32, 1);
		case TYPE_I64: id = context.type_op(TYPE_INT, 32, 1);
		// case TYPE_I64: id = context.type_op(TYPE_INT, 64, 1); // Limiting 64 bit constants for now.
		// case TYPE_I128: // unsupported for now.
		case TYPE_U8: id = context.type_op(TYPE_INT, 8, 0);
		case TYPE_U16: id = context.type_op(TYPE_INT, 16, 0);
		case TYPE_U32: id = context.type_op(TYPE_INT, 32, 0);
		case TYPE_U64: id = context.type_op(TYPE_INT, 32, 0);
		// case TYPE_U64: id = context.type_op(TYPE_INT, 64, 0); // Limiting 64 bit constants for now.
		// case TYPE_U128: // unsupported for now.
		case TYPE_F16: id = context.type_op(TYPE_FLOAT, 16);
		// case TYPE_BF16: // unsupported for now.
		case TYPE_F32: id = context.type_op(TYPE_FLOAT, 32);
		case TYPE_F64: id = context.type_op(TYPE_FLOAT, 64);
		// case TYPE_F128: // unsupported for now.

		case TYPE_POINTER: id = pointer_type_id(context, type);
		case TYPE_STRUCT: @pool() {
			StructDecl* struct_decl = &type.type.decl.strukt;

			Id[] member_ids = mem::talloc_array(Id, type.structure.members.len);
			foreach(sz i, SpirvType* member : type.structure.members) {
				member_ids[i] = type_id(context, member);
			};

			// Need to use op_raw here because struct type ops might be identical, but
			// should have different decorations.
			id = context.type_ops.op_raw(context, TYPE_STRUCT, (uint[])member_ids);
			if(type.structure.block) {
				context.decoration_op(DECORATE, id, Decoration.BLOCK);
				foreach(sz i, Decl* member : ast::vec(struct_decl.members)) {
					context.decoration_op(MEMBER_DECORATE, id, (uint)i, Decoration.OFFSET, (uint)member.offset);
				}
			}
		};
		case TYPE_VECTOR:
			Id inner = type_id(context, type.vector.member);
			id = context.type_op(TYPE_VECTOR, inner, (uint)type.vector.length);
		default:
			unreachable("Unsupported codegen type: %s", ast::const_name(type.type.type_kind));
	}

	assert(id);
	type.id = id;
	return id;
}