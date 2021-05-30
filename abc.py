
LOAD = 1
AND = 2
OR = 3
XOR = 4
NOT = 5
STORE = 6

class Base:
    def __invert__(self):
        return Not(self)

    def __and__(self, other):
        if not isinstance(other, Base):
            raise Exception(f"unknown type: {other}")
        return And(self, other)

    def __or__(self, other):
        if not isinstance(other, Base):
            raise Exception(f"unknown type: {other}")
        return Or(self, other)

    def __xor__(self, other):
        if not isinstance(other, Base):
            raise Exception(f"unknown type: {other}")
        return Xor(self, other)

def emit_operand(operand, code):
    if isinstance(operand, Model):
        code.append(LOAD)
        code.extend(operand().to_bytes(4, byteorder='little'))
    else:
        operand.emit(code)

class Not(Base):
    def __init__(self, rhs):
        self.rhs = rhs

    def emit(self, code):
        emit_operand(self.rhs, code)
        code.append(NOT)

class And(Base):
    def __init__(self, lhs, rhs):
        self.lhs = lhs
        self.rhs = rhs

    def emit(self, code):
        emit_operand(self.lhs, code)
        emit_operand(self.rhs, code)
        code.append(AND)

class Or(Base):
    def __init__(self, lhs, rhs):
        self.lhs = lhs
        self.rhs = rhs

    def emit(self, code):
        emit_operand(self.lhs, code)
        emit_operand(self.rhs, code)
        code.append(OR)

class Xor(Base):
    def __init__(self, lhs, rhs):
        self.lhs = lhs
        self.rhs = rhs

    def emit(self, code):
        emit_operand(self.lhs, code)
        emit_operand(self.rhs, code)
        code.append(XOR)

class Model(Base):
    def __init__(self, name="", indexer=None):
        self.__dict__["_Model__name"] = name
        self.__dict__["_Model__value"] = None
        self.__dict__["_Model__index"] = None
        self.__dict__["_Model__nodes"] = {}
        if indexer is None:
            index = -1
            def indexer(current=False):
                nonlocal index
                if current:
                    return index + 1
                index += 1
                return index
        self.__dict__["_Model__indexer"] = indexer

    def __call__(self, new=False):
        if self.__index is None:
            if not new:
                raise Exception(f"node '{self.__name}' is not defined")
            self.__dict__["_Model__value"] = self
            self.__dict__["_Model__index"] = self.__indexer()
        return self.__index

    def __getitem__(self, key):
        node = self.__nodes.get(key)
        if node is None:
            node = Model(f"{self.__name}.{key}", self.__indexer)
            self.__nodes[key] = node
        return node

    def __getattr__(self, name):
        return self.__getitem__(name)

    def __setitem__(self, key, value):
        node = self.__getitem__(key)
        if node._Model__value is not None:
            raise Exception(f"node '{node.__name}' is already defined")
        if isinstance(value, dict):
            for k, v in value.items():
                node[k] = v
            return
        if not isinstance(value, Base):
            raise Exception(f"it is forbidden to assign a {value}")
        node.__dict__["_Model__value"] = value
        node.__dict__["_Model__index"] = self.__indexer()

    def __setattr__(self, name, value):
        self.__setitem__(name, value)

    def __emit(self, code):
        nodes = self.__nodes
        if len(nodes) > 0:
            for key in nodes:
                nodes[key].__emit(code)
            if self.__value is None:
                return
        else:
            if self.__value is None:
                raise Exception(f"node '{self.__name}' is not defined")
        emit_operand(self.__value, code)
        code.append(STORE)
        code.extend(self().to_bytes(4, byteorder='little'))

def Compile(model):
    size = model._Model__indexer(True)
    code = bytearray()
    code.extend(size.to_bytes(4, byteorder='little'))
    model._Model__emit(code)
    return code

def Build(model):
    code = Compile(model)
    size = (code[3] << 24) + (code[2] << 16) + (code[1] << 8) + code[0]
    import numpy as np
    from numba import jit, uint64
    prg = np.array(code, np.uint8)
    stack = np.zeros(1000, np.uint64)
    state = np.zeros(size, np.uint64)
    _state = np.zeros(size, np.uint64)
    @jit((uint64[:], uint64[:], uint64[:]), nopython=True, nogil=True)
    def tickjit(state, _state, stack):
        i = 0
        ip = 0
        sp = -1
        while i < size:
            ip += 1
            b = prg[ip]
            if b == LOAD:
                sp += 1
                ip += 4
                idx = (prg[ip] << 24) + (prg[ip-1] << 16) + (prg[ip-2] << 8) + prg[ip-3]
                stack[sp] = state[idx]
            elif b == AND:
                sp -= 1
                stack[sp] = stack[sp] & stack[sp+1]
            elif b == OR:
                sp -= 1
                stack[sp] = stack[sp] | stack[sp+1]
            elif b == XOR:
                sp -= 1
                stack[sp] = stack[sp] ^ stack[sp+1]
            elif b == NOT:
                stack[sp] = ~stack[sp]
            elif b == STORE:
                ip += 4
                idx = (prg[ip] << 24) + (prg[ip-1] << 16) + (prg[ip-2] << 8) + prg[ip-3]
                _state[idx] = stack[sp]
                sp -= 1
                i += 1

    def tick():
        nonlocal state, _state, stack
        tickjit(state, _state, stack)
        state, _state = _state, state
        return state
    return tick

m = Model()

quacks = m.quacks(True)
flies = m.flies(True)
swims = m.swims(True)
croaks = m.croaks(True)

m.duck = m.quacks & (m.flies | m.swims)
m.frog = m.croaks & m.swims & ~m.flies

tick = Build(m)

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

########

# import time

# start = time.time()

# it = Model()

# it.quacks = it.quacks
# it.flies = it.flies
# it.swims = it.swims
# it.croaks = it.croaks

# for i in range(1_000_000):
#     it.duck[i] = it.quacks & (it.flies | it.swims)

########

# code = Compile(it)

# with open("code.data", "wb") as f:
#     f.write(code)

########

# tick = Build(it)

# print("compilation time: ", time.time() - start)

# tick()

# start = time.time()

# tick()

# print("calculation time: ", time.time()-start)