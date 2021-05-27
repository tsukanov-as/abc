
local abc = require "lua54.abc"

local it = abc.Model()

local quacks = it.quacks(true)
local flies = it.flies(true)
local swims = it.swims(true)
local croaks = it.croaks(true)

local function foo(x, y, z)
    return x & (y | z)
end

it.duck = foo(it.quacks, it.flies, it.swims)
it.frog = it.croaks & it.swims & ~it.flies

local tick, state, src = abc.Build(it)

print(state)

state[quacks] = 0
state[flies] = 0
state[swims] = 1
state[croaks] = 1

print(state)

state = tick()
print(state)

print("is it a duck?", state[it.duck()])
print("is it a frog?", state[it.frog()])