#!/bin/sh
# Fixed connection-test response. No proxying, file access, or uploads.
case "${HTTP_HOST:-}" in
  ctest.p01.ctest.srv.nintendo.net|ctest-ipv6.p01.ctest.srv.nintendo.net|ctest.cdn.nintendo.net|conntest.nintendowifi.net) ;;
  *) printf 'Status: 404 Not Found\r\nContent-Length: 0\r\n\r\n'; exit 0 ;;
esac
if [ "${REQUEST_METHOD:-}" != GET ] || [ "${REQUEST_URI:-}" != / ]; then
  printf 'Status: 404 Not Found\r\nContent-Length: 0\r\n\r\n'
  exit 0
fi
logger -t swfence "Connection test from ${REMOTE_ADDR:-unknown} for ${HTTP_HOST}"
printf 'Status: 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 2\r\nX-Organization: Nintendo\r\nCache-Control: no-cache, no-store\r\nPragma: no-cache\r\n\r\nok'
