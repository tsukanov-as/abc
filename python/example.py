import abc_dsl as abc

m = abc.Model()

quacks = m.quacks(True)
flies = m.flies(True)
swims = m.swims(True)
croaks = m.croaks(True)

m.duck = m.quacks & (m.flies | m.swims)
m.frog = m.croaks & m.swims & ~m.flies

tick, state = abc.Build(m)

state = tick()

print(state)

state[quacks] = 0
state[flies] = 0
state[swims] = 1
state[croaks] = 1

print(state)

state = tick()
print(state)

print("is it a duck?", state[m.duck()])
print("is it a frog?", state[m.frog()])