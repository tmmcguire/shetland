use "debug"
use "net"
use "net/ssl"
use "time"

class _HttpSvrConnection is (TCPConnectionNotify & ALPNProtocolNotify)
  """
  HTTP/1.1 or HTTP/2 (in the future) server incoming connection.
  """
  let _timers:               Timers
  let _notifier:             HttpSvrConnectionNotify ref
  let _read_yield_count:     USize
  let _timeout:              U64
  let _protocol:             HttpProtocol
  var _timer:               (Timer tag | None) = None

  new iso create(
      timers:           Timers,
      notifier:         HttpSvrConnectionNotify iso,
      read_yield_count: USize = 10             /* 10 requests / yield */,
      timeout:          U64   = 10_000_000_000 /* 10 seconds */,
      maximum_size:     USize = 80 * 1024      /* bytes */)
  =>
    _timers               = timers
    _notifier             = consume notifier
    _read_yield_count     = read_yield_count
    _timeout              = timeout
    _protocol             = Http1Protocol(maximum_size)

  fun ref accepted(conn: TCPConnection ref): None val =>
    // Received incoming connection; start the connection timer.
    Debug("accepted")
    conn.set_nodelay(false)
    _set_timer(conn)

  fun ref alpn_negotiated(
    conn: TCPConnection ref,
    protocol: (String | None))
  =>
    // SSL/ALPN protocol negotiation: should identify the protocol to
    // use. Options are HTTP/1.x, HTTP/2, or some kind of failure.
    // In the latter case, make the notification and dispose of the
    // connection.
    _clear_timer()
    Debug("alpn_negotiated")
    match protocol
    | let p: String if p == "http/1.1" => None
    | let p: String if p == "h2" => None
    else
      _notifier.ssl_error(SslAuthFailed)
      conn.dispose()
    end
    _set_timer(conn)

  fun ref auth_failed(conn: TCPConnection ref): None =>
    // SSL is a wonderous and varied thing. I think this would mean
    // client authentication failed. Make a notification and dispose of
    // the connection.
    _notifier.ssl_error(SslAuthFailed)
    conn.dispose()

  fun ref received(
    // Received data from the client. This kicks off the majority of the
    // HTTP protocol processing. This method also resets the connection
    // timer if the connection is persistent. (If not, it will be closed
    // at the end of the response.)
    conn: TCPConnection ref,
    data: Array[U8 val] iso,
    times: USize val)
  : Bool val
  =>
    _clear_timer()
    Debug("received")
    _protocol.received(conn, _notifier, consume data)
    if _protocol.persistent() then _set_timer(conn) end
    times < _read_yield_count

  fun ref sent(
    conn:  TCPConnection ref,
    data: (String val | Array[U8 val] val))
  : (String val | Array[U8 val] val)
  =>
    // The server back-end has sent some data; reset the connection
    // timer if the connection is persistent.
    _clear_timer()
    Debug("sent")
    if _protocol.persistent() then _set_timer(conn) end
    data

  fun ref sentv(
    conn: TCPConnection ref,
    data: ByteSeqIter val)
  : ByteSeqIter val
  =>
    // The server back-end has sent some data; reset the connection
    // timer if the connection is persistent.
    _clear_timer()
    Debug("sentv")
    if _protocol.persistent() then _set_timer(conn) end
    data

  fun ref throttled(conn: TCPConnection ref): None val =>
    _notifier.throttled(conn)

  fun ref unthrottled(conn: TCPConnection ref): None val =>
    _notifier.unthrottled(conn)

  fun ref closed(conn: TCPConnection ref): None val =>
    // Shutdown the connection timer.
    //
    // If the protocol is not idle (i.e. in the process of reading a
    // request), a bad request response is sent.
    Debug("closed")
    if not (_protocol.idle()) then
      _notifier.bad_request(conn)
    end
    _clear_timer()

  // ----------------------------------

  fun ref _set_timer(conn: TCPConnection tag) =>
    let timer = Timer(_ConnectionTimerNotify(conn), _timeout, 0)
    _timer = timer
    _timers(consume timer)

  fun ref _clear_timer() =>
    match _timer
    | let t: Timer tag => _timers.cancel(t)
    end
    _timer = None

  // ----------------------------------

  // Client-only?
  fun ref connect_failed(conn: TCPConnection ref): None val => None
  //   fun ref connecting(conn: TCPConnection ref, count: U32 val): None val => None
  //   fun ref connected(conn: TCPConnection ref): None val => None
  // Not applicable
  //   fun ref expect(conn: TCPConnection ref, qty: USize val): USize val

// ====================================

class _ConnectionTimerNotify is TimerNotify
  """
  Close the connection if no data is transferred for a period of time.
  """

  var _connection: TCPConnection tag

  new iso create(connection: TCPConnection tag) =>
    _connection = connection

  fun ref apply(timer: Timer ref, count: U64): Bool =>
    HttpResponses.request_timeout(_connection)
    false

  fun ref cancel(timer: Timer) =>
    None

// ====================================

interface HttpProtocol
  """
  Generic interface to a HTTP implementation.

  Generic in the sense of HTTP 1.x or HTTP 2.
  """

  fun persistent(): Bool
    """
    Return true if the connection should be held open for future
    requests.
    """

  fun idle(): Bool
    """
    Return true if the parser is not expecting more data for a request.
    """

  fun ref received(
    conn: TCPConnection ref,
    notify: HttpSvrConnectionNotify ref,
    data: Array[U8 val] iso)
  : None
    """
    The server has received data; process it in some useful fashion.
    """
