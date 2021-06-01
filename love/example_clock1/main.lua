-- require("lldebugger").start()

package.path = package.path .. ';../?.lua;../../?.lua'

local abc = require "luajit.abc"
local rectangle = love.graphics.rectangle
local setColor = love.graphics.setColor

local brain, tick, state

function love.load()
    brain = abc.Model()

    local b = brain

    b.left = b.left * -b.right
    b.right = b.right * -b.left

    for i = 0, 9 do
        b.x1[i] = b.x1[(i-1) % 10] * b.right
                - b.x1[(i+1) % 10] * b.left
    end

    for i = 0, 9 do
        b.x2[i] = b.x2[i] * -( b.x1[9] * b.right
                             + b.x1[0] * b.left )
                - b.x2[(i-1) % 10] * b.x1[9] * b.right
                - b.x2[(i+1) % 10] * b.x1[0] * b.left
    end

    tick, state = abc.Build(b)
    state[b.left()] = 1
    state[b.right()] = 0
    state[b.x1[4]()] = 1
    state[b.x2[2]()] = 1
end

function love.update(dt)
    state = tick()
end

local size = 50

function love.draw()
    setColor(1, 1, 1)
    for i = 0, 9 do
        if state[brain.x1[i]()] > 0 then
            rectangle("fill", 150+i*size, 200, size, size)
        end
    end
    setColor(1, 1, 1)
    for i = 0, 9 do
        if state[brain.x2[i]()] > 0 then
            rectangle("fill", 150+i*size, 200+size, size, size)
        end
    end
end