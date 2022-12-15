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
local find = string.find
local sub = string.sub
local resp_decode = require('resp').decode
--- constants
local EAGAIN = require('resp').EAGAIN
local EILSEQ = require('resp').EILSEQ
local STR = require('resp').STR
local ERR = require('resp').ERR
local INT = require('resp').INT
local BLK = require('resp').BLK
local ARR = require('resp').ARR
local T_NAMES = {
    [STR] = 'STR',
    [ERR] = 'ERR',
    [INT] = 'INT',
    [BLK] = 'BLK',
    [ARR] = 'ARR',
}

--- msg2table
---@param msg any[]
---@return table<string, any>
local function msg2table(msg)
    local tbl = {}
    for i = 1, #msg, 2 do
        tbl[msg[i]] = msg[i + 1]
    end
    return tbl
end

--- msg2err
--- @param msg string
--- @return string type
--- @return string msg
local function msg2err(msg)
    local tail, head = find(msg, '%s+')
    return sub(msg, 2, tail - 1), sub(msg, head + 1)
end

--- decode
--- @param cmd string
--- @param data string
--- @return any msg
--- @return any err
--- @return integer? pos
local function decode(cmd, data)
    local pos, msg, typ = resp_decode(data)
    if pos == EAGAIN then
        -- more bytes need
        return
    elseif pos == EILSEQ then
        -- decode failure
        return nil, 'illegal byte sequence received'
    end

    local res = {
        command = cmd,
        type = T_NAMES[typ],
        message = msg,
    }
    if typ == ERR then
        res.error, res.message = msg2err(msg)
    elseif typ == ARR and cmd == 'HGETALL' then
        res.message = msg2table(msg)
    end
    return res, nil, pos
end

return decode

