local ffi = require "ffi"

local LOAD = 1
local AND = 2
local OR = 3
local XOR = 4
local NOT = 5
local STORE = 6

local Proxy = setmetatable({
    __index = function(self, key)
        return self.__self:get(key)
    end;
    __newindex = function(self, key, val)
        return self.__self:set(key, val)
    end;
    __tostring = function(self)
        return self.__self:tostring()
    end;
    __call = function(self, new)
        local node = self.__self
        if not node.value then
            assert(new, ("node '%s' is not defined"):format(node.name))
            node.value = self
            node.index = node.new_index()
        end
        return node.index
    end;
}, {
    __call = function(Proxy, t)
        return setmetatable({__self = t or {}}, Proxy)
    end;
})

local function pack_u8(x)
    return ffi.string(ffi.new("uint8_t[1]", x), 1)
end

local function pack_u32(x)
    return ffi.string(ffi.new("uint32_t[1]", x), 4)
end

local function operand_tostring(t)
    if getmetatable(t) == Proxy then
        local node = t.__self
        assert(node.value, ("node '%s' is not defined"):format(node.name))
        if jit then
            return pack_u8(LOAD)..pack_u32(node.index)
        end
        return string.pack("BI4", LOAD, node.index)
    else
        return tostring(t)
    end
end

local Node = setmetatable({
    __index = {
        get = function(self, key)
            return self.nodes[key]
        end;
        set = function(self, key, val)
            local proxy = self.nodes[key]
            local node = proxy.__self
            assert(not node.value, ("node '%s' is already defined"):format(node.name))
            local val_type = type(val)
            if val_type == "table" and getmetatable(val) == nil then
                for k, v in pairs(val) do
                    proxy[k] = v
                end
                return
            end
            assert(val_type == "table", ("it is forbidden to assign a %s"):format(val_type))
            node.value = val
            node.index = self.new_index()
        end;
        tostring = function(self)
            local t = {}
            if next(self.nodes) then
                for _, v in pairs(self.nodes) do
                    t[#t+1] = tostring(v)
                end
            else
                assert(self.value, ("node '%s' is not defined"):format(self.name))
            end
            if self.value then
                t[#t+1] = operand_tostring(self.value)
                t[#t+1] = pack_u8(STORE)..pack_u32(self.index)
            end
            return table.concat(t)
        end;
    };
}, {
    __call = function(Node, name, indexer)
        assert(name, "name required")
        assert(indexer, "indexer required")
        local t = setmetatable({
            name = name;
            index = 0;
            value = false;
            nodes = setmetatable({}, {
                __index = function(self, key)
                    local node = Node(name.."."..key, indexer)
                    self[key] = node
                    return node
                end;
            });
            new_index = indexer;
        }, Node)
        return Proxy(t)
    end;
})

local Or = {
    __tostring = function(self)
        return operand_tostring(self.lhs)..operand_tostring(self.rhs)..pack_u8(OR)
    end;
}
local Xor = {
    __tostring = function(self)
        return operand_tostring(self.lhs)..operand_tostring(self.rhs)..pack_u8(XOR)
    end;
}
local And = {
    __tostring = function(self)
        return operand_tostring(self.lhs)..operand_tostring(self.rhs)..pack_u8(AND)
    end;
}
local Not = {
    __tostring = function(self)
        return operand_tostring(self.rhs)..pack_u8(NOT)
    end;
}

local function check_operand(operand)
    local mt = getmetatable(operand)
    assert(mt == Proxy or mt == Or or mt == And or mt == Not or mt == Xor, "unknown type")
end

local bor = function(self, other)
    check_operand(other)
    return setmetatable({op = "bor", lhs = self, rhs = other}, Or)
end

local bxor = function(self, other)
    check_operand(other)
    return setmetatable({op = "bxor", lhs = self, rhs = other}, Xor)
end

local band = function(self, other)
    check_operand(other)
    return setmetatable({op = "band", lhs = self, rhs = other}, And)
end

local bnot = function(self)
    return setmetatable({op = "bnot", rhs = self}, Not)
end

Proxy.__add = bor
Proxy.__sub = bxor
Proxy.__mul = band
Proxy.__unm = bnot

Or.__add = bor
Or.__sub = bxor
Or.__mul = band
Or.__unm = bnot

And.__add = bor
And.__sub = bxor
And.__mul = band
And.__unm = bnot

Not.__add = bor
Not.__sub = bxor
Not.__mul = band
Not.__unm = bnot

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
    local src = tostring(model)

    local prg = ffi.new("uint8_t[?]", #src, src)
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