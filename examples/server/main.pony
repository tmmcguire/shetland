use "files"
use "format"
use "net"
use "net/ssl"
use "signals"
use "../../http"

actor Main
  new create(env: Env) =>
    try
      let auth   = env.root as AmbientAuth
      let sslCtx = recover
        SSLContext
          // .>set_authority(FilePath(auth, "./examples/net/cert.pem")?)?
          .>set_cert(
            FilePath(auth, "./examples/server/cert.pem")?,
            FilePath(auth, "./examples/server/key.pem")?
          )?
      end
      env.out.print("created ssl context")
      let listener = HttpServer(
        auth,
        ListenHandler(env.out)
        where
          sslCtx  = consume sslCtx,
          host    = "",
          service = "8080"
      )
      SignalHandler(SigHandler(listener), Sig.hup())
      SignalHandler(SigHandler(listener), Sig.term())
      SignalHandler(SigHandler(listener), Sig.int())
    else
      env.err.print("cannot create TCPListener")
    end

// ====================================

class SigHandler is SignalNotify
  let _listener: HttpServer val
  new iso create(listener: HttpServer val) => _listener = listener
  fun ref apply(count: U32): Bool => _listener.dispose(); true

// ------------------------------------

class iso ListenHandler is HttpSvrListenerNotify
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

  fun ref connected(): HttpSvrConnectionNotify iso^ => MyRequestNotify(_out)

// ------------------------------------

class iso MyRequestNotify is HttpSvrConnectionNotify
  let _out: OutStream
  var _persistent: Bool = true

  new iso create(out: OutStream) => _out = out

  fun ref request(connection: TCPConnection tag, header: RawHttpRequest iso) =>
    _persistent = header.persistent()
    _out.print("MyRequestNotify received request: " + header.string() + " " + _persistent.string())

  fun ref body(connection: TCPConnection tag, data: Array[U8 val] iso) =>
    _out.print("MyRequestNotify received data: " + data.size().string())

  fun ref end_of_body(connection: TCPConnection tag) =>
    _out.print("MyRequestNotify end of data" + _persistent.string())
    HttpResponses.ok(connection, not _persistent)

  fun ref bad_request(connection: TCPConnection tag) =>
    _out.print("MyRequestNotify bad request")
    HttpResponses.bad_request(connection)
