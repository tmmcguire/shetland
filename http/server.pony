use "buffered"
use "format"
use "net"
use "signals"
use "time"

type HttpServerAuth is (TCPListenerAuth | AmbientAuth | NetAuth | TCPAuth | TCPListenAuth)

// ====================================

interface HttpSvrListenerNotify
  fun ref listening(local_address: NetAddress val) => None
  fun ref not_listening() => None
  fun ref closed() => None
  fun ref connected(): HttpSvrConnectionNotify iso^

// ====================================

interface HttpSvrConnectionNotify
  fun ref request(connection: TCPConnection box, header: RawHttpRequest iso)
  fun ref body(connection: TCPConnection box, data: Array[U8 val] iso)
  fun ref end_of_body(connection: TCPConnection box)
  fun ref bad_request(connection: TCPConnection box)
  fun ref throttled(connection: TCPConnection box) => None
  fun ref unthrottled(connection: TCPConnection box) => None

// ====================================

class val HttpServer
  let _listener: TCPListener tag

  new val create(
    auth: HttpServerAuth,
    notifier: HttpSvrListenerNotify iso,
    host: String = "",
    service: String = "8080",
    limit: USize = 0                         /* See TCPListener, bytes */,
    init_size: USize = 64                    /* See TCPListener, bytes */,
    max_size: USize = 16384                  /* See TCPListener, bytes */,
    read_yield_count: USize = 10             /* 10 requests / yield */,
    timeout:          U64   = 10_000_000_000 /* 10 seconds */,
    maximum_size:     USize = 80 * 1024      /* Max request header, bytes */)
  =>
    _listener = TCPListener(
      auth,
      _HttpSvrConnectionHandler(
        consume notifier,
        read_yield_count,
        timeout,
        maximum_size
      ),
      host,
      service,
      limit,
      init_size,
      max_size
    )

  fun dispose() => _listener.dispose()

// ====================================

class _HttpSvrConnectionHandler is TCPListenNotify
  let _notifier:             HttpSvrListenerNotify iso
  let _read_yield_count:     USize
  let _timeout:              U64
  let _maximum_request_size: USize
  let _timers:               Timers = Timers()

  new iso create(
      notifier: HttpSvrListenerNotify iso,
      read_yield_count: USize = 10             /* 10 requests / yield */,
      timeout:          U64   = 10_000_000_000 /* 10 seconds */,
      maximum_size:     USize = 80 * 1024      /* bytes */)
  =>
    _notifier             = consume notifier
    _read_yield_count     = read_yield_count
    _timeout              = timeout
    _maximum_request_size = maximum_size

  // Process has bound to a port
  fun ref listening(listen: TCPListener ref): None =>
    _notifier.listening(listen.local_address())

  // Error binding port
  fun ref not_listening(listen: TCPListener ref) =>
    _notifier.not_listening()

  // Listening socket closed?
  fun ref closed(listen: TCPListener ref): None =>
    _notifier.closed()

  // Client connected
  fun ref connected(listen: TCPListener ref): TCPConnectionNotify iso^ =>
    _HttpSvrConnection(
      _timers,
      _notifier.connected(),
      _read_yield_count,
      _timeout,
      _maximum_request_size
    )

