package = "net-redis"
version = "scm-1"
source = {
    url = "git+https://github.com/mah0x211/lua-net-redis.git",
}
description = {
    summary = "redis module for lua",
    homepage = "https://github.com/mah0x211/lua-net-redis",
    license = "MIT/X11",
    maintainer = "Masatoshi Fukunaga",
}
dependencies = {
    "lua >= 5.1",
    "isa >= 0.3",
    "net >= 0.34",
    "resp >= 0.5.3",
}
build = {
    type = "builtin",
    modules = {
        ['net.redis'] = "redis.lua",
        ['net.redis.decode'] = "lib/decode.lua",
        ['net.redis.encode'] = "lib/encode.lua",
        ['net.redis.subscriber'] = "lib/subscriber.lua",
    },
}

