local BCF={}
function BCF.process(c,o)
if not o or not o.enabled then return c end
return c
end
return BCF