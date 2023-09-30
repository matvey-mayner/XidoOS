local invoke = require("component").invoke
local address = ...

local signature = "--XidoOS"

local file = invoke(address, "open", "/system/main.lua", "rb")
if file then
    local data = invoke(address, "read", file, #signature)
    invoke(address, "close", file)
    return signature == data
end