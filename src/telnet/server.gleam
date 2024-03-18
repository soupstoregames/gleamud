import gleam/bytes_builder
import gleam/bit_array.{to_string}
import gleam/erlang/process
import gleam/otp/actor
import gleam/option.{type Option, None}
import glisten.{type Connection, Packet}
import telnet/constants
import telnet/states/states
import telnet/states/menu

pub fn start(port: Int) {
  glisten.handler(init, handler)
  |> glisten.serve(port)
}

fn init(conn) -> #(states.State, Option(process.Selector(b))) {
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

  #(states.FirstIAC(states.ClientDimensions(width: 80, height: 24)), None)
}

fn handler(msg, state, conn) {
  let assert Packet(msg) = msg
  actor.continue(case msg {
    <<255, _:bytes>> -> handle_iac(msg, state, conn)
    _ -> handle_input(msg, state, conn)
  })
}

fn handle_iac(
  msg: BitArray,
  state: states.State,
  conn: Connection(_),
) -> states.State {
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
    | <<255, 250, 31, width, width2, height, height2, 255, 240>> ->
      case state {
        states.FirstIAC(_) ->
          states.Menu(client_dimensions: states.ClientDimensions(width*256 + width2, height*256 + height2))
          |> menu.on_enter(conn)
        states.Menu(_) ->
          states.Menu(client_dimensions: states.ClientDimensions(width*256 + width2, height*256 + height2))
      }
    _ -> state
  }
}

fn handle_input(
  msg: BitArray,
  state: states.State,
  conn: Connection(_),
) -> states.State {
  case to_string(msg) {
    Ok(str) ->
      case state {
        states.FirstIAC(_) -> state
        states.Menu(_) -> menu.handle_input(state, conn, str)
      }
    Error(_) -> state
  }
}
