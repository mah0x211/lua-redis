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
local gsub = string.gsub
local ipairs = ipairs

--- @class redis.subscriber
--- @field conn redis.Connection
--- @field cmd string
local Subscriber = {}

--- init
--- @param conn redis.Connection
--- @param cmd string
--- @return redis.subscriber
function Subscriber:init(conn, cmd)
    self.conn = conn
    self.cmd = cmd
    return self
end

--- getconn
--- @param self redis.subscriber
--- @return redis.Connection
local function getconn(self)
    if not self.conn then
        error(
            'subscriber cannot be used after all channels have been unsubscribed',
            3)
    end
    return self.conn
end

--- unsubscribe
--- @param ... string
--- @return table? res
--- @return any err
--- @return boolean? timeout
function Subscriber:unsubscribe(...)
    local conn = getconn(self)
    local cmd = gsub(self.cmd, '(.?)SUB', '%1UNSUB')
    local msgs, err, timeout = conn:sendcmd(cmd, ...)
    if not msgs then
        return nil, err, timeout
    elseif #msgs == 0 then
        msgs = {
            msgs,
        }
    end

    local remains = -1
    local message = {}
    local res = {
        command = cmd,
        type = 'ARR',
        message = message,
    }
    for i, v in ipairs(msgs) do
        remains = v.message[3]
        message[i] = {
            kind = v.message[1],
            channel = v.message[2],
            remains = remains,
        }
    end
    res.remains = remains

    -- release a connection if there are no subscribed channels
    if remains == 0 then
        self.conn = nil
    end

    return res
end

--- rcvtimeo
--- @param sec number
--- @return number? sec
--- @return any err
function Subscriber:rcvtimeo(sec)
    local conn = getconn(self)
    return conn:rcvtimeo(sec)
end

--- recv
--- @return table? res
--- @return any err
--- @return boolean? timeout
function Subscriber:recv()
    local conn = getconn(self)
    local msgs, err, timeout = conn:recv({
        self.cmd,
    })
    if not msgs then
        return nil, err, timeout
    elseif msgs.error then
        return msgs
    elseif #msgs == 0 then
        msgs = {
            msgs,
        }
    end

    local message = {}
    local res = {
        command = self.cmd,
        type = 'ARR',
        message = message,
    }
    for i, v in ipairs(msgs) do
        if v.message[1] == 'message' then
            -- message
            message[i] = {
                channel = v.message[2],
                message = v.message[3],
            }
        else
            -- pmessage
            message[i] = {
                pattern = v.message[2],
                channel = v.message[3],
                message = v.message[4],
            }
        end
    end

    return res
end

Subscriber = require('metamodule').new(Subscriber)

return Subscriber
