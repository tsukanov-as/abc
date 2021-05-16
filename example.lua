
local abc = require "abc"

local it, dict = abc.Model()

it.quacks = it.quacks
it.flies = it.flies
it.swims = it.swims
it.croaks = it.croaks

-- luajit, lua >= 5.3
it.duck = it.quacks * (it.flies + it.swims)
it.frog = it.croaks * it.swims * -it.flies
-- lua >= 5.3
-- it.duck = it.quacks & (it.flies | it.swims)
-- it.frog = it.croaks & it.swims & ~it.flies

local tick, src = abc.Compile(it, dict)

local function print_state(state)
    local t = {}
    for i = 0, dict.len-1 do
        t[#t+1] = tostring(state[i])
    end
    print("["..table.concat(t, ", ").."]")
end

local state = tick()

print_state(state)

state[dict.map[".swims"]] = 1
state[dict.map[".croaks"]] = 1

print_state(state)

state = tick()
print_state(state)

print("is it a duck?", state[dict.map[".duck"]])
print("is it a frog?", state[dict.map[".frog"]])