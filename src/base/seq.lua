--
-- Sequences : sequence processing in a functional programming style similar to C# LINQ or Scala
--

Seq = {}
local SeqMT = {
	__index = Seq,
	__seq = true,
}
local nextUID = 1000		-- debugging

-- Sequence for iterating over a table, or just cloning another sequence
function Seq:new(t, optValue)
	local s = {}
	if t == nil then
		s.iterate = function()
			return function()
				return nil
			end
		end
	elseif Seq.isSeq(t) then
		-- Clone
		s.iterate = t.iterate
	elseif type(t) == 'string' then
		if optValue then
			local t2 = {}
			t2[t] = optValue
			return Seq:new(t2)
		else
			return Seq:new({t})
		end
	elseif type(t) == 'function' then
		s.iterate = function()
			-- setup
			-- moveNext
			return function()
				local v = t()
				return v,v
			end
		end
	else
		-- Create a new iterator object which will iterate over t
		s.iterate = function()
			-- Set up iterator state
			local fn = pairs(t)
			local key,value
			-- Return a moveNext function, which returns (idx,value), and idx=nil to end
			return function()
				key,value = fn(t,key)
				if key then return key,value
				else return nil
				end
			end
		end
	end
	s.uid = nextUID
	nextUID = nextUID + 1
	return setmetatable( s, SeqMT )
end

-- seq equivalent of ipairs. Iterates over the numerical keyed arguments in a table
function Seq:ipairs(t)
	local s = Seq:new(nil)
	if (not t) or (#t==0) then
		return s
	end
	s.iterate = function()
		local i = 0
		return function()
			i = i + 1
			if i <= #t then return i,t[i]
			else return nil
			end
		end
	end
	return s
end

function Seq.toSeq(s, optValue)
	if Seq.isSeq(s) then
		return s
	else
		return Seq:new(s, optValue)
	end
end

function Seq:tostring()
	return 'Seq' .. self.uid
end

function Seq.isSeq(s)
	local mt = getmetatable(s)
	return s and mt and mt.__seq
end

function Seq:each()
	return self.iterate()
end

function Seq:mkstring(delimiter)
	rv = nil
	for _,v in self:each() do
		if rv then
			rv = rv .. ' ' .. v
		else
			rv = v
		end
	end
	return rv or ''
end

-- note : Condition is on the value, not (key,value)
function Seq:where(cond)
	local s = Seq:new(self)
	s.iterate = function()
		-- setup
		local iter = self.iterate()
		-- moveNext
		return function(s)
			for i,v in iter do 
				if cond(v) then
					return i,v
				end
			end
			return nil
		end
	end
	return s
end

-- Condition is on (key,value)
function Seq:whereK(cond)
	local s = Seq:new(self)
	s.iterate = function()
		-- setup
		local iter = self.iterate()
		-- moveNext
		return function(s)
			for k,v in iter do 
				if cond(k,v) then
					return k,v
				end
			end
			return nil
		end
	end
	return s
end
function Seq:select(selector)
	local s = Seq:new(self)
	s.iterate = function()
		-- setup
		local iter = self.iterate()
		-- moveNext
		return function()
			for i,v in iter do
				return i, selector(v)
			end
		end
	end
	return s
end

-- Skips the next n values
function Seq:skip(n)
	local s = Seq:new(self)
	s.iterate = function()
		-- setup
		local iter = self.iterate()
		local skipN = n
		-- moveNext
		return function()
			while skipN > 0 do
				skipN = skipN - 1
				local i = iter()
				if not i then 			-- early out
					return nil
				end				
			end
			return iter()
		end
	end
	return s
end

-- Returns the first n values
function Seq:take(n)
	local s = Seq:new(self)
	s.iterate = function()
		-- setup
		local iter = self.iterate()
		local takeN = n
		-- moveNext
		return function()
			if takeN > 0 then
				takeN = takeN - 1
				return iter()
			else
				return nil
			end
		end
	end
	return s
end

-- Returns the first value
function Seq:first()
	local iter = self.iterate()
	local k,v = iter()
	return v
end

-- Remove any element in the string/sequence/set vs
function Seq:except(exceptValues)
	if exceptValues == nil then
		return self:where(function(v) return v ~= nil; end)
	else
		exceptValues = toSet(exceptValues)
		return self:where(function(v) return not exceptValues[v];	end)
	end
end

-- Prepend a string to each element
function Seq:prependEach(prepend)
	return self:select(function(v) return prepend .. v; end)
end

-- Append a string to each element
function Seq:appendEach(append)
	return self:select(function(v) return v .. append; end)
end

-- Iterate over the keys in a sequence
function Seq:getKeys()
	local s = Seq:new(self)
	s.iterate = function()
		-- setup
		local iter = self.iterate()
		-- moveNext
		return function()
			for k,_ in iter do
				return k, k
			end
		end
	end
	return s
end

-- concatenate sequence
function Seq:concat(seq2)
	seq2 = Seq.toSeq(seq2)
	
	local s = Seq:new(nil)
	s.iterate = function()
		-- setup
		local iter1 = self.iterate()
		local iter2 = seq2.iterate()
		-- moveNext
		return function()
			local i,v
			if iter1 then 
				i,v = iter1()
				if not i then iter1 = nil end				 
			end
			if not iter1 then 
				i,v = iter2()
			end
			return i,v
		end	
	end
	return s
end

-- concatenate index sequence
function Seq:iconcat(seq2)
	return self:concat(Seq:ipairs(seq2))
end


-- prepend a sequence, opposite of concat
function Seq:prepend(seq2, optValue)
	seq2 = Seq.toSeq(seq2, optValue)
	return seq2:concat(self)
end

function Seq:toTable()
	local t = {}
	for k,v in self:each() do
		t[k] = v
	end
	return t
end

-- Returns boolean
function Seq:contains(value)
	for k,v in self:each() do
		if k == value or v == value then
			return true
		end
	end
	return false
end

-- orderBy will put key/values in ascending order as defined by orderFn
-- orderFn takes (key, value) parameters, and returns an integer
function Seq:orderBy(orderFn)
	--untested
	local function compFn(a,b) return orderFn(a.key,a.value) < orderFn(b.key, b.value); end 	

	-- flatten the table in to a sequence of key/value pairs
	local tFlat = {}
	for k,v in self:each() do
		table.insert(tFlat, { key = k, value = v })
	end
	
	-- sort it
	local tSortedFlat = table.sort(tFlat, compFn)
	
	-- Unflatten the table
	local tSorted = {}
	for i,p in ipairs(tSortedFlat) do
		tSorted[p.key] = p.value
	end
	
	return Seq:new(tSorted)
end

-- Return the maximum value in a sequence, assume #value for non number types
function Seq:max()
	local hasValues = false 
	local maxValue = -9e99
	for k,v in self.iterate() do
		hasValues = true
		if type(v) == 'number' then
			maxValue = math.max(maxValue, v)
		elseif v ~= nil then
			maxValue = math.max(maxValue, #v)
		end
	end
	if not hasValues then
		return 0
	end
	return maxValue
end

function testSeq()
	bigT = { 'one', 'two', 'three', 'four', 'five', 'six', 'seven' }
	t2 = { 'door', 'stop' }
	
	local bigTseq = Seq:new(bigT)
	local no2 = bigTseq:where(function(v) return v ~= 'two'; end)
	local no23 = no2:where(function(v) return v ~= 'three'; end)
	local no23_2 = no23:select(function(v) return v .. string.upper(v); end)
	
	local tconcat = bigTseq:take(2):concat(t2)
	local ticoncat = Seq:ipairs(bigT):concat(Seq:ipairs(t2))

	print('bigTseq ' .. bigTseq:tostring()) 
	print('tconcat ' .. tconcat:mkstring(' ')) 
	print('ticoncat ' .. ticoncat:mkstring(' ')) 
	--print('no2     ' .. no2:tostring()) 
	--print('no23    ' .. no23:tostring()) 
	--print('no23_2  ' .. no23_2:tostring()) 
	
	print('')
	for i,x in no23:skip(0):take(3):except('four'):concat('theend'):each() do
	--for i,x in bigTseq:take(5):except('four'):concat('theend'):each() do
		print(tostring(i) .. ':' ..tostring(x))
	end	
	print('')
end
