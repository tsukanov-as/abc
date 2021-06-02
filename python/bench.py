import abc_dsl as abc

import time

start = time.time()

it = abc.Model()

it.quacks = it.quacks
it.flies = it.flies
it.swims = it.swims
it.croaks = it.croaks

for i in range(1_000_000):
    it.duck[i] = it.quacks & (it.flies | it.swims)

tick, state = abc.Build(it)

print("compilation time: ", time.time() - start)

tick()

start = time.time()

tick()

print("calculation time: ", time.time()-start)