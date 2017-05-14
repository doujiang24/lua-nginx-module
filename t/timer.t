# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(1);

plan tests => repeat_each() * (blocks() * 4);

#no_diff();
no_long_string();

our $HtmlDir = html_dir;

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;
$ENV{TEST_NGINX_HTML_DIR} = $HtmlDir;

worker_connections(1024);
run_tests();

__DATA__

=== TEST 1: lua_code_cache off
--- http_config
    lua_code_cache off;
--- config
    location /t {
        content_by_lua_block {
            local function f()
                -- do nothing
            end

            local ok, err = ngx.timer.at(1, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]
[crit]
