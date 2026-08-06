# transit_agent.lex — an LLM-driven agent persona that operates THIS pack's
# own REST service (transit_http.lex's /transit/* routes).
#
# Same loopback-HTTP pattern as lex-pack-construction/src/construction_agent.lex.
# Transit has no external backend to wrap (no outbound HTTP calls anywhere in
# transit_http.lex) — its mount() IS the domain logic.

import "std.str" as str

import "std.http" as http

import "std.map" as map

import "std.bytes" as bytes

import "lex-schema/json_value" as jv

import "lex-schema/schema" as sch

import "lex-schema/error" as e

import "lex-spec/capability" as cap

import "lex-llm/src/tool" as t

import "lex-agent/src/server" as srv

import "lex-agent/src/agent_card" as card

import "lex-soft/src/runner" as runner

fn http_post_json(url :: Str, body :: Str, tenant :: Str) -> [net] jv.Json {
  let req0 := { method: "POST", url: url, headers: map.new(), body: Some(bytes.from_str(body)), timeout_ms: Some(30000) }
  let req1 := http.with_header(req0, "Content-Type", "application/json")
  let req := if str.is_empty(tenant) {
    req1
  } else {
    http.with_header(req1, "X-Tenant-Id", tenant)
  }
  match http.send(req) {
    Err(_) => JObj([("error", JStr("unreachable")), ("url", JStr(url))]),
    Ok(resp) => match bytes.to_str(resp.body) {
      Err(_) => JObj([("error", JStr("decode error"))]),
      Ok(b) => match jv.parse(b) {
        Err(_) => JStr(b),
        Ok(j) => j,
      },
    },
  }
}

fn http_get_json(url :: Str, tenant :: Str) -> [net] jv.Json {
  let base := { method: "GET", url: url, headers: map.new(), body: None, timeout_ms: Some(30000) }
  let req := if str.is_empty(tenant) {
    base
  } else {
    http.with_header(base, "X-Tenant-Id", tenant)
  }
  match http.send(req) {
    Err(_) => JObj([("error", JStr("unreachable")), ("url", JStr(url))]),
    Ok(resp) => match bytes.to_str(resp.body) {
      Err(_) => JObj([("error", JStr("decode error"))]),
      Ok(body) => match jv.parse(body) {
        Err(_) => JStr(body),
        Ok(j) => j,
      },
    },
  }
}

fn jstr(j :: jv.Json, key :: Str) -> Str {
  match jv.get_field(j, key) {
    Some(JStr(s)) => s,
    _ => "",
  }
}

# ── Capability ────────────────────────────────────────────────────────────────
fn transit_capability() -> cap.Capability {
  cap.inbound("handle", "Operate a scheduled-service (GTFS-style) transit trip: declare trips, list them, look up departures, and check schedule adherence.", { title: "TransitOps", description: "Inbound message for the transit ops agent.", fields: [sch.required_str("text", [])] })
}

# ── Tools (self — this pack's own REST routes, no external backend) ──────────
fn make_transit_tools(self_base_url :: Str) -> List[t.Tool] {
  [t.define("create_trip", "Declare a frequency-based scheduled trip: its route, headsign, and the first/last minute of service plus the headway (minutes between departures).", { title: "CreateTrip", description: "Trip declaration.", fields: [sch.required_str("trip_id", []), sch.required_str("route", []), sch.required_str("headsign", []), sch.required_float("first_min", []), sch.required_float("headway_min", []), sch.required_float("last_min", [])] }, fn (args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
    Ok(http_post_json(str.concat(self_base_url, "/transit/trips"), jv.stringify(args), ""))
  }), t.define("list_trips", "List every scheduled trip.", { title: "ListTrips", description: "No parameters.", fields: [] }, fn (_args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
    Ok(http_get_json(str.concat(self_base_url, "/transit/trips"), ""))
  }), t.define("get_departures", "Expand a trip's frequency schedule into its concrete departure times -- the 'when does it run' query.", { title: "GetDepartures", description: "Trip departures lookup.", fields: [sch.required_str("trip_id", [])] }, fn (args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
    Ok(http_get_json(str.join([self_base_url, "/transit/trips/", jstr(args, "trip_id"), "/departures"], ""), ""))
  }), t.define("check_adherence", "Evaluate a position update against schedule: pass the scheduled minute and the actual minute (plus optional early/late tolerance in minutes, defaults 1.0/5.0) to get an on-time/early/late verdict.", { title: "CheckAdherence", description: "Schedule adherence check.", fields: [sch.required_float("scheduled_min", []), sch.required_float("actual_min", []), sch.optional(sch.required_float("early_tol", [])), sch.optional(sch.required_float("late_tol", []))] }, fn (args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
    Ok(http_post_json(str.concat(self_base_url, "/transit/adherence"), jv.stringify(args), ""))
  })]
}

# ── System prompt ──────────────────────────────────────────────────────────────
fn transit_system_prompt(id :: Str) -> Str {
  str.join(["You are transit ops agent ", id, ". You operate scheduled-service transit trips.", " Use create_trip to declare a new frequency-based service, list_trips to see what's running, get_departures to expand a trip into concrete departure times, and check_adherence to evaluate whether a real position update was on time.", " Be precise about trip_id and minute values, and always name the specific trip you acted on."], "")
}

# ── Agent factory (the persona builder the pack mounts) ────────────────────────
fn make_transit_def(db :: Db, id :: Str, base_url :: Str, self_base_url :: Str, provider_name :: Str, provider_url :: Str, provider_key :: Str, model_name :: Str) -> srv.AgentDef {
  let capability := transit_capability()
  let cfg := { id: id, kind: "transit-ops", system_prompt: transit_system_prompt(id), model_name: model_name, provider_name: provider_name, provider_url: provider_url, provider_key: provider_key, backends: [{ key: "self_url", url: self_base_url }], intent_roles: [], tools: make_transit_tools(self_base_url) }
  let handler := runner.make_handler(db, cfg)
  let c := card.make(id, str.concat("Transit ops agent ", id), "0.1.0", base_url, [capability])
  srv.make_agent_def(c, [{ capability: capability, handle: handler }])
}

