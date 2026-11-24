## A secret: a password, a key, a token. The app gets one from its settings
## (`Config.secret "API_KEY"`) and can only hand it to the platform or compare
## a value with it: there is no way back to text, so a secret can't end up
## in a log, a response or an error message (rule R2). `Str.inspect` and
## `dbg` show `<secret>`.
##
## (In this file the arguments are in Roc's order: punk passes the secret
## last.)
Secret :: { value : Str }.{
    ## A secret made in the program. For tests: a real secret comes from the
    ## settings, not from the source code.
    from_text : Str -> Secret
    from_text = |text| { value: text }

    ## The text is the secret, in punk `Secret.matches token apiKey`. Every
    ## byte is compared, also after the first difference, so the time it
    ## takes tells nothing about where they differ (only whether the lengths
    ## differ).
    matches : Secret, Str -> Bool
    matches = |secret, text| {
        a = Str.to_utf8(secret.value)
        b = Str.to_utf8(text)
        if List.len(a) != List.len(b) {
            False
        } else {
            difference(a, b, 0, 0) == 0
        }
    }

    difference : List(U8), List(U8), U64, U8 -> U8
    difference = |a, b, i, found| match (List.get(a, i), List.get(b, i)) {
        (Ok(x), Ok(y)) => difference(a, b, i + 1, U8.bitwise_or(found, U8.bitwise_xor(x, y)))
        _ => found
    }

    ## What `Str.inspect` and `dbg` show.
    to_inspect : Secret -> Str
    to_inspect = |_| "<secret>"
}
