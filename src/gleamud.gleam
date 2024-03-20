import gleam/erlang/process
import gleam/io
import telnet/server
import model/simulation
import repeatedly

pub fn main() {
  let assert Ok(sim_subject) = simulation.start()
  let assert Ok(_) = server.start(3000, sim_subject)

  let _ =
    repeatedly.call(100, Nil, fn(_state, _i) {
      process.send(sim_subject, simulation.Tick)
    })

  io.println("Connect with:")
  io.println("  telnet localhost 3000")

  process.sleep_forever()
}
