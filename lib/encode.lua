--
--  Copyright (C) 2022 Masatoshi Fukunaga
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.
--
--- assign to local
local select = select
local type = type
local tostring = tostring
local pairs = pairs
local concat = table.concat
-- constants
local CRLF = '\r\n'

--- stringify
--- @param v string|number|boolean
--- @return string|nil
local function stringify(v)
    local t = type(v)
    if t == 'string' then
        return v
    elseif t ~= 'number' and t ~= 'boolean' then
        error('v must be string or number or boolean')
    end

    return tostring(v)
end

--- encode
--- @param cmd string
--- @return string qry
local function encode(cmd, ...)
    local len = 1
    local arr = {
        '',
        -- set command name
        '$' .. tostring(#cmd),
        cmd,
    }
    local idx = #arr + 1
    local args = {
        ...,
    }

    for i = 1, select('#', ...) do
        local v = args[i]
        if v == nil then
            -- nil argument is treated as an empty string
            arr[idx], arr[idx + 1] = '$0', ''
            idx = idx + 2
            len = len + 1
        elseif type(v) ~= 'table' then
            -- non table argument is converted to string
            v = stringify(v)
            arr[idx], arr[idx + 1] = '$' .. tostring(#v), v
            idx = idx + 2
            len = len + 1
        else
            for k, vv in pairs(v) do
                -- ignore non-string key or empty key
                if type(k) == 'string' and #k > 0 then
                    vv = stringify(vv)
                    arr[idx], arr[idx + 1] = '$' .. tostring(#k), k
                    arr[idx + 2], arr[idx + 3] = '$' .. tostring(#vv), vv
                    idx = idx + 4
                    len = len + 2
                end
            end
        end
    end
    -- set array length
    arr[1] = '*' .. tostring(len)

    return concat(arr, CRLF) .. CRLF
end

return encode

