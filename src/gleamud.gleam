import data/sqlite
import envoy
import gleam/erlang/process
import gleam/io
import repeatedly
import simulation
import telnet/server

pub fn main() {
  let db_str = case envoy.get("DB") {
    Ok(db) -> db
    Error(Nil) -> "./gleamud.db"
  }

  let assert Ok(_) = sqlite.init_schema(db_str)
  let assert Ok(sim_subject) = simulation.start(db_str)
  let assert Ok(_) = server.start(3000, sim_subject)

  let _ =
    repeatedly.call(100, Nil, fn(_state, _i) {
      process.send(sim_subject, simulation.Tick)
    })

  io.println("Connect with:")
  io.println("  telnet localhost 3000")

  process.sleep_forever()
}
