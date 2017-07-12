package = "net-redis"
version = "scm-1"
source = {
    url = "git://github.com/mah0x211/lua-net-redis.git"
}
description = {
    summary = "redis module for lua",
    homepage = "https://github.com/mah0x211/lua-net-redis",
    license = "MIT/X11",
    maintainer = "Masatoshi Teruya"
}
dependencies = {
    "lua >= 5.1",
    "deque >= 0.4.0",
    "net >= 0.11.0",
    "resp >= 0.3.3"
}
build = {
    type = "builtin",
    modules = {
        ['net.redis.client'] = "lib/client.lua",
    }
}

