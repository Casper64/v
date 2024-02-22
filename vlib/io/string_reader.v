module io

import strings

// StringReader is able to read data from an Reader interface to a dynamically
// growing buffer using a string builder. Unlike the BufferedReader, StringReader will
// keep the entire contents of the buffer in memory, allowing the incoming data to be reused
// and read in an efficient matter
pub struct StringReader {
mut:
	reader Reader
pub mut:
	end_of_stream bool // whether we reached the end of the upstream reader
	builder strings.Builder
}

// new creates a new StringReader and sets the string builder size to `initial_size`
pub fn StringReader.new(reader Reader, initial_size int) StringReader {
	return StringReader{
		reader: reader
		builder: strings.new_builder(initial_size)
	}
}

// fill_bufer tries to read data into the buffer until either a 0 length read or if read_to_end_of_stream 
// is true then the end of the stream. It returns the number of bytes read
pub fn (mut r StringReader) fill_buffer(read_till_end_of_stream bool) !int {
	if r.end_of_stream {
		return Eof{}
	}
	
	start := r.builder.len
	// make sure there is enough room in the string builder
	r.builder.grow_len(io.read_all_len)

	mut end := start
	for {
		read := r.reader.read(mut r.builder[start..]) or {
			r.end_of_stream = true
			break
		}
		end += read
		
		if !read_till_end_of_stream && read == 0 {
			break
		} else if r.builder.len == end {
			r.builder.grow_len(io.read_all_grow_len)
		}
	}

	if end == start { return Eof{} }

	// shrink the length of the buffer to the total of bytes read
	r.builder.go_back(r.builder.len - end)
	return end - start
}

// fill_buffer_until tries read `n` amount of bytes from the reader into the buffer
pub fn (mut r StringReader) fill_buffer_until(n int) ! {
	if r.end_of_stream {
		return Eof{}
	}
	
	start := r.builder.len
	// make sure there is enough room in the string builder
	if n > io.read_all_len {
		r.builder.grow_len(io.read_all_len)
	} else {
		r.builder.grow_len(n)
	}

	mut end := start
	for {
		read := r.reader.read(mut r.builder[start..]) or {
			r.end_of_stream = true
			break
		}
		end += read
		
		if read == 0 || end - start == n {
			break
		} else if r.builder.len == end {
			if n - end > io.read_all_grow_len {
				r.builder.grow_len(io.read_all_grow_len)
			} else {
				r.builder.grow_len(n - end)
			}
		}
	}

	if end == start { return Eof{} }
}

// read_all reads all bytes from a reader until either a 0 length read or if read_to_end_of_stream 
// is true then the end of the stream. It returns a copy of the read data
pub fn (mut r StringReader) read_all(read_till_end_of_stream bool) ![]u8 {
	n := r.fill_buffer(read_till_end_of_stream)!
	return r.get_data_from(r.builder.len - n, r.builder.len)!
}

// read_bytes tries to read n amount of bytes from the reader
pub fn (mut r StringReader) read_bytes(n int) ![]u8 {
	r.fill_buffer_until(n)!
	return r.get_data_from(r.builder.len - n, r.builder.len)!
}

// read implements the Reader interface
pub fn (mut r StringReader) read(mut buf []u8) !int {
	start := r.builder.len

	r.fill_buffer_until(buf.len)!

	copy(mut buf, r.builder[start..])
	return r.builder.len - start
}

// TODO: implement + test
pub fn (mut r StringReader) read_line() !string {}

// write implements the Writer interface
pub fn (mut r StringReader) write(buf []u8) !int {
	return r.builder.write(buf)!
}

// get_data returns a copy of the buffer
pub fn (r StringReader) get_data() []u8 {
	mut data := []u8{len: r.builder.len}
	copy(mut data, r.builder)
	return data
}

// get data_from returns a copy of a part of the buffer
pub fn (r StringReader) get_data_from(start int, end int) ![]u8 {
	if end > r.builder.len { return Eof{} }

	// copy data from the string builder so it can be reused
	mut data := []u8{len: end - start}
	copy(mut data, r.builder[start..end])
	return data
}

// get_string produces a string from all the bytes in the buffer
pub fn (r StringReader) get_string() string {
	return r.builder.bytestr()
}

// get_string_from produces a string from `start` till `end` of the buffer
pub fn (r StringReader) get_string_from(start int, end int) !string {
	if end > r.builder.len { return Eof{} }

	return r.builder[start..end].bytestr()
}

// get a part of the buffer and shrink the length of the string builder, but keep the capacity.
// This method is useful when you need to grow the buffer by an unkown amount
pub fn (mut r StringReader) get_data_and_go_back(start int, end int) ![]u8 {
	if end > r.builder.len { return Eof{} }

	data := r.get_data_from(start, end)!
	r.builder.go_back(r.builder.len - end)

	return data
}