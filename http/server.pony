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
    limit: USize = 0,
    init_size: USize = 64,
    max_size: USize = 16384)
  =>
    _listener = TCPListener(
      auth,
      _HttpSvrConnectionHandler(consume notifier),
      host,
      service,
      limit,
      init_size,
      max_size
    )

  fun dispose() => _listener.dispose()

// ====================================

class _HttpSvrConnectionHandler is TCPListenNotify
  let _notifier: HttpSvrListenerNotify iso
  let _timers: Timers = Timers()

  new iso create(notifier: HttpSvrListenerNotify iso) =>
    _notifier = consume notifier

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
    _HttpConnection(_timers, _notifier.connected())

