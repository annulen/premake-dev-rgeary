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
function Seq:new(t)
	local s = {}
	if Seq.isSeq(t) then
		-- Clone
		s.iterate = t.iterate
	elseif type(t) == 'string' then
		return Seq:new({t})
	else
		-- Create a new iterator object which will iterate over t
		s.iterate = function()
			-- Set up iterator state
			local i = 0
			-- Return a moveNext function, which returns (idx,value), and idx=nil to end
			return function()
				i = i + 1
				if i <= #t then return i,t[i]
				else return nil
				end
			end
		end
	end
	s.uid = nextUID
	nextUID = nextUID + 1
	return setmetatable( s, SeqMT )
end

function Seq.toSeq(s)
	if Seq.isSeq(s) then
		return s
	else
		return Seq:new(s)
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

-- Remove any element in the string/sequence/set vs
function Seq:except(vs)
	vs = toSet(vs)
	return self:where(function(v) return not vs[v];	end)
end

-- concatenate sequence
function Seq:concat(seq2)
	seq2 = Seq.toSeq(seq2)
	
	local s = Seq:new(self)
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

function testSeq()
	bigT = { 'one', 'two', 'three', 'four', 'five', 'six', 'seven' }
	
	local bigTseq = Seq:new(bigT)
	local no2 = bigTseq:where(function(v) return v ~= 'two'; end)
	local no23 = no2:where(function(v) return v ~= 'three'; end)
	local no23_2 = no23:select(function(v) return v .. string.upper(v); end)

	print('bigTseq ' .. bigTseq:tostring()) 
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
