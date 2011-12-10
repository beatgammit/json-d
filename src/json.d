module json;

import std.ascii;
import std.conv;
import std.range;
import std.utf;

import std.file;
import std.stdio;

enum JSON_TYPE : byte {
	// unicode string
	STRING,

	// double precision floating point (like in the browser)
	NUMBER,

	// hash string-JSON_TYPE
	OBJECT,

	// hash of numbers-JSON_TYPE
	ARRAY,

	// true or false
	BOOLEAN,

	// null
	NULL
}

struct JSONValue {
	union {
		string str;
		double num;
		JSONValue[string] obj;
		JSONValue[] arr;
		bool boolean;
	}

	JSON_TYPE type;

	auto typeString() {
		switch (this.type) {
			case JSON_TYPE.STRING:
				return "string";

			case JSON_TYPE.NUMBER:
				return "number";

			case JSON_TYPE.BOOLEAN:
				return "boolean";
	
			case JSON_TYPE.NULL:
				return "null";

			case JSON_TYPE.OBJECT:
				return "object";

			case JSON_TYPE.ARRAY:
				return "array";

			default:
				throw new Exception("Invalid JSON value type.");
		}
	}

	auto valueString() {
		switch (this.type) {
			case JSON_TYPE.STRING:
				return '"' ~ this.str ~ '"';

			case JSON_TYPE.NUMBER:
				return text(this.num);

			case JSON_TYPE.BOOLEAN:
				return text(this.boolean);
	
			case JSON_TYPE.NULL:
				return "null";

			case JSON_TYPE.OBJECT:
				string[] contents;
				foreach(key, value; this.obj) {
					contents ~= '"' ~ key ~ "\":" ~ value.valueString();
				}
				return '{' ~ contents.join(",") ~ '}';

			case JSON_TYPE.ARRAY:
				string[] contents;
				foreach(t; this.arr) {
					contents ~= t.valueString();
				}
				return '[' ~ contents.join(",") ~ ']';

			default:
				throw new Exception("Invalid JSON value type.");
		}
	}
	auto toString() {
		return this.typeString() ~ ':' ~ this.valueString;
	}
}

class JSONException : Exception {
	this(string msg) {
		super(msg);
	}
}

/*
 * Removes and returns the first element in arr.
 */
auto next(T)(ref T arr) if(isInputRange!T) {
	if (arr.empty) {
		throw new JSONException("Unexpected end of input.");
	}

	auto ret = arr.front;
	arr.popFront();

	return ret;
}

/*
 * Returns the first non-whitespace element in arr, popping whitespace elements as necessary.
 */
auto peekNonWhite(T)(ref T arr, in bool throwError = true) if(isInputRange!T) {
	auto c = arr.front;
	while (isWhite(c) && !arr.empty) {
		arr.popFront();

		// defer to next if for error handling
		if (arr.empty) {
			break;
		}

		c = arr.front;
	}

	if (throwError && arr.empty) {
		throw new JSONException("Unexpected end of input.");
	}

	return c;
}

/*
 * Pops off all whitespace elements until the first non-whitespace element is found, which is popped and returned.
 */
auto nextNonWhite(T)(ref T arr) if(isInputRange!T) {
	auto ret = arr.next();
	while (isWhite(ret)) {
		ret = arr.next();
	}

	return ret;
}

/*
 * Parses a JSON string.
 */
auto parseString(T)(ref T arr) if (isInputRange!T) {
	auto c = arr.nextNonWhite();
	if (c != '"') {
		throw new JSONException("Illegal start of string");
	}

	auto str = appender!string();
	c = arr.next();
	while(c != '"') {
		switch (c) {
			case '\\': // escape sequence
				c = arr.next();
				switch (c) {
					case '"':
					case '\\':
					case '/':
						str.put(c);
						break;
					case 'b':
						str.put('\b');
						break;
					case 'f':
						str.put('\f');
						break;
					case 'n':
						str.put('\n');
						break;
					case 'r':
						str.put('\r');
						break;
					case 't':
						str.put('\t');
						break;
					case 'u':
						auto val = 0;
						foreach_reverse(i; 0 .. 4) {
							auto hex = toUpper(arr.next());
							if(!isHexDigit(hex)) {
								throw new JSONException("Expecting hex character");
							}
							val += (isDigit(hex) ? hex - '0' : (hex - 'A') + 10) << (4 * i);
						}
						char[4] buf;
						str.put(toUTF8(buf, val));
						break;
					default:
						throw new JSONException(text("Invalid escape sequence '\\", c, "'."));
				}
				break;
			default: // anything else
				str.put(c);
				break;
		}

		c = arr.next();
	}

	return str.data;
}

unittest {
	import std.exception;

	// good values
	auto s = "\"hello\"";
	assertNotThrown!JSONException(assert(s.parseString() == "hello"));
	s = "\"hi\n\n\r\r\n\"";
	assertNotThrown!JSONException(assert(s.parseString() == "hi\n\n\r\r\n"));
	s = "\"\\u3992\"";
	assertNotThrown!JSONException(assert(s.parseString() == "\u3992"));
	s = "  \n \"sweet\" \t ";
	assertNotThrown!JSONException(assert(s.parseString() == "sweet"));

	// bad values
	s = "hi";
	assertThrown!JSONException(s.parseString());
	s = "\"hello";
	assertThrown!JSONException(s.parseString());
	s = "[]";
	assertThrown!JSONException(s.parseString());
	s = "{}";
	assertThrown!JSONException(s.parseString());
	s = "5";
	assertThrown!JSONException(s.parseString());
	s = " ";
	assertThrown!JSONException(s.parseString());
}

/*
 * Parses a JSON number.
 */
auto parseNumber(T)(ref T arr) if(isInputRange!T) {
	try {
		return parse!double(arr);
	} catch (Exception e) {
		throw new JSONException("Invalid number.");
	}
}

unittest {
	import std.exception;

	// good values
	auto s = "5";
	assertNotThrown!JSONException(assert(s.parseNumber() == 5));
	s = "5.5";
	assertNotThrown!JSONException(assert(s.parseNumber() == 5.5));
	s = "545.2342";
	assertNotThrown!JSONException(assert(s.parseNumber() == 545.2342));
	s = "-5.2e+10";
	assertNotThrown!JSONException(assert(s.parseNumber() == -5.2e+10));

	// bad values
	s = "true";
	assertThrown!JSONException(s.parseNumber());
	s = "false";
	assertThrown!JSONException(s.parseNumber());
	s = "hi";
	assertThrown!JSONException(s.parseNumber());
	s = "\"hello";
	assertThrown!JSONException(s.parseNumber());
	s = "[]";
	assertThrown!JSONException(s.parseNumber());
	s = "{}";
	assertThrown!JSONException(s.parseNumber());
	s = "pi";
	assertThrown!JSONException(s.parseNumber());
	s = " ";
	assertThrown!JSONException(s.parseNumber());
}

/*
 * Parses a JSON boolean value.
 */
bool parseBool(T)(ref T arr) if (isInputRange!T) {
	if (arr.length >= 4 && arr[0 .. 4] == "true") {
		arr.popFrontN(4);
		return true;
	} else if (arr.length >= 5 && arr[0 .. 5] == "false") {
		arr.popFrontN(5);
		return false;
	}

	throw new JSONException("Invalid expression. Expecting boolean.");
}

unittest {
	import std.exception;

	// good values
	auto s = "true";
	assertNotThrown!JSONException(assert(s.parseBool() == true));
	s = "false";
	assertNotThrown!JSONException(assert(s.parseBool() == false));

	// bad values
	s = "True";
	assertThrown!JSONException(s.parseBool());
	s = "FalSe";
	assertThrown!JSONException(s.parseBool());
	s = "hi";
	assertThrown!JSONException(s.parseBool());
	s = "\"hello";
	assertThrown!JSONException(s.parseBool());
	s = "[]";
	assertThrown!JSONException(s.parseBool());
	s = "{}";
	assertThrown!JSONException(s.parseBool());
	s = "pi";
	assertThrown!JSONException(s.parseBool());
	s = " ";
	assertThrown!JSONException(s.parseBool());
}

/*
 * Parses a JSON object.
 */
JSONValue[string] parseObject(T)(ref T arr) if (isInputRange!T) {
	JSONValue[string] obj;

	if (arr.next() != '{') {
		throw new JSONException("Illegal start of object.");
	}

	// empty object
	if (arr.peekNonWhite() == '}') {
		arr.next();
		return obj;
	}

	while (true) {
		auto key = arr.parseString();
		if (arr.nextNonWhite() != ':') {
			throw new JSONException("Illegal key/value separater");
		}

		obj[key] = arr.parseValue();

		auto c = arr.nextNonWhite();
		if (c == '}') {
			break;
		} else if (c != ',') {
			throw new JSONException(text("Unexpected character '", c, "'."));
		}
	}

	return obj;
}

unittest {
	import std.exception;

	// good values
	auto s = "{}";
	assertNotThrown!JSONException(s.parseObject());
	s = "{\"something\": 6, \"awesome\": []}";
	assertNotThrown!JSONException(s.parseObject());

	// bad values
	s = "True";
	assertThrown!JSONException(s.parseObject());
	s = "FalSe";
	assertThrown!JSONException(s.parseObject());
	s = "hi";
	assertThrown!JSONException(s.parseObject());
	s = "\"hello";
	assertThrown!JSONException(s.parseObject());
	s = "[]";
	assertThrown!JSONException(s.parseObject());
	s = "pi";
	assertThrown!JSONException(s.parseObject());
	s = " ";
	assertThrown!JSONException(s.parseObject());
}

/*
 * Parses a JSON array.
 */
JSONValue[] parseArray(T)(ref T arr) if (isInputRange!T) {
	JSONValue[] val;

	if (arr.next() != '[') {
		throw new JSONException("Illegal start of array.");
	}

	if (arr.peekNonWhite() == ']') {
		arr.popFront();
		return val;
	}

	while (true) {
		val ~= arr.parseValue();

		auto c = arr.nextNonWhite();
		if (c == ']') {
			break;
		} else if (c != ',') {
			throw new JSONException(text("Unexpected character '", c, "'."));
		}
	}

	return val;
}

unittest {
	import std.exception;

	// good values
	auto s = "[]";
	assertNotThrown!JSONException(s.parseArray());
	s = "[\"something\", 6, \"awesome\", []]";
	assertNotThrown!JSONException(s.parseArray());

	// bad values
	s = "True";
	assertThrown!JSONException(s.parseArray());
	s = "FalSe";
	assertThrown!JSONException(s.parseArray());
	s = "hi";
	assertThrown!JSONException(s.parseArray());
	s = "\"hello";
	assertThrown!JSONException(s.parseArray());
	s = "{}";
	assertThrown!JSONException(s.parseArray());
	s = "pi";
	assertThrown!JSONException(s.parseArray());
	s = " ";
	assertThrown!JSONException(s.parseArray());
}

/*
 * Determines what the next JSON value is and parses it.
 */
JSONValue parseValue(T)(ref T arr) if (isInputRange!T) {
	JSONValue val;
	switch (arr.peekNonWhite()) {
		case '"':
			val.type = JSON_TYPE.STRING;
			val.str = arr.parseString();
			break;
	
		case '0': .. case '9':
		case '-':
			val.type = JSON_TYPE.NUMBER;
			val.num = arr.parseNumber();
			break;
	
		case 't':
		case 'f':
			val.type = JSON_TYPE.BOOLEAN;
			val.boolean = arr.parseBool();
			break;

		case 'n':
			val.type = JSON_TYPE.NULL;
			if (arr[0 .. 3] != null) {
				throw new JSONException("Invalid expression. Expecting null.");
			}

			arr.popFrontN(4);
			break;

		case '{':
			val.type = JSON_TYPE.OBJECT;
			val.obj = arr.parseObject();
			break;

		case '[':
			val.type = JSON_TYPE.ARRAY;
			val.arr = arr.parseArray();
			break;

		default:
			throw new JSONException(text("Unexpected character '", arr.front, "'."));
	}

	return val;
}

/*
 * Parses a JSON string.
 */
JSONValue parseJSON(T)(ref T arr) if (isInputRange!T) {
	JSONValue root;

	root = arr.parseValue();

	if (!arr.empty && !isWhite(arr.peekNonWhite(false))) {
		throw new JSONException(text("Unexpected character '", arr.front, "'."));
	}

	return root;
}

int main(string[] args) {
	auto s = readText(args[1]);
	try {
		JSONValue root = parseJSON(s);
		writefln(root.toString());
	} catch (JSONException e) {
		writefln(e.msg);
		return 1;
	}

	return 0;
}
