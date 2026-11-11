module ardot::c3spirv::codegen;
import ardot::c3spirv, ardot::c3c::ast;

fn void emit_statement(EmissionContext* context, Ast* statement) {
	while(statement) {
		switch(statement.ast_kind) {
			case AST_COMPOUND_STMT:
				emit_statement(context, ast::ast_ptr(statement.compound_stmt.first_stmt));
			case AST_DECLARE_STMT:
				emit_declaration(context, statement.declare_stmt);
			case AST_EXPR_STMT:
				emit_expression(context, statement.expr_stmt);
			case AST_IF_STMT:
				AstIfStmt* if_statement = &statement.if_stmt;
				SpirvExpr* condition = emit_expression(context, ast::expr_ptr(if_statement.cond));

				assert(!if_statement.else_body);

				OpStream merge_stream;
				Id merge_label;
				@push_stream(context, &merge_stream) {
					merge_label = context.func_op(LABEL);
				};

				OpStream then_stream;
				Id then_label;
				@push_stream(context, &then_stream) {
					then_label = context.func_op(LABEL);
					emit_statement(context, ast::ast_ptr(if_statement.then_body));
					context.func_op(BRANCH, merge_label);
				};

				context.func_op(SELECTION_MERGE, merge_label, SelectionControl.NONE);
				context.func_op(BRANCH_CONDITIONAL, expr_value(context, condition), then_label, merge_label);

				append_stream(context, &then_stream);
				append_stream(context, &merge_stream);
			default: unreachable("Unsupported codegen statement: %s", ast::const_name(statement.ast_kind));
		}

		statement = ast::ast_ptr(statement.next);
	}
}