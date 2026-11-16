module ardot::c3spirv;
import ardot::c3c::ast, std::collections::list, std::collections::map;

import std::io;

typedef Id = inline uint;

struct SpirvEntryPoint {
	Decl* declaration;
	Id label;
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
			uint length;
		}
	}
}

struct SpirvFlowCommon {
	bitstruct : uint {
		bool func_return;
		bool macro_return;
	}
	SpirvExpr* macro_block;
}

struct SpirvAst {
	Ast* statement;
	union {
		SpirvFlowCommon flow;
		// Used for linked lists.
		SpirvAst* next;

		struct block_return {
			SpirvAst* next;
			SpirvExpr* block;
			Id value;
			Id* label;
		}
		struct if_s {
			SpirvFlowCommon flow;
			Id then_label;
			Id else_label;
			Id merge_label;
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
		struct function {
			Id return_var;
			Id return_label;
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
		struct access {
			uint index;
		}
		struct call {
			bool is_builtin;
			ShaderBuiltin builtin;
		}
		struct macro_block {
			LinkedList{SpirvAst} returns;
			Id return_label;
		}
		struct macro_return {
			SpirvExpr* next;
		}
		struct subscript {
			SpirvExpr* index;
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

struct GlobalContext {
	Vmem vmem;

	List{SpirvEntryPoint*} entry_points;
	HashMap{Expr*, SpirvExpr*} spirv_expressions;
	HashMap{Ast*, SpirvAst*} spirv_statements;

	GenContext* gen_context;
}

enum SemaStackFrameKind {
	MACRO,
	CONTROL_FLOW,
	FUNCTION,
}

struct SemaStackFrame {
	SemaStackFrame* parent;
	SemaStackFrameKind kind;
	Id* label;

	union {
		struct macro_frame {
			SpirvType* return_type;
			SpirvExpr* block;
		}
		struct function {
			SpirvType* return_type;
		}
		struct flow {
			SpirvAst* statement;
		}
	}
}

// Semantic analysis context.
struct SemaContext {
	GlobalContext* global;

	HashMap{SpirvType, SpirvType*} types;

	SpirvType* first_type;
	SpirvType* last_type;

	SemaStackFrame* frame;
}

struct GenContext {
	GlobalContext* global;

	uint id_count;

	HashMap{HashOp, Id} op_map;

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
fn uint Ast.hash(Ast* self) => void*.hash(self);

fn void GlobalContext.init(&self, sz vmem_size) {
	self.vmem.init(vmem_size)!!;
	self.entry_points.init(&self.vmem);
}

fn void GlobalContext.free(&self) {
	self.vmem.free();
}

fn void? GlobalContext.write(&self, OutStream stream) {
	return self.gen_context.write(stream);
}

fn void SemaContext.init(&self, GlobalContext* context) {
	self.global = context;
	self.types.init(&context.vmem);
}

fn void GenContext.init(&self, GlobalContext* context) {
	self.global = context;
	self.func_interfaces.init(&context.vmem);
	self.func_ops = &self.top_func_ops;
	self.id_count = 1;
}