module ardot::c3spirv::sema;
import ardot::c3c::ast, ardot::c3spirv;

fn SpirvType* create_type(EmissionContext* context, SpirvType* type) {
	SpirvType*? existing = context.types[c3spirv::byte_view(type, SpirvType::size)];
	if(try existing) {
		return existing;
	}

	SpirvType* new = alloc::alloc(&context.vmem, SpirvType);
	mem::copy(new, type, SpirvType::size);
	return new;
}

fn SpirvType* create_type_primitive(EmissionContext* context, Type* type) {
	return create_type(context, &&{
		.type = type
	});
}

fn SpirvType* create_type_struct(EmissionContext* context, Type* type, SpirvType*[] members) {
	SpirvType struct_type = {
		.type = type,
		.structure = {
			.members = alloc::alloc_array(&context.vmem, SpirvType*, members.len),
		}
	};
	mem::copy(struct_type.structure.members, members, members.len * SpirvType*::size);
	return create_type(context, &struct_type);
}

fn SpirvType* create_type_vector(EmissionContext* context, Type* type, SpirvType* member, int length) {
	return create_type(context, &&{
		.type = type,
		.vector = {
			.member = member,
			.length = length,
		}
	});
}

fn SpirvType* create_type_pointer(EmissionContext* context, Type* type, StorageClass class, SpirvType* inner) {
	return create_type(context, &&{
		.type = type,
		.pointer = {
			.class = class,
			.inner = inner,
		}
	});
}

fn SpirvType*? analyse_logical_type(EmissionContext* context, Type* type, SourceLocId loc) {
	bool is_primitive = false;
	is_primitive |= type.type_kind >= TYPE_NUM_FIRST && type.type_kind <= TYPE_NUM_LAST;
	is_primitive |= type.type_kind == TYPE_VOID || type.type_kind == TYPE_BOOL;
	if(is_primitive) {
		return create_type_primitive(context, type);
	}

	switch(type.type_kind) {
		case TYPE_ALIAS:
			return analyse_logical_type(context, type.canonical, loc);
		case TYPE_STRUCT: @pool() {
			StructDecl* struct_decl = &type.decl.strukt;
			Decl*[] members = ast::vec(struct_decl.members);

			SpirvType*[] member_types = mem::talloc_array(SpirvType*, members.len);
			foreach(sz i, Decl* member : members) {
				member_types[i] = analyse_logical_type(context, member.type, member.loc)!;
			}

			return create_type_struct(context, type, member_types);
		};
		case TYPE_VECTOR:
			return create_type_vector(context, type, analyse_logical_type(context, type.array.base, loc), type.array.len);
		default: return err::error(loc, "Unsupported logical memory type kind: %s", ast::const_name(type.type_kind))~;
	}
}

fn SpirvType*? analyse_physical_type(EmissionContext* context, Type* type, SourceLocId loc) {
	bool is_primitive = false;
	is_primitive |= type.type_kind >= TYPE_NUM_FIRST && type.type_kind <= TYPE_NUM_LAST;
	is_primitive |= type.type_kind == TYPE_VOID || type.type_kind == TYPE_BOOL;
	if(is_primitive) {
		return create_type_primitive(context, type);
	}

	switch(type.type_kind) {
		case TYPE_STRUCT: @pool() {
			StructDecl* struct_decl = &type.decl.strukt;
			Decl*[] members = ast::vec(struct_decl.members);

			SpirvType*[] member_types = mem::talloc_array(SpirvType*, members.len);
			foreach(sz i, Decl* member : members) {
				member_types[i] = analyse_physical_type(context, member.type, member.loc)!;
			}

			return create_type_struct(context, type, member_types);
		};
		case TYPE_POINTER:
			return create_type_pointer(context, type, PHYSICAL_STORAGE_BUFFER, analyse_physical_type(context, type.pointer, loc))!;
		default: return err::error(loc, "Unsupported physical memory type kind: %s", ast::const_name(type.type_kind))~;
	}
}

