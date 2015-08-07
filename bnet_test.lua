socket = require("bnet")

sock = assert(socket.tcp())
sock:settimeout(5000)

start = socket.gettime()
print(sock:connect("85.214.102.60", 80)) -- it still doesn't work with dns
print((socket.gettime() - start) * 1000)
