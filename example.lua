
local abc = require "abc"

local it = abc.Model()

local quacks = it.quacks()
local flies = it.flies()
local swims = it.swims()
local croaks = it.croaks()

local function foo(x, y, z)
    return x * (y + z)
end

-- luajit, lua < 5.3
it.duck = foo(it.quacks, it.flies, it.swims)
it.frog = it.croaks * it.swims * -it.flies
-- lua >= 5.3
-- it.duck = it.quacks & (it.flies | it.swims)
-- it.frog = it.croaks & it.swims & ~it.flies

local tick, src = abc.Compile(it)

local function print_state(state)
    local t = {}
    for i = 1, #state do
        t[#t+1] = tostring(state[i])
    end
    print("["..table.concat(t, ", ").."]")
end

local state = tick()

print_state(state)

state[quacks] = 0
state[flies] = 0
state[swims] = 1
state[croaks] = 1

print_state(state)

state = tick()
print_state(state)

print("is it a duck?", state[it.duck()])
print("is it a frog?", state[it.frog()])