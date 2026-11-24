//! The database capability: what `Postgres.rows!`, `Postgres.row!` and `Postgres.execute!` of
//! `platforms/server/Postgres.roc` reach. The wiring hands the app a [`Database`] with
//! [`App::with_database`](crate::App::with_database); an app without one gets an error for
//! every query.
//!
//! The SQL comes from the program (punk only takes SQL written in the source, rule P301) and the
//! values come as parameters, so a request can't change what a query does. Real databases are in
//! the crate `punk-server-postgres`.

use std::fmt;

/// A value going to the database as a parameter, or coming back as a cell of a row.
#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Null,
    Text(String),
    Int(i64),
    Float(f64),
    Bool(bool),
    /// A moment in time, as milliseconds since 1970-01-01 UTC (punk's `Posix`): a `timestamptz`.
    Time(i64),
    /// A UUID (punk's `Uuid`), its 16 bytes: a `uuid`.
    Uuid([u8; 16]),
    /// JSON text (punk's `Json.Value`): a `jsonb` or `json`.
    Json(String),
    /// An exact decimal number written as text, `-12.50` (punk's `Dec`): a `numeric`.
    Dec(String),
}

/// Whether the text is a decimal number as punk and Postgres write one: an optional `-`,
/// digits, and maybe a `.` with digits after it.
pub fn is_decimal(text: &str) -> bool {
    let digits = text.strip_prefix('-').unwrap_or(text);
    let (whole, fraction) = match digits.split_once('.') {
        Some((w, f)) => (w, Some(f)),
        None => (digits, None),
    };
    !whole.is_empty()
        && whole.bytes().all(|c| c.is_ascii_digit())
        && fraction.is_none_or(|f| !f.is_empty() && f.bytes().all(|c| c.is_ascii_digit()))
}

/// The 16 bytes of a UUID written as 32 hexadecimal digits, with or without the four `-` of
/// `8-4-4-4-12`, in either case. `None` for anything else.
pub fn parse_uuid(text: &str) -> Option<[u8; 16]> {
    let digits: Vec<u8> = if text.len() == 36 {
        for (i, c) in text.bytes().enumerate() {
            if matches!(i, 8 | 13 | 18 | 23) != (c == b'-') {
                return None;
            }
        }
        text.bytes().filter(|c| *c != b'-').collect()
    } else {
        text.bytes().collect()
    };
    if digits.len() != 32 {
        return None;
    }
    let mut bytes = [0u8; 16];
    for (i, pair) in digits.chunks(2).enumerate() {
        let hex = |c: u8| (c as char).to_digit(16);
        bytes[i] = (hex(pair[0])? * 16 + hex(pair[1])?) as u8;
    }
    Some(bytes)
}

/// A UUID as `8-4-4-4-12` lowercase hexadecimal digits, as Postgres writes it.
pub fn uuid_text(bytes: &[u8; 16]) -> String {
    let mut out = String::with_capacity(36);
    for (i, b) in bytes.iter().enumerate() {
        if matches!(i, 4 | 6 | 8 | 10) {
            out.push('-');
        }
        out.push_str(&format!("{b:02x}"));
    }
    out
}

/// What a query gave: the names of its columns, its rows, and how many rows it changed (for
/// `INSERT`, `UPDATE` and `DELETE`; 0 for a `SELECT`).
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Rows {
    pub columns: Vec<String>,
    pub rows: Vec<Vec<Value>>,
    pub affected: u64,
}

/// Why a query failed. `code` is Postgres's SQLSTATE (`23505` for a unique violation), or one of
/// its connection codes (`08000`) when the database couldn't be reached.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DbError {
    pub code: String,
    pub message: String,
}

impl DbError {
    pub fn new(code: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            code: code.into(),
            message: message.into(),
        }
    }
}

impl fmt::Display for DbError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if self.code.is_empty() {
            write!(f, "database: {}", self.message)
        } else {
            write!(f, "database ({}): {}", self.code, self.message)
        }
    }
}

impl std::error::Error for DbError {}

/// A database the app may run queries on. One app, one database: which one is up to the
/// wiring.
pub trait Database: Send + Sync + 'static {
    /// Runs `sql` with these values for `$1`, `$2`, ...
    fn run(&self, sql: &str, params: &[Value]) -> Result<Rows, DbError>;

    /// Runs `sql` in a transaction that has these settings (`punk.user_id` and its value): what
    /// punk's `Db.runAs! user query` gives, so that the row-level security policies of the tables
    /// see who the user is. A database without settings can only run a query without them.
    fn run_as(
        &self,
        settings: &[(String, String)],
        sql: &str,
        params: &[Value],
    ) -> Result<Rows, DbError> {
        if settings.is_empty() {
            self.run(sql, params)
        } else {
            Err(DbError::new(
                "0A000",
                "this database can't run a query as a user",
            ))
        }
    }

    /// Begins a transaction with these settings (as [`Database::run_as`]): what punk's
    /// `Db.transaction!` and `Db.transactionAs! user` give. The queries of the app run in it until
    /// the host commits it, or drops it, which rolls it back.
    fn begin(&self, settings: &[(String, String)]) -> Result<Box<dyn Transaction>, DbError> {
        let _ = settings;
        Err(DbError::new("0A000", "this database has no transactions"))
    }
}

/// A transaction that [`Database::begin`] began: its queries see each other's changes, and
/// others see them all once it commits, or none when it is dropped without a commit.
pub trait Transaction {
    /// Runs `sql` in the transaction.
    fn run(&mut self, sql: &str, params: &[Value]) -> Result<Rows, DbError>;

    /// Makes the changes of the transaction hold.
    fn commit(self: Box<Self>) -> Result<(), DbError>;
}

impl<T: Database + ?Sized> Database for std::sync::Arc<T> {
    fn run(&self, sql: &str, params: &[Value]) -> Result<Rows, DbError> {
        (**self).run(sql, params)
    }

    fn run_as(
        &self,
        settings: &[(String, String)],
        sql: &str,
        params: &[Value],
    ) -> Result<Rows, DbError> {
        (**self).run_as(settings, sql, params)
    }

    fn begin(&self, settings: &[(String, String)]) -> Result<Box<dyn Transaction>, DbError> {
        (**self).begin(settings)
    }
}

impl<T: Database + ?Sized> Database for Box<T> {
    fn run(&self, sql: &str, params: &[Value]) -> Result<Rows, DbError> {
        (**self).run(sql, params)
    }

    fn run_as(
        &self,
        settings: &[(String, String)],
        sql: &str,
        params: &[Value],
    ) -> Result<Rows, DbError> {
        (**self).run_as(settings, sql, params)
    }

    fn begin(&self, settings: &[(String, String)]) -> Result<Box<dyn Transaction>, DbError> {
        (**self).begin(settings)
    }
}

/// The database of an app the wiring gave none: every query fails.
pub(crate) struct NoDatabase;

impl Database for NoDatabase {
    fn run(&self, _sql: &str, _params: &[Value]) -> Result<Rows, DbError> {
        Err(DbError::new("08000", "this app was given no database"))
    }
}

// --- Through the C ABI ----------------------------------------------------------------------------

/// The kinds of `Sql.Param` and `Row.Cell`.
pub(crate) const NULL: u8 = 0;
pub(crate) const TEXT: u8 = 1;
pub(crate) const INT: u8 = 2;
pub(crate) const FLOAT: u8 = 3;
pub(crate) const BOOL: u8 = 4;
pub(crate) const TIME: u8 = 5;
pub(crate) const UUID: u8 = 6;
pub(crate) const JSON: u8 = 7;
pub(crate) const DEC: u8 = 8;

/// A value as punk writes it in a `Sql.Param`: its kind and its text. `None` when the text
/// doesn't fit the kind (only a bug in `Sql.roc` makes one).
pub(crate) fn from_cell(kind: u8, text: &str) -> Option<Value> {
    Some(match kind {
        NULL => Value::Null,
        TEXT => Value::Text(text.to_owned()),
        INT => Value::Int(text.parse().ok()?),
        FLOAT => Value::Float(text.parse().ok()?),
        BOOL => match text {
            "true" => Value::Bool(true),
            "false" => Value::Bool(false),
            _ => return None,
        },
        TIME => Value::Time(text.parse().ok()?),
        UUID => Value::Uuid(parse_uuid(text)?),
        JSON => Value::Json(text.to_owned()),
        DEC if is_decimal(text) => Value::Dec(text.to_owned()),
        _ => return None,
    })
}

/// A value as a `Row.Cell`: its kind and its text, as `Row.roc` reads them back.
pub(crate) fn to_cell(value: &Value) -> (u8, String) {
    match value {
        Value::Null => (NULL, String::new()),
        Value::Text(s) => (TEXT, s.clone()),
        Value::Int(n) => (INT, n.to_string()),
        Value::Float(x) => (FLOAT, float_text(*x)),
        Value::Bool(b) => (BOOL, if *b { "true" } else { "false" }.to_owned()),
        Value::Time(ms) => (TIME, ms.to_string()),
        Value::Uuid(bytes) => (UUID, uuid_text(bytes)),
        Value::Json(text) => (JSON, text.clone()),
        Value::Dec(text) => (DEC, text.clone()),
    }
}

/// `x` as text Roc's `F64.from_str` reads back exactly.
fn float_text(x: f64) -> String {
    if x.is_nan() {
        "NaN".to_owned()
    } else if x.is_infinite() {
        if x > 0.0 { "inf" } else { "-inf" }.to_owned()
    } else {
        format!("{x:?}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cells_go_back_and_forth() {
        for value in [
            Value::Null,
            Value::Text("tekst met \"quotes\"".into()),
            Value::Int(i64::MIN),
            Value::Float(0.1),
            Value::Float(-2.5e-300),
            Value::Bool(true),
            Value::Bool(false),
            Value::Time(-1),
            Value::Time(1_764_000_000_123),
            Value::Uuid(*b"0123456789abcdef"),
            Value::Json(r#"{"a": [1, null]}"#.into()),
            Value::Dec("-12.50".into()),
            Value::Dec("0".into()),
        ] {
            let (kind, text) = to_cell(&value);
            assert_eq!(from_cell(kind, &text), Some(value));
        }
    }

    #[test]
    fn a_broken_param_is_none() {
        assert_eq!(from_cell(INT, "12a"), None);
        assert_eq!(from_cell(BOOL, "yes"), None);
        assert_eq!(from_cell(9, ""), None);
        assert_eq!(from_cell(UUID, "0190c3a5-7b1e-7cc0-8a3b-2f1e7d6c5b4"), None);
        assert_eq!(
            from_cell(UUID, "0190c3a57-b1e-7cc0-8a3b-2f1e7d6c5b4a"),
            None
        );
        for bad in ["", "-", "1.", ".5", "1e5", "1,5", "+1", "NaN"] {
            assert_eq!(from_cell(DEC, bad), None, "{bad}");
        }
    }

    #[test]
    fn uuids_are_read_in_either_case() {
        let bytes = parse_uuid("0190C3A5-7B1E-7CC0-8A3B-2F1E7D6C5B4A").unwrap();
        assert_eq!(uuid_text(&bytes), "0190c3a5-7b1e-7cc0-8a3b-2f1e7d6c5b4a");
        assert_eq!(parse_uuid("0190c3a57b1e7cc08a3b2f1e7d6c5b4a"), Some(bytes));
    }
}
