-- require("lldebugger").start()

package.path = package.path .. ';../?.lua'

local abc = require "luajit.abc"
local rectangle = love.graphics.rectangle
local setColor = love.graphics.setColor

local brain, tick, state

local SIZE = 200

local p = {
        {-1, -1},
        {-1,  0},
        {-1,  1},
        { 0, -1},
        { 0,  1},
        { 1, -1},
        { 1,  0},
        { 1,  1},
    }

function love.load()
    brain = abc.Model()

    local b = brain

    -- часы
    for i = 0, 9 do
        b.t[i] = b.t[(i-1) % 10]
    end

    local function Or(t)
        assert(#t > 0)
        local r = t[1]
        for i = 2, 8 do
            r = r + t[i]
        end
        return r
    end

    for x = 0, SIZE-1 do
        for y = 0, SIZE-1 do
            local f = {}
            for i = 1, 8 do
                local dx = p[i][1]
                local dy = p[i][2]
                f[i] = b[(x+dx)%SIZE][(y+dy)%SIZE] * b.t[i]
            end
            local cur = b[x][y]
            cur.hit = Or(f)
            
            cur.c[1] = -b.t[0] * (cur.c[1] + cur.hit)
            cur.c[2] = -b.t[0] * (cur.c[2] + cur.c[1] * cur.hit)
            cur.c[3] = -b.t[0] * (cur.c[3] + cur.c[2] * cur.hit)
            cur.c[4] = -b.t[0] * (cur.c[4] + cur.c[3] * cur.hit)
            
            b[x][y] = -b.t[0] * b[x][y]
                      + b.t[0] * -cur.c[4] * (cur * (cur.c[2] + cur.c[3]) + -cur * cur.c[3])
        end
    end

    tick, state = abc.Build(b)
    state[b.t[1]()] = 1
    for x = 0, SIZE-1 do
        for y = 0, SIZE-1 do
            state[b[x][y]()] = math.random(0, 1)
        end
    end

end

function love.update(dt)
    for i = 1, 10 do
        state = tick()
    end
end

local size = 3

function love.draw()
    setColor(1, 1, 1)
    for x = 0, SIZE-1 do
        for y = 0, SIZE-1 do
            if state[brain[x][y]()] > 0 then
                rectangle("fill", x*size, y*size, size, size)
            end
        end
    end
end