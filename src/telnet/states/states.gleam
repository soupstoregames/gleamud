import gleam/bit_array
import gleam/erlang/process.{type Subject}
import gleam/option.{type Option, None, Some}
import gleam/string
import simulation
import glisten.{type Connection}
import telnet/render
import gleam/io

pub type State {
  FirstIAC(
    conn: Connection(BitArray),
    dimensions: ClientDimensions,
    directory: Directory,
    buffer: String,
  )
  Menu(
    conn: Connection(BitArray),
    dimensions: ClientDimensions,
    directory: Directory,
    buffer: String,
  )
  InWorld(
    conn: Connection(BitArray),
    dimensions: ClientDimensions,
    directory: Directory,
    buffer: String,
  )
}

pub type ClientDimensions {
  ClientDimensions(width: Int, height: Int)
}

pub type Directory {
  Directory(
    sim_subject: Subject(simulation.Control),
    command_subject: Option(Subject(simulation.Command)),
  )
}

pub fn with_command_subject(
  state: State,
  subject: Subject(simulation.Command),
) -> State {
  case state {
    FirstIAC(_, _, _, _) -> state
    Menu(_, _, _, _) -> state
    InWorld(conn, dim, dir, buffer) ->
      InWorld(
        conn,
        dim,
        Directory(sim_subject: dir.sim_subject, command_subject: Some(subject)),
        buffer,
      )
  }
}

pub fn on_enter(state: State) -> State {
  case state {
    FirstIAC(_, _, _, _) -> state
    Menu(_, _, _, _) -> {
      let assert Ok(_) = render.logo(state.conn)
      let assert Ok(_) = render.menu(state.conn)

      state
    }
    InWorld(_, _, _, _) -> state
  }
}

pub fn handle_input(
  state: State,
  data: BitArray,
) -> #(State, Option(Subject(simulation.Update))) {
  case state {
    FirstIAC(_, _, _, _) -> #(state, None)
    Menu(conn, dim, dir, _) -> {
      let assert Ok(msg) = bit_array.to_string(data)
      case msg {
        "3" -> {
          let update_subject = process.new_subject()
          process.send(
            state.directory.sim_subject,
            simulation.JoinAsGuest(update_subject),
          )
          #(InWorld(conn, dim, dir, ""), Some(update_subject))
        }
        _ -> #(state, None)
      }
    }
    InWorld(conn, dim, dir, buffer) -> {
      case bit_array.byte_size(data) {
        2 -> {
          let assert Ok(msg) = bit_array.to_string(data)
          io.debug(msg)
          #(state, None)
        }
        1 -> {
          case data {
            <<127>> -> {
              case string.length(buffer) {
                0 -> #(state, None)
                _ -> {
                  let assert Ok(_) = render.backspace(state.conn)
                  #(InWorld(conn, dim, dir, string.drop_left(buffer, 1)), None)
                }
              }
            }
            <<n:8>> if n >= 32 && n <= 126 -> {
              let assert Ok(msg) = bit_array.to_string(data)
              let assert Ok(_) = render.print(msg, conn)
              #(InWorld(conn, dim, dir, msg <> buffer), None)
            }
            _ -> #(state, None)
          }
        }
        _ -> #(state, None)
      }
    }
  }
}

pub fn handle_update(state: State, update: simulation.Update) -> State {
  case state {
    FirstIAC(_, _, _, _) -> state
    Menu(_, _, _, _) -> state
    InWorld(_, _, _, buffer) ->
      case update {
        simulation.RoomDescription(region, name, desc) -> {
          let assert Ok(_) =
            render.room_descripion(state.conn, region, name, desc)
          let assert Ok(_) =
            render.prompt(
              buffer
                |> string.reverse,
              state.conn,
            )
          state
        }
        _ -> state
      }
  }
}
