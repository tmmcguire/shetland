use "debug"

// ------------------------------------
// Important headers

primitive HConnection       fun apply(): String => "CONNECTION"
primitive HTransferEncoding fun apply(): String => "TRANSFER-ENCODING"
primitive HContentLength    fun apply(): String => "CONTENT-LENGTH"

type Header is (HConnection|HTransferEncoding|HContentLength)

// ------------------------------------
// Connection header tokens

primitive CClose     fun apply(): String => "CLOSE"
primitive CKeepAlive fun apply(): String => "KEEP-ALIVE"

type Connection is (CClose | CKeepAlive)

// ------------------------------------
// Transfer-encoding tokens

primitive TENone     fun apply(): String => "NONE"
primitive TEChunked  fun apply(): String => "CHUNKED"
primitive TECompress fun apply(): String => "COMPRESS"
primitive TEDeflate  fun apply(): String => "DEFLATE"
primitive TEGzip     fun apply(): String => "GZIP"
primitive TEOther    fun apply(): String => "UNKNOWN"

type TransferEncoding is (TENone|TEChunked|TECompress|TEDeflate|TEGzip|TEOther)

// ------------------------------------

interface val Stringish fun apply(): String

// ------------------------------------

class RawHttpRequest
  var text:               Text
  // Request line
  var method:             Extent
  var uri:                Extent
  var version:            USize
  // Connection
  var _persistent:        Bool
  var _seenConnection:    Bool
  // Transfer-Encoding
  var _transferEncoding:  TransferEncoding
  var _seenTE:            Bool
  // Content-Length
  var _contentLength:     USize
  var _seenContentLength: Bool
  // Headers
  var _headers:           Array[Extents]

  new create(text': Text, method': Extent, uri': Extent, version': USize, hSize: USize = 32) =>
    """
    Create a new RawHttpRequest object based on a given text', method',
    uri', and version'. Space will be allocated by hSize headers.
    """
    text               = text'
    method             = method'
    uri                = uri'
    version            = version'
    _persistent        = version' > 0
    _seenConnection    = false
    _transferEncoding  = TENone
    _seenTE            = false
    _contentLength     = 0
    _seenContentLength = false
    _headers           = Array[Extents](hSize)

  fun ref reset(text': Text, method': Extent, uri': Extent, version': USize): RawHttpRequest =>
    """
    Return an existing RawHttpRequest object to a newly-initialized
    state, based on new text', method', uri', and version'. The existing
    space for headers will be re-used.
    """
    text               = text'
    method             = method'
    uri                = uri'
    version            = version'
    _persistent        = version' > 0
    _seenConnection    = false
    _transferEncoding  = TENone
    _seenTE            = false
    _contentLength     = 0
    _seenContentLength = false
    _headers.clear()
    this

  fun clone(): RawHttpRequest iso^ =>
    """
    Duplicate this RawHttpRequest structure.

    Does not copy the text, but allocates space for the headers.
    """
    let hSize = _headers.size()
    let request = recover RawHttpRequest(text, method, uri, version, hSize) end
    for header in _headers.values() do request._push_header(header) end
    consume request

  fun extent(ext: Extent): Array[U8 val] val =>
    """
    Return the data contained in the Extent ext from text.
    """
    recover text.slice(ext._1, ext._2) end

  fun persistent():       Bool             => _persistent
  fun transferEncoding(): TransferEncoding => _transferEncoding
  fun contentLength():    USize            => _contentLength

  // ----------------------------------

  fun ref _push_header(header: Extents): Bool =>
    """
    Store the header's extents in the RawHttpRequest structure.

    The headers important for the HTTP protocol are handled specially:
    Connection, Transfer-Encoding, and Content-Length.
    
    Returns false if the header processing fails.
    """
    _headers.push(header)
    (let name, let value) = header
    if     _eq_case(name, HConnection)       and (not _handle_connection(value))        then false
    elseif _eq_case(name, HTransferEncoding) and (not _handle_transfer_encoding(value)) then false
    elseif _eq_case(name, HContentLength)    and (not _handle_content_length(value))    then false
    else true
    end

  fun ref _handle_connection(value: Extent): Bool =>
    """
    Set _persistent based on the Connection header.
    
    The default value of _persistent comes from the HTTP version; this
    handles a keep-alive or close token in the header.

    Returns false if the header has been seen before.
    """
    if _seenConnection then return false end
    _seenConnection = true
    (var start, let finish) = value
    while start < finish do
      (let token, start) = HttpParser.get_token(text, (start, finish))
      if     _eq_case(token, CKeepAlive) then _persistent = true
      elseif _eq_case(token, CClose)     then _persistent = false
      end
      start = start + 1
    end
    ifdef debug then
      Debug("Connection " + _persistent.string())
    end
    true

  fun ref _handle_transfer_encoding(value: Extent): Bool =>
    """
    Record the transfer encoding from the Tronsfer-Encoding header.

    Returns false if the header has been seen before.
    """
    if _seenTE then return false end
    _seenTE = true
    (var start, let finish) = value
    while start < finish do
      (let token, start) = HttpParser.get_token(text, (start, finish))
      _transferEncoding = _parse_transfer_encoding(token)
      start = start + 1
    end
    ifdef debug then
      Debug("Transfer-Encoding " + _transferEncoding())
    end
    true

  fun _parse_transfer_encoding(token: Extent): TransferEncoding =>
    """
    Return a TransferEncoding matching the token string.
    """
    if     _eq_case(token, TEChunked)  then TEChunked
    elseif _eq_case(token, TECompress) then TECompress
    elseif _eq_case(token, TEDeflate)  then TEDeflate
    elseif _eq_case(token, TEGzip)     then TEGzip
    else   TEOther
    end

  fun ref _handle_content_length(value: Extent): Bool =>
    """
    Record the content length from the Content-Length header.

    Returns false if the header has been seen before or the value is not
    valid.
    """
    let maxIntrimLength = (USize.max_value() - 10) / 10
    if _seenContentLength then return false end
    _seenContentLength = true
    (var start, let finish) = value
    while start < finish do
      let ch = try text(start)? else 0 end
      if ((ch >= 0x30) and (ch <= 0x39)) and (_contentLength < maxIntrimLength)
      then
        _contentLength = (_contentLength * 10) + (ch.usize() - 0x30)
      else
        return false
      end
      start = start + 1
    end
    ifdef debug then
      Debug("Content-Length " + _contentLength.string())
    end
    true

  // ----------------------------------

  fun _uc(ch: U8): U8 =>
    """
    Returns an uppercase character corresponding to ch.
    """
    if (ch >= 0x61) and (ch <= 0x7a) then ch - 0x20 else ch end

  fun _eq_case(ext: Extent, str: Stringish): Bool =>
    """
    Return true if str equals the Extent ext.

    The comparison is case insensitive, but str must be uppercase.
    """
    (let start, let finish) = ext
    let str' = str()
    let sSize = str'.size()
    if (finish - start) != sSize then
      return false
    end
    var i: USize = 0
    while i < sSize do
      let ch  = try text(start + i)? else 0 end
      let ch' = try str'(i)?         else 1 end
      if _uc(ch) != ch' then return false end
      i = i + 1
    end
    true

  // ----------------------------------

  fun string(): String iso^ =>
    let output = recover String end
    output.append("RawHttpRequest ")
    output.append(extent(method))
    output.append(" ")
    output.append(extent(uri))
    output.append(" ")
    output.append("HTTP/1." + version.string())
    output.append(" ")
    for header in _headers.values() do
      output.append(extent(header._1))
      output.append(": ")
      output.append(extent(header._2))
    output.append(" ")
    end
    consume output

