local abc = require "abc"

local m, indexer = abc.Model()

local left = m.left()
local right = m.right()

for i = 0, 9 do
    m[i] = m[(i-1) % 10] * m.right + m[(i+1) % 10] * m.left
end

local len = indexer() - 1
local tick, src = abc.Compile(m, len)

local function print_state(state)
    local t = {}
    for i = 1, len do
        t[#t+1] = tostring(state[i])
    end
    print("["..table.concat(t, ", ").."]")
end

local state = tick()

state[left] = 1
state[right] = 0
state[m[4]()] = 1

print_state(state)

for _ = 1, 10 do
    state = tick()
    print_state(state)
end

state[left] = 0
state[right] = 1

for _ = 1, 10 do
    state = tick()
    print_state(state)
end
