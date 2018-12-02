use "buffered"
use "debug"
use "format"
use "net"
use "time"

primitive _ReadHeader
  """
  Connection state: expecting a HTTP request line, followed by headers.
  """

primitive _ReadData
  """
  Connection state: expecting _state_expect bytes of raw data.
  """

primitive _ReadChunked
  """
  Connection state: expecting a chunk of chunked data.
  """

primitive _ReadChunk
  """
  Connection state: expecting a _state_expect byte chunk of data.
  """

type _ConnectionState is
    (_ReadHeader | _ReadData | _ReadChunked | _ReadChunk)

// ====================================

class _HttpSvrConnection is TCPConnectionNotify
  """
  HTTP 1.1 server incoming connection.

  This class converts the incoming data stream from the client to HTTP
  requests followed by the accompanying data.

  The core of the HTTP 1.x protocol is very simple. Fundamentally,
  it parses an incoming request into a form that can be used by
  further server-side processing steps (here represented by a
  HttpSvrConnectionNotify object), in the process determining whether
  or not the connection can be kept active for future requests. The
  HttpParser class mostly handles the former; the majority of this class
  handles the latter.

  An HTTP request is a block of headers followed by some amount of data
  (or none). In order to determine whether the connection can be reused,
  two pieces of information are needed:

  - Whether the client supports it: this is true for a HTTP 1.0
    request with a "Connection: Keep-Alive" header or HTTP 1.1 without a
    "Connection: Close" header.

  - The end of the request: The end of the request can be found if
    the request has a "Content-Length" header or a Transfer-Encoding of
    "Chunked". Otherwise, the end of the request is marked by the close of
    the connection.
  """
  let _timers:           Timers
  let _notifier:         HttpSvrConnectionNotify ref
  let _read_yield_count: USize
  let _timeout:          U64
  let _buffer:           Reader            = Reader
  var _state:            _ConnectionState  = _ReadHeader
  var _state_expect:     USize             = 0
  var _persistent:       Bool              = true
  var _timer:           (Timer tag | None) = None

  new iso create(
      timers:           Timers,
      notifier:         HttpSvrConnectionNotify iso,
      read_yield_count: USize = 10             /* 10 requests / yield */,
      timeout:          U64   = 10_000_000_000 /* 10 seconds */)
  =>
    _timers           = timers
    _notifier         = consume notifier
    _read_yield_count = read_yield_count
    _timeout          = timeout

  fun ref accepted(conn: TCPConnection ref): None val =>
    _set_timer(conn)

  fun ref closed(conn: TCPConnection ref): None val =>
    if not (_state is _ReadHeader) then
      _notifier.bad_request(conn)
    end
    _clear_timer()

  fun ref received(
    conn: TCPConnection ref,
    data: Array[U8 val] iso,
    times: USize val)
  : Bool val
  =>
    _clear_timer()
    _buffer.append(consume data)
    match _state
    | _ReadHeader       => _read_request(conn)
    | _ReadData         => _read_data(conn)
    | _ReadChunked      => _read_chunked(conn)
    | _ReadChunk        => None
    end
    if _persistent then _set_timer(conn) end
    times < _read_yield_count

  fun ref throttled(conn: TCPConnection ref): None val =>
    _notifier.throttled(conn)

  fun ref unthrottled(conn: TCPConnection ref): None val =>
    _notifier.unthrottled(conn)

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

  fun ref _get_block(size: USize): Array[U8] iso^ =>
    try
      _buffer.block(size)?
    else
      recover Array[U8](0) end
    end

  // ----------------------------------

  // Three possible states for the connection: expecting the request
  // line and headers, reading and forwarding raw data, or reading and
  // forwarding chunked data.

  fun ref _read_request(conn: TCPConnection ref) =>
    let eoh = HttpParser.end_of_headers(_buffer)
    if eoh <= _buffer.size() then
      match HttpParser.parse_request(_get_block(eoh))
      | let r: RawHttpRequest =>
        _persistent = r.persistent()
        // forward request, current data, and change state
        match r.transferEncoding()
        | TENone =>
          _notifier.request(conn, r.clone())
          _state        = _ReadData
          _state_expect = r.contentLength()
          _read_data(conn)
        | TEChunked =>
          _notifier.request(conn, r.clone())
          _state        = _ReadChunked
          _state_expect = 0
          _read_chunked(conn)
        else
          HttpResponses.bad_request(conn)
        end
      | None => HttpResponses.bad_request(conn)
      end
    end

  fun ref _read_data(conn: TCPConnection ref) =>
    let size = _state_expect.min( _buffer.size() )
    if size > 0 then
      /* forward data */
      _notifier.body(conn, _get_block(size))
    end
    if (_state_expect - size) > 0 then
      _state_expect = _state_expect - size
    else
      _state        = _ReadHeader
      _state_expect = 0
      /* forward end-of-data */
      _notifier.end_of_body(conn)
    end

  fun ref _read_chunked(conn: TCPConnection ref) =>
    None

  // ----------------------------------

  // CLient-only?
  fun ref connect_failed(conn: TCPConnection ref): None val => None
  //   fun ref connecting(conn: TCPConnection ref, count: U32 val): None val => None
  //   fun ref connected(conn: TCPConnection ref): None val => None

  // Not applicable
  //   fun ref auth_failed(conn: TCPConnection ref): None val => None
  //   fun ref sent(conn: TCPConnection ref, data: (String val | Array[U8 val] val)): (String val | Array[U8 val] val)
  //   fun ref sentv(conn: TCPConnection ref, data: ByteSeqIter val): ByteSeqIter val
  //   fun ref expect(conn: TCPConnection ref, qty: USize val): USize val

// ====================================

class _ConnectionTimerNotify is TimerNotify
  var _connection: TCPConnection tag

  new iso create(connection: TCPConnection tag) =>
    _connection = connection

  fun ref apply(timer: Timer ref, count: U64): Bool =>
    HttpResponses.request_timeout(_connection)
    false

  fun ref cancel(timer: Timer) =>
    None
