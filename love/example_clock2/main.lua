-- require("lldebugger").start()

package.path = package.path .. ';../?.lua'

local abc = require "luajit.abc"
local rectangle = love.graphics.rectangle
local setColor = love.graphics.setColor

local brain, tick, state, signals

function love.load()
    brain = abc.Model()

    local b = brain

    b.U = b.U * -b.D * -b.L * -b.R
    b.D = b.D * -b.U * -b.L * -b.R
    b.L = b.L * -b.D * -b.U * -b.R
    b.R = b.R * -b.D * -b.U * -b.L

    local L1 = b.level1

    for i = 0, 9 do
        L1.x[i] = L1.x[i] * -(b.R + b.L)
                - L1.x[(i-1) % 10] * b.R
                - L1.x[(i+1) % 10] * b.L
        L1.y[i] = L1.y[i] * -(b.D + b.U)
                - L1.y[(i-1) % 10] * b.D
                - L1.y[(i+1) % 10] * b.U
    end

    for x = 0, 9 do
        for y = 0, 9 do
            L1[x][y] = L1[(x-1) % 10][y] * b.R
                     - L1[(x+1) % 10][y] * b.L
                     - L1[x][(y-1) % 10] * b.D
                     - L1[x][(y+1) % 10] * b.U
        end
    end

    local L2 = b.level2

    for x = 0, 9 do
        for y = 0, 9 do
            L2[x][y] = L2[x][y] * -( L1.x[9] * b.R
                                   + L1.x[0] * b.L
                                   + L1.y[0] * b.D
                                   + L1.y[9] * b.U )
                     - L2[(x-1) % 10][y] * L1.x[9] * b.R
                     - L2[(x+1) % 10][y] * L1.x[0] * b.L
                     - L2[x][(y-1) % 10] * L1.y[0] * b.D
                     - L2[x][(y+1) % 10] * L1.y[9] * b.U
        end
    end

    tick, state = abc.Build(b)

    state[b.L()] = 0
    state[b.R()] = 0
    state[b.U()] = 1
    state[b.D()] = 0
    state[b.level1[3][3]()] = 1
    state[b.level1.x[3]()] = 1
    state[b.level1.y[3]()] = 1
    state[b.level2[3][3]()] = 1

    signals = {
        ["left" ] = brain.L(),
        ["right"] = brain.R(),
        ["up"   ] = brain.U(),
        ["down" ] = brain.D(),
    }
end

function love.update(dt)
    state = tick()
end

local size = 20

function love.draw()

    setColor(1, 1, 1)

    rectangle("line", 100, 100, size*10, size*10)
    rectangle("line", 350, 100, size*10, size*10)

    for x = 0, 9 do
        for y = 0, 9 do
            if state[brain.level1[x][y]()] > 0 then
                rectangle("fill", 100+x*size, 100+y*size, size, size)
            end
        end
    end

    for x = 0, 9 do
        for y = 0, 9 do
            if state[brain.level2[x][y]()] > 0 then
                rectangle("fill", 350+x*size, 100+y*size, size, size)
            end
        end
    end

end

function love.keypressed(key, scancode, isrepeat)
    for _, i in pairs(signals) do
        state[i] = 0
    end
    local i = signals[key]
    if i then
        state[i] = 1
    end
end