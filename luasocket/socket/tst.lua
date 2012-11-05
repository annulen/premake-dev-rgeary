print('hi')
require "remdebug.engine"
remdebug.engine.start()

function fibo(iter)
  if( iter == 0 ) then
  	return 0
  elseif( iter == 1 ) then
    return 1
  else
    return fibo(iter-1) + fibo(iter-2)
  end
end

for i=1,10 do
  print("fibo(" .. i .. ") = " .. fibo(i))
end
