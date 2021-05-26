
local abc = require "luajit.abc"

local it = abc.Model()

it.quacks = it.quacks
it.flies = it.flies
it.swims = it.swims
it.croaks = it.croaks

for i = 1, 1e6 do
    it.duck[i] = it.quacks * (it.flies + it.swims)
end

local tick = abc.Build(it)

local start = os.clock()

tick()

print("compilation time: ", start)
print("calculation time: ", os.clock()-start)