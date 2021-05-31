local abc = require "lua.abc"

local it = abc.Model()

it.quacks = it.quacks
it.flies = it.flies
it.swims = it.swims
it.croaks = it.croaks

for i = 1, 1e5 do
    it.duck[i] = it.quacks * (it.flies + it.swims)
end

local tick = abc.Build(it)

local start = os.clock()

local state = tick()

print("compilation time: ", start)
print("calculation time: ", os.clock()-start)