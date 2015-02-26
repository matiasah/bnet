local ffi = require("ffi")
local socket_wrapper = require("socket")
local tostring = tostring
local tonumber = tonumber
local strsub = string.sub
local setmetatable = setmetatable
local assert = assert
local bor = require("bit").bor
local char = string.char

local function isnil(object)
	if object then
		return strsub(tostring(object), -4) == "NULL"
	end
	return true
end

ffi.cdef [[
	void free (void* ptr);
	void *malloc(size_t size);
]]
ffi.free = ffi.C.free
ffi.alloc = ffi.C.malloc

module("bnet")
BNET_MAX_CLIENTS = 1024

local function Shl(A, B)
	if A and B then
		return A * (2 ^ B)
	end
end

function CountHostIPs(Host)
	assert(Host)
	local Addresses, AdressType, AddressLength = socket_wrapper.gethostbyname_(Host)
	if isnil(Addresses) or AddressType ~= socket_wrapper.AF_INET or AddressLength ~= 4 then
		return 0
	end

	local Count = 0
	while not isnil(Addresses[Count]) do
		Count = Count + 1
	end
	return Count
end

function IntIP(IP)
	assert(IP)
	local InetADDR = socket_wrapper.inet_addr_(IP)
	local HTONL = socket_wrapper.htonl_(InetADDR)
	return HTONL
end

function StringIP(IP)
	assert(IP)
	local HTONL = socket_wrapper.htonl_(IP)
	local Addr = ffi.new("struct in_addr")
	Addr.s_addr = HTONL
	local NTOA = socket_wrapper.inet_ntoa_(Addr)
	return ffi.string(NTOA)
end

function ReadAvail(Stream)
	assert(Stream)
	local Size = ffi.new("int[1]")
	if Stream.UDP then
		if Stream.Socket == stream_wrapper.INVALID_SOCKET then
			return 0
		end
		if socket_wrapper.ioctl_(Stream.Socket, socket_wrapper.FIONREAD, Size) then
			return 0
		end
		return Size[0]
	elseif Stream.TCP then
		return Stream:Size()
	end
	return 0
end

TUDPStream = {
	Timeout = 0,
	Socket = 0,
	LocalIP = 0,
	LocalPort = 0,
	MessageIP = 0,
	MessagePort = 0,
	RecvSize = 0,
	SendSize = 0,
	UDP = true
}
UDP = {__index = TUDPStream}

function TUDPStream:ReadByte()
	local n = ffi.new("char[1]")
	self:ReadBytes(n, 1)
	return n[0]
end

function TUDPStream:ReadShort()
	local n = ffi.new("unsigned short[1]")
	self:ReadBytes(n, 2)
	return n[0]
end

function TUDPStream:ReadInt()
	local n = ffi.new("int[1]")
	self:ReadBytes(n, 4)
	return n[0]
end

function TUDPStream:ReadLong()
	local n = ffi.new("unsigned long[1]")
	self:ReadBytes(n, 8)
	return n[0]
end

function TUDPStream:ReadLine()
	local Buffer = ""
	local Size = 0
	while true do
		local Char = ffi.new("char[1]")
		local Result = self:Read(Char, 1)
		if self:Size() == 0 or Char[0] == 10 then
			break
		end
		if Char[0] ~= 13 and Char[0] ~= 0 then
			Buffer = Buffer .. char(Char[0])
		end
	end
	return Buffer
end

function TUDPStream:ReadString(Length)
	assert(Length >= 0, "illegal string length")
	local Buffer = ffi.new("char["..Length.."]")
	self:ReadBytes(Buffer, Length)
	return ffi.string(Buffer)
end

function TUDPStream:WriteByte(n)
	local q = ffi.new("char[1]", n)
	return self:WriteBytes(q, 1)
end

function TUDPStream:WriteShort(n)
	local q = ffi.cast("unsigned short[1]", n)
	return self:WriteBytes(q, 2)
end

function TUDPStream:WriteInt(n)
	local q = ffi.cast("int[1]", n)
	return self:WriteBytes(q, 4)
end

function TUDPStream:WriteLong(n)
	local q = ffi.cast("unsigned long[1]", n)
	return self:WriteBytes(q, 8)
end

function TUDPStream:WriteLine(String)
	local Line = String.."\n"
	return self:Write(Line, #Line)
end

function TUDPStream:WriteString(StringIP)
	local Buffer = ffi.new("char["..#String.."]", String)
	return self:WriteBytes(Buffer, ffi.sizeof(Buffer))
end

function TUDPStream:Read(Buffer, Size)
	local Temp
	if Size > self.RecvSize then
		Size = self.RecvSize
	end

	if Size > 0 then
		ffi.copy(Buffer, self.RecvBuffer, Size)
		if Size <  self.RecvSize then
			Temp = ffi.alloc(self.RecvBuffer, Size)
			ffi.copy(Temp, self.RecvBuffer + Size, self.RecvSize - Size)
			ffi.free(self.RecvBuffer)
			self.RecvBuffer = Temp
			self.RecvSize = self.RecvSize - Size
		else
			ffi.free(self.RecvBuffer)
			self.RecvSize = 0
		end
	end

	return Size
end

function TUDPStream:ReadBytes(Buffer, Count)
	for i = Count, 1, -1 do
		local n = self:Read(Buffer, i)
		if not n then
			return error("Failed to read amount of bytes")
		end
		Buffer = Buffer + n
	end
	return Count
end

function TUDPStream:Write(Buffer, Size)
	if Size <= 0 then
		return 0
	end

	local Temp = ffi.alloc(self.SendSize + Size)
	if self.SendSize > 0 then
		ffi.copy(Temp, self.SendBuffer, self.SendSize)
		ffi.copy(Temp + self.SendSize, Buffer, Size)
		ffi.free(self.SendBuffer)
		self.SendBuffer = Temp
		self.SendSize = self.SendSize + Size
	else
		ffi.copy(Temp, Buffer, Size)
		self.SendBuffer = Temp
		self.SendSize = Size
	end
end

function TUDPStream:WriteBytes(Buffer, Count)
	for i = Count, 1, -1 do
		local n = self:Write(Buffer, i)
		if not n then
			return error("Failed to write amount of bytes")
		end
		Buffer = Buffer + n
	end
	return Count
end

function TUDPStream:Size()
	return self.RecvSize
end

function TUDPStream:Eof()
	if self.Socket == socket_wrapper.INVALID_SOCKET then
		return true
	end
	return self.RecvSize == 0
end

function TUDPStream:Close()
	if self.Socket ~= socket_wrapper.INVALID_SOCKET then
		socket_wrapper.shutdown_(self.Socket, socket_wrapper.SD_BOTH)
		socket_wrapper.closesocket_(self.Socket)
		self.Socket = INVALID_SOCKET
	end
end

function CreateUDPStream(Port)
	if not Port then
		Port = 0
	end
	local Socket = socket_wrapper.socket_(socket_wrapper.AF_INET, socket_wrapper.SOCK_DGRAM, 0)
	if Socket == socket_wrapper.INVALID_SOCKET then
		return nil
	end

	if socket_wrapper.bind_(Socket, socket_wrapper.AF_INET, Port) == socket_wrapper.SOCKET_ERROR then
		socket_wrapper.shutdown_(Socket, socket_wrapper.SD_BOTH)
		socket_wrapper.closesocket_(Socket)
		return nil
	end

	local Address = ffi.new("struct sockaddr_in")
	local Addr = ffi.cast("struct sockaddr *", Address)
	local SizePtr = ffi.new("int[1]")
	SizePtr[0] = ffi.sizeof(Address)

	if socket_wrapper.getsockname_(Socket, Addr, SizePtr) == socket_wrapper.SOCKET_ERROR then
		socket_wrapper.shutdown_(Socket, socket_wrapper.SD_BOTH)
		socket_wrapper.closesocket_(Socket)
		return nil
	end

	local IP = socket_wrapper.inet_ntoa_(Address.sin_addr)
	local Port = socket_wrapper.ntohs_(Address.sin_port)
	local Stream = setmetatable({
		Socket = Socket,
		LocalIP = ffi.string(IP),
		LocalPort = Port
	}, UDP)
	return Stream
end

function CloseUDPStream(Stream)
	assert(Stream)
	return Stream:Close()
end

function RecvUDPMsg(Stream)
	assert(Stream)
	if Stream.Socket == socket_wrapper.INVALID_SOCKET then
		return false
	end

	local Read = ffi.new("int[1]", Stream.Socket)
	if socket_wrapper.select_(1, Read, 0, nil, 0, nil, self.Timeout) ~= 1  then
		return false
	end

	local Size = ffi.new("int[1]")
	if socket_wrapper.ioctl_(Stream.Socket, socket_wrapper.FIONREAD, Size) == socket_wrapper.SOCKET_ERROR then
		return false
	end

	Size = Size[0]
	if Size <= 0 then
		return false
	end

	if Stream.RecvSize > 0 then
		local Temp = ffi.alloc(Stream.RecvSize + Size)
		ffi.copy(Temp, Stream.RecvBuffer, Stream.RecvSize)
		ffi.free(Stream.RecvBuffer)
		Stream.RecvBuffer = Temp
	else
		Stream.RecvBuffer = ffi.alloc(Size)
	end

	local MessageIP = ffi.new("int", 0)
	local MessagePort = ffi.new("int", 0)
	local Result = socket_wrapper.recvfrom_(Stream.Socket, Stream.RecvBuffer + Stream.RecvSize, Size, 0, MessageIP, MessagePort)

	if Result == socket_wrapper.SOCKET_ERROR or Result == 0 then
		return nil
	else
		Stream.MessageIP = MessageIP
		Stream.MessagePort = MessagePort
		Stream.RecvSize = Stream.RecvSize + Result
		return MessageIP
	end
end

function SendUDPMsg(Stream, IP, Port)
	assert(Stream)
	assert(IP)
	assert(Port)
	if Stream.Socket == socket_wrapper.INVALID_SOCKET or Stream.SendSize == 0 then
		return nil
	end

	local Write = ffi.new("int[1]", Stream.Socket)
	if socket_wrapper.select_(0, nil, 1, Write, 0, nil, 0) ~= 1 then
		return nil
	end

	if not Port or Port == 0 then
		Port = Stream.LocalPort
	end

	local Result = socket_wrapper.sendto_(Stream.Socket, Stream.SendBuffer, Stream.SendSize, 0, IP, Port)
	if Result == socket_wrapper.SOCKET_ERROR or Result == 0 then
		return nil
	end

	if Result == Stream.SendSize then
		ffi.free(Stream.SendBuffer)
		Stream.SendSize = 0
	else
		local Temp = ffi.alloc(Stream.SendSize - Result)
		ffi.copy(Temp, Stream.SendBuffer + Result, Stream.SendSize - Result)
		ffi.free(Stream.SendBuffer)
		Stream.SendBuffer = Temp
	end
end

function UDPMsgIP(Stream)
	assert(Stream)
	return Stream.MessageIP
end

function UDPMsgPort(Stream)
	assert(Stream)
	return Stream.MessagePort
end

function UDPStreamIP(Stream)
	assert(Stream)
	return Stream.Socket ~= socket_wrapper.INVALID_SOCKET and Stream.LocalIP
end

function UDPStreamPort(Stream)
	assert(Stream)
	return Stream.Socket ~= socket_wrapper.INVALID_SOCKET and Stream.LocalPort
end

function UDPTimeouts(Recv)
	assert(Recv)
	if Recv >= 0 then
		TUDPStream.Timeout = Recv
	end
end

TTCPStream = {
	Timeouts = {
		[0] = 10000,
		[1] = 0
	},
	Socket = 0,
	LocalIP = 0,
	LocalPort = 0,
	TCP = true
}
TCP = {__index = TTCPStream}

function TTCPStream:ReadByte()
	local n = ffi.new("char[1]")
	self:ReadBytes(n, 1)
	return n[0]
end

function TTCPStream:ReadShort()
	local n = ffi.new("unsigned short[1]")
	self:ReadBytes(n, 2)
	return n[0]
end

function TTCPStream:ReadInt()
	local n = ffi.new("int[1]")
	self:ReadBytes(n, 4)
	return n[0]
end

function TTCPStream:ReadLong()
	local n = ffi.new("unsigned long[1]")
	self:ReadBytes(n, 8)
	return n[0]
end

function TTCPStream:ReadLine()
	local Buffer = ""
	local Size = 0
	while true do
		local Char = ffi.new("char[1]")
		local Result = self:Read(Char, 1)
		if self:Size() == 0 or Char[0] == 10 then
			break
		end
		if Char[0] ~= 13 and Char[0] ~= 0 then
			Buffer = Buffer .. char(Char[0])
		end
	end
	return Buffer
end

function TTCPStream:ReadString(Length)
	assert(Length >= 0, "illegal string length")
	local Buffer = ffi.new("char["..Length.."]")
	self:ReadBytes(Buffer, Length)
	return ffi.string(Buffer)
end

function TTCPStream:WriteByte(n)
	local q = ffi.new("char[1]", n)
	return self:WriteBytes(q, 1)
end

function TTCPStream:WriteShort(n)
	local q = ffi.cast("unsigned short[1]", n)
	return self:WriteBytes(q, 2)
end

function TTCPStream:WriteInt(n)
	local q = ffi.cast("int[1]", n)
	return self:WriteBytes(q, 4)
end

function TTCPStream:WriteLong(n)
	local q = ffi.cast("unsigned long[1]", n)
	return self:WriteBytes(q, 8)
end

function TTCPStream:WriteLine(String)
	local Line = String.."\n"
	return self:Write(Line, #Line)
end

function TTCPStream:WriteString(StringIP)
	local Buffer = ffi.new("char["..#String.."]", String)
	return self:WriteBytes(Buffer, ffi.sizeof(Buffer))
end

function TTCPStream:Connected()
	if self.Socket == socket_wrapper.INVALID_SOCKET then
		return false
	end
	local Read = ffi.new("int[1]", self.Socket)
	if socket_wrapper.select_(1, Read, 0, nil, 0, nil, 0) ~= 1 or ReadAvail(self) ~= 0 then
		return true
	end
	self:Close()
	return false
end

function TTCPStream:Read(Buffer, Size)
	if self.Socket == socket_wrapper.INVALID_SOCKET then
		return 0
	end

	local Read = ffi.new("int[1]", self.Socket)
	if socket_wrapper.select_(1, Read, 0, nil, 0, nil, self.Timeouts[0]) ~= 1 then
		return 0
	end

	local Result = socket_wrapper.recv_(self.Socket, Buffer, Size, 0)
	if Result == socket_wrapper.SOCKET_ERROR then
		return 0
	end
	return Result
end

function TTCPStream:ReadBytes(Buffer, Count)
	for i = Count, 1, -1 do
		local n = self:Read(Buffer, i)
		if not n then
			return error("Failed to read amount of bytes")
		end
		Buffer = Buffer + n
	end
	return Count
end

function TTCPStream:Write(Buffer, Size)
	if self.Socket == socket_wrapper.INVALID_SOCKET then
		return 0
	end

	local Write = ffi.new("int[1]", self.Socket)
	if socket_wrapper.select_(1, nil, 1, Write, 0, nil, 0) ~= 1 then
		return 0
	end

	local Result = socket_wrapper.send_(self.Socket, Buffer, Size, 0)
	if Result == socket_wrapper.SOCKET_ERROR then
		return 0
	end
	return Result
end

function TTCPStream:WriteBytes(Buffer, Count)
	for i = Count, 1, -1 do
		local n = self:Write(Buffer, i)
		if not n then
			return error("Failed to write amount of bytes")
		end
		Buffer = Buffer + n
	end
	return Count
end

function TTCPStream:Size()
	local Size = ffi.new("int[1]")
	if socket_wrapper.ioctl_(self.Socket, socket_wrapper.FIONREAD, Size) == socket_wrapper.SOCKET_ERROR then
		return 0
	end
	return Size[0]
end

function TTCPStream:Eof()
	if self.Socket == socket_wrapper.INVALID_SOCKET then
		return true
	end

	local Read = ffi.new("int[1]", self.Socket)
	local Result = socket_wrapper.select_(1, Read, 0, nil, 0, nil, self.Timeouts[0])
	if Result == socket_wrapper.SOCKET_ERROR then
		self:Close()
		return true
	elseif Result == 1 then
		if self:Size() == 0 then
			return true
		end
		return false
	end
	return true
end

function TTCPStream:Close()
	if self.Socket ~= socket_wrapper.INVALID_SOCKET then
		socket_wrapper.shutdown_(self.Socket, socket_wrapper.SD_BOTH)
		socket_wrapper.closesocket_(self.Socket)
		self.Socket = socket_wrapper.INVALID_SOCKET
	end
end

function TCPStreamConnected(Stream)
	assert(Stream)
	return Stream:Connected()
end

function OpenTCPStream(Server, ServerPort, LocalPort)
	assert(Server)
	assert(ServerPort)
	if not LocalPort then
		LocalPort = 0
	end

	local ServerIP = socket_wrapper.inet_addr_(Server)
	local PAddress
	if ServerIP == socket_wrapper.INADDR_NONE then
		local Addresses, AddressType, AddressLength = socket_wrapper.gethostbyname_(Server)
		if isnil(Addresses) or AddressType ~= socket_wrapper.AF_INET or AddressLength ~= 4 then
			return nil
		end
		if isnil(Addresses[0]) then
			return nil
		end
		PAddress = Addresses[0]
		local NAddress = {[0] = PAddress[0], PAddress[1], PAddress[2], PAddress[3]}
		if PAddress[0] < 0 then NAddress[0] = PAddress[0] + 256 end
		if PAddress[1] < 0 then NAddress[1] = PAddress[1] + 256 end
		if PAddress[2] < 0 then NAddress[2] = PAddress[2] + 256 end
		if PAddress[3] < 0 then NAddress[3] = PAddress[3] + 256 end
		ServerIP = bor(Shl(NAddress[3], 24), Shl(NAddress[2], 16), Shl(NAddress[1], 8), NAddress[0])
	end

	local Socket = socket_wrapper.socket_(socket_wrapper.AF_INET, socket_wrapper.SOCK_STREAM, 0)
	if Socket == socket_wrapper.INVALID_SOCKET then
		return nil
	end

	if socket_wrapper.bind_(Socket, socket_wrapper.AF_INET, LocalPort) == socket_wrapper.SOCKET_ERROR then
		socket_wrapper.shutdown_(Socket, socket_wrapper.SD_BOTH)
		socket_wrapper.closesocket_(Socket)
		return nil
	end

	local SAddress = ffi.new("struct sockaddr_in")
	local Addr = ffi.cast("struct sockaddr *", SAddress)
	local SizePtr = ffi.new("int[1]")
	SizePtr[0] = ffi.sizeof(SAddress)

	if socket_wrapper.getsockname_(Socket, Addr, SizePtr) == socket_wrapper.SOCKET_ERROR then
		socket_wrapper.shutdown_(Socket, socket_wrapper.SD_BOTH)
		socket_wrapper.closesocket_(Socket)
		return nil
	end

	local IP = socket_wrapper.inet_ntoa_(SAddress.sin_addr)
	local Port = socket_wrapper.ntohs_(SAddress.sin_port)
	local Stream = setmetatable({
		Socket = Socket,
		LocalIP = ffi.string(IP),
		LocalPort = Port
	}, TCP)

	local ServerPtr = ffi.new("int[1]")
	ServerPtr[0] = ServerIP

	if socket_wrapper.connect_(Socket, ServerPtr, socket_wrapper.AF_INET, 4, ServerPort) == socket_wrapper.SOCKET_ERROR then
		socket_wrapper.shutdown_(Socket, socket_wrapper.SD_BOTH)
		socket_wrapper.closesocket_(Socket)
		return nil
	end
	return Stream
end

function CloseTCPStream(Stream)
	assert(Stream)
	return Stream:Close()
end

function CreateTCPServer(Port)
	if not Port then
		Port = 0
	end

	local Socket = socket_wrapper.socket_(socket_wrapper.AF_INET, socket_wrapper.SOCK_STREAM, 0)
	if Socket == socket_wrapper.INVALID_SOCKET then
		return nil
	end

	if socket_wrapper.bind_(Socket, socket_wrapper.AF_INET, Port) == socket_wrapper.SOCKET_ERROR then
		socket_wrapper.shutdown_(Socket, socket_wrapper.SD_BOTH)
		socket_wrapper.closesocket_(Socket)
		return nil
	end

	local SAddress = ffi.new("struct sockaddr_in")
	local Addr = ffi.cast("struct sockaddr *", SAddress)
	local SizePtr = ffi.new("int[1]")
	SizePtr[0] = ffi.sizeof(SAddress)

	if socket_wrapper.getsockname_(Socket, Addr, SizePtr) == socket_wrapper.SOCKET_ERROR then
		socket_wrapper.shutdown_(Socket, socket_wrapper.SD_BOTH)
		socket_wrapper.closesocket_(Socket)
		return nil
	end

	local IP = socket_wrapper.inet_ntoa_(SAddress.sin_addr)
	local Port = socket_wrapper.ntohs_(SAddress.sin_port)
	local Stream = setmetatable({
		Socket = Socket,
		LocalIP = ffi.string(IP),
		LocalPort = Port
	}, TCP)

	if socket_wrapper.listen_(Socket, BNET_MAX_CLIENTS) == socket_wrapper.SOCKET_ERROR then
		socket_wrapper.shutdown_(Socket, socket_wrapper.SD_BOTH)
		socket_wrapper.closesocket_(Socket)
		return nil
	end
	return Stream
end

function AcceptTCPStream(Stream)
	assert(Stream)
	if Stream.Socket == socket_wrapper.INVALID_SOCKET then
		return nil
	end

	local Read = ffi.new("int[1]", Stream.Socket)
	if socket_wrapper.select_(1, Read, 0, nil, 0, nil, TTCPStream.Timeouts[1]) ~= 1 then
		return nil
	end

	local Address = ffi.new("struct sockaddr_in")
	local Addr = ffi.cast("struct sockaddr *", Address)
	local SizePtr = ffi.new("int[1]")
	SizePtr[0] = ffi.sizeof(Address)

	local Result = socket_wrapper.accept_(Stream.Socket, Addr, SizePtr)
	if Result == socket_wrapper.SOCKET_ERROR then
		return nil
	end

	local IP = socket_wrapper.inet_ntoa_(Address.sin_addr)
	local Port = socket_wrapper.ntohs_(Address.sin_port)
	local Client = setmetatable({
		Socket = Result,
		LocalIP = ffi.string(IP),
		LocalPort = Port
	}, TCP)
	return Client
end

function TCPStreamIP(Stream)
	assert(Stream)
	return Stream.LocalIP
end

function TCPStreamPort(Stream)
	assert(Stream)
	return Stream.LocalPort
end

function TCPTimeouts(Read, Accept)
	assert(Read)
	assert(Accept)
	if Read < 0 then Read = 0 end
	if Accept < 0 then Accept = 0 end
	TTCPStream.Timeouts[0] = Read
	TTCPStream.Timeouts[1] = Accept
end
