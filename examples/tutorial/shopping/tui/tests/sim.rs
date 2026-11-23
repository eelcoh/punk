//! The shopping list on ambit's sim: keys in, the screen out as text.

use std::time::UNIX_EPOCH;

use ambit_tui::KeyCode;
use ambit_tui_sim::{Sim, SimClock};
use punk_tui::App;
use shopping::init;

fn start() -> Sim<App> {
    let clock = SimClock::at(UNIX_EPOCH);
    Sim::new(init(clock.clone()), clock, 50, 8)
}

/// Adds an item as a user does: a, the name, Enter.
fn add(sim: &mut Sim<App>, name: &str) {
    sim.key('a').keys(name).key(KeyCode::Enter);
}

/// The lines of the list, inside its frame, without the frame and trailing spaces.
fn items(sim: &Sim<App>) -> Vec<String> {
    sim.screen()
        .lines()
        .filter(|line| line.starts_with('│'))
        .map(|line| line.trim_matches('│').trim_end().to_owned())
        .filter(|line| !line.is_empty())
        .collect()
}

#[test]
fn starts_empty() {
    let sim = start();
    let screen = sim.screen();
    assert!(screen.starts_with("Shopping"), "{screen}");
    assert!(screen.contains("0 to get"), "{screen}");
    assert!(screen.contains("a add"), "{screen}");
    assert!(items(&sim).is_empty());
}

#[test]
fn a_adds_an_item() {
    let mut sim = start();
    sim.key('a').keys("milk");
    assert!(sim.screen().contains("New item: milk"), "{}", sim.screen());
    sim.key(KeyCode::Backspace).keys("k").key(KeyCode::Enter);
    assert_eq!(items(&sim), ["  milk"]);
    assert!(sim.screen().contains("1 to get"));
}

#[test]
fn esc_and_an_empty_name_add_nothing() {
    let mut sim = start();
    sim.key('a').keys("bread").key(KeyCode::Esc);
    sim.key('a').keys("  ").key(KeyCode::Enter);
    assert!(items(&sim).is_empty());
    // Back to browsing: q quits.
    sim.key('q');
    assert!(sim.quit());
}

#[test]
fn space_ticks_off_the_selected_item() {
    let mut sim = start();
    add(&mut sim, "milk");
    add(&mut sim, "bread");
    // The new item is selected; Up goes to milk.
    sim.key(KeyCode::Up).key(' ');
    assert_eq!(items(&sim), ["✓ milk", "  bread"]);
    assert!(sim.screen().contains("1 to get"));
    sim.key(' ');
    assert_eq!(items(&sim), ["  milk", "  bread"]);
}

#[test]
fn d_deletes_the_selected_item() {
    let mut sim = start();
    add(&mut sim, "milk");
    add(&mut sim, "bread");
    add(&mut sim, "eggs");
    sim.key(KeyCode::Up).key('d');
    assert_eq!(items(&sim), ["  milk", "  eggs"]);
    // The selection stays in the list.
    sim.key(KeyCode::Down)
        .key(KeyCode::Down)
        .key('d')
        .key('d')
        .key('d');
    assert!(items(&sim).is_empty());
}

#[test]
fn letters_go_into_the_name_while_adding() {
    let mut sim = start();
    sim.key('a').keys("quads").key(KeyCode::Enter);
    assert!(!sim.quit());
    assert_eq!(items(&sim), ["  quads"]);
}
