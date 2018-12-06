use "buffered"
use "debug"
use "net"

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

class Http1Protocol is HttpProtocol
  """
  HTTP 1.x implementation.

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
  let _max_buffer_size:      USize
  var _state:                _ConnectionState  = _ReadHeader
  var _state_expect:         USize             = 0
  let _buffer:               Reader            = Reader
  var _persistent:           Bool              = true

  new create(max_buffer_size: USize) => _max_buffer_size = max_buffer_size

  fun ref received(
    conn:     TCPConnection ref,
    notifier: HttpSvrConnectionNotify ref,
    data:     Array[U8 val] iso)
  =>
    _buffer.append(consume data)
    match _state
    | _ReadHeader       => _read_request(conn, notifier)
    | _ReadData         => _read_data(conn, notifier)
    | _ReadChunked      => _read_chunked(conn, notifier)
    | _ReadChunk        => None
    end

  fun persistent(): Bool => _persistent

  fun idle(): Bool => _state is _ReadHeader

  // ----------------------------------

  // Three possible states for the connection: expecting the request
  // line and headers, reading and forwarding raw data, or reading and
  // forwarding chunked data.

  fun ref _read_request(
    conn:     TCPConnection ref,
    notifier: HttpSvrConnectionNotify ref)
  =>
    let eoh = HttpParser.end_of_headers(_buffer)
    if eoh <= _buffer.size() then
      match HttpParser.parse_request(_get_block(eoh))
      | let r: RawHttpRequest =>
        _persistent = r.persistent()
        // forward request, current data, and change state
        match r.transferEncoding()
        | TENone =>
          notifier.request(conn, r.clone())
          _state        = _ReadData
          _state_expect = r.contentLength()
          _read_data(conn, notifier)
        | TEChunked =>
          notifier.request(conn, r.clone())
          _state        = _ReadChunked
          _state_expect = 0
          _read_chunked(conn, notifier)
        else
          HttpResponses.bad_request(conn)
        end
      | None => HttpResponses.bad_request(conn)
      end
    elseif _buffer.size() > _max_buffer_size then
      HttpResponses.request_too_large(conn)
    end

  fun ref _read_data(
    conn: TCPConnection ref,
    notifier: HttpSvrConnectionNotify ref)
  =>
    let size = _state_expect.min( _buffer.size() )
    if size > 0 then
      /* forward data */
      notifier.body(conn, _get_block(size))
    end
    if (_state_expect - size) > 0 then
      _state_expect = _state_expect - size
    else
      _state        = _ReadHeader
      _state_expect = 0
      /* forward end-of-data */
      notifier.end_of_body(conn)
    end
    Debug("_read_data")

  fun ref _read_chunked(
    conn: TCPConnection ref,
    notifier: HttpSvrConnectionNotify ref)
  =>
    None

  fun ref _get_block(size: USize): Array[U8] iso^ =>
    try
      _buffer.block(size)?
    else
      recover Array[U8](0) end
    end
