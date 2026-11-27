#!/usr/bin/env python3
"""Log every HTTP exchange, so the network side of the port is observable.

The app talks to two servers: a business server over HTTP(S) for accounts, config,
features and billing, and the game server over TCP for matches. Nothing in the port could
say which requests leave the device or what came back, so three claims in
`01_port/PARITY_INVENTORY.md` sat at "presence only": analytics delivery, the `/client/config`
answer, and whether `/client/transfer-legacy-inventory` is ever called.

This patch writes one line per request and one per response to `$HOME/net.log` when
`BIM_NETLOG` is set:

    -> POST /client/authenticate
    <- 200 /client/authenticate

**Never the body, and never the query string.** A first version of this seam logged both, and a
copy of its output reached the repository carrying the session token and device id from
`/client/authenticate`. Endpoint paths and status codes answer "did the request happen and what
came back"; bodies answer that too, and also leak credentials into files people commit.

The seam sits at `iscool::http::detail::process_response`, the single point every response
passes through, and at the two `send_*_request` functions. A request with no matching
response line is a request that never came back - which is exactly what a hanging config
fetch looks like from the app's side.

Guarded by `BIM_TEST_SEAMS`, so it is compiled out of device builds like every other seam.
Idempotent: running it twice is a no-op.
"""

import pathlib
import sys

root = pathlib.Path(sys.argv[1])
send = root / "modules/core/http/module/src/iscool/http/send.cpp"

text = send.read_text()

if "net_endpoint" in text:
    print("   net log: already patched")
    sys.exit(0)

helper = '''#include <iscool/http/request.hpp>

#if BIM_TEST_SEAMS
#include <cstdio>
#include <cstdlib>
#include <string>

namespace iscool::http::detail
{
  inline std::string net_endpoint(const std::string& url)
  {
    std::string result(url);
    const std::size_t scheme = result.find("://");

    if (scheme != std::string::npos)
      result.erase(0, scheme + 3);

    const std::size_t path = result.find('/');
    result = path == std::string::npos ? std::string("/") : result.substr(path);

    const std::size_t query = result.find('?');

    if (query != std::string::npos)
      result.erase(query);

    return result;
  }

  inline void net_log_body(const char* direction, const request& r, int status)
  {
    if (std::getenv("BIM_NETLOG") == nullptr)
      return;

    const char* const home = std::getenv("HOME");
    const std::string file(std::string(home != nullptr ? home : ".") + "/net.log");
    FILE* const f = std::fopen(file.c_str(), "a");

    if (f == nullptr)
      return;

    const char* const method =
        r.request_type == request::type::get ? "GET" : "POST";

    const std::string endpoint(net_endpoint(r.url));

    if (status < 0)
      std::fprintf(f, "-> %s %s\\n", method, endpoint.c_str());
    else
      std::fprintf(f, "<- %d %s %s\\n", status, method, endpoint.c_str());

    std::fclose(f);
  }
}
#endif
'''

anchor_include = "#include <iscool/http/request.hpp>\n"
assert anchor_include in text
text = text.replace(anchor_include, helper, 1)

anchor_get = "  r->request_type = request::type::get;\n"
assert anchor_get in text
text = text.replace(
    anchor_get,
    anchor_get
    + """
#if BIM_TEST_SEAMS
  detail::net_log_body("send", *r, -1);
#endif
""",
    1,
)

anchor_post = "  r->request_type = request::type::post;\n"
assert anchor_post in text
text = text.replace(
    anchor_post,
    anchor_post
    + """
#if BIM_TEST_SEAMS
  detail::net_log_body("send", *r, -1);
#endif
""",
    1,
)

anchor_response = """  request_handler& handler = g_handler_pool.get(handler_index);

  if (r.status == 200)"""
assert anchor_response in text
text = text.replace(
    anchor_response,
    """  request_handler& handler = g_handler_pool.get(handler_index);

#if BIM_TEST_SEAMS
  detail::net_log_body("recv", handler.request, static_cast<int>(r.status));
#endif

  if (r.status == 200)""",
    1,
)

send.write_text(text)
print("   net log: patched iscool::http")
