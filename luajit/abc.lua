local ffi = require "ffi"
local rshift = bit.rshift

local LOAD = 1
local AND = 2
local OR = 3
local XOR = 4
local NOT = 5
local STORE = 6

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
        if not node.value then
            if not new then
                error(("node '%s' is not defined"):format(node.name))
            end
            node.value = self
            node.index = node.new_index()
        end
        return node.index
    end;
}, {
    __call = function(Proxy, t)
        return setmetatable({
            __self = t or {};
        }, Proxy)
    end;
})

local function emit_u32(x, b)
    b[#b+1] = x % 255
    b[#b+1] = rshift(x, 8) % 255
    b[#b+1] = rshift(x, 16) % 255
    b[#b+1] = rshift(x, 24) % 255
end

local function emit_operand(t, b)
    if getmetatable(t) == Proxy then
        local node = t.__self
        if not node.value then
            error(("node '%s' is not defined"):format(node.name))
        end
        b[#b+1] = LOAD
        emit_u32(node.index, b)
    else
        t:emit(b)
    end
end

function emit_node(self, b)
    if next(self.nodes) then
        for _, n in pairs(self.nodes) do
            emit_proxy(n, b)
        end
    else
        if not self.value then
            error(("node '%s' is not defined"):format(self.name))
        end
    end
    if self.value then
        emit_operand(self.value, b)
        b[#b+1] = STORE
        emit_u32(self.index, b)
    end
end;

local Node

local nodes_index = function(self, key)
    local mt = getmetatable(self)
    local node = Node(mt.name.."."..key, mt.new_index)
    self[key] = node
    return node
end

Node = setmetatable({
    __index = {
        get = function(self, key)
            return self.nodes[key]
        end;
        set = function(self, key, val)
            local proxy = self.nodes[key]
            local node = proxy.__self
            if node.value then
                error(("node '%s' is already defined"):format(node.name))
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
            node.value = val
            node.index = self.new_index()
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
            name = name;
            index = 0;
            value = false;
            nodes = setmetatable({}, {
                name = name;
                new_index = indexer;
                __index = nodes_index;
            });
            new_index = indexer;
        }, Node)
        return Proxy(t)
    end;
})

local Or = {
    __index = {
        emit = function(self, b)
            emit_operand(self.lhs, b)
            emit_operand(self.rhs, b)
            b[#b+1] = OR
        end;
    };
}
local Xor = {
    __index = {
        emit = function(self, b)
            emit_operand(self.lhs, b)
            emit_operand(self.rhs, b)
            b[#b+1] = XOR
        end;
    };
}
local And = {
    __index = {
        emit = function(self, b)
            emit_operand(self.lhs, b)
            emit_operand(self.rhs, b)
            b[#b+1] = AND
        end;
    };
}
local Not = {
    __index = {
        emit = function(self, b)
            emit_operand(self.rhs, b)
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
    return setmetatable({op = "bor", lhs = self, rhs = other}, Or)
end

local __bxor = function(self, other)
    check_operand(other)
    return setmetatable({op = "bxor", lhs = self, rhs = other}, Xor)
end

local __band = function(self, other)
    check_operand(other)
    return setmetatable({op = "band", lhs = self, rhs = other}, And)
end

local __bnot = function(self)
    return setmetatable({op = "bnot", rhs = self}, Not)
end

Proxy.__add = __bor
Proxy.__sub = __bxor
Proxy.__mul = __band
Proxy.__unm = __bnot

Or.__add = __bor
Or.__sub = __bxor
Or.__mul = __band
Or.__unm = __bnot

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
    if self.index == 0 then
        self.index = self.new_index()
    end
    local len = self.index
    local b = {}
    emit_proxy(model, b)

    local prg = ffi.new("uint8_t[?]", #b, b)
    local stack = ffi.new("uint32_t[?]", stack_size or 1000)
    local state = ffi.new("uint32_t[?]", len)
    local _state = ffi.new("uint32_t[?]", len)

    local function tick()
        local band, bor, bxor, bnot  = bit.band, bit.bor, bit.bxor, bit.bnot
        local lshift = bit.lshift
        local s, _s = state, _state
        local ip = -1
        local sp = -1
        local b = prg[0]
        for i = 1, len do
            ::start::
            ip = ip + 1; b = prg[ip];
            if b == LOAD then
                sp = sp + 1
                ip = ip + 4
                local idx = lshift(prg[ip], 24) + lshift(prg[ip-1], 16) + lshift(prg[ip-2], 8) + prg[ip-3]
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
                ip = ip + 4
                local idx = lshift(prg[ip], 24) + lshift(prg[ip-1], 16) + lshift(prg[ip-2], 8) + prg[ip-3]
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