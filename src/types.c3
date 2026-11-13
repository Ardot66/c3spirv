module ardot::c3spirv;
import ardot::c3c::ast, std::collections::list, std::collections::map;

import std::io;

typedef Id = inline uint;

struct SpirvEntryPoint {
	Decl* declaration;
	ExecutionModel model;
	union {
		struct compute {
			uint[<3>] group_size;
		}
	}
}

struct SpirvType {
	Type* type;
	Id id;
	bitstruct : uint {
		TypeKind kind : 0..16;
		// Whether the type an all subtypes have had their storage class
		// determined.
		bool resolved : 17;
	}
	// If this type was resolved, it is going to be a copy of another existing type.
	// This variable points back to that existing type to make codegen more efficient.	 
	SpirvType* original;

	// All SpirvTypes are stored in a linked list so that they can be fully resolved
	// in another sema pass.
	SpirvType* next;
	union {
		struct pointer {
			SpirvType* inner;
			StorageClass class;
		}
		struct structure {
			bool block;
			SpirvType*[] members;
		}
		struct vector {
			SpirvType* member;
			int length;
		}
	}
}

struct SpirvDecl {
	Decl* declaration;
	union {
		struct variable {
			ExprType type;
			Id pointer_type_id;
			Id id;
		}
	}
}

struct ExprType {
	// The type being pointed at, it is the same as the real type if there is no reference.
	SpirvType* ref;
	SpirvType* real;
}

struct SpirvExpr {
	Expr* expression;
	ExprType type;
	Id id;
	union {
		struct call {
			bool is_builtin;
			ShaderBuiltin builtin;
		}
		struct access {
			uint index;
		}
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

// Needed so that Op* works correctly in hashmaps.
typedef HashOp = inline Op*;

struct EmissionContext {
	List{SpirvEntryPoint*} entry_points;
	SpirvType* first_type;
	SpirvType* last_type;

	Vmem vmem;
	uint id_count;
	HashMap{SpirvType, SpirvType*} types;
	HashMap{Expr*, SpirvExpr*} spirv_expressions;
	HashMap{HashOp, Id} op_map;
	// HashMap{HashOp, Id} global_ids;

	OpStream init_ops;
	OpStream decoration_ops;
	OpStream type_ops;
	OpStream top_func_ops;

	OpStream* func_ops;

	// Function specific stuff, managed by emit_function and emit_entry_point.
	OpStream func_var_ops;
	List{Id} func_interfaces;
}

macro char[] byte_view(void* ptr, sz size) => ((char*)ptr)[..size - 1];

fn uint SpirvType.hash(self) => byte_view(&self, SpirvType::size).hash();
fn bool SpirvType.equals(SpirvType a, SpirvType b) => byte_view(&a, SpirvType::size) == byte_view(&b, SpirvType::size);

fn uint Expr.hash(Expr* self) => void*.hash(self);

fn void EmissionContext.init(&self, sz vmem_size) {
	self.vmem.init(vmem_size)!!;
	self.entry_points.init(&self.vmem);
	self.types.init(&self.vmem);
	self.func_interfaces.init(&self.vmem);

	self.id_count = 1;
	self.func_ops = &self.top_func_ops;
}

fn void EmissionContext.free(&self) {
	self.vmem.free();
}

fn void EmissionContext.add_type(&self, SpirvType* type) {
	if(!self.first_type) {
		self.first_type = type;
		self.last_type = type;
		return;
	}

	self.last_type.next = type;
	self.last_type = type;
}