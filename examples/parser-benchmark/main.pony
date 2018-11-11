use "buffered"
use "debug"
use "files"
use "../../http"

actor Main
  let buffer: Reader ref = Reader
  var req: (RawHttpRequest | None) = None
  let mb: USize = 1024 * 1024

  new create(env: Env) =>
    try
      let filename = env.args(1)?
      match OpenFile(FilePath(env.root as AmbientAuth, filename)?)
      | let file: File =>
        while file.errno() is FileOK do
          bufferInput(file, mb)
          if skipEmptyLines() then continue end
          var eoh = HttpParser.end_of_headers(buffer)
          while eoh <= buffer.size() do
            parseRequest(file, eoh)?
            if skipEmptyLines() then break end
            eoh = HttpParser.end_of_headers(buffer)
          end
        end
      else
        env.err.print("error opening file " + filename)
      end
    else
      env.err.print("error reading input file")
    end

  fun ref parseRequest(file: File, eoh: USize) ? =>
    let data = buffer.block(eoh)?
    let r = match HttpParser.parse_request(consume data, req)
    | let r': RawHttpRequest => r'
    | None => error
    end
    req = r
    let transferEncoding = r.transferEncoding()
    let contentLength = r.contentLength()
    match transferEncoding
    | TENone =>
      bufferInput(file, contentLength)
      try buffer.block(contentLength)? end
    | TEChunked => None
    else
      None
    end

  fun ref bufferInput(file: File, length: USize) =>
    while (buffer.size() < length) and (file.errno() is FileOK) do
      buffer.append(file.read(mb))
    end

  fun ref skipEmptyLines(): Bool =>
    try
      var ch = buffer.peek_u8()?
      while (ch == '\r') or (ch == '\n') do
        try buffer.u8()? end
        ch = buffer.peek_u8()?
      end
      false
    else
      true
    end
