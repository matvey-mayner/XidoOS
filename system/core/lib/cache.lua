local cache = {}
cache.cache = {}
cache.copiedText = "PASTE" --put the copied text here

function cache.clearCache()
    for key, value in pairs(cache.cache) do
        cache.cache[key] = nil
    end
end

return cache