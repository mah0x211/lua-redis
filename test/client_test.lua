require('luacov')
local testcase = require('testcase')
local timer = require('testcase.timer')
local redis = require('net.redis.client')

function testcase.before_each()
    local c = assert(redis.new())
    local res = assert(c:flushall())
    assert.equal(res.message, 'OK')
    assert(c:quit())
end

function testcase.error_message()
    local c = assert(redis.new())

    -- test that get an error reply
    local res = assert(c:set('foo'))
    assert.equal(res.command, 'SET')
    assert.equal(res.type, 'ERR')
    assert.equal(res.error, 'ERR')
end

function testcase.set_get()
    local c = assert(redis.new())

    -- test that set key-value pair
    local res = assert(c:set('foo', 'hello\nworld!'))
    assert.equal(res.command, 'SET')
    assert.equal(res.type, 'STR')
    assert.equal(res.message, 'OK')

    -- test that get value for key
    res = assert(c:get('foo'))
    assert.equal(res.type, 'BLK')
    assert.equal(res.command, 'GET')
    assert.equal(res.message, 'hello\nworld!')
end

function testcase.set_get_hashdata()
    local c = assert(redis.new())

    -- test that the table<string, value> arguments are unfolded into an array
    local res = assert(c:hmset('foo', {
        bar = 'baz',
    }, 'hello', 'world', {
        qux = 'quux',
        key = 'value',
    }))
    assert.equal(res.command, 'HMSET')
    assert.equal(res.type, 'STR')
    assert.equal(res.message, 'OK')

    -- test that the result of hgetall command is automatically converted to a lua table
    res = assert(c:hgetall('foo'))
    assert.equal(res.command, 'HGETALL')
    assert.equal(res.type, 'ARR')
    assert.equal(res.message, {
        bar = 'baz',
        hello = 'world',
        key = 'value',
        qux = 'quux',
    })
end

function testcase.pipeline()
    local c = assert(redis.new())

    -- test that execute the pipeline request
    local res, err, timeout = assert(c:pipeline(function()
        assert.is_nil(c:set('foo', 'bar'))
        assert.is_nil(c:get('foo'))
        assert.is_nil(c:set('foo', 'hello world!'))
        assert.is_nil(c:get('foo'))
        assert.is_nil(c:set('foo'))
        assert.is_nil(c:set('foo', 'qux'))
        assert.is_nil(c:get('foo'))
        return true
    end))
    assert.is_nil(err)
    assert.is_nil(timeout)
    assert.contains(res, {
        {
            command = 'SET',
            type = 'STR',
            message = 'OK',
        },
        {
            command = 'GET',
            type = 'BLK',
            message = 'bar',
        },
        {
            command = 'SET',
            type = 'STR',
            message = 'OK',
        },
        {
            command = 'GET',
            type = 'BLK',
            message = 'hello world!',
        },
        {
            command = 'SET',
            type = 'ERR',
        },
        {
            command = 'SET',
            type = 'STR',
            message = 'OK',
        },
        {
            command = 'GET',
            type = 'BLK',
            message = 'qux',
        },
    })

    -- test that not execute the request if function does not return true
    res, err, timeout = c:pipeline(function()
        assert.is_nil(c:set('foo', 'bar'))
        assert.is_nil(c:get('foo'))
        assert.is_nil(c:set('foo', 'hello world!'))
        assert.is_nil(c:get('foo'))
    end)
    assert.is_nil(res)
    assert.is_nil(err)
    assert.is_nil(timeout)

    -- test that throws an error from a function
    err = assert.throws(function()
        c:pipeline(function()
            error('throws-an-error')
        end)
    end)
    assert.match(err, 'throws-an-error')

    -- test that throws an error if fn argument is not callable
    err = assert.throws(function()
        c:pipeline(1)
    end)
    assert.match(err, 'fn must be callable')
end

function testcase.multi()
    local c = assert(redis.new())

    -- test that execute the multi request
    local res, err, timeout = assert(c:multi(function()
        assert.equal(c:set('foo', 'bar'), {
            command = 'SET',
            type = 'STR',
            message = 'QUEUED',
        })
        assert.equal(c:get('foo'), {
            command = 'GET',
            type = 'STR',
            message = 'QUEUED',
        })
        assert.equal(c:set('foo', 'hello world!'), {
            command = 'SET',
            type = 'STR',
            message = 'QUEUED',
        })
        assert.equal(c:get('foo'), {
            command = 'GET',
            type = 'STR',
            message = 'QUEUED',
        })
        return true
    end))
    assert.is_nil(err)
    assert.is_nil(timeout)
    assert.equal(res, {
        command = 'EXEC',
        type = 'ARR',
        message = {
            'OK',
            'bar',
            'OK',
            'hello world!',
        },
    })

    -- test that discards queued request if function does not return true
    res = assert(c:multi(function()
        assert.equal(c:set('foo', 'bar'), {
            command = 'SET',
            type = 'STR',
            message = 'QUEUED',
        })
        assert.equal(c:get('foo'), {
            command = 'GET',
            type = 'STR',
            message = 'QUEUED',
        })
    end))
    assert.equal(res, {
        command = 'DISCARD',
        type = 'STR',
        message = 'OK',
    })

    -- test that cannot execute a multi command in pipeline mode
    c:pipeline(function()
        res, err = c:multi(function()
        end)
        assert.is_nil(res)
        assert.match(err, 'cannot be executed in the pipeline mode')
    end)

    -- test that catch the exception from a function
    err = assert.throws(function()
        c:multi(function()
            error('throws-an-error')
        end)
    end)
    assert.match(err, 'throws-an-error')

    -- test that throws an error if fn argument is not callable
    err = assert.throws(function()
        c:multi(1)
    end)
    assert.match(err, 'fn must be callable')
end

function testcase.client_cannot_exec_unsubscribe_commands()
    local c = assert(redis.new())

    -- test that cannot exec unsubscribe command from client
    for _, cmd in ipairs({
        'unsubscribe',
        'punsubscribe',
        'sunsubscribe',
    }) do
        local res, err = c[cmd](c)
        assert.is_nil(res)
        assert.equal(err,
                     string.format(
                         'command %q must be executed by the net.redis.subscriber',
                         string.upper(cmd)))
    end
end

function testcase.pubsub_channel()
    local c = assert(redis.new())
    local pubs = {
        {
            p = assert(redis.new()),
            ch = 'foo',
            msg = 'foo-msg',
        },
        {
            p = assert(redis.new()),
            ch = 'bar',
            msg = 'bar-msg',
        },
        {
            p = assert(redis.new()),
            ch = 'baz',
            msg = 'baz-msg',
        },
    }

    local res, err, timeout = assert(pubs[1].p:publish('foo', 'bar'))
    assert.is_nil(err)
    assert.is_nil(timeout)
    assert.equal(res.command, 'PUBLISH')
    assert.equal(res.type, 'INT')
    assert.equal(res.message, 0)

    -- test that create subscriber
    local s = assert(c:subscribe('foo', 'bar', 'baz'))

    -- test that can set a receive timeout
    assert(s:rcvtimeo(1.2))
    local t = timer.new()
    t:start()
    res, err, timeout = s:recv()
    t = t:stop()
    assert.is_nil(res)
    assert.is_nil(err)
    assert.is_boolean(timeout)
    assert.greater(t, 1.2)
    assert.less(t, 1.3)

    -- test that publish message
    for _, v in ipairs(pubs) do
        res = assert(v.p:publish(v.ch, v.msg))
        assert.equal(res.command, 'PUBLISH')
        assert.equal(res.type, 'INT')
        assert.equal(res.message, 1)
    end

    -- test that receive the message of 'foo', 'bar' and 'baz' channels
    res, err, timeout = assert(s:recv())
    assert.is_nil(err)
    assert.is_nil(timeout)
    assert.equal(res.command, 'SUBSCRIBE')
    assert.equal(res.type, 'ARR')
    assert.equal(res.message, {
        {
            channel = 'foo',
            message = 'foo-msg',
        },
        {
            channel = 'bar',
            message = 'bar-msg',
        },
        {
            channel = 'baz',
            message = 'baz-msg',
        },
    })

    -- test that unsubscribe channel 'foo'
    res = assert(s:unsubscribe('foo'))
    assert.equal(res.command, 'UNSUBSCRIBE')
    assert.equal(res.type, 'ARR')
    assert.equal(res.remains, 2)
    assert.equal(res.message, {
        {
            channel = 'foo',
            kind = 'unsubscribe',
            remains = 2,
        },
    })

    -- test that publish message
    for _, v in ipairs(pubs) do
        res = assert(v.p:publish(v.ch, v.msg))
        assert.equal(res.command, 'PUBLISH')
        assert.equal(res.type, 'INT')
        if v.ch == 'foo' then
            assert.equal(res.message, 0)
        end
    end

    -- test that receive the message of 'bar' and 'baz' channels
    res = assert(s:recv())
    assert.equal(res.message, {
        {
            channel = 'bar',
            message = 'bar-msg',
        },
        {
            channel = 'baz',
            message = 'baz-msg',
        },
    })

    -- test that unsubscribe all channels
    res = assert(s:unsubscribe())
    assert.equal(res.remains, 0)
    local channels = {
        bar = true,
        baz = true,
    }
    for _, m in ipairs(res.message) do
        assert(channels[m.channel])
        channels[m.channel] = nil
    end
    assert.is_nil(next(channels))

    -- test that cannot subscribe in pipeline mode
    c:pipeline(function()
        local s2, err2 = c:subscribe('foo')
        assert.is_nil(s2)
        assert.equal(err2, 'command "SUBSCRIBE" cannot be executed in pipeline')
    end)

    -- test that subscriber cannot be used after unsubscribed all channels
    err = assert.throws(s.recv, s)
    assert.equal(err,
                 'subscriber cannot be used after all channels have been unsubscribed')

end

function testcase.pubsub_pattern()
    local c = assert(redis.new())
    local pubs = {
        {
            p = assert(redis.new()),
            ch = 'foo',
            msg = 'foo-msg',
        },
        {
            p = assert(redis.new()),
            ch = 'bar',
            msg = 'bar-msg',
        },
        {
            p = assert(redis.new()),
            ch = 'baz',
            msg = 'baz-msg',
        },
    }

    local res, err, timeout = assert(pubs[1].p:publish('foo', 'bar'))
    assert.is_nil(err)
    assert.is_nil(timeout)
    assert.equal(res.command, 'PUBLISH')
    assert.equal(res.type, 'INT')
    assert.equal(res.message, 0)

    -- test that create subscriber
    local s = assert(c:psubscribe('f?o', 'b?r', 'b?z'))

    -- test that publish message
    for _, v in ipairs(pubs) do
        res = assert(v.p:publish(v.ch, v.msg))
        assert.equal(res.command, 'PUBLISH')
        assert.equal(res.type, 'INT')
        assert.equal(res.message, 1)
    end

    -- test that receive the message of 'f?o', 'b?r' and 'b?z' channels
    res, err, timeout = assert(s:recv())
    assert.is_nil(err)
    assert.is_nil(timeout)
    assert.equal(res.command, 'PSUBSCRIBE')
    assert.equal(res.type, 'ARR')
    assert.equal(res.message, {
        {
            pattern = 'f?o',
            channel = 'foo',
            message = 'foo-msg',
        },
        {
            pattern = 'b?r',
            channel = 'bar',
            message = 'bar-msg',
        },
        {
            pattern = 'b?z',
            channel = 'baz',
            message = 'baz-msg',
        },
    })

    -- test that unsubscribe channel 'foo'
    res = assert(s:unsubscribe('f?o'))
    assert.equal(res.command, 'PUNSUBSCRIBE')
    assert.equal(res.type, 'ARR')
    assert.equal(res.remains, 2)
    assert.equal(res.message, {
        {
            channel = 'f?o',
            kind = 'punsubscribe',
            remains = 2,
        },
    })

    -- test that unsubscribe all channels
    res = assert(s:unsubscribe())
    assert.equal(res.remains, 0)
    local channels = {
        ['b?r'] = true,
        ['b?z'] = true,
    }
    for _, m in ipairs(res.message) do
        assert(channels[m.channel])
        channels[m.channel] = nil
    end
    assert.is_nil(next(channels))
end
