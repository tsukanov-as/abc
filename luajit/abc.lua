local ffi = require "ffi"
local band, bor, bxor, bnot  = bit.band, bit.bor, bit.bxor, bit.bnot
local lshift, rshift = bit.lshift, bit.rshift

local LOAD = 1
local AND = 2
local OR = 3
local XOR = 4
local NOT = 5
local STORE = 6

local Node

local function emit_u24(x, b)
    b[#b+1] = x % 256
    b[#b+1] = rshift(x, 8) % 256
    b[#b+1] = rshift(x, 16) % 256
end

local function emit_operand(t, b)
    if getmetatable(t) == Node then
        if not t._value then
            error(("node '%s' is not defined"):format(t._name))
        end
        b[#b+1] = LOAD
        emit_u24(t._index, b)
    else
        t:emit(b)
    end
end

local function emit_node(node, b)
    if next(node._nodes) then
        for _, n in pairs(node._nodes) do
            emit_node(n, b)
        end
    else
        if not node._value then
            error(("node '%s' is not defined"):format(node._name))
        end
    end
    if node._value then
        emit_operand(node._value, b)
        b[#b+1] = STORE
        emit_u24(node._index, b)
    end
end

Node = setmetatable({
    __index = function(self, key)
        local node = self._nodes[key]
        if node == nil then
            node = Node(self._name.."."..key, self._indexer)
            self._nodes[key] = node
        end
        return node
    end;
    __newindex = function(self, key, val)
        local node = self[key]
        if node._value then
            error(("node '%s' is already defined"):format(node._name))
        end
        local val_type = type(val)
        if val_type == "table" and getmetatable(val) == nil then
            for k, v in pairs(val) do
                node[k] = v
            end
            return
        end
        if val_type ~= "table" then
            error(("it is forbidden to assign a %s"):format(val_type))
        end
        node._value = val
        node._index = self._indexer()
    end;
    __call = function(self, new)
        if not self._value then
            if not new then
                error(("node '%s' is not defined"):format(self._name))
            end
            self._value = self
            self._index = self._indexer()
        end
        return self._index
    end;
}, {
    __call = function(self, name, indexer)
        if not name then
            error("name required")
        end
        if not indexer then
            error("indexer required")
        end
        return setmetatable({
            _name = name;
            _value = false;
            _index = 0;
            _indexer = indexer;
            _nodes = {};
        }, self)
    end;
})

local Or = {
    __index = {
        emit = function(self, b)
            emit_operand(self[1], b)
            emit_operand(self[2], b)
            b[#b+1] = OR
        end;
    };
}
local Xor = {
    __index = {
        emit = function(self, b)
            emit_operand(self[1], b)
            emit_operand(self[2], b)
            b[#b+1] = XOR
        end;
    };
}
local And = {
    __index = {
        emit = function(self, b)
            emit_operand(self[1], b)
            emit_operand(self[2], b)
            b[#b+1] = AND
        end;
    };
}
local Not = {
    __index = {
        emit = function(self, b)
            emit_operand(self[1], b)
            b[#b+1] = NOT
        end;
    };
}

local function check_operand(operand)
    local mt = getmetatable(operand)
    if not (mt == Node or mt == Or or mt == And or mt == Not or mt == Xor) then
        error("unknown type")
    end
end

local __bor = function(self, other)
    check_operand(other)
    return setmetatable({self, other}, Or)
end

local __bxor = function(self, other)
    check_operand(other)
    return setmetatable({self, other}, Xor)
end

local __band = function(self, other)
    check_operand(other)
    return setmetatable({self, other}, And)
end

local __bnot = function(self)
    return setmetatable({self}, Not)
end

Node.__add = __bor
Node.__sub = __bxor
Node.__mul = __band
Node.__unm = __bnot

Or.__add = __bor
Or.__sub = __bxor
Or.__mul = __band
Or.__unm = __bnot

Xor.__add = __bor
Xor.__sub = __bxor
Xor.__mul = __band
Xor.__unm = __bnot

And.__add = __bor
And.__sub = __bxor
And.__mul = __band
And.__unm = __bnot

Not.__add = __bor
Not.__sub = __bxor
Not.__mul = __band
Not.__unm = __bnot

local function Model(indexer)
    local index = -1
    indexer = indexer or function()
        index = index + 1
        return index
    end
    return Node("", indexer)
end

local function Build(model, stack_size)
    if model._index == 0 then
        model._index = model._indexer()
    end
    local len = model._index

    local b = {}
    emit_node(model, b)

    local prg = ffi.new("uint8_t[?]", #b, b)
    local stack = ffi.new("uint32_t[?]", stack_size or 1000)
    local state = ffi.new("uint32_t[?]", len)
    local _state = ffi.new("uint32_t[?]", len)

    local function tick()
        local s, _s = state, _state
        local ip = -1
        local sp = -1
        local b = prg[0]
        for i = 1, len do
            ::start::
            ip = ip + 1; b = prg[ip];
            if b == LOAD then
                sp = sp + 1
                ip = ip + 3
                local idx = lshift(prg[ip], 16) + lshift(prg[ip-1], 8) + prg[ip-2]
                stack[sp] = s[idx]
                goto start
            elseif b == AND then
                sp = sp - 1
                stack[sp] = band(stack[sp], stack[sp+1])
                goto start
            elseif b == OR then
                sp = sp - 1
                stack[sp] = bor(stack[sp], stack[sp+1])
                goto start
            elseif b == XOR then
                sp = sp - 1
                stack[sp] = bxor(stack[sp], stack[sp+1])
                goto start
            elseif b == NOT then
                stack[sp] = bnot(stack[sp])
                goto start
            elseif b == STORE then
                ip = ip + 3
                local idx = lshift(prg[ip], 16) + lshift(prg[ip-1], 8) + prg[ip-2]
                _s[idx] = stack[sp]
                sp = sp - 1
            end
        end
        state, _state = _s, s
        return state
    end

    return tick, state, len
end

return {
    Model = Model;
    Build = Build;
}