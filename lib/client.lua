--[[

  Copyright (C) 2017 Masatoshi Teruya

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in
  all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
  THE SOFTWARE.

  lib/client.lua
  lua-net-redis
  Created by Masatoshi Teruya on 17/07/11.

--]]

--- assign to local
local InetClient = require('net.stream.inet').client;
local RESP = require('resp');
local encode = RESP.encode;
local concat = table.concat;
local _tostring = tostring;
--- constants
local OK = RESP.OK;
local EAGAIN = RESP.EAGAIN;
local EILSEQ = RESP.EILSEQ;
local DEFAULT_OPTS = {
    host = '127.0.0.1',
    port = 6379,
    nonblock = false
};


--- tostring
-- @param v
-- @return str
local function tostring( v )
    if type( v ) ~= 'string' then
        v = _tostring( v );
    end

    if #v > 0 then
        return v;
    end
end


--- flatten
-- @param tbl
-- @return arr
-- @return err
local function flatten( tbl )
    local arr = {};
    local idx = 1;

    for k, v in pairs( tbl ) do
        k = tostring( k );
        v = k and tostring( v );
        if v then
            arr[idx] = k;
            arr[idx + 1] = v;
            idx = idx + 2;
        end
    end

    return arr;
end


--- query
-- @param cmd
-- @param key
-- @param ...
-- @return qry
local function query( cmd, key, ... )
    if key then
        if cmd == 'HMSET' then
            return encode( cmd, key, flatten( ... ) );
        end

        return encode( cmd, key, ... );
    end

    return encode( cmd );
end


--- pushq
-- @param c
-- @param ...
-- @return ok
-- @return err
-- @return again
local function pushq( c, ... )
    -- enqueue
    c.tail = c.tail + 1;
    c.rcvq[c.tail] = c.cmd;
    if c.sink ~= false then
        c.sink[#c.sink + 1] = query( c.cmd, ... );
        return true;
    end

    c.sock:sendq( query( c.cmd, ... ) );

    return c:drain();
end


--- command
-- @param c
-- @param cmd
-- @return fn
local function command( c, cmd )
    if type( cmd ) ~= 'string' or not cmd:find('^%a%w*$') then
        error( ('invalid command %q'):format( cmd ) );
    end

    c.cmd = cmd:upper();

    return pushq;
end


--- class Client
local Client = {};


--- pipeline
-- @return self
function Client:pipeline()
    if self.sink == false then
        self.sink = {};
    end

    return self;
end


--- emit
-- @return ok
-- @return err
-- @return again
function Client:emit()
    -- enqueue
    if self.sink ~= false then
        self.sock:sendq( concat( self.sink ) );
        self.sink = false;
    end

    return self:drain();
end


--- recv
-- @return ok
-- @return msg
-- @return extra
-- @return again
function Client:recv()
    -- recv response
    if self.tail > 0 then
        local sock = self.sock;
        local resp = self.resp;
        local data;

        while true do
            local rc, msg, extra = resp:decode( data );

            -- decoded
            if rc == OK then
                self.rcvq[self.head] = nil;
                -- update head
                if self.head ~= self.tail then
                    self.head = self.head + 1;
                -- reset head and tail
                else
                    self.head, self.tail = 1, 0;
                end

                return true, msg, extra;
            elseif rc == EILSEQ then
                self.rcvq:shift();
                return false, nil, nil, 'illegal byte sequence';
            elseif rc == EAGAIN then
                local err, again;

                data, err, again = sock:recv();
                if not data then
                    return false, nil, nil, err, again;
                end
            end
        end
    end

    return false, nil, nil, true;
end


--- drain
-- @return ok
-- @return err
-- @return again
function Client:drain()
    -- send queued queries
    local len, err, again = self.sock:flushq();

    -- send buffer is full
    if again then
        return true, nil, true;
    -- got error
    elseif err then
        return false, err;
    -- closed by peer
    elseif not len then
        return false;
    end

    return true;
end


Client = setmetatable( Client, {
    __index = command;
});


--- new
-- @param cfg
--  host: string
--  port: string
--  nonblock: boolean
-- @return cli
-- @return err
local function new( cfg )
    local opts = DEFAULT_OPTS;
    local sock, err;

    if cfg then
        assert( type( cfg ) == 'table', 'cfg must be table' );
        opts = {};
        for k, v in pairs( DEFAULT_OPTS ) do
            local cv = cfg[k];

            -- use default value
            if cv == nil then
                opts[k] = v;
            else
                local t = type( v );

                if type( cv ) ~= t then
                    error( ('cfg.%s must be %s'):format( k, t ) );
                end
                opts[k] = cv;
            end
        end
    end

    -- connect
    sock, err = InetClient.new( opts );
    if err then
        return nil, err;
    end

    return setmetatable({
        sock = sock,
        resp = RESP.new(),
        rcvq = {},
        head = 1,
        tail = 0,
        sink = false
    }, {
        __index = Client
    });
end


return {
    new = new
};

