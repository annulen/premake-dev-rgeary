--
-- Spelling corrector, based on http://norvig.com/spell-correct.html
--

	premake.spelling = {}
	local spelling = premake.spelling
	
	spelling.alphabet = { "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "-", "+", "_", "/", }
	
	function spelling.new(dictionary)
		local s = inheritFrom(spelling)
		if not dictionary then
			error("Need to supply a dictionary")
		end
		s.dictionary = {}
		s.dictionaryMaxLen = 0
		for _,w in ipairs(dictionary) do
			local v = spelling:getValidLetters(w)
			s.dictionary[v] = w
			s.dictionaryMaxLen = math.max(s.dictionaryMaxLen, #v) 
		end
		
		return s
	end
	
	function spelling:edits1(word)
		local splits = {}
		for i = 0,#word do
			table.insert(splits, { word:sub(1,i), word:sub(i+1) }) 
		end
		
		local set = {}
		
		-- deletes
		for _,p in ipairs(splits) do
			if #p[2] > 0 then
				set[ p[1] .. p[2]:sub(2) ] = 1
			end
		end
		
		-- transposes
		for _,p in ipairs(splits) do
			if #p[2] > 1 then
				set[ p[1] .. p[2]:sub(2,2) .. p[2]:sub(1,1) .. p[2]:sub(3) ] = 1 
			end
		end
		
		-- replaces
		for _,p in ipairs(splits) do
			if #p[2] > 0 then
				for _,c in ipairs(self.alphabet) do
					set[ p[1] .. c .. p[2]:sub(2) ] = 1
				end
			end
		end
		
		-- inserts
		for _,p in ipairs(splits) do
			for _,c in ipairs(self.alphabet) do
				set[ p[1] .. c .. p[2] ] = 1
			end
		end
		
		return set
	end
	
	function spelling:edits2(word)
		local e1 = self:edits1(word)
		local set = {}
		for w,_ in pairs(e1) do
			if #w < self.dictionaryMaxLen then 
				local e2 = self:edits1(w)
				for w2,_ in pairs(e2) do
					if self.dictionary[w2] then
						set[w2] = 1
					end
				end
			end
		end
		return set
	end
	
	function spelling:getValidLetters(text)
		return text:lower()
	end
	
	function spelling:known(words)
		local rv = {}
		if not words then return rv end
		if #words == 0 then
		for w,_ in pairs(words) do
			if self.dictionary[w] then
				table.insert( rv, self.dictionary[w] )
			end
		end
		else
			for _,w in ipairs(words) do
				if self.dictionary[w] then
					table.insert( rv, self.dictionary[w] )
				end
			end
		end
		return rv
	end
	
	function spelling:getSuggestions(word)
		local tmr = timer.start('spelling:getSuggestions')
		word = self:getValidLetters(word)
		local candidates = self:known({ word })
		if table.isempty(candidates) then
			candidates = self:known(self:edits1(word))
			if table.isempty(candidates) then
				candidates = self:known(self:edits2(word))
			end
		end
		
		timer.stop(tmr)
		timer.print(tmr)
		
		local suggestionStr = ''
		if #candidates > 0 then
			suggestionStr = Seq:new(candidates):take(20):mkstring(', ')
			if #candidates > 20 then 
				suggestionStr = suggestionStr .. '...'
			end 
			suggestionStr = ' Did you mean ' .. suggestionStr .. '?'
		end
		
		-- no sorting as we don't have any word probability data
		return candidates, suggestionStr			 
	end
	
	