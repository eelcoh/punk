## Requests and responses.
Http := [].{
    ## A request, as the platform received it. `path` starts with `/`
    ## (`/links`), `query` is the text after `?` (empty when there is none),
    ## header names are lower case, and `body` holds its bytes (at most 1 MiB).
    Request : {
        method : Str,
        path : Str,
        query : Str,
        headers : List((Str, Str)),
        body : List(U8),
    }

    ## A response. A header name or value the platform can't send (a line
    ## break in it, for instance) or a status outside 100 to 999 turns the
    ## whole response into a 500, so a request can never inject a header.
    Response : {
        status : U16,
        headers : List((Str, Str)),
        body : List(U8),
    }

    ## The method of a request, as a tag, so that a `case` on it can't
    ## misspell one: `Get`, `Post`, ... Any other method is `Other "PURGE"`.
    Method : [Get, Head, Post, Put, Patch, Delete, Options, Other(Str)]

    ## The method of the request, in punk `Http.method req`.
    method : Request -> Method
    method = |req| match req.method {
        "GET" => Get
        "HEAD" => Head
        "POST" => Post
        "PUT" => Put
        "PATCH" => Patch
        "DELETE" => Delete
        "OPTIONS" => Options
        other => Other(other)
    }

    ## The parts of the path of the request, in punk `Http.segments req`:
    ## `/notes/n12` is `["notes", "n12"]` and `/` is `[]`. A slash at the
    ## end makes no difference (`/notes/` is `["notes"]`), and each part is
    ## percent-decoded (`/notes/a%20b` is `["notes", "a b"]`), as Elm's
    ## `Url.Parser` does. A part that doesn't decode to UTF-8 stays as it is.
    segments : Request -> List(Str)
    segments = |req| {
        parts = Str.split_on(req.path, "/")
        without_first = match List.first(parts) {
            Ok(first) if first == "" => List.drop_first(parts, 1)
            _ => parts
        }
        without_last = match List.last(without_first) {
            Ok(last) if last == "" => List.drop_last(without_first, 1)
            _ => without_first
        }
        List.map(without_last, percent_decode)
    }

    ## A request with this method and path, and no headers or body: for an
    ## `expect` on a function that routes requests. In punk
    ## `Http.request Get "/notes/n12"`. A query after `?` goes into `query`.
    request : Str, Method -> Request
    request = |target, how| match Str.split_first(target, "?") {
        Ok({ before, after }) => { method: method_text(how), path: before, query: after, headers: [], body: [] }
        Err(_) => { method: method_text(how), path: target, query: "", headers: [], body: [] }
    }

    method_text : Method -> Str
    method_text = |how| match how {
        Get => "GET"
        Head => "HEAD"
        Post => "POST"
        Put => "PUT"
        Patch => "PATCH"
        Delete => "DELETE"
        Options => "OPTIONS"
        Other(other) => other
    }

    percent_decode : Str -> Str
    percent_decode = |part| {
        bytes = Str.to_utf8(part)
        if List.contains(bytes, 37) {
            match Str.from_utf8(decode_from(bytes, 0, [])) {
                Ok(decoded) => decoded
                Err(_) => part
            }
        } else {
            part
        }
    }

    ## The bytes from index `i` on, with each `%` and two hexadecimal digits
    ## as the byte they stand for; a `%` without them stays a `%`.
    decode_from : List(U8), U64, List(U8) -> List(U8)
    decode_from = |bytes, i, done| match List.get(bytes, i) {
        Err(_) => done
        Ok(byte) if byte == 37 => match (hex_digit(bytes, i + 1), hex_digit(bytes, i + 2)) {
            (Ok(high), Ok(low)) => decode_from(bytes, i + 3, List.append(done, high * 16 + low))
            _ => decode_from(bytes, i + 1, List.append(done, byte))
        }
        Ok(byte) => decode_from(bytes, i + 1, List.append(done, byte))
    }

    hex_digit : List(U8), U64 -> Try(U8, [NotHex])
    hex_digit = |bytes, i| match List.get(bytes, i) {
        Ok(c) if c >= 48 and c <= 57 => Ok(c - 48)
        Ok(c) if c >= 65 and c <= 70 => Ok(c - 55)
        Ok(c) if c >= 97 and c <= 102 => Ok(c - 87)
        _ => Err(NotHex)
    }
}
