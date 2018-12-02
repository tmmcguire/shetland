use "buffered"
use "debug"

// Character values
// 0x09  HT  tab
// 0x0a  LF  newline
// 0x0d  CR  carriage return
// 0x20  SP  space

type Text    is Array[U8] val
type Extent  is (USize, USize)
type Extents is (Extent, Extent)

// ------------------------------------

primitive HttpParser

  fun end_of_headers(buffer: Reader): USize =>
    """
    Locate a CR NL CR NL string in the buffer.

    Returns the index of the next location in the buffer (which may
    equal buffer.size()) or greater than the size of the buffer if the
    string is not found.
    """
    let finish = buffer.size()
    var i: USize = 0
    while i < finish do
      match try buffer.peek_u8(i)? else 0 end
      | 0x0d /* CR */ =>
        if     ((i+2) <= finish) and _eoh(buffer, i-2) then return (i + 2)
        elseif ((i+4) <= finish) and _eoh(buffer,   i) then return (i + 4)
        else                                                i = i + 4
        end
      | 0x0a /* LF */ =>
        if     /* i+1 <= finish */   _eoh(buffer, i-3) then return (i + 1)
        elseif ((i+3) <= finish) and _eoh(buffer, i-1) then return (i + 3)
        else                                                i = i + 4
        end
      else
        i = i + 4
      end
    end
    finish + 1

  fun _eoh(buffer: Reader, i: USize): Bool =>
    try buffer.peek_u32_be(i)? == 0x0d0a0d0a else false end

  // ==================================

  fun parse_request(text: Text, req: (RawHttpRequest ref|None) = None): (RawHttpRequest|None) =>
    """
    Parse a HTTP request line and headers.

    Creates a new RawHttpRequest structure if none is passed in; re-uses
    one if it is passed in.
    """
    let finish = text.size()
    // parse method
    var cur = _skip_whitespace(text, (0, finish))
    (let method, cur) = _get_token(text, (cur, finish))
    if _at(text, cur) != 0x20 then
      return None
    end
    // parse uri
    cur = _skip_spaces(text, (cur, finish))
    (let uri, cur) = match _get_uri(text, (cur, finish))
    | (true, let uri': Extent, let cur': USize) => (uri', cur')
    else
      return None
    end
    // parse version
    cur = _skip_spaces(text, (cur, finish))
    (let version, cur) = match _get_version(text, (cur, finish))
    | (true, let version': USize, let cur': USize) => (version', cur')
    else
      return None
    end
    // create/reset request structure
    let request = match req
    | None                  => RawHttpRequest(text, method, uri, version)
    | let r: RawHttpRequest => r.reset(text, method, uri, version)
    end
    // parse headers
    cur = _skip_whitespace(text, (cur, finish))
    while (cur < finish) and (_at(text, cur) != 0x0d) do
      cur = match _parse_header(text, (cur, finish))
      | (true, let header': Extents, let cur': USize) if request._push_header(header') => cur'
      else
        return None
      end
    end
    request

  fun _parse_header(text: Text, extent: Extent): (Bool, Extents, USize) =>
    """
    Parse a HTTP header "line" from text.

    Returns a tuple of (validity, header, next character index), where
    validity is true if a header has been parsed, the header is made of an
    Extent for the header name and another for the value, cur is the index
    of the next character after the end of the header's logical line.

    This handles the deprecated "continuation" lines which begin with 
    spaces or tabs.

    The extent of the value is narrowed to the range between the first
    non-whitespace character and the last non-whitespace characte.
    """
    (let start, let finish) = extent
    // parse field-name
    (let name, var cur) = _get_token(text, (start, finish))
    // parse separator
    if (cur >= finish) or (_at(text, cur) != ':') then
      return (false, ((0,0), (0,0)), 0)
    end
    cur = cur + 1
    // parse field-value
    cur = _skip_spaces(text, (cur, finish))
    let value_start = cur
    // find end of line
    var ch: U8
    repeat
      // handle continuation lines, if necessary
      cur = match _skip_to_newline(text, (cur, finish))
      | (true, let cur': USize) => cur'
      else
        return (false, ((0,0), (0,0)), 0)
      end
      ch = _at(text, cur)
    until (cur >= finish) or (not _is_horiz_space(ch)) end
    // trim ending whitespace
    var last = cur - 2       // one past last character of previous line
    repeat
      last = last - 1
      ch = _at(text, last)
    until (last == start) or not _is_whitespace(ch) end
    (true, (name, (value_start, (last + 1))), cur)

  // ----------------------------------

  fun _is_whitespace(ch: U8): Bool =>
    """
    Return true if ch is in (horizontal tab, carriage return, new line
    (linefeed), space).
    """
    (ch == 0x09) or (ch == 0x0a) or (ch == 0x0d) or (ch == 0x20)

  fun _is_horiz_space(ch: U8): Bool =>
    """
    Return true if ch is a horizontal tab or space.
    """
    (ch == 0x09) or (ch == 0x20)

  fun _is_digit(ch: U8): Bool =>
    """
    Return true if ch is a decimal digit.
    """
    (ch >= 0x30) and (ch <= 0x39)

  fun _is_alpha(ch: U8): Bool =>
    """
    Return true if ch is an upper- or lower-case letter.
    """
    ((ch >= 0x41) and (ch <= 0x5a)) or ((ch >= 0x61) and (ch <= 0x7a))

  fun _is_token_char(ch: U8): Bool =>
    """
    Return true if ch is in the characters allowed for "tokens" in the
    HTTP 1.1 spec.

    token = 1*tchar

    tchar = "!" / "#" / "$" / "%" / "&" / "'" / "*" / "+" / "-" / "." / "^"
                / "_" / "`" / "|" / "~" / DIGIT / ALPHA
    """
    // 0x21 0x23-27 0x2a-2d 0x5e 0x5f 0x60 0x7c 0x7e 0x30-39 0x41-5a 0x61-7a
    (((ch == 0x21) or ((ch >= 0x23) and (ch <= 0x27))) or (((ch >= 0x2a) and (ch <= 0x2d)) or (ch == 0x5e))) or
    ((((ch == 0x5f) or (ch == 0x60)) or ((ch == 0x7c) or (ch == 0x7e))) or (_is_digit(ch) or _is_alpha(ch)))

  fun _is_uri_char(ch: U8): Bool =>
    """
    Return true if ch is in the characters allowed in the request-line URI by the HTTP 1.1 spec and the URI spec.

    Valid URI characters: "!" / "$" / "%" / "&" / "'" / "(" / ")" / "*"
                              / "+" / "," / "-" / "." / "/" / ":" / ";"
                              / "=" / "?" / "@" / "_" / "~" / DIGIT / ALPHA
    """
    // 0x21 0x24-2f 0x3a 0x3b 0x3d 0x3f 0x40 0x5f 0x7e
    (((ch == 0x21) or ((ch >= 0x24) and (ch <= 0x2f))) or (((ch == 0x3a) or
        (ch == 0x3b)) or ((ch == 0x3d) or (ch == 0x3f)))) or
        ((((ch == 0x40) or (ch == 0x5f)) or (ch == 0x7e)) or (_is_digit(ch) or _is_alpha(ch)))

  // ----------------------------------

  fun _at(text: Text, i: USize): U8 =>
    """
    Return the character at location i in text, or 0 if i is not in text.
    """
    try text(i)? else 0 end

  // ----------------------------------

  fun _skip_whitespace(text: Text, extent: Extent): USize =>
    """
    Return location of first non-whitespace character.
    """
    (let start, let finish) = extent
    var i = start
    while (i < finish) and (_is_whitespace(_at(text, i))) do
      i = i + 1
    end
    i

  fun _skip_spaces(text: Text, extent: Extent): USize =>
    """
    Return the location of the first non-horizontal-space character.
    """
    (let start, let finish) = extent
    var i = start
    while (i < finish) and _is_horiz_space(_at(text, i)) do
      i = i + 1
    end
    i

  fun _skip_to_newline(text: Text, extent: Extent): (Bool, USize) =>
    """
    Finds the index of the character after the next CR LF pair or the end of the range.

    Returns a tuple of (validity, next character index).

    Validity is false if a bare CR or LF is found, or if no newline is found.
    """
    (let start, let finish) = extent
    var i = start
    while i < finish do
      match _at(text, i)
      | 0x0d /* CR */ => return if _at(text, i+1) == 0x0a then (true, i+2) else (false, 0) end
      | 0x0a /* LF */ => return if _at(text, i-1) == 0x0d then (true, i+1) else (false, 0) end
      end
      i = i + 2
    end
    (false, 0)

  fun _get_token(text: Text, extent: Extent): (Extent,USize) =>
    """
    Return the extent containing the next token in extent.
    """
    (let start, let finish) = extent
    var i = start
    while (i < finish) and (_is_token_char(_at(text, i))) do
      i = i + 1
    end
    ((start, i), i)

  fun _get_uri(text: Text, extent: Extent): (Bool, Extent, USize) =>
    """
    Get the URI string from the request line.

    Returns a tuple of (validity, URI, next character index).

    Validity is false if the URI extends to the end of the extent or the
    character after the URI is not whitespace.
    """
    (let start, let finish) = extent
    var i = start
    while (i < finish) and (_is_uri_char(_at(text, i))) do
      i = i + 1
    end
    if (i < finish) and _is_whitespace(_at(text, i))
    then (true,  (start, i), i)
    else (false, (0,     0), 0)
    end

  fun _get_version(text: Text, extent: Extent): (Bool, USize, USize) =>
    """
    Get the HTTP minor version number, from the version string.

    Returns a tuple of (validity, version number, next character index).

    Validity is false if the HTTP version string is not found or the
    version number is not a digit.
    """
    // 'HTTP/x.y'
    (let start, let finish) = extent
    if ((finish - start) >= 8)
      and (_at(text, start)   == 'H')
      and (_at(text, start+1) == 'T')
      and (_at(text, start+2) == 'T')
      and (_at(text, start+3) == 'P')
      and (_at(text, start+4) == '/')
      and (_at(text, start+5) == '1')
      and (_at(text, start+6) == '.')
    then
      let digit = _at(text, start+7).usize()
      if (0x30 <= digit) and (digit < 0x3a) then
        return (true, digit - 0x30, start + 8)
      else
        return (false, 0, 0)
      end
    end
    (false, 0, 0)

