import gleam/bytes_builder
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/option.{type Option, None}
import glisten.{Packet}
import telnet/constants
import simulation
import telnet/game_connection

pub fn start(port: Int, sim_subject: Subject(simulation.Control)) {
  glisten.handler(init(_, sim_subject), handler)
  |> glisten.serve(port)
}

fn init(
  conn,
  sim_subject: Subject(simulation.Control),
) -> #(Subject(game_connection.Message), Option(process.Selector(b))) {
  let parent_subject = process.new_subject()
  let assert Ok(_subject) =
    game_connection.start(parent_subject, sim_subject, conn)
  let assert Ok(tcp_subject) = process.receive(parent_subject, 1000)

  let assert Ok(_) =
    glisten.send(
      conn,
      bytes_builder.concat_bit_arrays([
        constants.char_iac,
        constants.char_will,
        constants.char_echo,
        constants.char_iac,
        constants.char_will,
        constants.char_sga,
        constants.char_iac,
        constants.char_wont,
        constants.char_linemode,
        constants.char_iac,
        constants.char_do,
        constants.char_naws,
      ]),
    )

  #(tcp_subject, None)
}

fn handler(msg, state, _conn) {
  let assert Packet(msg) = msg
  case msg {
    <<255, _:bytes>> -> handle_iac(msg, state)
    _ -> handle_input(msg, state)
  }
  actor.continue(state)
}

fn handle_iac(msg: BitArray, tcp_subject: Subject(game_connection.Message)) {
  // this is gross
  case msg {
    <<
      255,
      253,
      1,
      255,
      253,
      3,
      255,
      251,
      31,
      255,
      250,
      31,
      width,
      width2,
      height,
      height2,
      255,
      240,
    >>
    | <<255, 250, 31, width, width2, height, height2, 255, 240>> -> {
      process.send(
        tcp_subject,
        game_connection.Dimensions(width * 256 + width2, height * 265 + height2),
      )
      Nil
    }
    _ -> Nil
  }
}

import gleam/io
import gleam/bit_array

fn handle_input(msg: BitArray, tcp_subject: Subject(game_connection.Message)) {
  io.debug(bit_array.base16_encode(msg))
  process.send(tcp_subject, game_connection.Data(msg))
}
