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
			
			argumentOrder = { 'cfgflags', 'includedirs', 'protobufout', 'input' },
			
			prefixes = {
				includedirs = '-I',
			},
			
			decorateFn = {
				protobufout = function(arg)
					local rv = {}
					local cwd = repoRoot
					
					local function formatPath(p)
						if _OPTIONS.absolutepaths then
							return p
						else
							return path.getrelative(cwd, p)
						end
					end 
					
					if arg.protoPath then
						table.insert(rv, '--proto_path='..formatPath(arg.protoPath))
					else
						error("Must specify protobufout { protoPath=<path> }")
					end
					
					if arg.cppRoot then
						table.insert(rv, '--cpp_out='..formatPath(arg.cppRoot))
					end
					if arg.javaRoot then
						table.insert(rv, '--java_out='..formatPath(arg.javaRoot))
					end
					if arg.pythonRoot then
						table.insert(rv, '--python_out='..formatPath(arg.pythonRoot))
					end
					
					if (not arg.cppRoot) and (not arg.javaRoot) and (not arg.pythonRoot) then
						error("Must specify one of protobufout { cppRoot=PATH, javaRoot=PATH, pythonRoot=PATH }")
					end
					
					return table.concat(rv, ' ')
				end,
				
				-- no output variable
				output = function(arg) end,
			},
			
			getDescription = function(self, cfg)
				return "protobuf : "..cfg.project.name
			end,
			
			getOutputFiles = function(self, cfg, linkerInputs)
				linkerInputs = linkerInputs or {}
				local args = cfg.protobufout 
				local outputFiles = {}
				for _,file in ipairs(linkerInputs) do
					local fileNoExt = path.stripextension(file)
					if(args.cppRoot) then
						table.insert(outputFiles, fileNoExt..'.pb.cc')
						table.insert(outputFiles, fileNoExt..'.pb.h')
					end
					if args.javaRoot then
						-- Might be in a different directory, need to ask user to fill in these details 
						table.insert(outputFiles, fileNoExt..'.java')
					end
					if args.pythonRoot then
						table.insert(outputFiles, fileNoExt..'_pb2.py')
					end
				end
				return outputFiles
			end,
		}
	}
}