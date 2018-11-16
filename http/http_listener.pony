use "buffered"
use "format"
use "net"
use "signals"
use "time"

class val HttpListener
  let _listener: TCPListener tag

  new val create(
    auth: HttpListenerAuth,
    notifier: HttpListenNotify iso,
    host: String = "",
    service: String = "8080",
    limit: USize = 0,
    init_size: USize = 64,
    max_size: USize = 16384)
  =>
    _listener = TCPListener(
      auth,
      HttpConnectionHandler(consume notifier),
      host,
      service,
      limit,
      init_size,
      max_size
    )

  fun dispose() => _listener.dispose()

// ====================================

class HttpConnectionHandler is TCPListenNotify
  let _notifier: HttpListenNotify iso
  let _timers: Timers = Timers()

  new iso create(notifier: HttpListenNotify iso) =>
    _notifier = consume notifier

  // Process has bound to a port
  fun ref listening(listen: TCPListener ref): None =>
    _notifier.listening(listen.local_address())

  // Error binding port
  fun ref not_listening(listen: TCPListener ref) =>
    _notifier.not_listening()

  // Listening socket closed?
  fun ref closed(listen: TCPListener ref):
    None => _notifier.closed()

  // Client connected
  fun ref connected(listen: TCPListener ref): TCPConnectionNotify iso^ =>
    HttpConnection(_timers, _notifier.connected())
