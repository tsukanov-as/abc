local ffi = require "ffi"
local rshift = bit.rshift

local LOAD = 1
local AND = 2
local OR = 3
local XOR = 4
local NOT = 5
local STORE = 6


-- node fields
local _NAME = 1
local _VALUE = 2
local _INDEX = 3
local _INDEXER = 4
local _NODES = 5

local emit_node

local function emit_proxy(proxy, b)
    emit_node(proxy.__self, b)
end;

local Proxy = setmetatable({
    __index = function(self, key)
        return self.__self:get(key)
    end;
    __newindex = function(self, key, val)
        return self.__self:set(key, val)
    end;
    __call = function(self, new)
        local node = self.__self
        if not node[_VALUE] then
            if not new then
                error(("node '%s' is not defined"):format(node[1]))
            end
            node[_VALUE] = self
            node[_INDEX] = node[_INDEXER]()
        end
        return node[_INDEX]
    end;
}, {
    __call = function(Proxy, t)
        return setmetatable({
            __self = t or {};
        }, Proxy)
    end;
})

local function emit_u24(x, b)
    b[#b+1] = x % 256
    b[#b+1] = rshift(x, 8) % 256
    b[#b+1] = rshift(x, 16) % 256
end

local function emit_operand(t, b)
    if getmetatable(t) == Proxy then
        local node = t.__self
        if not node[_VALUE] then
            error(("node '%s' is not defined"):format(node[1]))
        end
        b[#b+1] = LOAD
        emit_u24(node[_INDEX], b)
    else
        t:emit(b)
    end
end

function emit_node(node, b)
    if next(node[_NODES]) then
        for _, n in pairs(node[_NODES]) do
            emit_proxy(n, b)
        end
    else
        if not node[_VALUE] then
            error(("node '%s' is not defined"):format(node[1]))
        end
    end
    if node[_VALUE] then
        emit_operand(node[_VALUE], b)
        b[#b+1] = STORE
        emit_u24(node[_INDEX], b)
    end
end;

local Node

local nodes_index = function(self, key)
    local mt = getmetatable(self)
    local node = Node(mt.name.."."..key, mt.indexer)
    self[key] = node
    return node
end

Node = setmetatable({
    __index = {
        get = function(self, key)
            return self[_NODES][key]
        end;
        set = function(self, key, val)
            local proxy = self[_NODES][key]
            local node = proxy.__self
            if node[_VALUE] then
                error(("node '%s' is already defined"):format(node[1]))
            end
            local val_type = type(val)
            if val_type == "table" and getmetatable(val) == nil then
                for k, v in pairs(val) do
                    proxy[k] = v
                end
                return
            end
            if val_type ~= "table" then
                error(("it is forbidden to assign a %s"):format(val_type))
            end
            node[_VALUE] = val
            node[_INDEX] = self[_INDEXER]()
        end;
    };
}, {
    __call = function(Node, name, indexer)
        if not name then
            error("name required")
        end
        if not indexer then
            error("indexer required")
        end
        local t = setmetatable({
            name;    -- _NAME = 1
            false;   -- _VALUE = 2
            0;       -- _INDEX = 3
            indexer; -- _INDEXER = 4
            setmetatable({}, {
                name = name;
                indexer = indexer;
                __index = nodes_index;
            });      -- _NODES = 5
        }, Node)
        return Proxy(t)
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
    if not (mt == Proxy or mt == Or or mt == And or mt == Not or mt == Xor) then
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

Proxy.__add = __bor
Proxy.__sub = __bxor
Proxy.__mul = __band
Proxy.__unm = __bnot

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
    local self = model.__self
    if self[_INDEX] == 0 then
        self[_INDEX] = self[_INDEXER]()
    end
    local len = self[_INDEX]
    local b = {}
    emit_proxy(model, b)

    local prg = ffi.new("uint8_t[?]", #b, b)
    local stack = ffi.new("uint32_t[?]", stack_size or 1000)
    local state = ffi.new("uint32_t[?]", len)
    local _state = ffi.new("uint32_t[?]", len)

    local band, bor, bxor, bnot  = bit.band, bit.bor, bit.bxor, bit.bnot
    local lshift = bit.lshift

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