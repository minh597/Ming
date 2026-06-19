local SE={}
function SE.process(c,o)
if not o or not o.enabled then return c end
math.randomseed(os.time())
local k=math.random(1,255)
local dn="_e"..math.random(1000,9999)
local dec="local "..dn.."=function(s)local r={}for i=1,#s do r[i]=string.char(string.byte(s,i)~"..k..")end return table.concat(r)end"
local n=0
local function enc(s)
local e={}
for i=1,#s do e[i]=string.char(string.byte(s,i)~k)end
return table.concat(e)
end
c=c:gsub('"([^"]*)"',function(s)
if #s>=3 then n=n+1;local h={}for i=1,#enc(s)do h[i]=string.format("\\x%02x",string.byte(enc(s),i))end;return dn..'("'..table.concat(h)..'")'end
return'"'..s..'"'
end)
if n>0 then c=dec.."\n"..c end
return c
end
return SE