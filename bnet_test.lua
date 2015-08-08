for k, v in pairs(package.loaders) do
	print("lib", k)
end

local ffi = require("ffi")
local bit = require("bit")
socket = require("bnet")

sock = assert(socket.tcp())
sock:settimeout(5000)

start = socket.gettime()
print(sock:connect("unrealsoftware.de", 80)) -- it still doesn't work with dns
print((socket.gettime() - start) * 1000)
print(sock:getsockname())
print(sock:getpeername())
