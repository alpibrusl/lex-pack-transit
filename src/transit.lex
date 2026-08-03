# transit.lex — scheduled-service schedule core (lex-ev-fleet#164), pure.
#
# A fixed bus route runs a timetabled service. Rather than the full GTFS
# route/stop/stop_times explosion, this v0 uses the GTFS `frequencies` model: a
# trip runs every `headway_min` from `first_min` to `last_min` (minutes from
# midnight). This module expands that into departure times and evaluates schedule
# adherence (the heart of a GTFS-RT trip update). Pure — no I/O — so it unit-tests
# directly; the persistence + HTTP live in transit_http.lex.

import "std.list" as list

import "lex-schema/json_value" as jv

fn departures_go(t :: Float, last :: Float, headway :: Float, acc :: List[Float], guard :: Int) -> List[Float] {
  if guard <= 0 or t > last or headway <= 0.0 {
    list.reverse(acc)
  } else {
    departures_go(t + headway, last, headway, list.concat([t], acc), guard - 1)
  }
}

# Expand a frequency-based service into departure times (minutes from midnight).
# guard caps the expansion so a zero/tiny headway can't loop.
fn headway_departures(first_min :: Float, last_min :: Float, headway_min :: Float) -> List[Float] {
  departures_go(first_min, last_min, headway_min, [], 2000)
}

# Schedule adherence for a GTFS-RT-style update: early if the vehicle is more than
# `early_tol` ahead, late if more than `late_tol` behind, else on_time.
fn adherence(scheduled_min :: Float, actual_min :: Float, early_tol :: Float, late_tol :: Float) -> Str {
  if actual_min < scheduled_min - early_tol {
    "early"
  } else {
    if actual_min > scheduled_min + late_tol {
      "late"
    } else {
      "on_time"
    }
  }
}

fn departures_json(deps :: List[Float]) -> Str {
  jv.stringify(JObj([("count", JInt(list.len(deps))), ("departures_min", JList(list.map(deps, fn (d :: Float) -> jv.Json {
    JFloat(d)
  })))]))
}

fn adherence_json(scheduled_min :: Float, actual_min :: Float, status :: Str) -> Str {
  jv.stringify(JObj([("scheduled_min", JFloat(scheduled_min)), ("actual_min", JFloat(actual_min)), ("delay_min", JFloat(actual_min - scheduled_min)), ("status", JStr(status))]))
}

