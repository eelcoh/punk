import Clock

## Time, as Elm's `Time`: a `Posix` is a moment, the same everywhere on
## earth, counted in milliseconds since 1970-01-01 UTC. A table column of
## type `Posix` is a `timestamptz` in Postgres.
##
##     type alias Note =
##         { id : Uuid
##         , created : Posix
##         }
##
##     created = Time.now! ()
##     E.string (Time.toIso8601 note.created)    -- "2026-11-24T12:14:20.123Z"
##
## A `Posix` has no order and no arithmetic of its own, as in Elm: compare
## or add with `Time.posixToMillis`. In a query a `Posix` column can be
## compared (`note.created > since`) and sorted on.
Time := [].{
    Posix :: { millis : I64 }.{
        is_eq : Posix, Posix -> Bool
        is_eq = |a, b| a.millis == b.millis

        ## What `Str.inspect` and `dbg` show: the moment in ISO 8601.
        to_inspect : Posix -> Str
        to_inspect = |posix| Time.to_iso8601(posix)
    }

    ## The time now, from the server's clock. In tests it is a clock the
    ## test sets. In punk `Time.now! ()`.
    now! : () => Posix
    now! = || { millis: Clock.now!() }

    ## Milliseconds since 1970-01-01 UTC, in punk `Time.posixToMillis`.
    posix_to_millis : Posix -> I64
    posix_to_millis = |posix| posix.millis

    ## The moment this many milliseconds after 1970-01-01 UTC (before it,
    ## when negative), in punk `Time.millisToPosix`.
    millis_to_posix : I64 -> Posix
    millis_to_posix = |millis| { millis: millis }

    ## The moment as ISO 8601 text in UTC, with milliseconds:
    ## "2026-11-24T12:14:20.123Z". What JSON APIs usually send.
    to_iso8601 : Posix -> Str
    to_iso8601 = |posix| {
        days = I64.div_floor_by(posix.millis, 86_400_000)
        ms_of_day = posix.millis - days * 86_400_000
        (year, month, day) = civil_from_days(days)
        hour = I64.div_trunc_by(ms_of_day, 3_600_000)
        minute = I64.div_trunc_by(I64.rem_by(ms_of_day, 3_600_000), 60_000)
        second = I64.div_trunc_by(I64.rem_by(ms_of_day, 60_000), 1000)
        milli = I64.rem_by(ms_of_day, 1000)
        "${pad(year, 4)}-${pad(month, 2)}-${pad(day, 2)}T${pad(hour, 2)}:${pad(minute, 2)}:${pad(second, 2)}.${pad(milli, 3)}Z"
    }

    ## The moment ISO 8601 text gives, `Nothing` when the text is not one:
    ## a date, `T`, a time with seconds and maybe a fraction of them, and `Z`
    ## or an offset ("2026-11-24T13:14:20+01:00"). In punk
    ## `Time.fromIso8601`.
    from_iso8601 : Str -> [Just(Posix), Nothing]
    from_iso8601 = |text| {
        b = Str.to_utf8(text)
        match parse(b) {
            Ok(millis) => Just({ millis: millis })
            Err(_) => Nothing
        }
    }

    parse : List(U8) -> Try(I64, [Bad])
    parse = |b| {
        year = digits(b, 0, 4)?
        expect_byte(b, 4, '-')?
        month = digits(b, 5, 2)?
        expect_byte(b, 7, '-')?
        day = digits(b, 8, 2)?
        t = byte(b, 10)?
        if t != 'T' and t != 't' and t != ' ' {
            Err(Bad)
        } else {
            hour = digits(b, 11, 2)?
            expect_byte(b, 13, ':')?
            minute = digits(b, 14, 2)?
            expect_byte(b, 16, ':')?
            second = digits(b, 17, 2)?
            (milli, after) = fraction(b, 19)?
            offset = zone(b, after)?
            if month < 1 or month > 12 or day < 1 or day > days_in_month(year, month) or hour > 23 or minute > 59 or second > 59 {
                Err(Bad)
            } else {
                days = days_from_civil(year, month, day)
                Ok(days * 86_400_000 + hour * 3_600_000 + minute * 60_000 + second * 1000 + milli - offset * 60_000)
            }
        }
    }

    ## Milliseconds from a fraction of a second at `i` (".123", or nothing),
    ## and where the text goes on.
    fraction : List(U8), U64 -> Try((I64, U64), [Bad])
    fraction = |b, i| match List.get(b, i) {
        Ok('.') => fraction_digits(b, i + 1, 0, 0)
        Ok(',') => fraction_digits(b, i + 1, 0, 0)
        _ => Ok((0, i))
    }

    fraction_digits : List(U8), U64, U64, I64 -> Try((I64, U64), [Bad])
    fraction_digits = |b, i, n, ms| match List.get(b, i) {
        Ok(c) if c >= '0' and c <= '9' => {
            next = if n < 3 ms * 10 + (c - '0').to_i64() else ms
            fraction_digits(b, i + 1, n + 1, next)
        }
        _ => if n == 0 Err(Bad) else Ok((pad_fraction(ms, n), i))
    }

    pad_fraction : I64, U64 -> I64
    pad_fraction = |ms, n| if n >= 3 ms else pad_fraction(ms * 10, n + 1)

    ## The offset at `i` in minutes east of UTC: `Z` is 0, `+01:00` is 60.
    ## Nothing may follow it.
    zone : List(U8), U64 -> Try(I64, [Bad])
    zone = |b, i| match List.get(b, i) {
        Ok(c) if (c == 'Z' or c == 'z') and List.len(b) == i + 1 => Ok(0)
        Ok(c) if (c == '+' or c == '-') and List.len(b) == i + 6 => {
            hours = digits(b, i + 1, 2)?
            expect_byte(b, i + 3, ':')?
            minutes = digits(b, i + 4, 2)?
            if hours > 23 or minutes > 59 {
                Err(Bad)
            } else {
                sign = if c == '+' 1 else -1
                Ok(sign * (hours * 60 + minutes))
            }
        }
        _ => Err(Bad)
    }

    byte : List(U8), U64 -> Try(U8, [Bad])
    byte = |b, i| match List.get(b, i) {
        Ok(c) => Ok(c)
        Err(_) => Err(Bad)
    }

    expect_byte : List(U8), U64, U8 -> Try({}, [Bad])
    expect_byte = |b, i, want| if byte(b, i)? == want Ok({}) else Err(Bad)

    ## The number written with `n` digits at `i`.
    digits : List(U8), U64, U64 -> Try(I64, [Bad])
    digits = |b, i, n| digits_from(b, i, n, 0)

    digits_from : List(U8), U64, U64, I64 -> Try(I64, [Bad])
    digits_from = |b, i, n, acc|
        if n == 0 {
            Ok(acc)
        } else {
            c = byte(b, i)?
            if c >= '0' and c <= '9' {
                digits_from(b, i + 1, n - 1, acc * 10 + (c - '0').to_i64())
            } else {
                Err(Bad)
            }
        }

    days_in_month : I64, I64 -> I64
    days_in_month = |year, month|
        if month == 2 {
            if I64.mod_by(year, 4) == 0 and (I64.mod_by(year, 100) != 0 or I64.mod_by(year, 400) == 0) 29 else 28
        } else if month == 4 or month == 6 or month == 9 or month == 11 {
            30
        } else {
            31
        }

    ## Days since 1970-01-01 of a date (Howard Hinnant's `days_from_civil`).
    days_from_civil : I64, I64, I64 -> I64
    days_from_civil = |y0, m, d| {
        y = if m <= 2 y0 - 1 else y0
        era = I64.div_floor_by(y, 400)
        yoe = y - era * 400
        mp = if m > 2 m - 3 else m + 9
        doy = I64.div_trunc_by(153 * mp + 2, 5) + d - 1
        doe = yoe * 365 + I64.div_trunc_by(yoe, 4) - I64.div_trunc_by(yoe, 100) + doy
        era * 146_097 + doe - 719_468
    }

    ## The date of a number of days since 1970-01-01.
    civil_from_days : I64 -> (I64, I64, I64)
    civil_from_days = |z0| {
        z = z0 + 719_468
        era = I64.div_floor_by(z, 146_097)
        doe = z - era * 146_097
        yoe = I64.div_trunc_by(doe - I64.div_trunc_by(doe, 1460) + I64.div_trunc_by(doe, 36_524) - I64.div_trunc_by(doe, 146_096), 365)
        doy = doe - (365 * yoe + I64.div_trunc_by(yoe, 4) - I64.div_trunc_by(yoe, 100))
        mp = I64.div_trunc_by(5 * doy + 2, 153)
        d = doy - I64.div_trunc_by(153 * mp + 2, 5) + 1
        m = if mp < 10 mp + 3 else mp - 9
        y = yoe + era * 400
        (if m <= 2 y + 1 else y, m, d)
    }

    ## `n` with zeros in front, to at least `width` digits.
    pad : I64, U64 -> Str
    pad = |n, width| {
        digits_text = n.to_str()
        len = Str.count_utf8_bytes(digits_text)
        if len >= width digits_text else Str.concat(Str.repeat("0", width - len), digits_text)
    }
}
