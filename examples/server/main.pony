use "format"
use "net"
use "signals"
use "../../http"

actor Main
  new create(env: Env) =>
    try
      let listener = HttpListener(env.root as AmbientAuth, ListenHandler(env.out) where host = "", service = "8080")
      SignalHandler(SigHandler(listener), Sig.hup())
      SignalHandler(SigHandler(listener), Sig.term())
      SignalHandler(SigHandler(listener), Sig.int())
    else
      env.err.print("cannot create TCPListener")
    end

// ====================================

class SigHandler is SignalNotify
  let _listener: HttpListener val
  new iso create(listener: HttpListener val) => _listener = listener
  fun ref apply(count: U32): Bool => _listener.dispose(); true

// ------------------------------------

class iso ListenHandler is HttpListenNotify
  let _out: OutStream

  new iso create(out: OutStream) => _out = out

  fun ref listening(local_address: NetAddress val) =>
    try
      (let host, let port) = local_address.name()?
      _out.print("listening on " + Format(host) + ":" + Format(port))
    else
      _out.print("cannot get local address")
    end

  fun ref not_listening() => _out.print("cannot bind to local address")

  fun ref connected(): HttpRequestNotify iso^ => MyRequestNotify(_out)

// ------------------------------------

class iso MyRequestNotify is HttpRequestNotify
  let _out: OutStream
  var _persistent: Bool = true

  new iso create(out: OutStream) => _out = out

  fun ref request(connection: TCPConnection tag, header: RawHttpRequest iso) =>
    _persistent = header.persistent()
    _out.print("MyRequestNotify received request: " + header.string() + " " + _persistent.string())

  fun ref received(connection: TCPConnection tag, data: Array[U8 val] iso) =>
    _out.print("MyRequestNotify received data: " + data.size().string())

  fun ref eod(connection: TCPConnection tag) =>
    _out.print("MyRequestNotify end of data" + _persistent.string())
    HttpResponses.ok(connection, not _persistent)
