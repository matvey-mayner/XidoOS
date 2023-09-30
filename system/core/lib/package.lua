local bootloader = ...
local component = component
local computer = computer
local unicode = unicode

------------------------------------

local package = {}
package.paths = {"/data/lib",  "/vendor/lib", "/system/lib", "/system/core/lib"} --позиция по мере снижения приоритета(первый элемент это самый высокий приоритет)
package.loaded = {
    ["package"] = package,
    ["bootloader"] = bootloader
}
for key, value in pairs(_G) do
    if type(value) == "table" then
        package.loaded[key] = value
    end
end
package.cache = {}
package.loadingList = {}
package.allowEnclosedLoadingCycle = false

function package.find(name)
    local fs = require("filesystem")
    local paths = require("paths")

    local function resolve(path, deep)
        if fs.exists(path) then
            if fs.isDirectory(path) then
                local lpath = paths.concat(path, "init.lua")
                if fs.exists(lpath) and not fs.isDirectory(lpath) then
                    return lpath
                end
            else
                return path
            end
        end

        if not deep then
            return resolve(path .. ".lua", true)
        end
    end
    
    if unicode.sub(name, 1, 1) == "/" then
        return resolve(name)
    else
        for i, v in ipairs(package.paths) do
            local path = resolve(paths.concat(v, name))
            if path then
                return path
            end
        end
    end
end

function package.require(name)
    local libtbl = package.loaded[name] or package.cache[name]
    if libtbl then return libtbl end

    local function loadLib()
        if libtbl then return libtbl end
        if not package.loaded[name] and not package.cache[name] then
            local finded = package.find(name)
            if not finded then
                error("lib " .. name .. " is not found", 3)
            end

            package.loadingList[name] = true
            local lib = assert(loadfile(finded, nil, bootloader.createEnv()))()
            package.loadingList[name] = nil

            if type(lib) == "table" and lib.unloadable then
                package.cache[name] = lib
            else
                package.loaded[name] = lib
            end
        end
        if not package.loaded[name] and not package.cache[name] then
            error("lib " .. name .. " is not found" , 3)
        end
        libtbl = package.loaded[name] or package.cache[name]
        return libtbl
    end

    if package.loadingList[name] then
        if package.allowEnclosedLoadingCycle then
            return setmetatable({}, {__index = function (_, key)
                loadLib()
                return libtbl[key]
            end, __newindex = function (_, key, value)
                loadLib()
                libtbl[key] = value
            end})
        else
            error("enclosed loading cycle is disabled", 2)
        end
    else
        return loadLib()
    end
end

function package.get(name)
    return package.loaded[name] or package.cache[name]
end

function package.isLoaded(name)
    return not not package.get(name)
end

function package.isInstalled(name)
    return not not package.find(name)
end

function package.raw_reg(name, path)
    if bootloader.bootfs.exists(path) and not package.loaded[name] and not package.cache[name] then
        local lib = bootloader.dofile(path, nil, bootloader.createEnv())
        if type(lib) == "table" and lib.unloadable then
            package.cache[name] = lib
        else
            package.loaded[name] = lib
        end
    end
end

------------------------------------

return package