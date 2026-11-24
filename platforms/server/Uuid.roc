import Clock
import Random

## A UUID: an id that no other row, server or database has, without asking
## any of them. A table column of type `Uuid` is a `uuid` in Postgres.
##
##     id = Uuid.generate! ()
##     Uuid.toString id                       -- "019ab5c4-1e2f-7a3b-9c4d-5e6f7a8b9c0d"
##     Uuid.fromString "019AB5C4-1E2F-..."    -- Just .., or Nothing
##
## (In this file the arguments are in Roc's order: punk passes the UUID
## last.)
Uuid :: { text : Str }.{
    ## A new UUID (version 7): the time in milliseconds, then 74 random
    ## bits. Ids made later sort later, which keeps a table's index small.
    ## In punk `Uuid.generate! ()`.
    generate! : () => Uuid
    generate! = || {
        millis = Clock.now!().to_u64_wrap()
        a = Random.u64!()
        b = Random.u64!()
        variant = 8 + U64.rem_by(U64.div_trunc_by(a, 4096), 4)
        hex = Str.concat(Str.concat(Str.concat(Str.concat(hex_digits(U64.rem_by(millis, 281_474_976_710_656), 12), "7"), hex_digits(U64.rem_by(a, 4096), 3)), hex_digits(variant, 1)), hex_digits(U64.rem_by(b, 1_152_921_504_606_846_976), 15))
        { text: dashed(hex) }
    }

    ## The UUID as 32 lowercase hexadecimal digits in groups of 8-4-4-4-12,
    ## in punk `Uuid.toString`.
    to_string : Uuid -> Str
    to_string = |uuid| uuid.text

    ## The UUID written in the text: 32 hexadecimal digits, in either case,
    ## with or without the dashes of 8-4-4-4-12. `Nothing` for anything else.
    ## In punk `Uuid.fromString`.
    from_string : Str -> [Just(Uuid), Nothing]
    from_string = |text| {
        bytes = Str.to_utf8(text)
        len = List.len(bytes)
        dashes_fit = len == 36 and List.fold_with_index(bytes, True, |ok, c, i| ok and ((i == 8 or i == 13 or i == 18 or i == 23) == (c == '-')))
        digits = List.keep_if(bytes, |c| c != '-')
        if (len == 32 or dashes_fit) and List.len(digits) == 32 and List.all(digits, is_hex) {
            Just({ text: dashed(Str.from_utf8_lossy(List.map(digits, lower))) })
        } else {
            Nothing
        }
    }

    is_eq : Uuid, Uuid -> Bool
    is_eq = |a, b| a.text == b.text

    to_inspect : Uuid -> Str
    to_inspect = |uuid| uuid.text

    is_hex : U8 -> Bool
    is_hex = |c| (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F')

    lower : U8 -> U8
    lower = |c| if c >= 'A' and c <= 'F' c + 32 else c

    ## 32 digits in groups of 8-4-4-4-12.
    dashed : Str -> Str
    dashed = |hex| {
        b = Str.to_utf8(hex)
        part = |start, n| Str.from_utf8_lossy(List.sublist(b, { start, len: n }))
        Str.join_with([part(0, 8), part(8, 4), part(12, 4), part(16, 4), part(20, 12)], "-")
    }

    ## `n` as `width` hexadecimal digits.
    hex_digits : U64, U64 -> Str
    hex_digits = |n, width| hex_from(n, width, [])

    hex_from : U64, U64, List(U8) -> Str
    hex_from = |n, width, done|
        if width == 0 {
            Str.from_utf8_lossy(done)
        } else {
            d = U64.rem_by(n, 16).to_u8_wrap()
            c = if d < 10 '0' + d else 'a' + d - 10
            hex_from(U64.div_trunc_by(n, 16), width - 1, List.prepend(done, c))
        }
}
