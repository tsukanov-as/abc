local abc = require "lua.abc"

local m = abc.Model()

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

local tick, state, src = abc.Build(m)

local left = m.left()
local right = m.right()

state[left] = 1
state[right] = 0
state[m.x1[4]()] = 1
state[m.x2[2]()] = 1

print(state)

for _ = 1, 10 do
    state = tick()
    print(state)
end

state[left] = 0
state[right] = 1

for _ = 1, 10 do
    state = tick()
    print(state)
end

print(m)