use "debug"
use "net"

primitive HttpResponses

  fun ok(conn: TCPConnection tag, close: Bool): None =>
    Debug("200 Ok " + close.string())
    conn.write("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 4\r\n")
    if close then
      conn.write("Connection: close\r\n")
    else
      conn.write("Connection: keep-alive\r\n")
    end
    conn.write("\r\nOK\r\n")
    if close then
      conn.dispose()
    end

  fun request_too_large(conn: TCPConnection tag) =>
    conn.write("HTTP/1.1 413 Request too larnge\r\nConnection: close\r\n\r\n")
    conn.dispose()

  fun bad_request(conn: TCPConnection tag) =>
    Debug("400 Bad request")
    conn.write("HTTP/1.1 400 Bad requset\r\nConnection: close\r\n\r\n")
    conn.dispose()

  fun request_timeout(conn: TCPConnection tag) =>
    Debug("408 Request timeout")
    conn.write("HTTP/1.1 408 Request timeout\r\nConnection: close\r\n\r\n")
    conn.dispose()

