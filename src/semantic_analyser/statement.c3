module ardot::c3spirv::sema;
import ardot::c3c::ast, ardot::c3spirv;

fn void? analyse_statement(SemaContext* context, Ast* statement) {
	while(statement) {
		switch(statement.ast_kind) {
			case AST_COMPOUND_STMT: 
				analyse_statement(context, ast::ast_ptr(statement.compound_stmt.first_stmt))!;
			case AST_DECLARE_STMT:
				analyse_declaration(context, statement.declare_stmt)!;
			case AST_EXPR_STMT:
				analyse_expression(context, statement.expr_stmt)!;
			case AST_IF_STMT:
				AstIfStmt* if_statement = &statement.if_stmt;
				analyse_expression(context, ast::expr_ptr(if_statement.cond))!;
				analyse_statement(context, ast::ast_ptr(if_statement.then_body))!;
				analyse_statement(context, ast::ast_ptr(if_statement.else_body))!;
			default: return err::error(statement.loc, "Unsupported statement kind: %s", ast::const_name(statement.ast_kind))~;
		}

		statement = ast::ast_ptr(statement.next);
	}
}