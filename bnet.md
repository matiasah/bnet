---
tagline: networking library
platforms: mingw32, mingw64
---

<warn>Work in progress! To be released when?</warn>

## `local bnet = require'bnet'`

Networking library, API compatible with LuaSocket 2.0.2.

This library ports most of the functions from LuaSocket 2.0.2 in pure Lua code,
you won't need to install any other dynamic libraries.

Why is it called bnet?
Because it's first version was intended to be a port from the BNet library for BlitzMax in Lua,
but later it was improved to be API compatible with the traditional LuaSocket library.

# API

------------------------------ ----------------------------------------------------
##DNS (in socket)
socket.dns.gethostname()       Returns the standard host name for the machine as a string.
socket.dns.tohostname(address) Converts from IP address to host name. Address can be an IP address or host name. The function returns a string with the canonic host name of the given address, followed by a table with all information returned by the resolver. In case of error, the function returns nil followed by an error message.
##Socket
##TCP (in socket)
##UDP (in socket)
------------------------------ ----------------------------------------------------

# Notes
