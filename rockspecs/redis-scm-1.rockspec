package = "redis"
version = "scm-1"
source = {
    url = "git+https://github.com/mah0x211/lua-redis.git",
}
description = {
    summary = "redis module for lua",
    homepage = "https://github.com/mah0x211/lua-redis",
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
        ['redis'] = "redis.lua",
        ['redis.decode'] = "lib/decode.lua",
        ['redis.encode'] = "lib/encode.lua",
        ['redis.subscriber'] = "lib/subscriber.lua",
    },
}

