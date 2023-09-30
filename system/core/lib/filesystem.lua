local component = require("component")
local computer = require("computer")
local unicode = require("unicode")
local paths = require("paths")
local bootloader = require("bootloader")

------------------------------------

local filesystem = {}
filesystem.mountList = {}
filesystem.baseFileDirectorySize = 512 --задаеться к конфиге мода(по умалчанию 512 байт)
filesystem.autoMount = true
filesystem.inited = false

local function startSlash(path)
    if unicode.sub(path, 1, 1) ~= "/" then
        return "/" .. path
    end
    return path
end

local function endSlash(path)
    if unicode.sub(path, unicode.len(path), unicode.len(path)) ~= "/" then
        return path .. "/"
    end
    return path
end

local function noEndSlash(path)
    if unicode.len(path) > 1 and unicode.sub(path, unicode.len(path), unicode.len(path)) == "/" then
        return unicode.sub(path, 1, unicode.len(path) - 1)
    end
    return path
end

function filesystem.mount(proxy, path)
    if type(proxy) == "string" then
        local lproxy, err = component.proxy(proxy)
        if not lproxy then
            return nil, err
        end
        proxy = lproxy
    end

    path = paths.canonical(path)
    if filesystem.inited then
        filesystem.makeDirectory(paths.path(path))
    end

    path = endSlash(path)
    for i, v in ipairs(filesystem.mountList) do
        if v[2] == path then
            return nil, "another filesystem is already mounted here"
        end
    end

    table.insert(filesystem.mountList, {proxy, path})
    table.sort(filesystem.mountList, function(a, b) --просто нужно, иначе все по бараде пойдет
        return unicode.len(a[2]) > unicode.len(b[2])
    end)

    return true
end

function filesystem.umount(path)
    path = endSlash(paths.canonical(path))
    for i, v in ipairs(filesystem.mountList) do
        if v[2] == path then
            table.remove(filesystem.mountList, i)
            return true
        end
    end
    return false
end

function filesystem.mounts()
    local list = {}
    for i, v in ipairs(filesystem.mountList) do
        local proxy, path = v[1], v[2]
        list[path] = v
        list[proxy.address] = v
        list[i] = v
    end
    return list
end

function filesystem.get(path)
    path = endSlash(paths.canonical(path))
    for i = 1, #filesystem.mountList do
        if unicode.sub(path, 1, unicode.len(filesystem.mountList[i][2])) == filesystem.mountList[i][2] then
            if not pcall(filesystem.mountList[i][1].exists, "/null") then --disconnect check
                table.remove(filesystem.mountList, i)
                return filesystem.get(path)
            end
            return filesystem.mountList[i][1], noEndSlash(startSlash(unicode.sub(path, unicode.len(filesystem.mountList[i][2]) + 1, unicode.len(path))))
        end
    end

    if filesystem.mountList[1] then
        return filesystem.mountList[1][1], filesystem.mountList[1][2]
    end
end

--[[
function filesystem.get(path)
    path = paths.canonical(path)
    for i = 1, #filesystem.mountList do
        if path:sub(1, unicode.len(filesystem.mountList[i][2])) == filesystem.mountList[i][2] then
            return filesystem.mountList[i][1], unicode.sub(path, filesystem.mountList[i][2]:len() + 1, -1)
        end
    end
end
]]

function filesystem.exists(path)
    local proxy, proxyPath = filesystem.get(path)
    return proxy.exists(proxyPath)
end

function filesystem.size(path, baseCostMath)
    local proxy, proxyPath = filesystem.get(path)
    local size = 0
    local function recurse(lpath)
        for _, filename in ipairs(filesystem.list(lpath)) do
            local fullpath = paths.concat(lpath, filename)
            if proxy.isDirectory(fullpath) then
                if baseCostMath then
                    size = size + filesystem.baseFileDirectorySize
                end
                recurse(fullpath)
            else
                local lsize = proxy.size(fullpath)
                size = size + lsize
                if baseCostMath then
                    size = size + filesystem.baseFileDirectorySize
                end
            end
        end
    end
    if proxy.isDirectory(proxyPath) then
        recurse(proxyPath)
    else
        local lsize = proxy.size(proxyPath)
        size = size + lsize
        if baseCostMath then
            size = size + filesystem.baseFileDirectorySize
        end
    end
    return size
end

function filesystem.isDirectory(path)
    for i, v in ipairs(filesystem.mountList) do
        if v[2] == paths.canonical(path) then
            return true
        end
    end

    local proxy, proxyPath = filesystem.get(path)
    return proxy.isDirectory(proxyPath)
end

function filesystem.isReadOnly(path)
    local proxy, proxyPath = filesystem.get(path)
    return proxy.isReadOnly()
end

function filesystem.makeDirectory(path)
    local proxy, proxyPath = filesystem.get(path)
    return proxy.makeDirectory(proxyPath)
end

function filesystem.lastModified(path)
    local proxy, proxyPath = filesystem.get(path)
    return proxy.lastModified(proxyPath)
end

function filesystem.remove(path)
    local proxy, proxyPath = filesystem.get(path)
    return proxy.remove(proxyPath)
end

function filesystem.list(path)
    local proxy, proxyPath = filesystem.get(path)
    local tbl = proxy.list(proxyPath)

    if tbl then
        tbl.n = nil
        for i = 1, #filesystem.mountList do
            if paths.canonical(path) == paths.path(filesystem.mountList[i][2]) then
                table.insert(tbl, paths.name(filesystem.mountList[i][2]))
            end
        end
        table.sort(tbl)
        return tbl
    else
        return {}
    end
end

function filesystem.rename(fromPath, toPath)
    fromPath = paths.canonical(fromPath)
    toPath = paths.canonical(toPath)
    if paths.equals(fromPath, toPath) then return end

    local fromProxy, fromProxyPath = filesystem.get(fromPath)
    local toProxy, toProxyPath = filesystem.get(toPath)

    if fromProxy.address == toProxy.address then
        return fromProxy.rename(fromProxyPath, toProxyPath)
    else
        local success, err = filesystem.copy(fromPath, toPath)
        if not success then
            return nil, err
        end
        local success, err = filesystem.remove(fromPath)
        if not success then
            return nil, err
        end
    end

    return true
end

function filesystem.open(path, mode)
    local proxy, proxyPath = filesystem.get(path)
    local result, reason = proxy.open(proxyPath, mode)
    if result then
        local handle = { --а нам он и нафиг не нужен цей файл buffer...
            read = function(...) return proxy.read(result, ...) end,
            write = function(...) return proxy.write(result, ...) end,
            close = function(...) return proxy.close(result, ...) end,
            seek = function(...) return proxy.seek(result, ...) end,
            readAll = function()
                local buffer = ""
                repeat
                    local data = proxy.read(result, math.huge)
                    buffer = buffer .. (data or "")
                until not data
                return buffer
            end,
            handle = result,
        }

        return handle
    end
    return nil, reason
end

function filesystem.copy(fromPath, toPath, fcheck)
    fromPath = paths.canonical(fromPath)
    toPath = paths.canonical(toPath)
    if paths.equals(fromPath, toPath) then return end
    local function copyRecursively(fromPath, toPath)
        if not fcheck or fcheck(fromPath, toPath) then
            if filesystem.isDirectory(fromPath) then
                filesystem.makeDirectory(toPath)

                local list = filesystem.list(fromPath)
                for i = 1, #list do
                    local from = paths.canonical(fromPath .. "/" .. list[i])
                    local to =  paths.canonical(toPath .. "/" .. list[i])
                    local success, err = copyRecursively(from, to)
                    if not success then
                        return nil, err
                    end
                end
            else
                local fromHandle, err = filesystem.open(fromPath, "rb")
                if fromHandle then
                    local toHandle, err = filesystem.open(toPath, "wb")
                    if toHandle then
                        while true do
                            local chunk = fromHandle.read(math.huge)
                            if chunk then
                                if not toHandle.write(chunk) then
                                    return nil, "failed to write file"
                                end
                            else
                                toHandle.close()
                                fromHandle.close()

                                break
                            end
                        end
                    else
                        return nil, err
                    end
                else
                    return nil, err
                end
            end
        end

        return true
    end

    return copyRecursively(fromPath, toPath)
end

function filesystem.writeFile(path, data)
    filesystem.makeDirectory(paths.path(path))
    local file, err = filesystem.open(path, "wb")
    if not file then return nil, err or "unknown error" end
    local ok, err = file.write(data)
    if not ok then
        pcall(file.close)
        return err or "unknown error"
    end
    file.close()
    return true
end

function filesystem.readFile(path)
    local file, err = filesystem.open(path, "rb")
    if not file then return nil, err or "unknown error" end
    local result = {file.readAll()}
    file.close()
    return table.unpack(result)
end


filesystem.bootaddress = bootloader.bootaddress
filesystem.tmpaddress = bootloader.tmpaddress

assert(filesystem.mount(filesystem.bootaddress, "/"))
if filesystem.autoMount then
    assert(filesystem.mount(filesystem.tmpaddress, "/tmp"))
    assert(filesystem.mount(filesystem.tmpaddress, "/mnt/tmpfs"))
    assert(filesystem.mount(filesystem.bootaddress, "/mnt/root"))
end

filesystem.inited = true
return filesystem