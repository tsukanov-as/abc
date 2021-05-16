local abc = require "abc"

local it, dict = abc.Model()

it.quacks = it.quacks
it.flies = it.flies
it.swims = it.swims
it.croaks = it.croaks

for i = 1, 1e6 do
    it.duck[i] = it.quacks * (it.flies + it.swims)
end

local tick, src = abc.Compile(it, dict)

local start = os.clock()

local state = tick()

print("compilation time: ", start)
print("calculation time: ", os.clock()-start)