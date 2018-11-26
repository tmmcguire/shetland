use "net"

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
  fun ref received(connection: TCPConnection box, data: Array[U8 val] iso)
  fun ref eod(connection: TCPConnection box)
  fun ref throttled(connection: TCPConnection box) => None
  fun ref unthrottled(connection: TCPConnection box) => None

// ====================================

// ------------------------------------
// Important headers

primitive HConnection       fun string(): String => "CONNECTION"
primitive HTransferEncoding fun string(): String => "TRANSFER-ENCODING"
primitive HContentLength    fun string(): String => "CONTENT-LENGTH"

type Header is (HConnection|HTransferEncoding|HContentLength)

// ------------------------------------
// Connection header tokens

primitive CClose     fun string(): String => "CLOSE"
primitive CKeepAlive fun string(): String => "KEEP-ALIVE"

type Connection is (CClose | CKeepAlive)

// ------------------------------------
// Transfer-encoding tokens

primitive TENone     fun string(): String => "NONE"
primitive TEChunked  fun string(): String => "CHUNKED"
primitive TECompress fun string(): String => "COMPRESS"
primitive TEDeflate  fun string(): String => "DEFLATE"
primitive TEGzip     fun string(): String => "GZIP"
primitive TEOther    fun string(): String => "UNKNOWN"

type TransferEncoding is (TENone|TEChunked|TECompress|TEDeflate|TEGzip|TEOther)

// ------------------------------------

interface val Stringish fun string(): String val

