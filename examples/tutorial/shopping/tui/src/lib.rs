//! Shopping, compiled from `../Shopping.punk` (see build.rs), as an ambit tui app.

use ambit_caps::Clock;

/// The app. It uses no clock and reads no files, but the platform takes a clock.
pub fn init(clock: impl Clock) -> punk_tui::App {
    punk_tui::App::new(punk_tui::NoFolder, clock)
}
