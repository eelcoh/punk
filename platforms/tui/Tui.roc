## The keys of a terminal: what `Sub.onKey` gives the app.
##
##     subscriptions = fn _ -> Sub.onKey Pressed
##
##     update = fn msg, model ->
##         case msg of
##             Pressed (Char "j") -> ...
##             Pressed (Ctrl "c") -> (model, Cmd.quit)
##             _ -> (model, Cmd.none)
Tui := [].{
    ## A key. `Char "a"` is a character with shift already applied (`"A"`,
    ## not `"a"` and shift), `Ctrl "c"` and `Alt "x"` a character with that
    ## modifier held.
    Key : [
        Char(Str),
        Ctrl(Str),
        Alt(Str),
        Enter,
        Esc,
        Backspace,
        Delete,
        Tab,
        BackTab,
        Up,
        Down,
        Left,
        Right,
        Home,
        End,
        PageUp,
        PageDown,
        Insert,
        F(I64),
    ]

    ## The key the host describes with these numbers (see `key_to_host` in
    ## `host/src/lib.rs`): `code` 0 is a character in `text`, the others the
    ## keys below; `mods` 1 is ctrl, 2 alt.
    key_from_host : Str, U32, U8 -> Key
    key_from_host = |text, code, mods| match code {
        0 => match mods {
            1 => Ctrl(text)
            2 => Alt(text)
            _ => Char(text)
        }
        1 => Enter
        2 => Esc
        3 => Backspace
        4 => Delete
        5 => Tab
        6 => BackTab
        7 => Up
        8 => Down
        9 => Left
        10 => Right
        11 => Home
        12 => End
        13 => PageUp
        14 => PageDown
        15 => Insert
        n => F((n - 100).to_i64())
    }
}
