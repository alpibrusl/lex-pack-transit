# tests/test_transit_agent.lex — pure-logic coverage for src/transit_agent.lex.
#
# lex test discards run_all's return value and only checks whether the call
# raises a runtime error -- see lex-ag-ui's README for the full writeup.
# This file forces a real runtime error when count_failures(...) > 0 so
# lex test/lex ci are real gates here.

import "std.list" as list

import "lex-schema/json_value" as jv

import "lex-schema/schema" as sch

import "lex-llm/src/tool" as t

import "../src/transit_agent" as agent

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

fn schema_of(name :: Str) -> Option[sch.ModelSchema] {
  match t.find_by_name(agent.make_transit_tools("http://127.0.0.1:8100"), name) {
    None => None,
    Some(tool) => Some(tool.params),
  }
}

fn test_four_tools_defined() -> Result[Unit, Str] {
  assert_true(list.len(agent.make_transit_tools("http://127.0.0.1:8100")) == 4, "transit has exactly 4 REST routes today, so exactly 4 tools should be defined")
}

fn test_create_trip_schema_accepts_documented_shape() -> Result[Unit, Str] {
  let sample := JObj([("trip_id", JStr("T1")), ("route", JStr("42")), ("headsign", JStr("Downtown")), ("first_min", JFloat(360.0)), ("headway_min", JFloat(15.0)), ("last_min", JFloat(1320.0))])
  match schema_of("create_trip") {
    None => Err("create_trip tool must be defined"),
    Some(schema) => match sch.validate(schema, sample) {
      Err(_) => Err("create_trip's schema must accept transit_http.lex's documented POST /transit/trips body"),
      Ok(_) => pass(),
    },
  }
}

fn test_get_departures_schema_requires_trip_id() -> Result[Unit, Str] {
  match schema_of("get_departures") {
    None => Err("get_departures tool must be defined"),
    Some(schema) => match sch.validate(schema, JObj([])) {
      Err(_) => pass(),
      Ok(_) => Err("get_departures's schema must require trip_id"),
    },
  }
}

fn test_check_adherence_schema_accepts_without_tolerances() -> Result[Unit, Str] {
  let sample := JObj([("scheduled_min", JFloat(420.0)), ("actual_min", JFloat(424.0))])
  match schema_of("check_adherence") {
    None => Err("check_adherence tool must be defined"),
    Some(schema) => match sch.validate(schema, sample) {
      Err(_) => Err("check_adherence's early_tol/late_tol must be optional -- the route defaults them"),
      Ok(_) => pass(),
    },
  }
}

fn test_list_trips_schema_has_no_fields() -> Result[Unit, Str] {
  match schema_of("list_trips") {
    None => Err("list_trips tool must be defined"),
    Some(schema) => assert_true(list.is_empty(schema.fields), "list_trips takes no parameters"),
  }
}

fn suite_pure() -> List[Result[Unit, Str]] {
  [test_four_tools_defined(), test_create_trip_schema_accepts_documented_shape(), test_get_departures_schema_requires_trip_id(), test_check_adherence_schema_accepts_without_tolerances(), test_list_trips_schema_has_no_fields()]
}

fn count_failures(results :: List[Result[Unit, Str]]) -> Int {
  list.fold(results, 0, fn (acc :: Int, r :: Result[Unit, Str]) -> Int {
    match r {
      Ok(_) => acc,
      Err(_) => acc + 1,
    }
  })
}

fn run_all() -> Int {
  let failures := count_failures(suite_pure())
  let _crash_if_failed := if failures > 0 {
    1 / 0
  } else {
    0
  }
  failures
}

