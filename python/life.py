import pygame as p
import abc_dsl as abc
import random

size = 10
SIZE = 50

b = None
tick = None
state = None

pp = [
    (-1, -1),
    (-1, +0),
    (-1, +1),
    (+0, -1),
    (+0, +1),
    (+1, -1),
    (+1, +0),
    (+1, +1),
]

b = abc.Model()

for i in range(0, 10):
    b.t[i] = b.t[(i-1) % 10]

def Or(t):
    assert len(t) > 0
    r = t[0]
    for i in range(1, len(t)):
        r = r | t[i]
    return r

for x in range(SIZE):
    for y in range(SIZE):
        f = []
        for i in range(1, 9):
            dx = pp[i-1][0]
            dy = pp[i-1][1]
            f.append(b[(x+dx)%SIZE][(y+dy)%SIZE] & b.t[i])
        cur = b[x][y]
        cur.hit = Or(f)

        cur.c[1] = ~b.t[0] & (cur.c[1] | cur.hit)
        cur.c[2] = ~b.t[0] & (cur.c[2] | cur.c[1] & cur.hit)
        cur.c[3] = ~b.t[0] & (cur.c[3] | cur.c[2] & cur.hit)
        cur.c[4] = ~b.t[0] & (cur.c[4] | cur.c[3] & cur.hit)

        b[x][y] = ~b.t[0] & b[x][y] | b.t[0] & ~cur.c[4] & (cur & (cur.c[2] | cur.c[3]) | ~cur & cur.c[3])

tick, state = abc.Build(b)
state[b.t[1]()] = 1

for x in range(SIZE):
    for y in range(SIZE):
        state[b[x][y]()] = random.randint(0, 1)

BLACK = (0, 0, 0)
WHITE = (255, 255, 255)
root = p.display.set_mode((size*SIZE, size*SIZE))

while True:
    for i in p.event.get():
        if i.type == p.QUIT:
            quit()
    root.fill(WHITE)
    for x in range(SIZE):
        for y in range(SIZE):
            if state[b[x][y]()] > 0:
                p.draw.rect(root, BLACK, [x*size, y*size, size, size])
    p.display.update()
    state = tick()