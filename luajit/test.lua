
local abc = require "luajit.abc"

local it = abc.Model()

local quacks = it.quacks(true)
local flies = it.flies(true)
local swims = it.swims(true)
local croaks = it.croaks(true)

local function foo(x, y, z)
    return x * (y + z)
end

it.duck = foo(it.quacks, it.flies, it.swims)
it.frog = it.croaks * it.swims * -it.flies

local tick, state, len = abc.Build(it)

local function print_state(state, len)
    local t = {}
    for i = 0, len-1 do
        t[#t+1] = tostring(state[i])
    end
    print("["..table.concat(t, ", ").."]")
end

print_state(state, len)

state[quacks] = 0
state[flies] = 0
state[swims] = 1
state[croaks] = 1

print_state(state, len)

state = tick()

print_state(state, len)

print(it.duck(), it.frog())
print("is it a duck?", state[it.duck()])
print("is it a frog?", state[it.frog()])