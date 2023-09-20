--
--  Copyright (C) 2017-2022 Masatoshi Fukunaga
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
local format = string.format
local upper = string.upper
local type = type
local new_connection = require('redis.connection').new

--- subscriber can send only the following commands
local SUBSCRIBE = 1
local UNSUBSCRIBE = 2
local SUBSCRIBE_CMDS = {
    -- subscribe
    SUBSCRIBE = SUBSCRIBE,
    SSUBSCRIBE = SUBSCRIBE,
    PSUBSCRIBE = SUBSCRIBE,
    -- unsubscribe
    UNSUBSCRIBE = UNSUBSCRIBE,
    SUNSUBSCRIBE = UNSUBSCRIBE,
    PUNSUBSCRIBE = UNSUBSCRIBE,
}

--- sendcmd
--- @param self redis
--- @return table? res
--- @return any err
--- @return boolean? timeout
local function sendcmd(self, ...)
    return self._conn:sendcmd(self._cmd, ...)
end

--- subscmd
--- @param self redis
--- @return table? res
--- @return any err
--- @return boolean? timeout
local function subscmd(self, ...)
    return self._conn:subscmd(self._cmd, ...)
end

--- unsubscmd
--- @param self redis
--- @return table? res
--- @return any err
--- @return boolean? timeout
local function unsubscmd(self, ...)
    return nil, format('command %q must be executed by the redis.subscriber',
                       self._cmd)
end

--- @class redis
--- @field _conn redis.connection
--- @field _cmd string
local Redis = {}

--- command
--- @param cmd string
--- @return function fn
function Redis:__index(cmd)
    if type(cmd) ~= 'string' or not find(cmd, '^%a%w*$') then
        error(format('invalid command %q', cmd))
    end

    self._cmd = upper(cmd)
    local subs = SUBSCRIBE_CMDS[self._cmd]
    if not subs then
        return sendcmd
    elseif subs == SUBSCRIBE then
        return subscmd
    end
    return unsubscmd
end

--- new
--- @param host? string
--- @param port? integer|string
--- @param opts? table
--- @return redis? c
--- @return any err
--- @return boolean? timeout
function Redis:init(host, port, opts)
    local conn, err, timeout = new_connection(host, port, opts)
    if err then
        return nil, err, timeout
    end

    self._conn = conn
    self._cmd = ''
    return self
end

--- pipeline
--- @param fn function
--- @return table? res
--- @return any err
--- @return boolean? timeout
function Redis:pipeline(fn)
    return self._conn:pipeline(fn)
end

--- multi
--- @param fn function
--- @return table? res
--- @return any err
--- @return boolean? timeout
function Redis:multi(fn)
    return self._conn:multi(fn)
end

--- quit
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
function Redis:quit()
    return self._conn:quit()
end

--- sndtimeo
--- @param sec? number
--- @return number? sec
--- @return any err
function Redis:sndtimeo(sec)
    return self._conn:sndtimeo(sec)
end

--- rcvtimeo
--- @param sec? number
--- @return number? sec
--- @return any err
function Redis:rcvtimeo(sec)
    return self._conn:rcvtimeo(sec)
end

return {
    new = require('metamodule').new(Redis),
}

