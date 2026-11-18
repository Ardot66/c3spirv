module ardot::c3spirv::err;
import ardot::c3c::ast, std::io;

struct LineInfo {
	String content;
	sz line;
}

<*
 @require before + after + 1 == dest.len : "Dest length is incompatible with the given parameters"
*>
fn void ast::File.get_lines(&self, sz offset, LineInfo[] dest, sz before = 0, sz after = 0) {
	String contents = (String)((char*)self.contents)[.. self.content_len - 1];
	sz lines = before + after + 1;

	sz start = offset;	
	while(start > 0) {
		if(contents[start] == '\n') {
			if(before <= 0) {
				start += 1;
				break;
			}
			before -= 1;
		}
		start -= 1;
	}

	sz line_no = 1;	
	for(sz i = start; i >= 0; i--) {
		if(contents[i] == '\n') {
			line_no += 1;
		}
	}

	sz output_idx = before;
	for(sz i = start, sz line_start = i; i < contents.len && output_idx < dest.len; i++) {
		if(contents[i] == '\n') {
			dest[output_idx] = {
				.content = contents[line_start..i - 1],
				.line = line_no,
			};

			line_start = i + 1;
			line_no += 1;
			output_idx += 1;
		}
	}
}

excuse {COMPILE_ERROR}
fn void error_msg(SourceLocId loc_id, String error_kind, String format, args...) {
	SourceLoc* loc = ast::source_loc_ptr(loc_id);
	ast::File* file = ast::gc().loaded_sources[loc.file_id];

	if(c3spirv::arg_context.test_mode) @pool() {
		io::eprintf("Error|%s|%s|%s|%s", ast::c_string(file.name), loc.row, loc.col, string::tformat(format, ...args));
		return;
	};

	LineInfo[7] lines;
	file.get_lines(loc.offset, &lines, before: 6);

	io::eprintf("\n");
	foreach(LineInfo line : lines) {
		if(line.line == 0) {
			continue;
		}
		io::eprintf("%6d: %s\n", line.line, line.content);
	}

	LineInfo* error_line = &lines[^1];
	for(sz i = 0; i < (sz)loc.col; i++) {
		char character = error_line.content[i];
		if(character == '\t') {
			io::eprintf("\t");
		} else {
			io::eprintf(" ");
		}
	}
	io::eprintf("       ");

	for(sz i = 0; i < loc.length; i++) {
		io::eprintf("^");
	}

	io::eprintf("\n%s:%s:%s: %s: ", (ZString)file.full_path, loc.row, loc.col, error_kind);
	io::eprintf(format, ...args);
	io::eprintf("\n\n");
}

fn fault error_note(SourceLocId loc, String format, args...) {
	error_msg(loc, "note", format, ...args);
	return COMPILE_ERROR;
}

fn fault error(SourceLocId loc, String format, args...) {
	error_msg(loc, "error", format, ...args);
	return COMPILE_ERROR;
}