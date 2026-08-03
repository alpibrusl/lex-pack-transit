# tests/test_transit_http.lex — manifest coverage for src/transit_http.lex.
#
# The effectful routes (import, list, departures, adherence) need a live DB to
# exercise meaningfully — that's covered by lex-ev-fleet's own integration
# testing of the mounted deployment.

import "std.list" as list

import "lex-soft/src/positions" as pos

import "../src/transit_http" as transit_http

fn pass() -> Result[Unit, Str] {
  Ok(())
}

fn assert_true(cond :: Bool, label :: Str) -> Result[Unit, Str] {
  if cond {
    pass()
  } else {
    Err(label)
  }
}

fn test_manifest_is_valid() -> Result[Unit, Str] {
  let m := transit_http.manifest()
  assert_true(list.is_empty(pos.validate(m)), "transit's own manifest must satisfy the shared position/pattern validator")
}

fn test_manifest_route_prefix() -> Result[Unit, Str] {
  assert_true(transit_http.manifest().route_prefix == "/transit", "manifest route_prefix must match the mounted routes")
}

fn test_manifest_has_no_custody_chain() -> Result[Unit, Str] {
  assert_true(transit_http.manifest().custody_ref_field == "" and not transit_http.manifest().settles, "a scheduled trip has no custody chain and settles nothing")
}

fn run_all() -> List[Result[Unit, Str]] {
  [test_manifest_is_valid(), test_manifest_route_prefix(), test_manifest_has_no_custody_chain()]
}

