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
local error = error
local assert = assert
local select = select
local setmetatable = setmetatable
local sub = string.sub
local find = string.find
local format = string.format
local upper = string.upper
local concat = table.concat
local isa = require('isa')
local is_callable = isa.callable
local is_string = isa.string
local new_inet_client = require('net.stream.inet').client.new
local new_subscriber = require('redis.subscriber')
local encode = require('redis.encode')
local decode = require('redis.decode')

--- @class redis.Connection
--- @field sock net.Socket
--- @field pipelined boolean
--- @field cmds string[]
--- @field queries string[]
local Connection = {}

--- new
--- @param host? string
--- @param port? integer|string
--- @param opts? table
--- @return redis.Connection? c
--- @return any err
--- @return boolean? timeout
function Connection:init(host, port, opts)
    local sock, err, timeout = new_inet_client(host or '127.0.0.1',
                                               port or 6379, opts)
    if err then
        return nil, err, timeout
    end

    self.sock = sock
    self.pipelined = false
    self.cmds = {}
    self.queries = {}
    return self
end

--- rcvtimeo
--- @param sec number
--- @return number? sec
--- @return any err
function Connection:rcvtimeo(sec)
    return self.sock:rcvtimeo(sec)
end

--- recv
--- @param cmds string[]
--- @return table? res
--- @return any err
--- @return boolean? timeout
function Connection:recv(cmds)
    local sock = self.sock
    local res = {}
    local data = ''
    local ncmd = #cmds
    local idx = 1

    while true do
        local chunk, err, timeout = sock:recv()
        if not chunk or err or timeout then
            return nil, err, timeout
        end
        data = data .. chunk

        while true do
            local msg, pos
            msg, err, pos = decode(cmds[ncmd == 1 and 1 or idx], data)
            if err then
                -- decode failure
                return nil, err
            elseif not msg then
                -- more bytes need
                break
            end
            data = sub(data, pos + 1)
            res[idx] = msg
            idx = idx + 1

            if ncmd == 1 then
                -- got an error or all responses received
                if msg.error or #data == 0 then
                    return idx == 2 and res[1] or res
                end
            elseif idx > ncmd then
                -- all pipelined response received
                assert(#data == 0)
                return res
            end
        end
    end
end

--- discard
--- @return table? res
--- @return any err
--- @return boolean? timeout
function Connection:discard()
    self.pipelined = false
    self.cmds = {}
    self.queries = {}
end

--- exec
--- @return table? res
--- @return any err
--- @return boolean? timeout
function Connection:exec()
    local cmds = self.cmds
    local q = concat(self.queries)
    self:discard()

    local len, err, timeout = self.sock:send(q)
    if not len or err or timeout then
        return nil, err, timeout
    end

    return self:recv(cmds)
end

--- pipeline
--- @param fn function
--- @return table? res
--- @return any err
--- @return boolean? timeout
function Connection:pipeline(fn)
    if not is_callable(fn) then
        error('fn must be callable', 2)
    end

    self.pipelined = true
    local ok, doexec = pcall(fn)
    if ok and doexec == true then
        return self:exec()
    end
    self:discard()
    if not ok then
        error(doexec)
    end
end

--- multi
--- @param fn function
--- @return table? res
--- @return any err
--- @return boolean? timeout
function Connection:multi(fn)
    if not is_callable(fn) then
        error('fn must be callable', 2)
    elseif self.pipelined then
        return nil, format('command %q cannot be executed in the pipeline mode',
                           'MULTI')
    end

    local res, err, timeout = self:sendcmd('MULTI')
    if not res then
        return nil, err, timeout
    elseif res.error then
        return nil, res.message
    end

    local ok, doexec = pcall(fn)
    if ok and doexec == true then
        -- exec
        return self:sendcmd('EXEC')
    end

    res, err, timeout = self:sendcmd('DISCARD')
    if not ok then
        error(doexec)
    end
    return res, err, timeout
end

--- quit
---@return boolean ok
---@return any err
---@return boolean? timeout
function Connection:quit()
    local res, err, timeout = self:sendcmd('QUIT')
    if res and res.error then
        err = res.message
    end

    -- forcibly close the connection
    local ok, serr, stimeout = self.sock:close()
    if not ok then
        return false, serr, stimeout
    end
    return true, err, timeout
end

--- pushcmd
--- @param cmd string
--- @param ... string
function Connection:pushcmd(cmd, ...)
    self.cmds[#self.cmds + 1] = cmd
    self.queries[#self.queries + 1] = encode(cmd, ...)
end

--- sendcmd
--- @param cmd string
--- @param ... string
--- @return table? res
--- @return any err
--- @return boolean? timeout
function Connection:sendcmd(cmd, ...)
    self:pushcmd(cmd, ...)
    if not self.pipelined then
        return self:exec()
    end
end

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

--- subscmd
--- @param cmd string
--- @param ... string
--- @return redis.subscriber? res
--- @return any err
--- @return boolean? timeout
function Connection:subscmd(cmd, ...)
    if self.pipelined then
        return nil, format('command %q cannot be executed in pipeline', cmd)
    end

    -- must receive results for each channel/pattern
    local chs = {
        ...,
    }
    for i = 1, select('#', ...) do
        local ch = chs[i]
        if not is_string(ch) or find(ch, '^%s*$') then
            -- invalid arguments
            error(format('channel#%d %q must be non-empty string', i,
                         tostring(ch)), 2)
        end
    end

    local res, err, timeout = self:sendcmd(cmd, ...)
    if not res or SUBSCRIBE_CMDS[cmd] == UNSUBSCRIBE then
        return res, err, timeout
    elseif res.error then
        return nil, res.message
    end

    -- create subscriber
    return new_subscriber(self, cmd, chs)
end

Connection = require('metamodule').new.Connection(Connection)

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

--- command
--- @param cmd string
--- @return function fn
local function command(self, cmd)
    if not is_string(cmd) or not find(cmd, '^%a%w*$') then
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

--- pipeline
--- @param self redis
--- @param fn function
--- @return table? res
--- @return any err
--- @return boolean? timeout
local function pipeline(self, fn)
    return self._conn:pipeline(fn)
end

--- multi
--- @param self redis
--- @param fn function
--- @return table? res
--- @return any err
--- @return boolean? timeout
local function multi(self, fn)
    return self._conn:multi(fn)
end

--- quit
--- @param self redis
--- @return table? res
--- @return any err
--- @return boolean? timeout
local function quit(self)
    return self._conn:quit()
end

--- @class redis
--- @field _conn redis.Connection
--- @field _cmd string

--- new
--- @param host? string
--- @param port? integer|string
--- @param opts? table
--- @return redis? c
--- @return any err
--- @return boolean? timeout
local function new(host, port, opts)
    local conn, err, timeout = Connection(host, port, opts)
    if err then
        return nil, err, timeout
    end

    return setmetatable({
        _conn = conn,
        _cmd = '',
        pipeline = pipeline,
        quit = quit,
        multi = multi,
    }, {
        __index = command,
    })
end

return {
    new = new,
}

