# tests/test_transit.lex — the scheduled-service schedule core (src/transit.lex).
#
# Frequency expansion (incl. the zero-headway guard) and schedule adherence.

import "std.io" as io

import "std.str" as str

import "std.list" as list

import "../src/transit" as transit

fn expect(name :: Str, cond :: Bool) -> Result[Unit, Str] {
  if cond {
    Ok(())
  } else {
    Err(name)
  }
}

# 06:00..07:00 every 15 min -> 06:00, 06:15, 06:30, 06:45, 07:00 = 5 departures.
fn headway_expands() -> Result[Unit, Str] {
  let deps := transit.headway_departures(360.0, 420.0, 15.0)
  expect("15-min headway over the hour = 5 departures", list.len(deps) == 5)
}

fn zero_headway_is_empty() -> Result[Unit, Str] {
  expect("zero headway does not loop", list.is_empty(transit.headway_departures(360.0, 420.0, 0.0)))
}

fn adherence_on_time() -> Result[Unit, Str] {
  expect("1 min late within a 5 min tolerance = on_time", transit.adherence(600.0, 601.0, 1.0, 5.0) == "on_time")
}

fn adherence_early() -> Result[Unit, Str] {
  expect("10 min ahead = early", transit.adherence(600.0, 590.0, 1.0, 5.0) == "early")
}

fn adherence_late() -> Result[Unit, Str] {
  expect("10 min behind = late", transit.adherence(600.0, 610.0, 1.0, 5.0) == "late")
}

fn run_all() -> [io] Unit {
  let results := [headway_expands(), zero_headway_is_empty(), adherence_on_time(), adherence_early(), adherence_late()]
  let failures := list.fold(results, [], fn (acc :: List[Str], r :: Result[Unit, Str]) -> List[Str] {
    match r {
      Ok(_) => acc,
      Err(m) => list.concat(acc, [m]),
    }
  })
  if list.is_empty(failures) {
    ()
  } else {
    let __show := list.fold(failures, (), fn (_a :: Unit, m :: Str) -> [io] Unit {
      io.print(str.concat("FAIL: ", str.concat(m, "\n")))
    })
    let __boom := 1 / 0
    ()
  }
}

