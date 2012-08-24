--
-- Caching to speed up Premake
--

premake.cache = {}
local cache = premake.cache

function cache.new()
	local c = {}
	c.lookup = {}
	return c
end

function cache.set(key, value)
	cache.lookup[key] = value
end

function cache.get(key)
	return cache.lookup[key]
end