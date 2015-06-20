local ffi = require("ffi")
local bit = require("bit")
local fd_lib

local tostring = tostring
local tonumber = tonumber
local strsub = string.sub
local setmetatable = setmetatable
local assert = assert
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
local C = ffi.C

module("bnet")
BNET_MAX_CLIENTS = 1024

local INVALID_SOCKET = -1
local INADDR_ANY = 0
local INADDR_NONE = 0XFFFFFFFF

local AF_INET = 2
local SOCK_STREAM = 1
local SOCK_DGRAM = 2
local SOCKET_ERROR = -1

local SD_BOTH = 2

local FIONREAD
local sock, netdb, ioctl_
if ffi.os == "Windows" then
	FIONREAD = 0x4004667F

	sock = ffi.load("ws2_32")
	ffi.cdef [[
		typedef uint16_t u_short;
		typedef uint32_t u_int;
		typedef unsigned long u_long;
		typedef uintptr_t SOCKET;
		struct TUDPStream {
			int Timeout;
			SOCKET Socket;
			char * LocalIP;
			int LocalPort;
			char * MessageIP;
			int MessagePort;
			int RecvSize;
			int SendSize;
			void * RecvBuffer;
			void * SendBuffer;
			bool UDP;
		};
		struct TTCPStream {
			int Timeouts[2];
			SOCKET Socket;
			char * LocalIP;
			int LocalPort;
			bool TCP;
		};
		struct sockaddr {
			unsigned short sa_family;
			char sa_data[14];
		};
		struct in_addr {
			uint32_t s_addr;
		};
		struct sockaddr_in {
			short   sin_family;
			unsigned short sin_port;
			struct  in_addr sin_addr;
			char    sin_zero[8];
		};
		typedef unsigned short WORD;
		typedef struct WSAData {
			WORD wVersion;
			WORD wHighVersion;
			char szDescription[257];
			char szSystemStatus[129];
			unsigned short iMaxSockets;
			unsigned short iMaxUdpDg;
			char *lpVendorInfo;
		} WSADATA, *LPWSADATA;
		typedef struct hostent {
			char *h_name;
			char **h_aliases;
			short h_addrtype;
			short h_length;
			char **h_addr_list;
		};
		typedef struct timeval {
			long tv_sec;
			long tv_usec;
		} timeval;
		typedef struct fd_set {
			u_int fd_count;
			SOCKET  fd_array[64];
		} fd_set;
		u_long htonl(u_long hostlong);
		u_short htons(u_short hostshort);
		u_short ntohs(u_short netshort);
		u_long ntohl(u_long netlong);
		unsigned long inet_addr(const char *cp);
		char *inet_ntoa(struct in_addr in);
		SOCKET socket(int af, int type, int protocol);
		SOCKET accept(SOCKET s,struct sockaddr *addr,int *addrlen);
		int bind(SOCKET s, const struct sockaddr *name, int namelen);
		int closesocket(SOCKET s);
		int connect(SOCKET s, const struct sockaddr *name, int namelen);
		int getsockname(SOCKET s, struct sockaddr *addr, int *namelen);
		int ioctlsocket(SOCKET s, long cmd, u_long *argp);
		int listen(SOCKET s, int backlog);
		int recv(SOCKET s, char *buf, int len, int flags);
		int recvfrom(SOCKET s, char *buf, int len, int flags, struct sockaddr *from, int *fromlen);
		int select(int nfds, fd_set *readfds, fd_set *writefds, fd_set *exceptfds, const struct timeval *timeout);
		int send(SOCKET s, const char *buf, int len, int flags);
		int sendto(SOCKET s, const char *buf, int len, int flags, const struct sockaddr *to, int tolen);
		int shutdown(SOCKET s, int how);
		struct hostent *gethostbyname(const char *name);
		struct hostent *gethostbyaddr(const char *addr, int len, int type);

		int __WSAFDIsSet(SOCKET fd, fd_set * set);
		int WSAStartup(WORD wVersionRequested, LPWSADATA lpWSAData);
		int WSACleanup(void);

		int atexit(void (__cdecl * func)( void));
	]]

	sock.WSAStartup(0x101, ffi.new("WSADATA"))
	ffi.C.atexit(sock.WSACleanup)

	fd_lib = {
		FD_CLR = function (fd, set)
			for i = 0, set.fd_count do
				if set.fd_array[i] == fd then
					while i < set.fd_count-1 do
						set.fd_array[i] = set.fd_array[i + 1]
						i = i + 1
					end
					set.fd_count = set.fd_count - 1
					break
				end
			end
		end,
		FD_SET = function (fd, set)
			local Index = 0
			for i = 0, set.fd_count do
				if set.fd_array[i] == fd then
					Index = i
					break
				end
			end

			if Index == set.fd_count then
				if set.fd_count < 64 then
					set.fd_array[Index] = fd
					set.fd_count = set.fd_count + 1
				end
			end
		end,
		FD_ZERO = function (set)
			set.fd_count = 0
		end,
		FD_ISSET = sock.__WSAFDIsSet,
	}

	function ioctl_(s, cmd, argp)
		return sock.ioctlsocket(s, cmd, argp)
	end
else
	sock = ffi.load("sys/socket.h")
	netdb = ffi.load("netdb.h")
	ffi.cdef [[
		typedef uint16_t u_short;
		typedef uint32_t u_int;
		typedef unsigned long u_long;
		typedef uintptr_t SOCKET;
		struct TUDPStream {
			int Timeout;
			SOCKET Socket;
			char * LocalIP;
			int LocalPort;
			char * MessageIP;
			int MessagePort;
			int RecvSize;
			int SendSize;
			void * RecvBuffer;
			void * SendBuffer;
			bool UDP;
		};
		struct TTCPStream {
			int Timeouts[2];
			SOCKET Socket;
			char * LocalIP;
			int LocalPort;
			bool TCP;
		};
		struct sockaddr {
			unsigned short sa_family;
			char sa_data[14];
		};
		struct in_addr {
			uint32_t s_addr;
		};
		struct sockaddr_in {
			short   sin_family;
			u_short sin_port;
			struct  in_addr sin_addr;
			char    sin_zero[8];
		};
		typedef struct hostent {
			char *h_name;
			char **h_aliases;
			short h_addrtype;
			short h_length;
			char **h_addr_list;
		};
		typedef struct timeval {
			long int tv_sec;
			long int tv_usec;
		};
		typedef struct fd_set {
			u_int fd_count;
			SOCKET  fd_array[64];
		} fd_set;
		u_long htonl(u_long hostlong);
		u_short htons(u_short hostshort);
		u_short ntohs(u_short netshort);
		u_long ntohl(u_long netlong);
		unsigned long inet_addr(const char *cp);
		char *inet_ntoa(struct in_addr in);
		SOCKET socket(int af, int type, int protocol);
		SOCKET accept(SOCKET s,struct sockaddr *addr,int *addrlen);
		int bind(SOCKET s, const struct sockaddr *name, int namelen);
		int close(SOCKET s);
		int connect(SOCKET s, const struct sockaddr *name, int namelen);
		int getsockname(SOCKET s, struct sockaddr *addr, int *namelen);
		int ioctl(SOCKET s, long cmd, u_long *argp);
		int listen(SOCKET s, int backlog);
		int recv(SOCKET s, char *buf, int len, int flags);
		int recvfrom(SOCKET s, char *buf, int len, int flags, struct sockaddr *from, int *fromlen);
		int select(int nfds, fd_set *readfds, fd_set *writefds, fd_set *exceptfds, const struct timeval *timeout);
		int send(SOCKET s, const char *buf, int len, int flags);
		int sendto(SOCKET s, const char *buf, int len, int flags, const struct sockaddr *to, int tolen);
		int shutdown(SOCKET s, int how);
		struct hostent *gethostbyname(const char *name);
		struct hostent *gethostbyaddr(const char *addr, int len, int type);
	]]

	fd_lib = ffi.load("sys/select.h")
	ffi.cdef [[
		void FD_CLR(int fd, fd_set *set);
		void FD_SET(int fd, fd_set *set);
		void FD_ZERO(fd_set *set);
		int FD_ISSET(int fd, fd_set *set);
	]]

	function ioctl_(s, cmd, argp)
		return sock.ioctl(s, cmd, argp)
	end

	if ffi.os == "MacOS" then
		FIONREAD = 0x4004667F
	elseif ffi.os == "Linux" then
		FIONREAD = 0x0000541B
	end
end

local closesocket_
if ffi.os == "Windows" then
	function closesocket_(s)
		return sock.closesocket(s)
	end
else
	function closesocket_(s)
		return sock.close(s)
	end
end

local function bind_(socket, addr_type, port)
	local sa = ffi.new("struct sockaddr_in")
	if addr_type ~= AF_INET then
		return -1
	end

	ffi.fill(sa, 0, ffi.sizeof(sa))
	sa.sin_family = addr_type
	sa.sin_addr.s_addr = sock.htonl(INADDR_ANY)
	sa.sin_port = sock.htons(port)

	local _sa = ffi.cast("struct sockaddr *", sa)
	return sock.bind(socket, _sa, ffi.sizeof(sa))
end

local function gethostbyaddr_(addr, addr_len, addr_type)
	local e = sock.gethostbyaddr(addr, addr_len, addr_type)
	if not isnil(e) then
		return e.h_name
	end
end

local function gethostbyname_(name)
	local e = sock.gethostbyname(name)
	if not isnil(e) then
		return e.h_addr_list, e.h_addrtype, e.h_length
	end
end

local function connect_(socket, addr, addr_type, addr_len, port)
	local sa = ffi.new("struct sockaddr_in")
	if addr_type == AF_INET then
		ffi.fill(sa, 0, ffi.sizeof(sa))
		sa.sin_family = addr_type
		sa.sin_port = sock.htons(port)
		ffi.copy(sa.sin_addr, addr, addr_len)

		local Addr = ffi.cast("struct sockaddr *", sa)
		return sock.connect(socket, Addr, ffi.sizeof(sa))
	end
	return SOCKET_ERROR
end

local function select_(n_read, r_socks, n_write, w_socks, n_except, e_socks, millis)
	local r_set = ffi.new("fd_set")
	local w_set = ffi.new("fd_set")
	local e_set = ffi.new("fd_set")

	r_socks = r_socks or {}
	w_socks = w_socks or {}
	e_socks = e_socks or {}

	local n = -1

	fd_lib.FD_ZERO(r_set)
	for i = 0, n_read do
		if r_socks[i] then
			fd_lib.FD_SET(r_socks[i], r_set)
			if r_socks[i] > n then
				n = r_socks[i]
			end
		end
	end

	fd_lib.FD_ZERO(w_set)
	for i = 0, n_write do
		if w_socks[i] then
			fd_lib.FD_SET(w_socks[i], w_set)
			if w_socks[i] > n then
				n = w_socks[i]
			end
		end
	end

	fd_lib.FD_ZERO(e_set)
	for i = 0, n_except do
		if e_socks[i] then
			fd_lib.FD_SET(e_socks[i], e_set)
			if e_socks[i] > n then
				n = e_socks[i]
			end
		end
	end

	local tvp
	if millis < 0 then
		tvp = ffi.new("struct timeval[0]")
	else
		tv = ffi.new("struct timeval")
		tv.tv_sec = millis / 1000
		tv.tv_usec = (millis % 1000) / 1000
		tvp = ffi.new("struct timeval[1]")
		tvp[0] = tv
	end

	local r = sock.select(n + 1, r_set, w_set, e_set, tvp)
	if r < 0 then
		return r
	end

	for i = 0, n_read do
		if r_socks[i] and not fd_lib.FD_ISSET(r_socks[i], r_set) then
			r_socks[i] = nil
		end
	end
	for i = 0, n_write do
		if w_socks[i] and not fd_lib.FD_ISSET(w_socks[i], w_set) then
			w_rocks[i] = nil
		end
	end
	for i = 0, n_except do
		if e_socks[i] and not fd_lib.FD_ISSET(e_socks[i], e_set) then
			e_socks[i] = nil
		end
	end
	return r
end

local function sendto_(socket, buf, size, flags, dest_ip, dest_port)
	local sa = ffi.new("struct sockaddr_in")
	ffi.fill(sa, 0, ffi.sizeof(sa))

	sa.sin_family = AF_INET
	sa.sin_addr.s_addr = sock.inet_addr(dest_ip)
	sa.sin_port = sock.htons(dest_port)
	return sock.sendto(socket, buf, size, flags, ffi.cast("struct sockaddr *", sa), ffi.sizeof(sa))
end

local function recvfrom_(socket, buf, size, flags)
	local sa = ffi.new("struct sockaddr_in")
	ffi.fill(sa, 0, ffi.sizeof(sa))

	local sasize = ffi.new("int[1]", ffi.sizeof(sa))
	local count = sock.recvfrom(socket, buf, size, flags, ffi.cast("struct sockaddr *", sa), sasize)
	return count, sock.inet_ntoa(sa.sin_addr), sock.ntohs(sa.sin_port)
end

local function Shl(A, B)
	if A and B then
		return A * (2 ^ B)
	end
end

function CountHostIPs(Host)
	assert(Host)
	local Addresses, AdressType, AddressLength = gethostbyname_(Host)
	if isnil(Addresses) or AddressType ~= AF_INET or AddressLength ~= 4 then
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
	local InetADDR = sock.inet_addr(IP)
	local HTONL = sock.htonl(InetADDR)
	return HTONL
end

function StringIP(IP)
	assert(IP)
	local HTONL = sock.htonl(IP)
	local Addr = ffi.new("struct in_addr")
	Addr.s_addr = HTONL
	local NTOA = sock.inet_ntoa(Addr)
	return ffi.string(NTOA)
end

local TUDPStream = {}
local UDP = {__index = TUDPStream}
ffi.metatype("struct TUDPStream", UDP)

function UDP:__gc()
	self:Close()
end

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
		local Char = self:ReadByte()
		if self:Size() == 0 or Char == 10 or Char == 0 then
			break
		end
		if Char ~= 13 then
			Buffer = Buffer .. char(Char)
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
	local NewBuffer, PrevBuffer
	if Size > self.RecvSize then
		Size = self.RecvSize
	end
	if Size > 0 then
		ffi.copy(Buffer, self.RecvBuffer, Size)
		if Size < self.RecvSize then
			NewBuffer = C.malloc(self.RecvSize - Size)
			PrevBuffer = ffi.string(self.RecvBuffer)
			ffi.copy(NewBuffer, PrevBuffer:sub(Size + 1), self.RecvSize - Size)
			C.free(self.RecvBuffer)
			self.RecvBuffer = NewBuffer
			self.RecvSize = self.RecvSize - Size
		else
			C.free(self.RecvBuffer)
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

	local Temp = C.malloc(self.SendSize + Size)
	if self.SendSize > 0 then
		ffi.copy(Temp, ffi.string(self.SendBuffer) .. ffi.string(Buffer), self.SendSize + Size)
		C.free(self.SendBuffer)
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
	if self.Socket == INVALID_SOCKET then
		return true
	end
	return self.RecvSize == 0
end

function TUDPStream:Close()
	if self.Socket ~= INVALID_SOCKET then
		sock.shutdown(self.Socket, SD_BOTH)
		closesocket_(self.Socket)
		self.Socket = INVALID_SOCKET
	end
end

function CreateUDPStream(Port)
	if not Port then
		Port = 0
	end
	local Socket = sock.socket(AF_INET, SOCK_DGRAM, 0)
	if Socket == INVALID_SOCKET then
		return nil
	end

	if bind_(Socket, AF_INET, Port) == SOCKET_ERROR then
		sock.shutdown(Socket, SD_BOTH)
		closesocket_(Socket)
		return nil
	end

	local Address = ffi.new("struct sockaddr_in")
	local Addr = ffi.cast("struct sockaddr *", Address)
	local SizePtr = ffi.new("int[1]")
	SizePtr[0] = ffi.sizeof(Address)

	if sock.getsockname(Socket, Addr, SizePtr) == SOCKET_ERROR then
		sock.shutdown(Socket, SD_BOTH)
		closesocket_(Socket)
		return nil
	end

	local Stream = ffi.new("struct TUDPStream")
	Stream.Socket = Socket
	Stream.LocalIP = sock.inet_ntoa(Address.sin_addr)
	Stream.LocalPort = sock.ntohs(Address.sin_port)
	Stream.UDP = true
	return Stream
end

function CloseUDPStream(Stream)
	assert(Stream)
	return Stream:Close()
end

function RecvUDPMsg(Stream)
	assert(Stream)
	if Stream.Socket == INVALID_SOCKET then
		return false
	end

	local Read = ffi.new("int[1]", Stream.Socket)
	if select_(1, Read, 0, nil, 0, nil, Stream.Timeout) ~= 1  then
		return false
	end

	local Size = ffi.new("int[1]")
	if ioctl_(Stream.Socket, FIONREAD, Size) == SOCKET_ERROR then
		return false
	end

	Size = Size[0]
	if Size <= 0 then
		return false
	end

	if Stream.RecvSize > 0 then
		local NewBuffer = C.malloc(Stream.RecvSize + Size)
		ffi.copy(NewBuffer, Stream.RecvBuffer, Stream.RecvSize)
		C.free(Stream.RecvBuffer)
		Stream.RecvBuffer = NewBuffer
	else
		Stream.RecvBuffer = C.malloc(Size)
	end

	local Result, MessageIP, MessagePort = recvfrom_(Stream.Socket, Stream.RecvBuffer, Size, 0, MessageIP, MessagePort)
	if Result == SOCKET_ERROR or Result == 0 then
		return false
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
	if Stream.Socket == INVALID_SOCKET or Stream.SendSize == 0 then
		return false
	end

	local Write = ffi.new("int[1]", Stream.Socket)
	if select_(0, nil, 1, Write, 0, nil, 0) ~= 1 then
		return false
	end

	if not Port or Port == 0 then
		Port = Stream.LocalPort
	end

	local Result = sendto_(Stream.Socket, Stream.SendBuffer, Stream.SendSize, 0, IP, Port)
	if Result == SOCKET_ERROR or Result == 0 then
		return false
	end

	if Result == Stream.SendSize then
		C.free(Stream.SendBuffer)
		Stream.SendSize = 0
		return true
	else
		local NewBuffer = C.malloc(Stream.SendSize - Result)
		local PrevBuffer = ffi.string(Stream.SendBuffer)
		ffi.copy(Temp, PrevBuffer:sub(Result + 1), Stream.SendSize - Result)
		C.free(Stream.SendBuffer)
		Stream.SendBuffer = NewBuffer
		return true
	end
	return false
end

function UDPMsgIP(Stream)
	assert(Stream)
	return ffi.string(Stream.MessageIP)
end

function UDPMsgPort(Stream)
	assert(Stream)
	return Stream.MessagePort
end

function UDPStreamIP(Stream)
	assert(Stream)
	return ffi.string(Stream.LocalIP)
end

function UDPStreamPort(Stream)
	assert(Stream)
	return Stream.LocalPort
end

function UDPTimeouts(Recv)
	assert(Recv)
	if Recv >= 0 then
		TUDPStream.Timeout = Recv
	end
end

local TTCPStream = {}
local TCP = {__index = TTCPStream}
ffi.metatype("struct TTCPStream", TCP)

function TCP:__gc()
	self:Close()
end

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
	if self.Socket == INVALID_SOCKET then
		return false
	end
	local Read = ffi.new("int[1]", self.Socket)
	if select_(1, Read, 0, nil, 0, nil, 0) ~= 1 or ReadAvail(self) ~= 0 then
		return true
	end
	self:Close()
	return false
end

function TTCPStream:Read(Buffer, Size)
	if self.Socket == INVALID_SOCKET then
		return 0
	end

	local Read = ffi.new("int[1]", self.Socket)
	if select_(1, Read, 0, nil, 0, nil, self.Timeouts[0]) ~= 1 then
		return 0
	end

	local Result = sock.recv(self.Socket, Buffer, Size, 0)
	if Result == SOCKET_ERROR then
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
	if self.Socket == INVALID_SOCKET then
		return 0
	end

	local Write = ffi.new("int[1]", self.Socket)
	if select_(1, nil, 1, Write, 0, nil, 0) ~= 1 then
		return 0
	end

	local Result = sock.send(self.Socket, Buffer, Size, 0)
	if Result == SOCKET_ERROR then
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
	if ioctl_(self.Socket, FIONREAD, Size) == SOCKET_ERROR then
		return 0
	end
	return Size[0]
end

function TTCPStream:Eof()
	if self.Socket == INVALID_SOCKET then
		return true
	end

	local Read = ffi.new("int[1]", self.Socket)
	local Result = select_(1, Read, 0, nil, 0, nil, self.Timeouts[0])
	if Result == SOCKET_ERROR then
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
	if self.Socket ~= INVALID_SOCKET then
		sock.shutdown(self.Socket, SD_BOTH)
		closesocket_(self.Socket)
		self.Socket = INVALID_SOCKET
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

	local ServerIP = sock.inet_addr(Server)
	local PAddress
	if ServerIP == INADDR_NONE then
		local Addresses, AddressType, AddressLength = gethostbyname_(Server)
		if isnil(Addresses) or AddressType ~= AF_INET or AddressLength ~= 4 then
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
		ServerIP = bit.bor(Shl(NAddress[3], 24), Shl(NAddress[2], 16), Shl(NAddress[1], 8), NAddress[0])
	end

	local Socket = sock.socket(AF_INET, SOCK_STREAM, 0)
	if Socket == INVALID_SOCKET then
		return nil
	end

	if bind_(Socket, AF_INET, LocalPort) == SOCKET_ERROR then
		sock.shutdown(Socket, SD_BOTH)
		closesocket_(Socket)
		return nil
	end

	local SAddress = ffi.new("struct sockaddr_in")
	local Addr = ffi.cast("struct sockaddr *", SAddress)
	local SizePtr = ffi.new("int[1]")
	SizePtr[0] = ffi.sizeof(SAddress)

	if sock.getsockname(Socket, Addr, SizePtr) == SOCKET_ERROR then
		sock.shutdown(Socket, SD_BOTH)
		closesocket_(Socket)
		return nil
	end

	local Stream = ffi.new("struct TTCPStream")
	Stream.Socket = Socket
	Stream.LocalIP = sock.inet_ntoa(SAddress.sin_addr)
	Stream.LocalPort = sock.ntohs(SAddress.sin_port)
	Stream.TCP = true

	local ServerPtr = ffi.new("int[1]")
	ServerPtr[0] = ServerIP

	if connect_(Socket, ServerPtr, AF_INET, 4, ServerPort) == SOCKET_ERROR then
		sock.shutdown(Socket, SD_BOTH)
		closesocket_(Socket)
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

	local Socket = sock.socket(AF_INET, SOCK_STREAM, 0)
	if Socket == INVALID_SOCKET then
		return nil
	end

	if bind_(Socket, AF_INET, Port) == SOCKET_ERROR then
		sock.shutdown(Socket, SD_BOTH)
		closesocket_(Socket)
		return nil
	end

	local SAddress = ffi.new("struct sockaddr_in")
	local Addr = ffi.cast("struct sockaddr *", SAddress)
	local SizePtr = ffi.new("int[1]")
	SizePtr[0] = ffi.sizeof(SAddress)

	if sock.getsockname(Socket, Addr, SizePtr) == SOCKET_ERROR then
		sock.shutdown(Socket, SD_BOTH)
		closesocket_(Socket)
		return nil
	end

	local Stream = ffi.new("struct TTCPStream")
	Stream.Socket = Socket
	Stream.LocalIP = sock.inet_ntoa(SAddress.sin_addr)
	Stream.LocalPort = sock.ntohs(SAddress.sin_port)
	Stream.TCP = true

	if sock.listen(Socket, BNET_MAX_CLIENTS) == SOCKET_ERROR then
		sock.shutdown(Socket, SD_BOTH)
		closesocket_(Socket)
		return nil
	end
	return Stream
end

function AcceptTCPStream(Stream)
	assert(Stream)
	if Stream.Socket == INVALID_SOCKET then
		return nil
	end

	local Read = ffi.new("int[1]", Stream.Socket)
	if select_(1, Read, 0, nil, 0, nil, TTCPStream.Timeouts[1]) ~= 1 then
		return nil
	end

	local Address = ffi.new("struct sockaddr_in")
	local Addr = ffi.cast("struct sockaddr *", Address)
	local SizePtr = ffi.new("int[1]")
	SizePtr[0] = ffi.sizeof(Address)

	local Socket = sock.accept(Stream.Socket, Addr, SizePtr)
	if Socket == SOCKET_ERROR then
		return nil
	end

	local Stream = ffi.new("struct TTCPStream")
	Stream.Socket = Socket
	Stream.LocalIP = sock.inet_ntoa(Address.sin_addr)
	Stream.LocalPort = sock.ntohs(Address.sin_port)
	Stream.TCP = true
	return Stream
end

function TCPStreamIP(Stream)
	assert(Stream)
	return ffi.string(Stream.LocalIP)
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
