local OP={}
function OP.process(c,o)
if not o or not o.enabled then return c end
return c
end
return OP