module ardot::c3spirv::codegen;
import ardot::c3spirv, ardot::c3c::ast;

fn uint[] tstr_literal(String string) {
	// + 4 here because if the string perfectly fits into the literal that leaves no space
	// for the null terminator!
	sz elements = (string.len + 4) / 4; 

	uint[] literal = mem::talloc_array(uint, elements);
	literal[^1] = 0;
	mem::copy(literal, string, string.len);
	return literal;
}

fn Id expr_value(EmissionContext* context, SpirvExpr* expression) {
	if(expression.type.ref != expression.type.real) {
		return context.func_op(LOAD, type_id(context, expression.type.ref), expression.id, (uint)(MemoryOperands){.aligned}, 4);
	} else {
		return expression.id;
	}
}