local abc = require "abc"

local m, indexer = abc.Model()

m.left = m.left * -m.right
m.right = m.right * -m.left

for i = 0, 9 do
    m.x1[i] = m.x1[(i-1) % 10] * m.right
            - m.x1[(i+1) % 10] * m.left
end

for i = 0, 9 do
    m.x2[i] = m.x2[i] * -( m.x1[9] * m.right
                         + m.x1[0] * m.left )
            - m.x2[(i-1) % 10] * m.x1[9] * m.right
            - m.x2[(i+1) % 10] * m.x1[0] * m.left
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

local left = m.left()
local right = m.right()

local state = tick()

state[left] = 1
state[right] = 0
state[m.x1[4]()] = 1
state[m.x2[2]()] = 1

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

print(m)