module ardot::c3spirv::linked_list <Type> ;

struct LinkedList {
	Type* first;
	Type* last;
}

<*
 @require $defined((Type){}.next)
*>
fn void LinkedList.push(&self, Type* value) {
	if(!self.first) {
		self.first = value;
		self.last = value;
		return;
	}

	self.last.next = value;
	self.last = value;
}

<*
 @require $defined((Type){}.next)
*>
fn sz LinkedList.len(&self) {
	sz count = 0;
	for(Type* element = self.first; element; element = element.next) {
		count += 1;
	}
	return count;
}

<*
 @require $defined((Type){}.next)
*>
macro void LinkedList.@enumerate(&self; @body(Type* element)) {
	for(Type* element = self.first; element; element = element.next) {
		@body(element);
	}
}