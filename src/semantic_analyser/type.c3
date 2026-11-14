module ardot::c3spirv::sema;
import ardot::c3c::ast, ardot::c3spirv;
import std::io;

fn SpirvType* create_type(SemaContext* context, SpirvType* type) {
	SpirvType*? existing = context.types[*type];
	if(try existing) {
		return existing;
	}

	SpirvType* new = alloc::alloc(&context.global.vmem, SpirvType);
	mem::copy(new, type, SpirvType::size);
	context.add_type(new);

	context.types[*new] = new;

	// The only case where type is null currently is if it's a pointer.
	new.kind = type.type ? type.type.type_kind : TYPE_POINTER;
	// Types are considered resolved by default. This property is only set to false
	// in copy_unresolved.
	new.resolved = true;
	// Setting the original value of the type to itself makes some checks simpler.
	new.original = new;
	return new;
}

fn SpirvType* create_type_primitive(SemaContext* context, Type* type) {
	return create_type(context, &&{
		.type = type
	});
}

fn SpirvType* create_type_struct(SemaContext* context, Type* type, SpirvType*[] members, bool block) {
	SpirvType struct_type = {
		.type = type,
		.structure = {
			.members = alloc::alloc_array(&context.global.vmem, SpirvType*, members.len),
			.block = block,
		}
	};
	mem::copy(struct_type.structure.members, members, members.len * SpirvType*::size);
	return create_type(context, &struct_type);
}

fn SpirvType* create_type_vector(SemaContext* context, Type* type, SpirvType* member, uint length) {
	return create_type(context, &&{
		.type = type,
		.vector = {
			.member = member,
			.length = length,
		}
	});
}

fn SpirvType* create_type_pointer(SemaContext* context, Type* type, StorageClass class, SpirvType* inner) {
	return create_type(context, &&{
		.type = type,
		.pointer = {
			.class = class,
			.inner = inner,
		}
	});
}

// Creates an unresolved copy of the given type to be fully determined during analysis.
fn SpirvType* copy_type_unresolved(SemaContext* context, SpirvType* type) {
	SpirvType* new = alloc::alloc(&context.global.vmem, SpirvType);
	mem::copy(new, type, SpirvType::size);

	new.next = null;
	context.add_type(new);

	new.resolved = false;
	new.original = null;
	return new;
}

fn void resolve_type_final(SemaContext* context, SpirvType* type) {
	if(type.resolved) {
		return;
	}

	switch(type.kind) {
		case TYPE_POINTER: 
			resolve_type_final(context, type.pointer.inner);
			// Set the class to a reasonable value, it will never actually be used,
			// but it needs to be a valid class for stuff to work.
			type.pointer.class = PHYSICAL_STORAGE_BUFFER;
		case TYPE_STRUCT:
			for(sz i = 0; i < type.structure.members.len; i++) {
				resolve_type_final(context, type.structure.members[i]);
			}
			type.structure.block = false;
		case TYPE_VECTOR: resolve_type_final(context, type.vector.member);
	}

	type.resolved = true;
	type.original = type;
}

fn void? resolve_type(SemaContext* context, SpirvType* unresolved, SpirvType* resolved, SourceLocId loc) {
	if(!resolved.resolved) {
		return err::error(loc, "Cannot assign an unresolved type.")~;
	}

	if(unresolved.resolved) {
		if(!types_equal(unresolved, resolved)) {
			return err::error(loc, "Unable to resolve conflicting types.")~;
		}

		return;
	}

	assert(unresolved.kind == resolved.kind);

	switch(unresolved.kind) {
		case TYPE_POINTER: resolve_type(context, unresolved.pointer.inner, resolved.pointer.inner, loc)!;
		case TYPE_STRUCT:
			assert(unresolved.structure.members.len == resolved.structure.members.len);
			for(sz i = 0; i < unresolved.structure.members.len; i++) {
				resolve_type(
					context, 
					unresolved.structure.members[i], 
					resolved.structure.members[i], 
					loc
				)!;
			}
		case TYPE_VECTOR: resolve_type(context, unresolved.vector.member, resolved.vector.member, loc)!;
	}

	// Need to track the next type in the chain to ensure that type resolution doesn't break.
	SpirvType* next = unresolved.next;

	// Ensure that the types are byte-for-byte identical. The SpirvType.original field ensures
	// that only the original version will be used for ID emission to make things more efficient
	// when lots of copies are involved.
	*unresolved = *resolved;
	unresolved.next = next;
}

enum PointerMode {
	LOGICAL,
	PHYSICAL,
	UNRESOLVED,
}

fn SpirvType*? analyse_type(SemaContext* context, Type* type, SourceLocId loc, PointerMode pointer_mode, bool* parent_resolved = null) {
	bool is_primitive = false;
	is_primitive |= type.type_kind >= TYPE_NUM_FIRST && type.type_kind <= TYPE_NUM_LAST;
	is_primitive |= type.type_kind == TYPE_VOID || type.type_kind == TYPE_BOOL;

	bool resolved = true;
	SpirvType* spirv_type;
	if(is_primitive) {
		spirv_type = create_type_primitive(context, type);
	} else {
		switch(type.type_kind) {
			case TYPE_ALIAS: 
				spirv_type = analyse_type(context, type.canonical, loc, pointer_mode, &resolved)!;
			case TYPE_POINTER:
				switch(pointer_mode) {
					case LOGICAL:
						return err::error(loc, "Logical pointers are not supported by SPIR-V.")~;
					case PHYSICAL:
						spirv_type = create_type_pointer(context, type, PHYSICAL_STORAGE_BUFFER, analyse_type(context, type.pointer, loc, pointer_mode, &resolved))!;
					case UNRESOLVED:
						// Pointers are the only type that can be unresolved on their own at the moment.
						// This is because the pointer could theoretically have any storage class,
						// and this needs to be determined later on in analysis.
						resolved = false;
						spirv_type = create_type_pointer(context, type, INVALID, analyse_type(context, type.pointer, loc, pointer_mode, &resolved))!;
				}
			case TYPE_STRUCT: @pool() {
				StructDecl* struct_decl = &type.decl.strukt;
				Decl*[] members = ast::vec(struct_decl.members);

				SpirvType*[] member_types = mem::talloc_array(SpirvType*, members.len);
				foreach(sz i, Decl* member : members) {
					member_types[i] = analyse_type(context, member.type, member.loc, pointer_mode, &resolved)!;
				}

				spirv_type = create_type_struct(context, type, member_types, pointer_mode == PHYSICAL);
				if(pointer_mode == UNRESOLVED) {
					resolved = false;
				}
			};
			case TYPE_VECTOR: 
				spirv_type = create_type_vector(
					context, 
					type, 
					analyse_type(context, type.array.base, loc, pointer_mode, &resolved),
					(uint)type.array.len
				)!;
			default: return err::error(loc, "Unsupported type kind: %s", ast::const_name(type.type_kind))~;
		}
	}

	if(!resolved) {
		// Unresolved types need to be copied so that they can be filled in properly later.
		spirv_type = copy_type_unresolved(context, spirv_type);
		if(parent_resolved) {
			// If this type is unresolved, then any parent types should also be unresolved.
			*parent_resolved = false;
		}
	}

	return spirv_type;
}