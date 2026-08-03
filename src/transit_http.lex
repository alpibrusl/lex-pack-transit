# transit_http.lex — scheduled-service pack (lex-ev-fleet#164): persistence + HTTP.
#
# The pure schedule math lives in transit.lex; this stores frequency-based trips
# and exposes them. A GTFS feed converted to JSON is ingested trip-by-trip; the
# departures endpoint expands the timetable and the adherence endpoint evaluates
# a GTFS-RT-style position update.
#
#   POST /transit/trips { trip_id, route, headsign, first_min, headway_min, last_min }
#   GET  /transit/trips
#   GET  /transit/trips/:id/departures      — expand the timetable
#   POST /transit/adherence { scheduled_min, actual_min, early_tol?, late_tol? }

import "std.str" as str

import "std.list" as list

import "std.int" as int

import "std.sql" as sql

import "lex-schema/json_value" as jv

import "lex-web/router" as router

import "lex-web/ctx" as ctx

import "lex-web/response" as resp

import "lex-soft/src/positions" as pos

import "./transit" as transit

type TripRow = { trip_id :: Str, route :: Str, headsign :: Str, first_min :: Float, headway_min :: Float, last_min :: Float }

fn jstr(j :: jv.Json, key :: Str) -> Str {
  match jv.get_field(j, key) {
    Some(JStr(s)) => s,
    _ => "",
  }
}

fn jnum(j :: jv.Json, key :: Str, default :: Float) -> Float {
  match jv.get_field(j, key) {
    Some(JFloat(f)) => f,
    Some(JInt(n)) => int.to_float(n),
    _ => default,
  }
}

fn trip_to_json(t :: TripRow) -> jv.Json {
  JObj([("trip_id", JStr(t.trip_id)), ("route", JStr(t.route)), ("headsign", JStr(t.headsign)), ("first_min", JFloat(t.first_min)), ("headway_min", JFloat(t.headway_min)), ("last_min", JFloat(t.last_min))])
}

# DOUBLE PRECISION, not REAL: lex's Postgres driver binds PFloat params as
# Rust f64 (float8), which tokio-postgres refuses to serialize against a
# REAL (float4) column — see reference_lex_postgres memory. The ALTERs below
# widen an already-deployed table in place (no-op on SQLite; no-op on
# Postgres once already widened).
fn ensure_tables(db :: Db) -> [sql] Unit {
  let __t := sql.exec(db, "CREATE TABLE IF NOT EXISTS transit_trips (tenant TEXT NOT NULL, trip_id TEXT NOT NULL, route TEXT NOT NULL DEFAULT '', headsign TEXT NOT NULL DEFAULT '', first_min DOUBLE PRECISION NOT NULL DEFAULT 0, headway_min DOUBLE PRECISION NOT NULL DEFAULT 0, last_min DOUBLE PRECISION NOT NULL DEFAULT 0, PRIMARY KEY (tenant, trip_id))", [])
  let __fm := sql.exec(db, "ALTER TABLE transit_trips ALTER COLUMN first_min TYPE DOUBLE PRECISION", [])
  let __hm := sql.exec(db, "ALTER TABLE transit_trips ALTER COLUMN headway_min TYPE DOUBLE PRECISION", [])
  let __lm := sql.exec(db, "ALTER TABLE transit_trips ALTER COLUMN last_min TYPE DOUBLE PRECISION", [])
  ()
}

fn handle_import_trip(c :: ctx.Ctx, db :: Db) -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] resp.Response {
  match jv.parse(c.body) {
    Err(_) => resp.bad_request("{\"error\":\"invalid json\"}"),
    Ok(j) => {
      let trip_id := jstr(j, "trip_id")
      if str.is_empty(trip_id) {
        resp.bad_request("{\"error\":\"trip_id is required\"}")
      } else {
        let tenant := ctx.header_or(c, "X-Tenant-Id", "demo")
        let route := jstr(j, "route")
        let headsign := jstr(j, "headsign")
        let first := jnum(j, "first_min", 0.0)
        let headway := jnum(j, "headway_min", 0.0)
        let last := jnum(j, "last_min", 0.0)
        let stmt := "INSERT INTO transit_trips (tenant, trip_id, route, headsign, first_min, headway_min, last_min) VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT (tenant, trip_id) DO UPDATE SET route = ?, headsign = ?, first_min = ?, headway_min = ?, last_min = ?"
        match sql.exec(db, stmt, [PStr(tenant), PStr(trip_id), PStr(route), PStr(headsign), PFloat(first), PFloat(headway), PFloat(last), PStr(route), PStr(headsign), PFloat(first), PFloat(headway), PFloat(last)]) {
          Err(e) => resp.json_status(500, str.concat("{\"error\":", str.concat(jv.stringify(JStr(e.message)), "}"))),
          Ok(_) => resp.json_status(201, jv.stringify(JObj([("ok", JBool(true)), ("trip_id", JStr(trip_id))]))),
        }
      }
    },
  }
}

fn handle_list_trips(c :: ctx.Ctx, db :: Db) -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] resp.Response {
  let tenant := ctx.header_or(c, "X-Tenant-Id", "demo")
  let rows :: Result[List[TripRow], SqlError] := sql.query(db, "SELECT trip_id, route, headsign, first_min, headway_min, last_min FROM transit_trips WHERE tenant = ? ORDER BY trip_id", [PStr(tenant)])
  match rows {
    Err(e) => resp.json_status(500, str.concat("{\"error\":", str.concat(jv.stringify(JStr(e.message)), "}"))),
    Ok(rs) => resp.json(jv.stringify(JList(list.map(rs, trip_to_json)))),
  }
}

fn handle_departures(c :: ctx.Ctx, db :: Db) -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] resp.Response {
  match ctx.path_param(c, "id") {
    None => resp.bad_request("{\"error\":\"missing trip id\"}"),
    Some(id) => {
      let tenant := ctx.header_or(c, "X-Tenant-Id", "demo")
      let rows :: Result[List[TripRow], SqlError] := sql.query(db, "SELECT trip_id, route, headsign, first_min, headway_min, last_min FROM transit_trips WHERE tenant = ? AND trip_id = ?", [PStr(tenant), PStr(id)])
      match rows {
        Err(e) => resp.json_status(500, str.concat("{\"error\":", str.concat(jv.stringify(JStr(e.message)), "}"))),
        Ok(rs) => match list.head(rs) {
          None => resp.json_status(404, "{\"error\":\"trip not found\"}"),
          Some(t) => resp.json(transit.departures_json(transit.headway_departures(t.first_min, t.last_min, t.headway_min))),
        },
      }
    },
  }
}

fn handle_adherence(c :: ctx.Ctx) -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] resp.Response {
  match jv.parse(c.body) {
    Err(_) => resp.bad_request("{\"error\":\"invalid json\"}"),
    Ok(j) => {
      let scheduled := jnum(j, "scheduled_min", 0.0)
      let actual := jnum(j, "actual_min", 0.0)
      let status := transit.adherence(scheduled, actual, jnum(j, "early_tol", 1.0), jnum(j, "late_tol", 5.0))
      resp.json(transit.adherence_json(scheduled, actual, status))
    },
  }
}

fn mount(r :: router.Router, db :: Db) -> [sql] router.Router {
  let __t := ensure_tables(db)
  let with_import := router.route_effectful(r, "POST", "/transit/trips", fn (c :: ctx.Ctx) -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] resp.Response {
    handle_import_trip(c, db)
  })
  let with_list := router.route_effectful(with_import, "GET", "/transit/trips", fn (c :: ctx.Ctx) -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] resp.Response {
    handle_list_trips(c, db)
  })
  let with_dep := router.route_effectful(with_list, "GET", "/transit/trips/:id/departures", fn (c :: ctx.Ctx) -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] resp.Response {
    handle_departures(c, db)
  })
  router.route_effectful(with_dep, "POST", "/transit/adherence", fn (c :: ctx.Ctx) -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] resp.Response {
    handle_adherence(c)
  })
}

# The domain vocabulary this pack speaks (lex-soft/src/positions). No custody
# chain and no settlement trail — a trip's "evidence" is a GTFS-RT-style
# position update assessed against the timetable, the closest existing pattern
# being capacity_tender's offered-capacity/metered-adherence shape.
fn manifest() -> pos.PackManifest {
  { id: "transit", title: "Scheduled service", tagline: "Frequency-based trips, timetable expansion, and adherence against a GTFS-RT-style position update.", pattern: "capacity_tender", subject: "trip", subject_ref_field: "trip_id", custody_ref_field: "", parties: [{ position: "originator", name: "operator", title: "Operator — declares the scheduled trip", field: "route", required: false }, { position: "executor", name: "vehicle", title: "Vehicle — runs the trip against its timetable", field: "trip_id", required: false }, { position: "observer", name: "rider", title: "Rider — reads departures without acting in the flow", field: "", required: false }], relationships: [{ from: "operator", to: "vehicle", role: "dispatch", label: "the operator's timetable is run by the vehicle" }, { from: "vehicle", to: "rider", role: "reporting", label: "schedule adherence is visible to riders via departures" }], event_kinds: [], evidence_kinds: ["position_update"], settles: false, route_prefix: "/transit" }
}

