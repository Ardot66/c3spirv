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
		}
	}
}

struct SpirvDecl {
	Decl* declaration;
	union {
		struct variable {
			SpirvType* type;
		}
	}
}

struct SpirvExpr {
	Expr* expression;
	SpirvType* type;
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
	HashMap{HashOp, Id} type_op_map;
	// HashMap{HashOp, Id} global_ids;

	OpStream init_ops;
	OpStream decoration_ops;
	OpStream type_ops;
	OpStream func_ops;
}

