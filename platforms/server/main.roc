platform ""
    requires {
        [Settings : settings] for main : {
            settings : Config.Decoder(settings),
            handle! : settings, Http.Request => Http.Response,
        }
    }
    exposes [Http, Clock, Random, Kv, Config, Secret, Time, Uuid, Log, Postgres, Sql, Row, Db, Mongo, Bson, Doc, Filter, Update]
    packages {}
    provides {
        "roc_check_settings": check_settings_for_host!,
        "roc_handle": handle_for_host!,
    }
    hosted {
        "roc_clock_now": Clock.now!,
        "roc_config_settings": Config.settings_host!,
        "roc_kv_delete": Kv.delete!,
        "roc_kv_get": Kv.get_host!,
        "roc_kv_put": Kv.put!,
        "roc_log_error": Log.error!,
        "roc_log_info": Log.info!,
        "roc_log_warn": Log.warn!,
        "roc_mongo_run": Mongo.run_host!,
        "roc_pg_begin": Postgres.begin_host!,
        "roc_pg_commit": Postgres.commit_host!,
        "roc_pg_rollback": Postgres.rollback_host!,
        "roc_pg_run": Postgres.run_host!,
        "roc_random_u64": Random.u64!,
    }
    targets: {
        inputs_dir: "targets/",
        x64glibc: { inputs: [app], output: Archive },
        arm64glibc: { inputs: [app], output: Archive },
        x64musl: { inputs: [app], output: Archive },
        arm64musl: { inputs: [app], output: Archive },
        x64mac: { inputs: [app], output: Archive },
        arm64mac: { inputs: [app], output: Archive },
        x64v1elf: { inputs: [app], output: Archive },
    }

import Http
import Clock
import Config
import Db
import Kv
import Log
import Mongo
import Bson
import Doc
import Filter
import Update
import Postgres
import Random
import Row
import Secret
import Sql
import Time
import Uuid

## Called by the host once, when the server starts: the app's settings
## decoder on the settings the wiring gives. Empty when they fit; otherwise
## one line for each setting that is missing or wrong, and the host doesn't
## start.
check_settings_for_host! : {} => Str
check_settings_for_host! = |{}|
    match Config.decode(Config.settings_host!(), main.settings) {
        Ok(_) => ""
        Err(problems) => problems
    }

## Called by the host for each request, with the request in pieces that are
## easy to hand over through the C ABI. The settings are decoded again, for
## this request only: a value of the app's type is never shared between the
## host's threads. They fit, since the host checked them at the start.
handle_for_host! : Str, Str, Str, List((Str, Str)), List(U8) => Http.Response
handle_for_host! = |method, path, query, headers, body|
    match Config.decode(Config.settings_host!(), main.settings) {
        Ok(settings) => (main.handle!)(settings, { method, path, query, headers, body })
        Err(_) => { status: 500, headers: [], body: Str.to_utf8("bad settings\n") }
    }
