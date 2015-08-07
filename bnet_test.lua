socket = require("bnet")

sock = assert(socket.tcp())
assert(sock:bind("*", 500))
assert(sock:listen())

repeat
	local cl, e = sock:accept()
	if cl then
		local ip, port = cl:getsockname()
		print("CL CONNECTED ", ip, port)
	end
until false
