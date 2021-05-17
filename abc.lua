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
    __call = function(self)
        return self.__self.index
    end;
}, {
    __call = function(Proxy, t)
        return setmetatable({__self = t or {}}, Proxy)
    end;
})

local function index_tostring(index)
    if not jit or index < 32767 then
        return tostring(index)
    end
    return ("%d*M+%d"):format(math.floor(index / 32767), index % 32767)
end

local function operand_tostring(t)
    if getmetatable(t) == Proxy then
        local node = t.__self
        assert(node.value, ("node '%s' is not defined"):format(node.name))
        return "x["..index_tostring(node.index).."]"
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
                t[#t+1] = "y["..index_tostring(self.index).."]="..operand_tostring(self.value).." -- "..self.name
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
        if _VERSION < "Lua 5.3" then
            return "O("..operand_tostring(self.lhs)..","..operand_tostring(self.rhs)..")"
        else
            return "("..operand_tostring(self.lhs).."|"..operand_tostring(self.rhs)..")"
        end
    end;
}
local And = {
    __tostring = function(self)
        if _VERSION < "Lua 5.3" then
            return "A("..operand_tostring(self.lhs)..","..operand_tostring(self.rhs)..")"
        else
            return "("..operand_tostring(self.lhs).."&"..operand_tostring(self.rhs)..")"
        end
    end;
}
local Not = {
    __tostring = function(self)
        if _VERSION < "Lua 5.3" then
            return "N("..operand_tostring(self.rhs)..")"
        else
            return "~("..operand_tostring(self.rhs)..")"
        end
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

Proxy.__bor = bor
Proxy.__band = band
Proxy.__bnot = bnot

Or.__add = bor
Or.__mul = band
Or.__unm = bnot

Or.__bor = bor
Or.__band = band
Or.__bnot = bnot

And.__add = bor
And.__mul = band
And.__unm = bnot

And.__bor = bor
And.__band = band
And.__bnot = bnot

Not.__add = bor
Not.__mul = band
Not.__unm = bnot

Not.__bor = bor
Not.__band = band
Not.__bnot = bnot

local function Model(indexer)
    local index = 0
    indexer = indexer or function()
        index = index + 1
        return index
    end
    local model = Node("", indexer)
    return model, indexer
end

local function Compile(model, len)
    local src = ([[
local bit = bit or bit32
local O, A, N
if _VERSION < "Lua 5.3" then
O, A, N = bit.bor, bit.band, bit.bnot
end
local x = {}
local y = {}
for i = 1, %d do x[i] = 0; y[i] = 0 end
local function tick()
    local M = 32767
%s
    x, y = y, x
    return x
end
return tick
]]):format(len, tostring(model))
    local f, err = load(src)
    assert(f, err)
    local tick = f()
    return tick, src
end

return {
    Model = Model;
    Compile = Compile;
}