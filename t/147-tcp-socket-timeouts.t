# vim:set ft= ts=4 sw=4 et fdm=marker:

BEGIN {
    if (!defined $ENV{LD_PRELOAD}) {
        $ENV{LD_PRELOAD} = '';
    }

    if ($ENV{LD_PRELOAD} !~ /\bmockeagain\.so\b/) {
        $ENV{LD_PRELOAD} = "mockeagain.so $ENV{LD_PRELOAD}";
    }

    if ($ENV{MOCKEAGAIN} eq 'r') {
        $ENV{MOCKEAGAIN} = 'rw';

    } else {
        $ENV{MOCKEAGAIN} = 'w';
    }

    $ENV{TEST_NGINX_EVENT_TYPE} = 'poll';
    $ENV{MOCKEAGAIN_WRITE_TIMEOUT_PATTERN} = 'slowdata';
}

use Test::Nginx::Socket::Lua;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 + 1);

$ENV{TEST_NGINX_RESOLVER} ||= '8.8.8.8';

#log_level 'warn';
log_level 'debug';

no_long_string();
#no_diff();
run_tests();

__DATA__

=== TEST 1: sanity
--- config
    server_tokens off;
    location /t {
        content_by_lua_block {
            local sock = ngx.socket.tcp()

            sock:settimeouts(150, 150, 150)  -- 150ms read timeout

            local port = ngx.var.server_port
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local req = "GET /foo HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n\r\n"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            while true do
                local line, err, part = sock:receive()
                if line then
                    ngx.say("received: ", line)

                else
                    ngx.say("failed to receive a line: ", err, " [", part, "]")
                    break
                end
            end

            sock:close()
        }
    }

    location /foo {
        content_by_lua_block {
            ngx.sleep(0.01) -- 10 ms
            ngx.say("foo")
        }
        more_clear_headers Date;
    }

--- request
GET /t
--- response_body_like
received: foo
--- no_error_log
[error]



=== TEST 2: read timeout
--- config
    server_tokens off;
    location /t {
        content_by_lua_block {
            local sock = ngx.socket.tcp()

            sock:settimeouts(150, 150, 2)  -- 2ms read timeout

            local port = ngx.var.server_port
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local req = "GET /foo HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n\r\n"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            while true do
                local line, err, part = sock:receive()
                if line then
                    ngx.say("received: ", line)

                else
                    ngx.say("failed to receive a line: ", err, " [", part, "]")
                    break
                end
            end

            sock:close()
        }
    }

    location /foo {
        content_by_lua_block {
            ngx.sleep(0.01) -- 10 ms
            ngx.say("foo")
        }
        more_clear_headers Date;
    }

--- request
GET /t
--- response_body_like
failed to receive a line: timeout \[\]
--- error_log
lua tcp socket read timed out



=== TEST 3: send ok
--- config
    server_tokens off;
    location /t {
        content_by_lua_block {
            local sock = ngx.socket.tcp()

            sock:settimeouts(500, 500, 500)  -- 500ms timeout

            local port = ngx.var.server_port
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local data = string.rep("a", 8) -- 8 bytes
            local num = 10 -- total: 80 bytes

            local req = "POST /foo HTTP/1.0\r\nHost: localhost\r\nContent-Length: "
                        .. #data * num .. "\r\nConnection: close\r\n\r\n"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            for i = 1, num do
                local bytes, err = sock:send(data)
                if not bytes then
                    ngx.say("failed to send body: ", err)
                    return
                end
            end

            while true do
                local line, err, part = sock:receive()
                if line then
                    ngx.say("received: ", line)

                else
                    ngx.say("failed to receive a line: ", err, " [", part, "]")
                    break
                end
            end

            sock:close()
        }
    }

    location /foo {
        content_by_lua_block {
            local content_length = ngx.req.get_headers()["Content-Length"]

            local sock = ngx.req.socket()

            sock:settimeouts(500, 500, 500)

            local chunk = 8

            for i = 1, content_length, chunk do
                local data, err = sock:receive(chunk)
                if not data then
                    ngx.say("failed to receive chunk: ", err)
                    return
                end
            end

            ngx.say("got len: ", content_length)
        }
    }

--- request
GET /t
--- response_body_like
received: got len: 80
--- no_error_log
[error]



=== TEST 4: send timeout
--- config
    server_tokens off;
    location /t {
        content_by_lua_block {
            local sock = ngx.socket.tcp()

            sock:settimeouts(500, 500, 500)  -- 500ms timeout

            local port = ngx.var.server_port
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local data = "slowdata" -- slow data
            local num = 10

            local req = "POST /foo HTTP/1.0\r\nHost: localhost\r\nContent-Length: "
                        .. #data * num .. "\r\nConnection: close\r\n\r\n"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            for i = 1, num do
                local bytes, err = sock:send(data)
                if not bytes then
                    ngx.say("failed to send body: ", err)
                    return
                end
            end

            while true do
                local line, err, part = sock:receive()
                if line then
                    ngx.say("received: ", line)

                else
                    ngx.say("failed to receive a line: ", err, " [", part, "]")
                    break
                end
            end

            sock:close()
        }
    }

    location /foo {
        content_by_lua_block {
            local content_length = ngx.req.get_headers()["Content-Length"]

            local sock = ngx.req.socket()

            sock:settimeouts(500, 500, 500)

            local chunk = 8

            for i = 1, content_length, chunk do
                local data, err = sock:receive(chunk)
                if not data then
                    ngx.say("failed to receive chunk: ", err)
                    return
                end
            end

            ngx.say("got len: ", content_length)
        }
    }

--- request
GET /t
--- response_body
failed to send body: timeout
--- error_log
lua tcp socket write timed out



=== TEST 5: connection timeout (tcp)
--- config
    resolver $TEST_NGINX_RESOLVER;
    resolver_timeout 3s;
    location /test {
        content_by_lua_block {
            local sock = ngx.socket.tcp()

            sock:settimeouts(100, 100, 100)

            local ok, err = sock:connect("agentzh.org", 12345)
            ngx.say("connect: ", ok, " ", err)

            local bytes
            bytes, err = sock:send("hello")
            ngx.say("send: ", bytes, " ", err)

            local line
            line, err = sock:receive()
            ngx.say("receive: ", line, " ", err)

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        }
    }
--- request
    GET /test
--- response_body
connect: nil timeout
send: nil closed
receive: nil closed
close: nil closed
--- error_log
lua tcp socket connect timed out
--- timeout: 10



=== TEST 6: different timeout with duplex socket (settimeout)
--- config
    server_tokens off;
    location /t {
        content_by_lua_block {
            local sock = ngx.socket.tcp()

            sock:settimeouts(200, 200, 200)  -- 200ms timeout

            local port = ngx.var.server_port
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local data = string.rep("a", 4) -- 4 bytes
            local num = 3

            local req = "POST /foo HTTP/1.0\r\nHost: localhost\r\nContent-Length: "
                        .. #data * num .. "\r\nConnection: close\r\n\r\n"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            for i = 1, num do
                local bytes, err = sock:send(data)
                if not bytes then
                    ngx.log(ngx.ERR, "failed to send body: ", err)
                    return
                end
                ngx.sleep(0.12) -- 120ms
            end

            while true do
                local line, err, part = sock:receive()
                if line then
                    ngx.say("received: ", line)

                else
                    ngx.say("failed to receive a line: ", err, " [", part, "]")
                    break
                end
            end

            sock:close()
        }
    }

    location /foo {
        content_by_lua_block {
            local content_length = ngx.req.get_headers()["Content-Length"]

            local sock = ngx.req.socket(true)

            local chunk = 4

            function read()
                sock:settimeout(200) -- read: 200 ms

                local data, err = sock:receive(content_length)
                if not data then
                    ngx.log(ngx.ERR, "failed to receive data: ", err)
                    return
                end
            end

            local co = ngx.thread.spawn(read)

            sock:settimeout(100) -- send: 100ms
            sock:send("ok\n")

            local ok, err = ngx.thread.wait(co)
            if not ok then
                ngx.log(ngx.ERR, "failed to wait co: ", err)
            end
        }
    }

--- request
GET /t
--- response_body
received: ok
failed to receive a line: closed []
--- error_log
lua tcp socket read timed out
failed to receive data: timeout



=== TEST 7: different timeout with duplex socket (settimeouts)
--- config
    server_tokens off;
    location /t {
        content_by_lua_block {
            local sock = ngx.socket.tcp()

            sock:settimeouts(200, 200, 200)  -- 200ms timeout

            local port = ngx.var.server_port
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local data = string.rep("a", 4) -- 4 bytes
            local num = 3

            local req = "POST /foo HTTP/1.0\r\nHost: localhost\r\nContent-Length: "
                        .. #data * num .. "\r\nConnection: close\r\n\r\n"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            for i = 1, num do
                local bytes, err = sock:send(data)
                if not bytes then
                    ngx.log(ngx.ERR, "failed to send body: ", err)
                    return
                end
                ngx.sleep(0.12) -- 120ms
            end

            while true do
                local line, err, part = sock:receive()
                if line then
                    ngx.say("received: ", line)

                else
                    ngx.say("failed to receive a line: ", err, " [", part, "]")
                    break
                end
            end

            sock:close()
        }
    }

    location /foo {
        content_by_lua_block {
            local content_length = ngx.req.get_headers()["Content-Length"]

            local sock = ngx.req.socket(true)

            sock:settimeouts(0, 100, 200) -- send: 100ms, read: 200ms

            local chunk = 4

            function read()
                local data, err = sock:receive(content_length)
                if not data then
                    ngx.log(ngx.ERR, "failed to receive data: ", err)
                    return
                end
            end

            local co = ngx.thread.spawn(read)

            sock:send("ok\n")

            local ok, err = ngx.thread.wait(co)
            if not ok then
                ngx.log(ngx.ERR, "failed to wait co: ", err)
            end
        }
    }

--- request
GET /t
--- response_body
received: ok
failed to receive a line: closed []
--- no_error_log
[error]



=== TEST 8: settimeouts on ngx.req.socket
--- config
    server_tokens off;
    location = /t {
        #set $port 5000;
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua_block {
            local sock = ngx.socket.tcp()
            local port = ngx.var.port
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local req = "GET /mysock HTTP/1.1\r\nUpgrade: mysock\r\nHost: localhost\r\nConnection: close\r\n\r\nhello"
            -- req = "OK"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            local reader = sock:receiveuntil("\r\n\r\n")
            local data, err, partial = reader()
            if not data then
                ngx.say("no response header found")
                return
            end

            local msg, err = sock:receive()
            if not msg then
                ngx.say("failed to receive: ", err)
                return
            end

            ngx.say("msg: ", msg)

            ok, err = sock:close()
            if not ok then
                ngx.say("failed to close socket: ", err)
                return
            end
        }
    }

    location = /mysock {
        content_by_lua_block {
            ngx.status = 101
            ngx.send_headers()
            ngx.flush(true)
            ngx.req.read_body()
            local sock, err = ngx.req.socket(true)
            if not sock then
                ngx.log(ngx.ERR, "server: failed to get raw req socket: ", err)
                return
            end

            sock:settimeouts(100, 100, 100)

            local data, err = sock:receive(5)
            if not data then
                ngx.log(ngx.ERR, "server: failed to receive: ", err)
                return
            end

            local bytes, err = sock:send("req.socket size: " .. table.maxn(sock) .. "\n")
            if not bytes then
                ngx.log(ngx.ERR, "server: failed to send: ", err)
                return
            end
        }
        more_clear_headers Date;
    }

--- request
GET /t
--- response_body
msg: req.socket size: 1
--- no_error_log
[error]
