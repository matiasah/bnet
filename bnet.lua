local ffi = require("ffi")
local bit = require("bit")
local rb = require("ringbuffer2")

ffi.cdef [[void free (void* ptr);]]
local C = ffi.C

local SOMAXCONN = 128

local INVALID_SOCKET = -1
local INADDR_ANY = 0
local INADDR_NONE = 0XFFFFFFFF

local AF_INET = 2
local SOCK_STREAM = 1
local SOCK_DGRAM = 2
local SOCKET_ERROR = -1

local SD_RECEIVE = 0
local SD_SEND = 1
local SD_BOTH = 2

local socket = {
	_VERSION = "LuaSocket 2.0.2",
	_DEBUG = false
}

ffi.cdef [[
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
		int * Timeouts;
		SOCKET Socket;
		char * LocalIP;
		int LocalPort;

		bool TCP;
		bool IsServer;
		bool IsClient;

		int Received;
		int Sent;
		int Age;
	};
]]

local FIONREAD
local sock, ioctl_, fd_lib
if ffi.os == "Windows" then
	FIONREAD = 0x4004667F

	sock = ffi.load("ws2_32")
	ffi.cdef [[
		typedef uint16_t u_short;
		typedef uint32_t u_int;
		typedef unsigned long u_long;
		typedef uintptr_t SOCKET;
		typedef unsigned char byte;
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

		int WSAGetLastError(void);

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
	sock = ffi.C
	ffi.cdef [[
		typedef uint16_t u_short;
		typedef uint32_t u_int;
		typedef unsigned long u_long;
		typedef uintptr_t SOCKET;
		typedef unsigned char byte;
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
		FD_ISSET = function (fd, set)
			for i = 0, set.fd_count do
				if set.fd_array[i] == fd then
					return true
				end
			end
			return false
		end,
	}

	function ioctl_(s, cmd, argp)
		return sock.ioctl(s, cmd, argp)
	end

	if ffi.os == "MacOS" then
		FIONREAD = 0x4004667F
	else --if ffi.os == "Linux" then
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
	if e ~= nil then
		return e.h_name
	end
end

local function gethostbyname_(name)
	local e = sock.gethostbyname(name)
	if e ~= nil then
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

local IO_DONE = 0
local IO_TIMEOUT = -1
local IO_CLOSED = -2

local function io_strerror(err)
	if err == IO_DONE then
		return nil
	elseif err == IO_CLOSED then
		return "closed"
	elseif err == IO_TIMEOUT then
		return "timeout"
	end
	return "unknown error"
end

local socket_strerror
if ffi.os == "Windows" then
	local WSAEINTR = 10004
	local WSAEACCES = 10013
	local WSAEFAULT = 10014
	local WSAEINVAL = 10022
	local WSAEMFILE = 10024
	local WSAEWOULDBLOCK = 10035
	local WSAEINPROGRESS = 10036
	local WSAEALREADY = 10037
	local WSAENOTSOCK = 10038
	local WSAEDESTADDRREQ = 10039
	local WSAEMSGSIZE = 10040
	local WSAEPROTOTYPE = 10041
	local WSAENOPROTOOPT = 10042
	local WSAEPROTONOSUPPORT = 10043
	local WSAESOCKTNOSUPPORT = 10044
	local WSAEOPNOTSUPP = 10045
	local WSAEPFNOSUPPORT = 10046
	local WSAEAFNOSUPPORT = 10047
	local WSAEADDRINUSE = 10048
	local WSAEADDRNOTAVAIL = 10049
	local WSAENETDOWN = 10050
	local WSAENETUNREACH = 10051
	local WSAENETRESET = 10052
	local WSAECONNABORTED = 10053
	local WSAECONNRESET = 10054
	local WSAENOBUFS = 10055
	local WSAEISCONN = 10056
	local WSAENOTCONN = 10057
	local WSAESHUTDOWN = 10058
	local WSAETIMEDOUT = 10060
	local WSAECONNREFUSED = 10061
	local WSAEHOSTDOWN = 10064
	local WSAEHOSTUNREACH = 10065
	local WSAEPROCLIM = 10067
	local WSASYSNOTREADY = 10091
	local WSAVERNOTSUPPORTED = 10092
	local WSANOTINITIALISED = 10093
	local WSAEDISCON = 10101
	local WSAHOST_NOT_FOUND = 11001
	local WSATRY_AGAIN = 11002
	local WSANO_RECOVERY = 11003
	local WSANO_DATA = 11004

	local function wstrerror(err)
		if err == WSAEINTR then
			return "Interrupted function call"
		elseif err == WSAEACCES then
			return "Permission denied"
		elseif err == WSAEFAULT then
			return "Bad address"
		elseif err == WSAEINVAL then
			return "Invalid argument"
		elseif err == WSAEMFILE then
			return "Too many open files"
		elseif err == WSAEWOULDBLOCK then
			return "Resource temporarily unavailable"
		elseif err == WSAEINPROGRESS then
			return "Operation now in progress"
		elseif err == WSAEALREADY then
			return "Operation already in progress"
		elseif err == WSAENOTSOCK then
			return "Socket operation on nonsocket"
		elseif err == WSAEDESTADDRREQ then
			return "Destination address required"
		elseif err == WSAEMSGSIZE then
			return "Message too long"
		elseif err == WSAEPROTOTYPE then
			return "Protocol wrong type for socket"
		elseif err == WSAENOPROTOOPT then
			return "Bad protocol option"
		elseif err == WSAEPROTONOSUPPORT then
			return "Protocol not supported"
		elseif err == WSAESOCKTNOSUPPORT then
			return "Socket type not supported"
		elseif err == WSAEOPNOTSUPP then
			return "Operation not supported"
		elseif err == WSAEPFNOSUPPORT then
			return "Protocol family not supported"
		elseif err == WSAEAFNOSUPPORT then
			return "Address family not supported by protocol family"
		elseif err == WSAEADDRINUSE then
			return "Address already in use"
		elseif err == WSAEADDRNOTAVAIL then
			return "Cannot assign requested address"
		elseif err == WSAENETDOWN then
			return "Network is down"
		elseif err == WSAENETUNREACH then
			return "Network is unreachable"
		elseif err == WSAENETRESET then
			return "Network dropped connection on reset"
		elseif err == WSAECONNABORTED then
			return "Software caused connection abort"
		elseif err == WSAECONNRESET then
			return "Connection reset by peer"
		elseif err == WSAENOBUFS then
			return "No buffer space available"
		elseif err == WSAEISCONN then
			return "Socket is already connected"
		elseif err == WSAENOTCONN then
			return "Socket is not connected"
		elseif err == WSAESHUTDOWN then
			return "Cannot send after socket shutdown"
		elseif err == WSAETIMEDOUT then
			return "Connection timed out"
		elseif err == WSAECONNREFUSED then
			return "Connection refused"
		elseif err == WSAEHOSTDOWN then
			return "Host is down"
		elseif err == WSAEHOSTUNREACH then
			return "No route to host"
		elseif err == WSAEPROCLIM then
			return "Too many processes"
		elseif err == WSASYSNOTREADY then
			return "Network subsystem is unavailable"
		elseif err == WSAVERNOTSUPPORTED then
			return "Winsock.dll version out of range"
		elseif err == WSANOTINITIALISED then
			return "Successful WSAStartup not yet performed"
		elseif err == WSAEDISCON then
			return "Graceful shutdown in progress"
		elseif err == WSAHOST_NOT_FOUND then
			return "Host not found"
		elseif err == WSATRY_AGAIN then
			return "Nonauthoritative host not found"
		elseif err == WSANO_RECOVERY then
			return "Nonrecoverable name lookup error"
		elseif err == WSANO_DATA then
			return "Valid name, no data record of requested type"
		end
		return "Unknown error"
	end

	local WSAEADDRINUSE = 10048
	local WSAECONNREFUSED = 10061
	local WSAEISCONN = 10056
	local WSAECONNABORTED = 10053
	local WSAECONNRESET = 10054
	local WSAETIMEDOUT = 10060

	function socket_strerror(err)
		if err <= 0 then
			return io_strerror(err)
		elseif err == WSAEADDRINUSE then
			return "address already in use"
		elseif err == WSAECONNREFUSED then
			return "connection refused"
		elseif err == WSAEISCONN then
			return "already connected"
		elseif err == WSAEACCES then
			return "permission denied"
		elseif err == WSAECONNABORTED then
			return "closed"
		elseif err == WSAECONNRESET then
			return "closed"
		elseif err == WSAETIMEDOUT then
			return "timeout"
		end
		return wstrerror(err)
	end
else
	ffi.cdef [[
		char * strerror(int errnum);
	]]
	function socket_strerror(err)
		if err <= 0 then
			return io_strerror(err)
		elseif err == EADDRINUSE then
			return "address already in use"
		elseif err == EISCONN then
			return "already connected"
		elseif err == EACCES then
			return "permission denied"
		elseif err == ECONNREFUSED then
			return "connection refused"
		elseif err == ECONNABORTED then
			return "closed"
		elseif err == ECONNRESET then
			return "closed"
		elseif err == ETIMEDOUT then
			return "timeout"
		end
		return ffi.string(C.strerror(err))
	end
end

function CountHostIPs(Host)
	assert(Host)
	local Addresses, AdressType, AddressLength = gethostbyname_(Host)
	if Addresses == nil or AddressType ~= AF_INET or AddressLength ~= 4 then
		return 0
	end

	local Count = 0
	while Addresses[Count] ~= nil do
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
	local n = ffi.new("byte[1]"); self:Read(n, 1)
	return n[0]
end

function TUDPStream:ReadShort()
	local n = ffi.new("byte[2]"); self:Read(n, 2)
	return n[0] + n[1] * 256
end

function TUDPStream:ReadInt()
	local n = ffi.new("byte[4]"); self:Read(n, 4)
	return n[0] + n[1] * 256 + n[2] * 65536 + n[3] * 16777216
end

function TUDPStream:ReadLong()
	local n = ffi.new("byte[8]"); self:Read(n, 8)
	local Value = ffi.new("uint64_t")
	local LongByte = ffi.new("uint64_t", 256)
	for i = 0, 7 do
		Value = Value + ffi.new("uint64_t", n[i]) * LongByte ^ i
	end
	return Value
end

function TUDPStream:ReadLine()
	local Buffer = ""
	local Size = 0
	while self:Size() > 0 do
		local Char = self:ReadByte()
		if Char == 10 or Char == 0 then
			break
		end
		if Char ~= 13 then
			Buffer = Buffer .. char(Char)
		end
	end
	return Buffer
end

function TUDPStream:ReadString(Length)
	if Length > 0 then
		local Buffer = ffi.new("byte["..Length.."]"); self:Read(Buffer, Length)
		return ffi.string(Buffer, Length)
	end
	return ""
end

function TUDPStream:WriteByte(n)
	local q = ffi.new("byte[1]")
	q[0] = n % 256
	return self:Write(q, 1)
end

function TUDPStream:WriteShort(n)
	local q = ffi.new("byte[2]")
	q[0] = n % 256; n = (n - q[0])/256
	q[1] = n % 256
	return self:Write(q, 2)
end

function TUDPStream:WriteInt(n)
	local q = ffi.new("byte[4]")
	q[0] = n % 256; n = (n - q[0])/256
	q[1] = n % 256; n = (n - q[1])/256
	q[2] = n % 256; n = (n - q[2])/256
	q[3] = n % 256; n = (n - q[3])/256
	return self:WriteBytes(q, 4)
end

function TUDPStream:WriteLong(n)
	local q = ffi.new("byte[8]")
	q[0] = n % 256; n = (n - q[0])/256
	q[1] = n % 256; n = (n - q[1])/256
	q[2] = n % 256; n = (n - q[2])/256
	q[3] = n % 256; n = (n - q[3])/256
	q[4] = n % 256; n = (n - q[4])/256
	q[5] = n % 256; n = (n - q[5])/256
	q[6] = n % 256; n = (n - q[6])/256
	q[7] = n % 256
	return self:WriteBytes(q, 8)
end

function TUDPStream:WriteLine(String)
	local Line = String.."\n"
	return self:Write(Line, #Line)
end

function TUDPStream:WriteString(String)
	return self:Write(String, #String)
end

function TUDPStream:Read(Buffer, Size)
	local NewBuffer --, PrevBuffer
	local Size = math.min(Size, self.RecvSize)
	if Size > 0 then
		--ffi.copy(Buffer, self.RecvBuffer, Size)
		self.RecvBuffer:read(Buffer, 0, 0, Size) -- This would copy 'Size' bytes into the buffer

		if Size < self.RecvSize then
			NewBuffer = rb.cbuffer{size = self.RecvSize - Size} -- The bytes we read must be removed from the begining of the buffer
			self.RecvBuffer:read(NewBuffer, Size + 1, 0, self.RecvSize - Size)

			--PrevBuffer = ffi.string(self.RecvBuffer, self.RecvSize)
			--ffi.copy(NewBuffer, PrevBuffer:sub(Size + 1), self.RecvSize - Size)
			--C.free(self.RecvBuffer)

			self.RecvBuffer = NewBuffer
			self.RecvSize = self.RecvSize - Size
		else
			--C.free(self.RecvBuffer)
			self.RecvBuffer = rb.cbuffer{size = 0}
			self.RecvSize = 0
		end
	end
	return Size
end

function TUDPStream:Write(Buffer, Size)
	local Buffer = ffi.string(Buffer, Size)
	local NewBuffer = C.malloc(self.SendSize + Size)
	if self.SendSize > 0 then
		ffi.copy(NewBuffer, ffi.string(self.SendBuffer, self.SendSize) .. Buffer)
		C.free(self.SendBuffer)
		self.SendBuffer = NewBuffer
		self.SendSize = self.SendSize + Size
	else
		ffi.copy(NewBuffer, Buffer)
		self.SendBuffer = NewBuffer
		self.SendSize = Size
	end
	return Size
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
		local Error = sock.shutdown(self.Socket, SD_BOTH)
		if Error ~= 0 then
			return false, socket_strerror(Error)
		end

		local Error = closesocket_(self.Socket)
		if Error ~= 0 then
			return false, socket_strerror(Error)
		end
		self.Socket = INVALID_SOCKET
	end
end

function TUDPStream:Timeout(Recv)
	assert(Recv)
	if Recv >= 0 then
		self.Timeout = Recv
	end
end

function TUDPStream:SendTo(IP, Port)
	if self.Socket == INVALID_SOCKET or self.SendSize == 0 then
		return false
	end

	local Write = {self.Socket}
	if select_(0, nil, 1, Write, 0, nil, 0) ~= 1 then
		return false
	end

	if not Port or Port == 0 then
		Port = self.MessagePort
	end
	if not IP then
		IP = ffi.string(self.MessageIP)
	end

	local Result = sendto_(self.Socket, ffi.string(self.SendBuffer, self.SendSize), self.SendSize, 0, IP, Port)
	if Result == SOCKET_ERROR or Result == 0 then
		return false
	end

	if Result == self.SendSize then
		C.free(self.SendBuffer)
		self.SendSize = 0
		return true
	else
		local NewBuffer = C.malloc(self.SendSize - Result)
		local PrevBuffer = ffi.string(self.SendBuffer, self.SendSize)
		ffi.copy(NewBuffer, PrevBuffer:sub(Result + 1), self.SendSize - Result)
		C.free(self.SendBuffer)
		self.SendBuffer = NewBuffer
		return true
	end
	return false
end

function TUDPStream:RecvFrom()
	if self.Socket == INVALID_SOCKET then
		return false
	end

	local Read = {self.Socket}
	if select_(1, Read, 0, nil, 0, nil, self.Timeout) ~= 1 then
		return false
	end

	local Size = ffi.new("int[1]")
	if ioctl_(self.Socket, FIONREAD, Size) == SOCKET_ERROR then
		return false
	end

	Size = Size[0]
	if Size <= 0 then
		return false
	end

	if self.RecvSize > 0 then
		local NewBuffer = C.malloc(self.RecvSize + Size)
		ffi.copy(NewBuffer, self.RecvBuffer, self.RecvSize)
		C.free(self.RecvBuffer)
		self.RecvBuffer = NewBuffer
	else
		self.RecvBuffer = C.malloc(Size)
	end

	local Result, MessageIP, MessagePort = recvfrom_(self.Socket, self.RecvBuffer, Size, 0)
	if Result == SOCKET_ERROR or Result == 0 then
		return false
	end
	self.MessageIP = MessageIP
	self.MessagePort = MessagePort
	self.RecvSize = self.RecvSize + Result
	return MessageIP, MessagePort
end

function TUDPStream:MsgIP()
	return ffi.string(self.MessageIP)
end

function TUDPStream:MsgPort()
	return tonumber(self.messagePort)
end

function TUDPStream:GetIP()
	return ffi.string(self.LocalIP)
end

function TUDPStream:GetPort()
	return tonumber(self.LocalPort)
end

function socket.CreateUDPStream(Port)
	if not Port then
		Port = 0
	end
	local Socket = sock.socket(AF_INET, SOCK_DGRAM, 0)
	if Socket == INVALID_SOCKET then
		return nil
	end

	if bind_(Socket, AF_INET, Port) == SOCKET_ERROR then
		local BindError = ffi.errno()

		local Error = sock.shutdown(Socket, SD_BOTH)
		if Error ~= 0 then
			return nil, socket_strerror(Error)
		end

		local Error = closesocket_(Socket)
		if Error ~= 0 then
			return nil, socket_strerror(Error)
		end

		return nil, socket_strerror(BindError)
	end

	local Address = ffi.new("struct sockaddr_in")
	local Addr = ffi.cast("struct sockaddr *", Address)
	local SizePtr = ffi.new("int[1]")
	SizePtr[0] = ffi.sizeof(Address)

	if sock.getsockname(Socket, Addr, SizePtr) == SOCKET_ERROR then
		local GetSockNameError = ffi.errno()

		local Error = sock.shutdown(Socket, SD_BOTH)
		if Error ~= 0 then
			return nil, socket_strerror(Error)
		end

		local Error = closesocket_(Socket)
		if Error ~= 0 then
			return nil, socket_strerror(Error)
		end

		return nil, socket_strerror(GetSockNameError)
	end

	local Stream = ffi.new("struct TUDPStream")
	Stream.Socket = Socket
	Stream.LocalIP = sock.inet_ntoa(Address.sin_addr)
	Stream.LocalPort = sock.ntohs(Address.sin_port)
	Stream.UDP = true

	-- Somehow those buffers start up with 4 bytes in their memory so I decided I should clean their memory, otherwise they'd be sending needless extra memory which spawns from nowhere
	Stream.SendBuffer = nil
	Stream.RecvBuffer = nil
	return Stream
end

local TTCPStream = {}
local TCP = {__index = TTCPStream}
ffi.metatype("struct TTCPStream", TCP)

function TCP:__gc()
	self:Close()
end

function TTCPStream:ReadByte()
	local n = ffi.new("byte[1]"); self:Read(n, 1)
	return n[0]
end

function TTCPStream:ReadShort()
	local n = ffi.new("byte[2]"); self:Read(n, 2)
	return n[0] + n[1] * 256
end

function TTCPStream:ReadInt()
	local n = ffi.new("byte[4]"); self:Read(n, 4)
	return n[0] + n[1] * 256 + n[2] * 65536 + n[3] * 16777216
end

function TTCPStream:ReadLong()
	local n = ffi.new("byte[8]"); self:Read(n, 8)
	local Value = ffi.new("uint64_t")
	local LongByte = ffi.new("uint64_t", 256)
	for i = 0, 7 do
		Value = Value + ffi.new("uint64_t", n[i]) * LongByte ^ i
	end
	return Value
end

function TTCPStream:ReadLine()
	local Buffer = ""
	local Size = 0
	while self:Size() > 0 do
		local Char = self:ReadByte()
		if Char == 10 or Char == 0 then
			break
		end
		if Char ~= 13 then
			Buffer = Buffer .. char(Char)
		end
	end
	return Buffer
end

function TTCPStream:ReadString(Length)
	if Length > 0 then
		local Buffer = ffi.new("byte["..Length.."]"); self:Read(Buffer, Length)
		return ffi.string(Buffer, Length)
	end
	return ""
end

function TTCPStream:WriteByte(n)
	local q = ffi.new("byte[1]")
	q[0] = n % 256
	return self:Write(q, 1)
end

function TTCPStream:WriteShort(n)
	local q = ffi.new("byte[2]")
	q[0] = n % 256; n = (n - q[0])/256
	q[1] = n % 256
	return self:Write(q, 2)
end

function TTCPStream:WriteInt(n)
	local q = ffi.new("byte[4]")
	q[0] = n % 256; n = (n - q[0])/256
	q[1] = n % 256; n = (n - q[1])/256
	q[2] = n % 256; n = (n - q[2])/256
	q[3] = n % 256; n = (n - q[3])/256
	return self:WriteBytes(q, 4)
end

function TTCPStream:WriteLong(n)
	local q = ffi.new("byte[8]")
	q[0] = n % 256; n = (n - q[0])/256
	q[1] = n % 256; n = (n - q[1])/256
	q[2] = n % 256; n = (n - q[2])/256
	q[3] = n % 256; n = (n - q[3])/256
	q[4] = n % 256; n = (n - q[4])/256
	q[5] = n % 256; n = (n - q[5])/256
	q[6] = n % 256; n = (n - q[6])/256
	q[7] = n % 256
	return self:WriteBytes(q, 8)
end

function TTCPStream:WriteLine(String)
	local Line = String.."\n"
	return self:Write(Line, #Line)
end

function TTCPStream:WriteString(String)
	return self:Write(String, #String)
end

function TTCPStream:Connected()
	if self.Socket == INVALID_SOCKET then
		return false
	end
	local Read = {self.Socket}
	if select_(1, Read, 0, nil, 0, nil, 0) ~= 1 or ReadAvail(self) ~= 0 then
		return true
	end
	self:Close()
	return false
end

function TTCPStream:SetTimeout(Read, Accept)
	assert(Read)
	assert(Accept)
	if Read < 0 then Read = 0 end
	if Accept < 0 then Accept = 0 end
	self.Timeouts = ffi.new("int[2]", Read, Accept)
end

function TTCPStream:Read(Buffer, Size)
	if self.Socket == INVALID_SOCKET then
		return 0
	end

	local Read = {self.Socket}
	if select_(1, Read, 0, nil, 0, nil, self.Timeouts[0]) ~= 1 then
		return 0
	end

	local Result = sock.recv(self.Socket, Buffer, Size, 0)
	if Result == SOCKET_ERROR then
		return 0
	end
	self.Received = self.Received + Size
	return Result
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
	self.Sent = self.Sent + Size
	return Result
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

function TTCPStream:GetIP(Stream)
	return ffi.string(self.LocalIP)
end

function TTCPStream:GetPort(Stream)
	return tonumber(self.LocalPort)
end

function socket.OpenTCPStream(Server, ServerPort, LocalPort)
	assert(Server)
	assert(ServerPort)
	if not LocalPort then
		LocalPort = 0
	end

	local ServerIP = sock.inet_addr(Server)
	local PAddress
	if ServerIP == INADDR_NONE then
		local Addresses, AddressType, AddressLength = gethostbyname_(Server)
		if Addresses == nil or AddressType ~= AF_INET or AddressLength ~= 4 then
			return nil
		end
		if Addresses[0] == nil then
			return nil
		end
		PAddress = Addresses[0]
		local NAddress = {[0] = PAddress[0], PAddress[1], PAddress[2], PAddress[3]}
		if PAddress[0] < 0 then NAddress[0] = PAddress[0] + 256 end
		if PAddress[1] < 0 then NAddress[1] = PAddress[1] + 256 end
		if PAddress[2] < 0 then NAddress[2] = PAddress[2] + 256 end
		if PAddress[3] < 0 then NAddress[3] = PAddress[3] + 256 end
		ServerIP = bit.bor(bit.lshift(NAddress[3], 24), bit.lshift(NAddress[2], 16), bit.lshift(NAddress[1], 8), NAddress[0])
	end

	local Socket = sock.socket(AF_INET, SOCK_STREAM, 0)
	if Socket == INVALID_SOCKET then
		return nil, socket_strerror(ffi.errno())
	end

	if bind_(Socket, AF_INET, LocalPort) == SOCKET_ERROR then
		local BindError = ffi.errno()

		local Error = sock.shutdown(Socket, SD_BOTH)
		if Error ~= 0 then
			return nil, socket_strerror(Error)
		end

		local Error = closesocket_(Socket)
		if Error ~= 0 then
			return nil, socket_strerror(Error)
		end

		return nil, socket_strerror(BindError)
	end

	local SAddress = ffi.new("struct sockaddr_in")
	local Addr = ffi.cast("struct sockaddr *", SAddress)
	local SizePtr = ffi.new("int[1]")
	SizePtr[0] = ffi.sizeof(SAddress)

	if sock.getsockname(Socket, Addr, SizePtr) == SOCKET_ERROR then
		local GetSockNameError = ffi.errno()

		local Error = sock.shutdown(Socket, SD_BOTH)
		if Error ~= 0 then
			return nil, socket_strerror(Error)
		end

		local Error = closesocket_(Socket)
		if Error ~= 0 then
			return nil, socket_strerror(Error)
		end

		return nil, socket_strerror(GetSockNameError)
	end

	local Stream = ffi.new("struct TTCPStream")
	Stream.Socket = Socket
	Stream.LocalIP = sock.inet_ntoa(SAddress.sin_addr)
	Stream.LocalPort = sock.ntohs(SAddress.sin_port)
	Stream.Timeouts = ffi.new("int[2]")
	Stream.TCP = true
	Stream.IsClient = true
	Stream.Age = socket.gettime()

	local ServerPtr = ffi.new("int[1]")
	ServerPtr[0] = ServerIP

	if connect_(Socket, ServerPtr, AF_INET, 4, ServerPort) == SOCKET_ERROR then
		local ConnectError = ffi.errno()

		local Error = sock.shutdown(Socket, SD_BOTH)
		if Error ~= 0 then
			return nil, socket_strerror(Error)
		end

		local Error = closesocket_(Socket)
		if Error ~= 0 then
			return nil, socket_strerror(Error)
		end

		return nil, socket_strerror(ConnectError)
	end
	return Stream
end

function socket.CreateTCPServer(Port, Backlog)
	if not Port then
		Port = 0
	end

	local Socket = sock.socket(AF_INET, SOCK_STREAM, 0)
	if Socket == INVALID_SOCKET then
		return nil, socket_strerror(ffi.errno())
	end

	if bind_(Socket, AF_INET, Port) == SOCKET_ERROR then
		local BindError = ffi.errno()

		local Error = sock.shutdown(Socket, SD_BOTH)
		if Error ~= 0 then
			return nil, socket_strerror(Error)
		end

		local Error = closesocket_(Socket)
		if Error ~= 0 then
			return nil, socket_strerror(Error)
		end

		return nil, socket_strerror(BindError)
	end

	local SAddress = ffi.new("struct sockaddr_in")
	local Addr = ffi.cast("struct sockaddr *", SAddress)
	local SizePtr = ffi.new("int[1]")
	SizePtr[0] = ffi.sizeof(SAddress)

	if sock.getsockname(Socket, Addr, SizePtr) == SOCKET_ERROR then
		local GetSockNameError = ffi.errno()

		local Error = sock.shutdown(Socket, SD_BOTH)
		if Error ~= 0 then
			return nil, socket_strerror(Error)
		end

		local Error = closesocket_(Socket)
		if Error ~= 0 then
			return nil, socket_strerror(Error)
		end

		return nil, socket_strerror(GetSockNameError)
	end

	local Stream = ffi.new("struct TTCPStream")
	Stream.Socket = Socket
	Stream.LocalIP = sock.inet_ntoa(SAddress.sin_addr)
	Stream.LocalPort = sock.ntohs(SAddress.sin_port)
	Stream.Timeouts = ffi.new("int[2]")
	Stream.TCP = true
	Stream.IsServer = true
	Stream.Age = socket.gettime()

	if sock.listen(Socket, Backlog or SOMAXCONN) == SOCKET_ERROR then
		local ListenError = ffi.errno()

		local Error = sock.shutdown(Socket, SD_BOTH)
		if Error ~= 0 then
			return nil, socket_strerror(Error)
		end

		local Error = closesocket_(Socket)
		if Error ~= 0 then
			return nil, socket_strerror(Error)
		end

		return nil, socket_strerror(ListenError)
	end
	return Stream
end

function TTCPStream:Accept()
	if self.Socket == INVALID_SOCKET then
		return nil
	end

	local Read = ffi.new("int[1]", self.Socket)
	local Select = select_(1, Read, 0, nil, 0, nil, self.Timeouts[1])
	if Select ~= 1 then
		if Select == SOCKET_ERROR then
			return nil, socket_strerror(ffi.errno())
		end
		return nil, ""
	end

	local Address = ffi.new("struct sockaddr_in")
	local Addr = ffi.cast("struct sockaddr *", Address)
	local SizePtr = ffi.new("int[1]")
	SizePtr[0] = ffi.sizeof(Address)

	local Socket = sock.accept(self.Socket, Addr, SizePtr)
	if Socket == SOCKET_ERROR then
		return nil, socket_strerror(ffi.errno())
	end

	local Stream = ffi.new("struct TTCPStream")
	Stream.Socket = Socket
	Stream.LocalIP = sock.inet_ntoa(Address.sin_addr)
	Stream.LocalPort = sock.ntohs(Address.sin_port)
	Stream.Timeouts = ffi.new("int[2]")
	Stream.TCP = true
	return Stream
end

---------- LuaSocket-like api

function TTCPStream:accept()
	if self.Socket == INVALID_SOCKET then
		return nil
	end

	local Read = ffi.new("int[1]", self.Socket)
	local Select = select_(1, Read, 0, nil, 0, nil, self.Timeouts[1])
	if Select ~= 1 then
		if Select == SOCKET_ERROR then
			return nil, socket_strerror(ffi.errno())
		end
		return nil, ""
	end

	local Address = ffi.new("struct sockaddr_in")
	local Addr = ffi.cast("struct sockaddr *", Address)
	local SizePtr = ffi.new("int[1]")
	SizePtr[0] = ffi.sizeof(Address)

	local Socket = sock.accept(self.Socket, Addr, SizePtr)
	if Socket == SOCKET_ERROR then
		return nil, socket_strerror(ffi.errno())
	end

	local Stream = ffi.new("struct TTCPStream")
	Stream.Socket = Socket
	Stream.LocalIP = sock.inet_ntoa(Address.sin_addr)
	Stream.LocalPort = sock.ntohs(Address.sin_port)
	Stream.Timeouts = ffi.new("int[2]")
	Stream.TCP = true
	return Stream
end

function TTCPStream:bind(Address, Port)
	if Address == "*" then
		if bind_(self.Socket, AF_INET, Port) == SOCKET_ERROR then
			local BindError = ffi.errno()

			local Error = sock.shutdown(self.Socket, SD_BOTH)
			if Error ~= 0 then
				return nil, socket_strerror(Error)
			end

			local Error = closesocket_(self.Socket)
			if Error ~= 0 then
				return nil, socket_strerror(Error)
			end

			return nil, socket_strerror(BindError)
		end

		local SAddress = ffi.new("struct sockaddr_in")
		local Addr = ffi.cast("struct sockaddr * ", SAddress)
		local SizePtr = ffi.new("int[1]")
		SizePtr[0] = ffi.sizeof(SAddress)

		if sock.getsockname(self.Socket, Addr, SizePtr) == SOCKET_ERROR then
			local GetSockNameError = ffi.errno()

			local Error = sock.shutdown(self.Socket, SD_BOTH)
			if Error ~= 0 then
				return nil, socket_strerror(Error)
			end

			local Error = closesocket_(self.Socket)
			if Error ~= 0 then
				return nil, socket_strerror(Error)
			end

			return nil, socket_strerror(GetSockNameError)
		end
		self.LocalIP = sock.inet_ntoa(SAddress.sin_addr)
		self.LocalPort = sock.ntohs(SAddress.sin_port)
		self.Timeouts = ffi.new("int[2]")
		return true
	end
end

function TTCPStream:connect(address, port)
	local AddressIP = sock.inet_addr(address)
	local PAddress
	if ServerIP == INADDR_NONE then
		local Addresses, AddressType, AddressLength = gethostbyname_(address)
		if Addresses == nil or AddressType ~= AF_INET or AddressLength ~= 4 then
			return nil
		elseif Addresses[0] == nil then
			return nil
		end
		PAddress = Addresses[0]
		local NAddress = {[0] = PAddress[0], PAddress[1], PAddress[2], PAddress[3]}
		if PAddress[0] < 0 then NAddress[0] = PAddress[0] + 256 end
		if PAddress[1] < 0 then NAddress[1] = PAddress[1] + 256 end
		if PAddress[2] < 0 then NAddress[2] = PAddress[2] + 256 end
		if PAddress[3] < 0 then NAddress[3] = PAddress[3] + 256 end
		ServerIP = bit.bor(bit.lshift(NAddress[3], 24), bit.lshift(NAddress[2], 16), bit.lshift(NAddress[1], 8), NAddress[0])
	end

	local Socket = sock.socket(AF_INET, SOCK_STREAM, 0)
	if Socket == INVALID_SOCKET then
		return nil
	end

	if bind_(Socket, AF_INET, port or 0) == SOCKET_ERROR then
		local BindError = ffi.errno()

		local Error = sock.shutdown(Socket, SD_BOTH)
		if Error ~= 0 then
			return nil, socket_strerror(Error)
		end

		local Error = closesocket_(Socket)
		if Error ~= 0 then
			return nil, socket_strerror(Error)
		end

		return nil, socket_strerror(BindError)
	end

	local SAddress = ffi.new("struct sockaddr_in")
	local Addr = ffi.cast("struct sockaddr *", SAddress)
	local SizePtr = ffi.new("int[1]")
	SizePtr[0] = ffi.sizeof(SAddress)

	if sock.getsockname(Socket, Addr, SizePtr) == SOCKET_ERROR then
		local GetSockNameError = ffi.errno()

		local Error = sock.shutdown(Socket, SD_BOTH)
		if Error ~= 0 then
			return nil, socket_strerror(Error)
		end

		local Error = closesocket_(Socket)
		if Error ~= 0 then
			return nil, socket_strerror(Error)
		end

		return nil, socket_strerror(GetSockNameError)
	end

	local Stream = ffi.new("struct TTCPStream")
	Stream.Socket = Socket
	Stream.LocalIP = sock.inet_ntoa(SAddress.sin_addr)
	Stream.LocalPort = sock.ntohs(SAddress.sin_port)
	Stream.Timeouts = ffi.new("int[2]")
	Stream.TCP = true
	Stream.IsClient = true

	local ServerPtr = ffi.new("int[1]")
	ServerPtr[0] = ServerIP

	if connect_(Socket, ServerPtr, AF_INET, 4, ServerPort) == SOCKET_ERROR then
		local ConnectError = ffi.errno()

		local Error = sock.shutdown(Socket, SD_BOTH)
		if Error ~= 0 then
			return nil, socket_strerror(Error)
		end

		local Error = closesocket_(Socket)
		if Error ~= 0 then
			return nil, socket_strerror(Error)
		end

		return nil, socket_strerror(ConnectError)
	end
	return Stream
end

function TTCPStream:getpeername()
	return ffi.string(self.LocalIP), tonumber(self.Port)
end

function TTCPStream:getsockname()
	return ffi.string(self.LocalIP), tonumber(self.Port)
end

function TTCPStream:getstats()
	local Age = socket.gettime() - tonumber(self.Age)
	return tonumber(self.Received), tonumber(self.Sent), Age
end

function TTCPStream:listen(backlog)
	if sock.listen(self.Socket, backlog or SOMAXCONN) == SOCKET_ERROR then
		local ListenError = ffi.errno()

		local Error = sock.shutdown(self.Socket, SD_BOTH)
		if Error ~= 0 then
			return nil, socket_strerror(Error)
		end

		local Error = closesocket_(self.Socket)
		if Error ~= 0 then
			return nil, socket_strerror(Error)
		end

		return nil, socket_strerror(ListenError)
	end
	self.IsServer = true
	return true
end

function TTCPStream:receive(pattern, prefix)
	if self.Socket == INVALID_SOCKET then
		return nil, "invalid socket"
	end

	local prefix = prefix or ""
	if pattern == nil or pattern == "*a" then
		local Size = ffi.new("int[1]")
		if ioctl_(self.Socket, FIONREAD, Size) == SOCKET_ERROR then
			return nil, socket_strerror(ffi.errno())
		end

		if Size[0] > 0 then
			local Select = select_(1, {self.Socket}, 0, nil, 0, nil, self.Timeouts[0])
			if Select ~= 1 then
				if Select == SOCKET_ERROR then
					return nil, socket_strerror(ffi.errno())
				end
				return nil, "timeout"
			end

			local Buffer = ffi.new("byte["..Size[0].."]")
			local Result = sock.recv(self.Socket, Buffer, Size[0], 0)
			if Result == SOCKET_ERROR then
				return nil, socket_strerror(ffi.errno())
			end
			return ffi.string(Buffer)
		end
	elseif pattern == "*l" then
		local Line = ""
		repeat
			local Select = select_(1, {self.Socket}, 0, nil, 0, nil, self.Timeouts[0])
			if Select ~= 1 then
				if Select == SOCKET_ERROR then
					return nil, socket_strerror(ffi.errno())
				end
				return nil, "timeout"
			end

			local Buffer = ffi.new("byte[1]")
			local Result = sock.recv(self.Socket, Buffer, 1, 0)
			if Result == SOCKET_ERROR then
				return nil, socket_strerror(ffi.errno())
			end

			Line = Line .. string.char(Buffer[0])
			self.Received = self.Received + 1
		until self:Eof()
		return prefix .. Line
	elseif type(pattern) == "number" then
		local Size = ffi.new("int[1]")
		if ioctl_(self.Socket, FIONREAD, Size) == SOCKET_ERROR then
			return nil, socket_strerror(ffi.errno())
		end

		local ReadSize = math.min(pattern, Size[0])
		if Size[0] > 0 then
			local Select = select_(1, {self.Socket}, 0, nil, 0, nil, self.Timeouts[0])
			if Select ~= 1 then
				if Select == SOCKET_ERROR then
					return nil, socket_strerror(ffi.errno())
				end
				return nil, "timeout"
			end

			local Buffer = ffi.new("byte["..Size[0].."]")
			local Result = sock.recv(self.Socket, Buffer, ReadSize, 0)
			if Result == SOCKET_ERROR then
				return nil, socket_strerror(ffi.errno())
			end
			return ffi.string(Buffer)
		end
	end

	local Select = select_(1, {self.Socket}, 0, nil, 0, nil, 0)
	if Select ~= 1 then
		if Select == SOCKET_ERROR then
			return nil, socket_strerror(ffi.errno())
		end
		return nil, "timeout"
	end
	return nil, "closed"
end

function TTCPStream:send(data, i, j)
	if self.Socket == INVALID_SOCKET then
		return nil, "closed"
	end

	if i and j then
		data = data:sub(i, j)
	elseif i then
		data = data:sub(i)
	end

	local Select = select_(1, nil, 1, {self.Socket}, 0, nil, 0)
	if Select ~= 1 then
		if Select == SOCKET_ERROR then
			return nil, socket_strerror(ffi.errno())
		end
		return nil, "WTF?"
	end

	local Result = sock.send(self.Socket, data, #data, 0)
	if Result == SOCKET_ERROR then
		return nil, socket_strerror(ffi.errno())
	end
	self.Sent = self.Sent + #data
	return Result
end

function TTCPStream:setstats(received, sent, age)
	self.Received = received
	self.Sent = sent
	self.Age = socket.gettime() - (tonumber(age) or 0)
end

function TTCPStream:settimeout(value, mode)
	if not mode then
		self.Timeouts[0] = value
		self.Timeouts[1] = value
	elseif mode == "b" then
		self.Timeouts[0] = value
	elseif mode == "t" then
		self.Timeouts[1] = value
	end
end

function TTCPStream:shutdown(mode)
	if mode == "both" then
		sock.shutdown(self.Socket, SD_BOTH)
	elseif mode == "send" then
		sock.shutdown(self.Socket, SD_SEND)
	elseif mode == "receive" then
		sock.shutdown(self.Socket, SD_RECEIVE)
	end
end

-- socket.tcp()
function socket.tcp()
	local Socket = sock.socket(AF_INET, SOCK_STREAM, 0)
	if Socket == INVALID_SOCKET then
		return false, ""
	end

	local Stream = ffi.new("struct TTCPStream")
	Stream.TCP = true
	return Stream
end

-- socket.protect(func)
function socket.protect(func)
	return function (...)
		local Args = {pcall(func, ...)}
		if Args[1] then
			local Args2 = {}
			Args[1] = nil
			for k, v in pairs(Args) do
				Args2[k - 1] = v
			end
			return unpack(Args2)
		end
	end
end

-- socket.select(recvt, sendt [, timeout])
function socket.select(recvt, sendt, timeout)
	if type(recvt) == "table" then
		for _, Stream in pairs(recvt) do

		end
	end
end

-- socket.skip(d [, ret1, ret2 ... retN])
function socket.skip(d, ...)
	local skip = {}
	for Key, Value in pairs({...}) do
		if Key >= d then
			skip[Key - d + 1] = value
		end
	end
	return unpack(skip)
end

-- socket.sleep(time)
if ffi.os == "Windows" then
	ffi.cdef [[void sleep(int ms);]]
	function socket.sleep(t)
		C.sleep(t * 1000)
	end
else
	ffi.cdef [[int poll(struct pollfd * fds, unsigned long nfds, int timeout);]]
	function socket.sleep(t)
		C.poll(nil, 0, s * 1000)
	end
end

-- socket.gettime()
ffi.cdef [[
	struct timeval {
		long tv_sec;
		long tv_usec;
	};
	struct timezone {
		int tz_minuteswest;
		int_tz_dsttime;
	};
	int gettimeofday(struct timeval * tv, struct timezone * tz);
]]
local _Start = ffi.new("struct timeval"); C.gettimeofday(_Start, nil)
function socket.gettime()
	local Time = ffi.new("struct timeval")
	C.gettimeofday(Time, nil)
	return (Time.tv_sec + Time.tv_usec/1.0e6) - Start
end

return socket
