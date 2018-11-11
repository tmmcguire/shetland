use "buffered"
use "../../http"

actor Main
  let req: String val =
"GET /wp-content/uploads/2010/03/hello-kitty-darth-vader-pink.jpg HTTP/1.1\r
Host: www.kittyhell.com\r
User-Agent: Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10.6; ja-JP-mac; rv:1.9.2.3) Gecko/20100401 Firefox/3.6.3 Pathtraq/0.9\r
Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8\r
Accept-Language: ja,en-us;q=0.7,en;q=0.3\r
Accept-Encoding: gzip,deflate\r
Accept-Charset: Shift_JIS,utf-8;q=0.7,*;q=0.7\r
Keep-Alive: 115\r
Connection: keep-alive\r
Cookie: wp_ozh_wsa_visits=2; wp_ozh_wsa_visit_lasttime=xxxxxxxxxx; __utma=xxxxxxxxx.xxxxxxxxxx.xxxxxxxxxx.xxxxxxxxxx.xxxxxxxxxx.x; __utmz=xxxxxxxxx.xxxxxxxxxx.x.x.utmccn=(referral)|utmcsr=reader.livedoor.com|utmcct=/reader/|utmcmd=referral\r
\r\n"

  new create(env: Env) =>
    let buffer: Reader = Reader
    let request = req.array()
    var header: (RawHttpRequest|None) = None

    buffer.append(recover req.array().clone() end)
    try
      var i: USize = 0
      while i < 1_000_000 do
        let eoh = HttpParser.end_of_headers(buffer)
        let r = match HttpParser.parse_request(request, header)
        | let r': RawHttpRequest => r'
        | None => error
        end
        header = r
        i = i + 1
      end
    else
      env.err.print("error")
    end
