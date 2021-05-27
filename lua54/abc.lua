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

local function operand_tostring(t)
    if getmetatable(t) == Proxy then
        local node = t.__self
        assert(node.value, ("node '%s' is not defined"):format(node.name))
        return "x["..tostring(node.index).."]"
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
                t[#t+1] = "y["..tostring(self.index).."]="..operand_tostring(self.value).." -- "..self.name
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
        return "("..operand_tostring(self.lhs).."|"..operand_tostring(self.rhs)..")"
    end;
}
local Xor = {
    __tostring = function(self)
        return "("..operand_tostring(self.lhs).."~"..operand_tostring(self.rhs)..")"
    end;
}
local And = {
    __tostring = function(self)
        return "("..operand_tostring(self.lhs).."&"..operand_tostring(self.rhs)..")"
    end;
}
local Not = {
    __tostring = function(self)
        return "~("..operand_tostring(self.rhs)..")"
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

Proxy.__bor = bor
Proxy.__bxor = bxor
Proxy.__band = band
Proxy.__bnot = bnot

Or.__add = bor
Or.__sub = bxor
Or.__mul = band
Or.__unm = bnot

Or.__bor = bor
Or.__bxor = bxor
Or.__band = band
Or.__bnot = bnot

Xor.__add = bor
Xor.__sub = bxor
Xor.__mul = band
Xor.__unm = bnot

Xor.__bor = bor
Xor.__bxor = bxor
Xor.__band = band
Xor.__bnot = bnot

And.__add = bor
And.__sub = bxor
And.__mul = band
And.__unm = bnot

And.__bor = bor
And.__bxor = bxor
And.__band = band
And.__bnot = bnot

Not.__add = bor
Not.__sub = bxor
Not.__mul = band
Not.__unm = bnot

Not.__bor = bor
Not.__bxor = bxor
Not.__band = band
Not.__bnot = bnot

local function Model(indexer)
    local index = 0
    indexer = indexer or function()
        index = index + 1
        return index
    end
    return Node("", indexer)
end

local function Build(model)
    local self = model.__self
    if self.index == 0 then
        self.index = self.new_index() - 1
    end
    local len = self.index
    local src = ([[
local mt = {
    __tostring = function(self)
        local t = {}
        for i = 1, #self do
            t[#t+1] = tostring(self[i])
        end
        return "["..table.concat(t, ", ").."]"
    end;
}
local X = setmetatable({}, mt)
local Y = setmetatable({}, mt)
for i = 1, %d do X[i] = 0; Y[i] = 0 end
local function tick()
    local x, y = X, Y
%s
    X, Y = y, x
    return X
end
return tick, X
]]):format(len, tostring(model))
    local f, err = load(src)
    assert(f, err)
    local tick, state = f()
    return tick, state, src
end

return {
    Model = Model;
    Build = Build;
}