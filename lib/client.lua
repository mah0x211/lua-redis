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
local encode2array = require('resp').encode2array;
local decode = require('resp').decode;
local type = type;
local error = error;
local assert = assert;
local setmetatable = setmetatable;
local strfind = string.find;
local strformat = string.format;
local concat = table.concat;
local _tostring = tostring;
--- constants
local EILSEQ = require('resp').EILSEQ;
local DEFAULT_OPTS = {
    host = '127.0.0.1',
    port = 6379,
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
        if type( k ) == 'string' and #k > 0 then
            if type( v ) ~= 'number' then
                v = tostring( v );
            end

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
            return encode2array( cmd, key, flatten( ... ) );
        end

        return encode2array( cmd, key, ... );
    end

    return encode2array( cmd );
end


--- recv
-- @param self
-- @param nres
-- @return res
-- @return err
-- @return timeout
local function recv( self, nres )
    local sock = self.sock;
    local res = {};
    local data = '';
    local idx = 0;
    local cur = 0;

    assert( nres > idx );
    -- recv N response
    while true do
        local chunk, err, timeout = sock:recv();

        if not chunk or err or timeout then
            return nil, err, timeout;
        end

        data = data .. chunk;
        while true do
            local pos, msg, typ = decode( data, cur );

            if pos > 0 then
                idx = idx + 1;
                res[idx] = {
                    typ = typ,
                    msg = msg
                };
                if idx == nres then
                    return idx == 1 and res[1] or res;
                end
                -- update cursor
                cur = pos;
            -- decode failure
            elseif pos == EILSEQ then
                return nil, 'illegal byte sequence received';
            else
                break;
            end
        end
    end
end


--- pushq
-- @param self
-- @param ...
-- @return res
-- @return err
-- @return timeout
local function pushq( self, ... )
    if not self.cmdq then
        local len, err, timeout = self.sock:send( query( self.cmd, ... ) );

        if not len or err or timeout then
            return nil, err, timeout;
        end

        return recv( self, 1 );
    end

    -- pipeline
    self.cmdq[#self.cmdq + 1] = query( self.cmd, ... );

    return self;
end


--- command
-- @param self
-- @param cmd
-- @return fn
local function command( self, cmd )
    if type( cmd ) ~= 'string' or not strfind( cmd, '^%a%w*$' ) then
        error( strformat('invalid command %q', cmd ) );
    end

    self.cmd = cmd:upper();

    return pushq;
end


--- class Client
local Client = {};


--- pipeline
-- @return self
function Client:pipeline()
    if not self.cmdq then
        self.cmdq = {};
    end

    return self;
end


--- emit
-- @return res
-- @return err
-- @return timeout
function Client:emit()
    if self.cmdq then
        local cmdq = self.cmdq;
        local ncmd = #cmdq;

        self.cmdq = false;
        if ncmd > 0 then
            local qry = concat( cmdq );
            local len, err, timeout = self.sock:send( qry );

            if not len or err or timeout then
                return nil, err, timeout;
            end

            return recv( self, ncmd );
        end
    end

    return nil, 'pipeline request not exists';
end



Client = setmetatable( Client, {
    __index = command;
});


--- new
-- @param cfg
--  host: string
--  port: string
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
                    error( strformat( 'cfg.%s must be %s', k, t ) );
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
        cmdq = false,
    }, {
        __index = Client
    });
end


return {
    new = new
};

