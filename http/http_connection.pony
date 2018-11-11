use "buffered"
use "debug"
use "format"
use "net"
use "time"

primitive ReadHeader
primitive ReadChunked

class ReadData
  var size: USize
  new create(size': USize) => size = size'

type ConnectionMode is (ReadHeader | ReadData | ReadChunked)

// ====================================

interface HttpRequestNotify
  fun ref request(connection: TCPConnection tag, header: RawHttpRequest iso)
  fun ref received(connection: TCPConnection tag, data: Array[U8 val] iso)
  fun ref eod(connection: TCPConnection tag)

// ====================================

class HttpConnection is TCPConnectionNotify
  let _timers:           Timers
  let _notifier:         HttpRequestNotify ref
  let _read_yield_count: USize
  let _timeout:          U64
  let _buffer:           Reader            = Reader
  var _state:            ConnectionMode    = ReadHeader
  var _persistent:       Bool              = true
  var _timer:           (Timer tag | None) = None

  new iso create(
      timers:           Timers,
      notifier:         HttpRequestNotify iso,
      read_yield_count: USize = 10             /* 10 requests / yield */,
      timeout:          U64   = 10_000_000_000 /* 10 seconds */)
  =>
    _timers           = timers
    _notifier         = consume notifier
    _read_yield_count = read_yield_count
    _timeout          = timeout
    Debug("connected")

  fun ref accepted(conn: TCPConnection ref): None val =>
    if Platform.debug()
    then
      try
        (let host, let port) = conn.remote_address().name()?
        Debug("accepted connection with " + Format(host) + ":" + Format(port))
      else
        Debug("accepted")
      end
    end
    _set_timer(conn)

  fun ref closed(conn: TCPConnection ref): None val =>
    _clear_timer()
    Debug("closed")

  fun ref received(conn: TCPConnection ref, data: Array[U8 val] iso, times: USize val): Bool val =>
    Debug("received " + Format.int[USize](data.size()))
    _clear_timer()
    _buffer.append(consume data)
    match _state
    | ReadHeader           => _read_headers(conn)
    | let rd: ReadData ref => _read_data(conn, rd)
    else None
    end
    if _persistent then _set_timer(conn) end
    Debug("times < _read_yield_count: " + (times < _read_yield_count).string())
    times < _read_yield_count

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

  fun ref _read_headers(conn: TCPConnection ref) =>
    let eoh = HttpParser.end_of_headers(_buffer)
    if eoh <= _buffer.size() then
      Debug("end of header: " + Format.int[USize](eoh))
      try
        let r = match HttpParser.parse_request(_buffer.block(eoh)?)
        | let r': RawHttpRequest => r'
        | None => error
        end
        Debug("request: " + r.string())
        _persistent = r.persistent()
        let transferEncoding = r.transferEncoding()
        let contentLength = r.contentLength()
        Debug(_persistent.string() + " " + transferEncoding() + " " + contentLength.string())
        /* forward request */
        _notifier.request(conn, r.clone())
        match transferEncoding
        | TENone =>
          let rd = ReadData(contentLength)
          _state = rd
          _read_data(conn, rd)
        | TEChunked => None
        else
          error
        end
      else
        HttpResponses.bad_request(conn)
      end
    end

  fun ref _read_data(conn: TCPConnection ref, rd: ReadData ref) =>
    let size = _buffer.size().min( rd.size )
    if size > 0 then
      try
        /* forward data */
        _notifier.received(conn, _buffer.block(size)?)
      end
    end
    if (rd.size - size) > 0 then
      rd.size = rd.size - size
    else
      _state = ReadHeader
      /* forward end-of-data */
      _notifier.eod(conn)
      // HttpResponses.ok(conn, not _persistent)
    end

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
  //   fun ref throttled(conn: TCPConnection ref): None val => None
  //   fun ref unthrottled(conn: TCPConnection ref): None val => None

// ====================================

class _ConnectionTimerNotify is TimerNotify
  var _connection: TCPConnection tag

  new iso create(connection: TCPConnection tag) => _connection = connection

  fun ref apply(timer: Timer ref, count: U64): Bool =>
    HttpResponses.request_timeout(_connection)
    false

  fun ref cancel(timer: Timer) => Debug("timer cancelled")
