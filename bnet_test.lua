local ffi = require("ffi")
socket = require("bnet")

--[[
sock = assert(socket.tcp())
sock:settimeout(5000)

start = socket.gettime()
print(sock:connect("85.214.102.60", 80)) -- it still doesn't work with dns
print((socket.gettime() - start) * 1000)
]]

local teststr = ffi.new("char [7]", "this is a test string")
local teststr2 = ffi.new("char [6]", "string")

ffi.copy(teststr + 2, teststr2)
print(ffi.string(teststr))
