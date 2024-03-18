import gleam/erlang/process
import gleam/io
import telnet/server

pub fn main() {
  let assert Ok(_) = server.start(3000)

  io.println("Connect with:")
  io.println("  telnet localhost 3000")

  process.sleep_forever()
}
