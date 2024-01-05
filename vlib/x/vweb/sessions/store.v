module sessions

// This
pub interface Store[T] {
mut:
	all() []T
	get(sid string) ?T
	destroy(sid string)
	clear()
	set(sid string, val T)
}

pub struct MemoryStore[T] {
mut:
	data map[string]T
}

pub fn (mut store MemoryStore[T]) all() []T {
	return store.data.values()
}

pub fn (mut store MemoryStore[T]) get(sid string) ?T {
	if data := store.data[sid] {
		return data
	} else {
		return none
	}
}

pub fn (mut store MemoryStore[T]) destroy(sid string) {
	store.data.delete(sid)
}

pub fn (mut store MemoryStore[T]) clear() {
	store.data.clear()
}

pub fn (mut store MemoryStore[T]) set(sid string, val T) {
	store.data[sid] = val
}
