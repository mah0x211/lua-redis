# lua-redis

[![test](https://github.com/mah0x211/lua-redis/actions/workflows/test.yml/badge.svg)](https://github.com/mah0x211/lua-redis/actions/workflows/test.yml)
[![codecov](https://codecov.io/gh/mah0x211/lua-redis/branch/master/graph/badge.svg)](https://codecov.io/gh/mah0x211/lua-redis)

redis client library for lua.


## Installation

```
luarocks install redis
```


## c, err, timeout = redis.new( [host [, port [, opts]]] )

create new redis client.

**Parameters**

- `host:string`: host address. (default: `127.0.0.1`)
- `port:string|integer`: port number (default: `6379`)
- `opts:table`: 
    - `deadline:uint`: specify a timeout milliseconds as unsigned integer.
    - `tlscfg:libtls.config`: [libtls.config](https://github.com/mah0x211/lua-libtls/blob/master/doc/config.md) object.

**Returns**

- `c:redis.client`: redis client.
- `err:any`: error message.
- `timeout:boolean`: `true` if operation has timed out.


## Command Execution

calling the client method executes the redis command with the same name as the method except the following methods;

- `sndtimeo`
- `rcvtimeo`
- `pipeline`
- `quit`
- `multi`
- `subscribe`
- `psubscribe`
- `ssubscribe`
- `unsubscribe`
- `punsubscribe`
- `sunsubscribe`


**Usage**

```lua
local dump = require('dump')
local function printdump(v)
    print(dump(v))
end

local redis = require('redis')
local c = redis.new()
-- execute: SET foo 'hello world!'
local res = assert(c:set('foo', 'hello world!'))
printdump(res)
-- {
--     command = "SET",
--     message = "OK",
--     type = "STR"
-- }

-- execute: GET foo
res = assert(c:get('foo'))
printdump(res)
-- {
--     command = "GET",
--     message = "hello world!",
--     type = "BLK"
-- }
```

basically, the replied message from redis-server will be converted to the following data structure;

```
{
  command = '<command-name>'   | executed command name.
  type    = '<message-type>'   | one of the following types.
              'STR' | Simple Strings, the first byte of the reply is "+"
              'ERR' | Errors, the first byte of the reply is "-"
              'INT' | Integers, the first byte of the reply is ":"
              'BLK' | Bulk Strings, the first byte of the reply is "$"
              'ARR' | Arrays, the first byte of the reply is "*"
  error   = '<error-type>'     | this field is added if the type field is 'ERR'.
  message = <decoded-message>  | if the command is 'HGETALL', it is decoded as 
                               | a lua key-value pair table.
}
```

if redis-server replies with multiple messages for a single command, such as the `SUBSCRIBE` command, the messages are returned in an array.

```
{
  {
    command = ...
    type    = ...
    error   = ...
    message = ...
  },
  ...
}
```

## Set timeout seconds

### sec, err = c:sndtimeo( [sec] )

get or set the send timeout seconds.

**Paramters**

- `sec:number`: set the timeout seconds.

**Returns**

- `sec:number`: current or previous timeout seconds.
- `err:any`: error message.


### sec, err = c:rcvtimeo( [sec] )

get or set the receive timeout seconds.

**Paramters**

- `sec:number`: set the timeout seconds.

**Returns**

- `sec:number`: current or previous timeout seconds.
- `err:any`: error message.

**Usage**

```lua
local clock = require('clock')
local dump = require('dump')
local function printdump(v)
    print(dump(v))
end

local redis = require('redis')

-- create client for subscribe
local c = redis.new()
-- set timeout 1.2 sec
local old_timeout_val = assert(c:rcvtimeo(1.2))
printdump({
    old_timeout_val = old_timeout_val,
})
-- {
--     old_timeout_val = 0
-- }

-- create subscriber
local s = assert(c:subscribe('foo'))
-- receive message
local elapsed = clock.gettime()
local res, err, timeout = s:recv()
elapsed = clock.gettime() - elapsed
printdump({
    res = res,
    err = err,
    timeout = timeout,
    elapsed = elapsed,
})
-- {
--     elapsed = 1.2011869999114,
--     timeout = true
-- }
```


## Close the connection

### ok, err, timeout = c:quit()

this method executes the `QUIT` command and close the connection. it also returns a command execution error even if the connection is successfully closed.

**Returns**

- `ok:boolean`: `true` on success.
- `err:any`: error message.
- `timeout:boolean`: `true` if operation has timed out.


## Execute mutiple commands in a single method call

### res, err, timeout = c:pipeline( fn )

the `pipeline` method is used to execute multiple commands in a single call.

**Paramters**

- `fn:function`: function or callable object. if this function does not return `true`, the queued command will not be executed.

**Returns**

- `res:table`: response messages.
- `err:any`: error message.
- `timeout:boolean`: `true` if operation has timed out.

**Usage**

```lua
local dump = require('dump')
local function printdump(v)
    print(dump(v))
end


local redis = require('redis')
local c = redis.new()
-- execute the multiple commands
local res = assert(c:pipeline(function()
    c:set('foo', 'bar')
    c:get('foo')
    c:set('foo', 'hello world!')
    c:get('foo')
    c:set('foo')
    c:set('foo', 'qux')
    c:get('foo')
    return true
end))
printdump(res)
-- {
--     [1] = {
--         command = "SET",
--         message = "OK",
--         type = "STR"
--     },
--     [2] = {
--         command = "GET",
--         message = "bar",
--         type = "BLK"
--     },
--     [3] = {
--         command = "SET",
--         message = "OK",
--         type = "STR"
--     },
--     [4] = {
--         command = "GET",
--         message = "hello world!",
--         type = "BLK"
--     },
--     [5] = {
--         command = "SET",
--         error = "ERR",
--         message = "wrong number of arguments for 'set' command",
--         type = "ERR"
--     },
--     [6] = {
--         command = "SET",
--         message = "OK",
--         type = "STR"
--     },
--     [7] = {
--         command = "GET",
--         message = "qux",
--         type = "BLK"
--     }
-- }
```


## Transactions

### res, err, timeout = c:multi( fn )

the `multi` method is used to execute transaction.

**Paramters**

- `fn:function`: function or callable object. if this function return `true`, the `EXEC` command is executed, otherwise the `DISCARD` command is executed.

**Returns**

- `res:table`: response messages.
- `err:any`: error message.
- `timeout:boolean`: `true` if operation has timed out.

**Usage**

```lua
local dump = require('dump')
local function printdump(v)
    print(dump(v))
end

local redis = require('redis')
local c = redis.new()

-- execute the multi-exec commands
local res = assert(c:multi(function()
    printdump(c:set('foo', 'bar'))
    -- {
    --     command = "SET",
    --     message = "QUEUED",
    --     type = "STR"
    -- }
    printdump(c:get('foo'))
    -- {
    --     command = "GET",
    --     message = "QUEUED",
    --     type = "STR"
    -- }
    printdump(c:set('foo', 'hello world!'))
    -- {
    --     command = "SET",
    --     message = "QUEUED",
    --     type = "STR"
    -- }
    printdump(c:get('foo'))
    -- {
    --     command = "GET",
    --     message = "QUEUED",
    --     type = "STR"
    -- }
    return true
end))
printdump(res)
-- {
--     command = "EXEC",
--     message = {
--         [1] = "OK",
--         [2] = "bar",
--         [3] = "OK",
--         [4] = "hello world!"
--     },
--     type = "ARR"
-- }
```

if an error occurs in a command issued during a transaction, the transaction fails.

```lua
local dump = require('dump')
local function printdump(v)
    print(dump(v))
end

local redis = require('redis')
local c = redis.new()

-- execution failure
local res = assert(c:multi(function()
    printdump(c:get('foo'))
    -- {
    --     command = "GET",
    --     message = "QUEUED",
    --     type = "STR"
    -- }
    printdump(c:set('foo'))
    -- {
    --     command = "SET",
    --     error = "ERR",
    --     message = "wrong number of arguments for 'set' command",
    --     type = "ERR"
    -- }
    return true
end))
printdump(res)
-- {
--     command = "EXEC",
--     error = "EXECABORT",
--     message = "Transaction discarded because of previous errors.",
--     type = "ERR"
-- }
```

if function does not return `true`, the `DISCARD` command is executed.

```lua
local dump = require('dump')
local function printdump(v)
    print(dump(v))
end

local redis = require('redis')
local c = redis.new()

-- discard queued commands
local res = assert(c:multi(function()
    printdump(c:get('foo'))
    -- {
    --     command = "GET",
    --     message = "QUEUED",
    --     type = "STR"
    -- }
end))
printdump(res)
-- {
--     command = "DISCARD",
--     message = "OK",
--     type = "STR"
-- }
```


## PubSub

the following subscribe commands are create an instance of `redis.subscriber`.

- `SUBSCRIBE`
- `PSUBSCRIBE`
- `SSUBSCRIBE`

### s, err, timeout = c:subscribe( channel [, ...] )

create an instance of `redis.subscriber`.

**NOTE**: this method cannot be used in a `pipeline` function.


**Paramters**

- `channel:string`: channel names.

**Returns**

- `s:redis.subscriber`: an instance of `redis.subscriber`.
- `err:any`: error message.
- `timeout:boolean`: `true` if operation has timed out.

**Usage**

```lua
local redis = require('redis')

local c = redis.new()
-- create subscriber
local s = assert(c:subscribe('foo', 'bar', 'baz'))
```


### Subscriber methods

### res, err, timeout = s:recv()

receive messages from subscribed channels.

**Returns**

- `res:table`: response messages.
- `err:any`: error message.
- `timeout:boolean`: `true` if operation has timed out.

**Usage**

```lua
local dump = require('dump')
local function printdump(v)
    print(dump(v))
end

local redis = require('redis')

-- create client for subscribe
local c = redis.new()
-- create subscriber
local s = assert(c:subscribe('foo'))

-- publish message
local p = redis.new()
local res = assert(p:publish('foo', 'hello world!'))
printdump(res)
-- {
--     command = "PUBLISH",
--     message = 1,
--     type = "INT"
-- }

-- receive message
res = assert(s:recv())
printdump(res)
-- {
--     command = "SUBSCRIBE",
--     message = {
--         [1] = {
--             channel = "foo",
--             message = "hello world!"
--         }
--     },
--     type = "ARR"
-- }
```

### res, err, timeout = s:unsubscribe( [channel [, ...]] )

unsubscribe specified or all channels.

**Paramters**

- `channel:string`: channel names.

**Returns**

- `res:table`: response messages.  
    **NOTE**: if the value of the `res.remains` field is `0`, the subscriber `s` has been disabled.
- `err:any`: error message.
- `timeout:boolean`: `true` if operation has timed out.

**Usage**

```lua
local dump = require('dump')
local function printdump(v)
    print(dump(v))
end

local redis = require('redis')

-- create client for subscribe
local c = redis.new()
-- create subscriber
local s = assert(c:subscribe('foo', 'bar', 'baz'))

-- unsubscribe channel 'bar'
local res = assert(s:unsubscribe('bar'))
printdump(res)
-- {
--     command = "UNSUBSCRIBE",
--     message = {
--         [1] = {
--             channel = "bar",
--             kind = "unsubscribe",
--             remains = 2
--         }
--     },
--     remains = 2,
--     type = "ARR"
-- }

-- unsubscribe all channels
res = assert(s:unsubscribe())
printdump(res)
-- {
--     command = "UNSUBSCRIBE",
--     message = {
--         [1] = {
--             channel = "baz",
--             kind = "unsubscribe",
--             remains = 1
--         },
--         [2] = {
--             channel = "foo",
--             kind = "unsubscribe",
--             remains = 0
--         }
--     },
--     remains = 0,
--     type = "ARR"
-- }
```
