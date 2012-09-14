--
-- Protocol Buffers
--

newtoolset {
	toolsetName = 'protobuf',
	tools = {
		newtool {
			toolName = 'protoc',
			binaryName = 'protoc',
			language = 'proto',
			isLinker = true,				-- Pass in all the inputs to one command
			extensionsForLinking = { '.proto' },
			
			argumentOrder = { 'cfgflags' },
			
			decorateFn = {
				protobufout = function(arg)
					local rv = {}
					if arg.cpp then
						table.insert(rv, '--cpp_out='..arg.cpp)
					end
					return table.concat(rv, ' ')
				end
			},
		}
	}
}