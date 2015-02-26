local ffi = require("ffi")
local fd_lib
local print = print
local tostring = tostring
local tonumber = tonumber
local strsub = string.sub

local function isnil(object)
	if object then
		return strsub(tostring(object), -4) == "NULL"
	end
	return true
end

module("socket_wrapper")

INVALID_SOCKET = -1
SOL_SOCKET = 0xFFFF
INADDR_ANY = 0
INADDR_NONE = 0XFFFFFFFF

AF_INET = 2
SOCK_STREAM = 1
SOCK_DGRAM = 2
SOCKET_ERROR = -1

SO_DEBUG = 1
SO_ACCEPTCONN = 2
SO_REUSEADDR = 4
SO_KEEPALIVE = 8
SO_DONTREROUTE = 0X10
SO_BROADCAST = 0X20
SO_USELOOPBACK = 0X40
SO_LINGER = 0X80
SO_OOBINLINE = 0X100

SO_SNDBUF = 0X1001
SO_RCVBUF = 0X1002
SO_SNDLOWAT = 0X1003
SO_RCVLOWAT = 0X1004
SO_SNDTIMEO = 0X1005
SO_RCVTIMEO = 0X1006
SO_ERROR = 0X1007
SO_TYPE = 0X1008

SO_SYNCHRONOUS_ALERT = 0X10
SO_SYNCHRONOUS_NONALERT = 0X20

TCP_NODELAY = 0X0001
TCP_BSDURGENT = 0X7000

IPPROTO_UDP = 17
IPPROTO_TCP = 6

SD_SEND = 1
SD_RECEIVE = 0
SD_BOTH = 2

if ffi.os == "Windows" then
	FIONREAD = 0x4004667F

	SO_OPENTYPE = 0X7008
	SO_MAXDG = 0X7009
	SO_MAXPATHDG = 0X700A
	SO_UPDATE_ACCEPT_CONTENXT = 0X700B
	SO_CONNECT_TIME = 0X700C

	sock = ffi.load("ws2_32")
	ffi.cdef [[
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
		typedef uint16_t u_short;
		typedef uint32_t u_int;
		typedef unsigned long u_long;
		typedef uintptr_t SOCKET;
		typedef struct fd_set {u_int fd_count;SOCKET  fd_array[64];} fd_set;
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
		int setsockopt(SOCKET s, int level, int optname, const char *optval, int optlen);
		int shutdown(SOCKET s, int how);
		struct hostent *gethostbyname(const char *name);
		struct hostent *gethostbyaddr(const char *addr, int len, int type);

		int __WSAFDIsSet(SOCKET fd, fd_set * set);
		int WSAStartup(WORD wVersionRequested, LPWSADATA lpWSAData);
		int WSACleanup(void);
		int WSAGetLastError(void);

		int atexit(void (__cdecl * func)( void));
	]]

	WSA_INVALID_HANDLE = 6
	WSA_NOT_ENOUGH_MEMORY = 8
	WSA_INVALID_PARAMETER = 87
	WSA_OPERATION_ABORTED = 995
	WSA_IO_INCOMPLETE = 996
	WSA_IO_PENDING = 997
	WSAEINTR = 10004
	WSAEBADF = 10009
	WSAEACCES = 10013
	WSAEFAULT = 10014
	WSAEINVAL = 10022
	WSAEMFILE = 10024
	WSAEWOULDBLOCK = 10035
	WSAEINPROGRESS = 10036
	WSAEALREADY = 10037
	WSAENOTSOCK = 10038
	WSAEDESTADDRREQ = 10039
	WSAEMSGSIZE = 10040
	WSAEPROTOTYPE = 10041
	WSAENOPROTOOPT = 10042
	WSAEPROTONOSUPPORT = 10043
	WSAESOCKTNOSUPPORT = 10044
	WSAEOPNOTSUPP = 10045
	WSAEPFNOSUPPORT = 10046
	WSAEAFNOSUPPORT = 10047
	WSAEADDRINUSE = 10048
	WSAEADDRNOTAVAIL = 10049
	WSAENETDOWN = 10050
	WSAENETUNREACH = 10051
	WSAENETRESET = 10052

	getError = sock.WSAGetLastError

	local ws = ffi.new("WSADATA")
	sock.WSAStartup(0x101, ws)
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

	function inet_addr_(cp)
		return sock.inet_addr(cp)
	end

	function inet_ntoa_(_in)
		return sock.inet_ntoa(_in)
	end
else
	sock = ffi.load("sys/socket.h")
	netdb = ffi.load("netdb.h")
	ffi.cdef [[
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
		typedef uint16_t u_short;
		typedef uint32_t u_int;
		typedef unsigned long u_long;
		typedef uintptr_t SOCKET;
		typedef struct fd_set {u_int fd_count;SOCKET  fd_array[64];} fd_set;
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
		int setsockopt(SOCKET s, int level, int optname, const char *optval, int optlen);
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

	function inet_addr_(cp)
		return sock.inet_addr(cp)
	end

	function inet_ntoa_(_in)
		return sock.inet_ntoa(_in)
	end

	if ffi.os == "MacOS" then
		FIONREAD = 0x4004667F
	elseif ffi.os == "Linux" then
		FIONREAD = 0x0000541B
	end
end

function htons_(n)
	return sock.htons(n)
end

function ntohs_(n)
	return sock.ntohs(n)
end

function htonl_(n)
	return sock.htonl(n)
end

function ntohl_(n)
	return sock.ntohl(n)
end

function socket_(addr_type, comm_type, protocol)
	return sock.socket(addr_type, comm_type, protocol)
end

if ffi.os == "Windows" then
	function closesocket_(s)
		return sock.closesocket(s)
	end
else
	function closesocket_(s)
		return sock.close(s)
	end
end

function bind_(socket, addr_type, port)
	local sa = ffi.new("struct sockaddr_in")
	if addr_type ~= AF_INET then
		return -1
	end

	ffi.fill(sa, 0, ffi.sizeof(sa))
	sa.sin_family = addr_type
	sa.sin_addr.s_addr = htonl_(INADDR_ANY)
	sa.sin_port = htons_(port)

	local _sa = ffi.cast("struct sockaddr *", sa)
	return sock.bind(socket, _sa, ffi.sizeof(sa))
end

function gethostbyaddr_(addr, addr_len, addr_type)
	local e = sock.gethostbyaddr(addr, addr_len, addr_type)
	if not isnil(e) then
		return e.h_name
	end
end

function gethostbyname_(name)
	local e = sock.gethostbyname(name)
	if not isnil(e) then
		return e.h_addr_list, e.h_addrtype, e.h_length
	end
end

function connect_(socket, addr, addr_type, addr_len, port)
	local sa = ffi.new("struct sockaddr_in")
	if addr_type == AF_INET then
		ffi.fill(sa, 0, ffi.sizeof(sa))
		sa.sin_family = addr_type
		sa.sin_port = htons_(port)
		ffi.copy(sa.sin_addr, addr, addr_len)

		local Addr = ffi.cast("struct sockaddr *", sa)
		return sock.connect(socket, Addr, ffi.sizeof(sa))
	end
	return SOCKET_ERROR
end

function listen_(socket, backlog)
	return sock.listen(socket, backlog)
end

function accept_(socket, addr, addr_len)
	return sock.accept(socket, addr, addr_len)
end

function select_(n_read, r_socks, n_write, w_socks, n_except, e_socks, millis)
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

--int select(int nfds, fd_set *readfds, fd_set *writefds, fd_set *exceptfds, const struct timeval *timeout);

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

function send_(socket, buf, size, flags)
	return sock.send(socket, buf, size, flags)
end

function sendto_(socket, buf, size, flags, dest_ip, dest_port)
	local sa = ffi.new("struct sockaddr_in")
	ffi.fill(sa, 0, ffi.sizeof(sa))
	sa.sin_family = AF_INET
	sa.sin_addr.s_addr = htonl_(dest_ip)
	sa.sin_port = htons_(dest_port)
	return sock.sendto(socket, buf, size, flags, sa, ffi.sizeof(sa))
end

function recv_(socket, buf, size, flags)
	return sock.recv(socket, buf, size, flags)
end

function recvfrom_(socket, buf, size, flags, ip, port)
	local sa = ffi.new("struct sockaddr_in")
	ffi.fill(sa, 0, ffi.sizeof(sa))

	local sasize = ffi.sizeof(sa)
	local count = sock.recvfrom(socket, buf, size, flags, sa, sasize)
	ip = ntohl_(sa.sin_addr.s_addr)
	port = ntohs_(sa.sin_port)
	return count
end

function setsockopt_(socket, level, optname, optval, count)
	return sock.setsockopt(socket, level, optname, optval, count)
end

function getsockopt_(socket, level, optname, optval, count)
	return sock.getsockopt(socket, level, optname, optval, count)
end

function shutdown_(socket, how)
	return sock.shutdown(socket, how)
end

function getsockname_(socket, addr, len)
	return sock.getsockname(socket, addr, len)
end

function getpeername_(socket, addr, len)
	return sock.getpeername(socket, addr, len)
end
