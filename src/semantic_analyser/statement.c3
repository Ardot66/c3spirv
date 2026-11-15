module ardot::c3spirv::sema @local;
import ardot::c3c::ast, ardot::c3spirv;

import std::io;

fn void? analyse_if(SemaContext* context, SpirvAst* spirv_stmt) {
	AstIfStmt* if_statement = &spirv_stmt.statement.if_stmt;
	SemaStackFrame frame = {
		.kind = CONTROL_FLOW, 
		.flow = {
			.statement = spirv_stmt
		},
	};
	context.@push_frame(&frame) {
		analyse_expression(context, ast::expr_ptr(if_statement.cond))!;
		analyse_statement(context, ast::ast_ptr(if_statement.then_body))!;
		analyse_statement(context, ast::ast_ptr(if_statement.else_body))!;
	};
}

fn void? analyse_return(SemaContext* context, SpirvAst* spirv_stmt) {
	AstReturnStmt* return_s = &spirv_stmt.statement.return_stmt;

	SpirvExpr* expression = null; 
	if(return_s.expr) {
		expression = analyse_expression(context, return_s.expr)!;
	}

	SemaStackFrame* frame = context.frame;
	bool flow_marked = false;
	while(frame) {
		if(frame.kind == CONTROL_FLOW && !flow_marked) {
			frame.flow.statement.flow.returns = true;
			flow_marked = true;	
		} else if(frame.kind == FUNCTION) {
			// Need to resolve the return type here if possible to ensure that the function
			// doesn't try to return incompatible types in different places.
			if(expression) {
				resolve_type(context, frame.function.return_type, expression.type.ref, expression.expression.loc)!;
			}
			break;
		}

		frame = frame.parent;
	}
}

fn void? analyse_statement(SemaContext* context, Ast* statement) @public {
	while(statement) {
		SpirvAst* spirv_stmt = alloc::new(&context.global.vmem, SpirvAst, {
			.statement = statement
		});
		context.global.spirv_statements[statement] = spirv_stmt;

		switch(statement.ast_kind) {
			case AST_COMPOUND_STMT: analyse_statement(context, ast::ast_ptr(statement.compound_stmt.first_stmt))!;
			case AST_DECLARE_STMT: analyse_declaration(context, statement.declare_stmt)!;
			case AST_EXPR_STMT: analyse_expression(context, statement.expr_stmt)!;
			case AST_IF_STMT: analyse_if(context, spirv_stmt)!;
			case AST_RETURN_STMT: analyse_return(context, spirv_stmt)!;
			default: return err::error(statement.loc, "Unsupported statement kind: %s", ast::const_name(statement.ast_kind))~;
		}

		statement = ast::ast_ptr(statement.next);
	}
}