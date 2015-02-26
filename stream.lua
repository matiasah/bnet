local ffi = require("ffi")
local print = print
local pairs = pairs
local table = table
local assert = assert

TStream = {}
local StreamMT = {__index = TStream}

function ReadByte(Stream)
	assert(Stream)
	return Stream:ReadByte()
end

function ReadShort(Stream)
	assert(Stream)
	return Stream:ReadShort()
end

function ReadInt(Stream)
	assert(Stream)
	return Stream:ReadInt()
end

function ReadLong(Stream)
	assert(Stream)
	return Stream:ReadLong()
end

function ReadLine(Stream)
	assert(Stream)
	return Stream:ReadLine()
end

function ReadString(Stream, Length)
	assert(Stream)
	return Stream:ReadString(Length)
end

function WriteByte(Stream, n)
	assert(Stream)
	return Stream:WriteByte(n)
end

function WriteShort(Stream, n)
	assert(Stream)
	return Stream:WriteShort(n)
end

function WriteInt(Stream, n)
	assert(Stream)
	return Stream:WriteInt(n)
end

function WriteLong(Stream, n)
	assert(Stream)
	return Stream:WriteLong(n)
end

function WriteLine(Stream, String)
	assert(Stream)
	return Stream:WriteLine(String)
end

function WriteString(Stream, String)
	assert(Stream)
	return Stream:WriteString(String)
end
