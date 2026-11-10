module ardot::c3spirv;
import ardot::c3c::ast, std::collections::list, std::collections::map;

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
	Id id;
	Type* type;
	union {
		struct pointer {
			SpirvType* inner;
			StorageClass class;
		}
		struct structure {
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
			bool writeable;
			SpirvType* type;
			SpirvType* real_type;
			Id id;
			Id pointer_type_id;
		}
	}
}

struct ExprType {
	SpirvType* real;
	// The type being pointed at, it is the same as the real type if there is no reference.
	SpirvType* ref;
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

	Vmem vmem;
	uint id_count;
	HashMap{char[], SpirvType*} types;
	HashMap{Expr*, SpirvExpr*} spirv_expressions;
	HashMap{HashOp, Id} op_map;
	// HashMap{HashOp, Id} global_ids;

	OpStream init_ops;
	OpStream decoration_ops;
	OpStream type_ops;
	OpStream func_ops;

	// Function specific stuff, managed by emit_function and emit_entry_point.
	OpStream func_var_ops;
	List{Id} func_interfaces;
}

macro char[] byte_view(void* ptr, sz size) => ((char*)ptr)[..size - 1];

fn uint Expr.hash(Expr* self) => void*.hash(self);

fn void EmissionContext.init(&self, sz vmem_size) {
	self.vmem.init(vmem_size)!!;
	self.entry_points.init(&self.vmem);
	self.types.init(&self.vmem);
	self.func_interfaces.init(&self.vmem);
	// self.global_ids.init(&self.vmem);
	self.id_count = 1;
}

fn void EmissionContext.free(&self) {
	self.vmem.free();
}

