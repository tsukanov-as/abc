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
}, {
    __call = function(Proxy, t)
        return setmetatable({__self = t or {}}, Proxy)
    end;
})

local function index_tostring(index)
    return ("%d * M + %d"):format(math.floor(index / 32767), index % 32767)
end

local function operand_tostring(t)
    if getmetatable(t) == Proxy then
        local node = t.__self
        assert(node.value, ("node '%s' is not defined"):format(node.name))
        return "m["..index_tostring(node.index).."]"
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
            node.index = self.new_index(node.name)
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
                t[#t+1] = "-- "..self.name..":"
                t[#t+1] = "    _m["..index_tostring(self.index).."] = "..operand_tostring(self.value)
            end
            return table.concat(t, "\n")
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
        return "bor("..operand_tostring(self.lhs)..", "..operand_tostring(self.rhs)..")"
    end;
}
local And = {
    __tostring = function(self)
        return "band("..operand_tostring(self.lhs)..", "..operand_tostring(self.rhs)..")"
    end;
}
local Not = {
    __tostring = function(self)
        return "bnot("..operand_tostring(self.rhs)..")"
    end;
}

local function check_operand(operand)
    local mt = getmetatable(operand)
    assert(mt == Proxy or mt == Or or mt == And or mt == Not, "unknown type")
end

local bor = function(self, other)
    check_operand(other)
    return setmetatable({op = "bor", lhs = self, rhs = other}, Or)
end

local band = function(self, other)
    check_operand(other)
    return setmetatable({op = "band", lhs = self, rhs = other}, And)
end

local bnot = function(self)
    return setmetatable({op = "bnot", rhs = self}, Not)
end

Proxy.__add = bor
Proxy.__mul = band
Proxy.__unm = bnot

Or.__add = bor
Or.__mul = band
Or.__unm = bnot

And.__add = bor
And.__mul = band
And.__unm = bnot

Not.__add = bor
Not.__mul = band
Not.__unm = bnot

local function Model()
    local dict = {
        len = 0;
        map = {}
    }
    local function indexer(name)
        local index = dict.len
        dict.map[name] = index
        dict.len = index + 1
        return index
    end
    local model = Node("", indexer)
    return model, dict
end

local function Compile(model, dict)
    local src = ([[
local ffi = require "ffi"
local bit = require("bit")
local bor, band, bnot = bit.bor, bit.band, bit.bnot
local Vector = ffi.typeof("int32_t[%d]")
local m = Vector()
local _m = Vector()
local function tick()
    local M = 32767
%s
    m, _m = _m, m
    return m
end
return tick
]]):format(dict.len, tostring(model))
    local f, err = load(src)
    assert(f, err)
    local tick = f()
    return tick, src
end

return {
    Model = Model;
    Compile = Compile;
}