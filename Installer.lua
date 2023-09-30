local fs = require("filesystem")
local component = require("component")
local term = require("term")
local computer = require("computer")
if not component.isAvailable("internet") then
    print("no internet card found")
    return
end

local function readFunc(alternativeSplast)
    if alternativeSplast then
        io.write("index: ")
    else
        io.write("[y/N] ")
    end
    local read = term.read()
    if not read then return end
    return read:sub(1, #read - 1)
end

print("вас приветствует мастер создания загрузочьного диска 𝖃𝖎𝖉𝖔𝕺𝕾")
print("выберите режим")
print("1. создать устоновочьный диск")
print("2. устоновить устоновшик в tmpfs и перезагрузиться туда(tmpfs будет очишенна)")
local index = readFunc(true)
if not index then
    return
end

local function installTo(address, auto, offlineMode)
    local proxy = component.proxy(address)

    if not auto then
        print("вы уверены сделать диск " .. address:sub(1, 4) .. ":" .. (component.invoke(address, "getLabel") or "") .. " устоновочьным диском 𝖃𝖎𝖉𝖔𝕺𝕾?")
        print("ВСЕ ДАННЫЕ С ДИСКА БУДУТ УДАЛЕНЫ")

        local ok = readFunc()
        if not ok or ok:lower() ~= "y" then
            return
        end
    end

    local mountPath = "/free/tempMounts/installdrive"
    fs.umount(mountPath)
    fs.mount(proxy, mountPath)

    proxy.remove("/")
    pcall(proxy.setLabel, "𝖃𝖎𝖉𝖔𝕺𝕾 installer")

    ------------------------------------

    local function getInternetFile(url)
        local handle, data, result, reason = component.internet.request(url), ""
        if handle then
            while true do
                result, reason = handle.read(math.huge) 
                if result then
                    data = data .. result
                else
                    handle.close()
                    
                    if reason then
                        return nil, reason
                    else
                        return data
                    end
                end
            end
        else
            return nil, "unvalid address"
        end
    end

    local function split(str, sep)
        local parts, count, i = {}, 1, 1
        while 1 do
            if i > #str then break end
            local char = str:sub(i, i - 1 + #sep)
            if not parts[count] then parts[count] = "" end
            if char == sep then
                count = count + 1
                i = i + #sep
            else
                parts[count] = parts[count] .. str:sub(i, i)
                i = i + 1
            end
        end
        if str:sub(#str - (#sep - 1), #str) == sep then t.insert(parts, "") end
        return parts
    end

    local url = "https://raw.githubusercontent.com/matvey-mayner/XidoOS/main"

    if offlineMode then
        local filelist = split(assert(getInternetFile(url .. "/filelist.txt")), "\n")

        for i, path in ipairs(filelist) do
            if path ~= "" then
                local full_url = url .. path
                local data = assert(getInternetFile(full_url))

                local lpath = fs.concat(mountPath, "core", path)
                fs.makeDirectory(fs.path(lpath))
                local file = assert(io.open(lpath, "wb"))
                file:write(data)
                file:close()
            end
        end

        --proxy.makeDirectory("/boot/kernel")
        --proxy.rename("/init.lua", "/boot/kernel/likemode")
    end

    local file = io.open(fs.concat(mountPath, "init.lua"), "wb")
    file:write(assert(getInternetFile(url .. "/maininstaller.lua")))
    file:close()

    local file = io.open(fs.concat(mountPath, ".install"), "wb")
    file:write(assert(getInternetFile(url .. "/oschanger.lua")))
    file:close()

    -----------------------------------------------------------------------------

    if offlineMode then
        local function downloadDistribution(url, folder)
            local filelist = split(assert(getInternetFile(url .. "/filelist.txt")), "\n")

            for i, path in ipairs(filelist) do
                if path ~= "" then
                    local full_url = url .. path
                    local data = assert(getInternetFile(full_url))

                    local lpath = fs.concat(mountPath, "distributions", folder, path)
                    fs.makeDirectory(fs.path(lpath))
                    local file = assert(io.open(lpath, "wb"))
                    file:write(data)
                    file:close()
                end
            end
        end

        local filelist = split(assert(getInternetFile("https://raw.githubusercontent.com/matvey-mayner/XidoOS/main/list.txt")), "\n")
        for i, v in ipairs(filelist) do
            if v ~= "" then
                downloadDistribution(table.unpack(split(v, ";")))
            end
        end
    end

    print("создания загрузочьного диска завершено")
end

if index == "1" then
    local count = 1
    local variantes = {}
    for address in component.list("filesystem") do
        if not component.invoke(address, "isReadOnly") and address ~= computer.tmpAddress() and address ~= fs.get("/").address then
            print(tostring(count) .. ". " .. address:sub(1, 4) .. " label: " .. (component.invoke(address, "getLabel") or ""))
            count = count + 1
            table.insert(variantes, address)
        end
    end

    print("выберите диск который хотите сделать устоновочьным")
    print("ВСЕ ДАННЫЕ С ДИСКА БУДУТ УДАЛЕНЫ")
    local read = readFunc(true)
    if not read then return end
    if not tonumber(read) then
        print("invalide input")
        return
    end
    local address = variantes[tonumber(read)]

    print("добавить на диск дистрибутивы и ядро для устоновки без internet card?(создания диска будет долгим)")
    local read = readFunc()
    if not read then return end

    installTo(address, false, read:lower() == "y")
elseif index == "2" then
    installTo(computer.tmpAddress(), true, false)

    local driveAddress = computer.tmpAddress()

    local function biosErr()
        print("¯\\_(ツ)_/¯ усп, ваш биос не поддерживает устоновку загрузочьного насителя, попробуйте сами загрузиться с диска/tmpfs через биос, инструкция должна быть написана в описании вашего биоса")
        if component.isAvailable("eeprom") then
            print("ваш биос был определен как \"" .. (component.eeprom.getLabel() or "unknown") .. "\"")
        end
    end

    if not computer.setBootAddress then
        biosErr()
        return
    end
    
    local result = {pcall(computer.setBootAddress, driveAddress)}
    if not result[1] then
        biosErr()
        return
    end
    if not result[2] and type(result[3]) == "string" then
        biosErr()
        return
    end

    if computer.setBootFile then
        pcall(computer.setBootFile, "/init.lua")
    end
    pcall(computer.shutdown, "fast")
else
    print("нету этого режима")
end
