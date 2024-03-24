import gleam/bit_array
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import simulation
import glisten.{type Connection}
import glisten/transport
import telnet/render

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
  RoomSay(
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
    RoomSay(conn, dim, dir, buffer) ->
      RoomSay(
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
    Menu(_, dim, _, _) -> {
      let assert Ok(_) = render.logo(dim.width, state.conn)
      let assert Ok(_) = render.menu(dim.width, state.conn)

      state
    }
    InWorld(_, _, _, _) -> state
    RoomSay(_, _, _, _) -> {
      let assert Ok(_) = render.erase_line(state.dimensions.width, state.conn)
      let assert Ok(_) = render.prompt_say("", state.conn)
      state
    }
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
        <<13:8, 0:8>> -> {
          let assert Some(command_subject) = state.directory.command_subject
          case string.reverse(string.trim(state.buffer)) {
            "say!" -> {
              #(
                RoomSay(conn, dim, dir, "")
                  |> on_enter,
                None,
              )
            }
            _ as str -> {
              let assert Ok(_) = render.println("", conn)
              case parse_command(str) {
                Ok(simulation.CommandQuit as com) -> {
                  let assert Ok(_) =
                    transport.close(state.conn.transport, state.conn.socket)
                  process.send(command_subject, com)
                  Nil
                }
                Ok(com) -> {
                  process.send(command_subject, com)
                }
                Error(UnknownCommand) -> {
                  let assert Ok(_) = render.error("Huh?", state.conn)
                  let assert Ok(_) = render.prompt("", conn)
                  Nil
                }
                Error(SayWhat) -> {
                  let assert Ok(_) = render.error("Say what?", state.conn)
                  let assert Ok(_) = render.prompt("", conn)
                  Nil
                }
              }
              #(InWorld(conn, dim, dir, ""), None)
            }
          }
        }
        <<n:8>> if n >= 32 && n <= 126 -> {
          let assert Ok(msg) = bit_array.to_string(data)
          let assert Ok(_) = render.print(msg, conn)
          #(InWorld(conn, dim, dir, string.trim_right(msg <> buffer)), None)
        }
        _ -> #(state, None)
      }
    }
    RoomSay(conn, dim, dir, buffer) -> {
      case data {
        <<127>> -> {
          case string.length(buffer) {
            0 -> #(state, None)
            _ -> {
              let assert Ok(_) = render.backspace(state.conn)
              #(RoomSay(conn, dim, dir, string.drop_left(buffer, 1)), None)
            }
          }
        }
        <<13:8, 0:8>> -> {
          case string.length(string.trim(buffer)) {
            0 -> #(state, None)
            _ -> {
              let assert Ok(_) = render.erase_line(state.dimensions.width, conn)
              let assert Some(command_subject) = state.directory.command_subject
              process.send(
                command_subject,
                simulation.CommandSayRoom(string.reverse(buffer)),
              )
              #(RoomSay(conn, dim, dir, ""), None)
            }
          }
        }
        <<27>> -> {
          // esc
          let assert Ok(_) =
            render.erase_line(state.dimensions.width, state.conn)
          let assert Ok(_) = render.prompt("", state.conn)
          #(InWorld(conn, dim, dir, ""), None)
        }
        <<n:8>> if n >= 32 && n <= 126 -> {
          let assert Ok(msg) = bit_array.to_string(data)
          let assert Ok(_) = render.print(msg, conn)
          #(RoomSay(conn, dim, dir, string.trim_right(msg <> buffer)), None)
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
    InWorld(_, _, _, buffer) -> {
      case update {
        simulation.UpdateRoomDescription(region, name, desc) -> {
          let assert Ok(_) =
            render.room_descripion(state.conn, region, name, desc)
        }
        simulation.UpdatePlayerSpawned(name) -> {
          let assert Ok(_) =
            render.erase_line(state.dimensions.width, state.conn)
          let assert Ok(_) = render.player_spawned(name, state.conn)
        }
        simulation.UpdatePlayerQuit(name) -> {
          let assert Ok(_) =
            render.erase_line(state.dimensions.width, state.conn)
          let assert Ok(_) = render.player_quit(name, state.conn)
        }
        simulation.UpdateSayRoom(name, text) -> {
          let assert Ok(_) =
            render.erase_line(state.dimensions.width, state.conn)
          let assert Ok(_) = render.speech(name, text, state.conn)
        }
        _ -> Ok(Nil)
      }
      let assert Ok(_) = render.prompt(buffer, state.conn)
      state
    }
    RoomSay(_, _, _, buffer) -> {
      case update {
        simulation.UpdateRoomDescription(region, name, desc) -> {
          let assert Ok(_) =
            render.room_descripion(state.conn, region, name, desc)
        }
        simulation.UpdatePlayerSpawned(name) -> {
          let assert Ok(_) =
            render.erase_line(state.dimensions.width, state.conn)
          let assert Ok(_) = render.player_spawned(name, state.conn)
        }
        simulation.UpdatePlayerQuit(name) -> {
          let assert Ok(_) =
            render.erase_line(state.dimensions.width, state.conn)
          let assert Ok(_) = render.player_quit(name, state.conn)
        }
        simulation.UpdateSayRoom(name, text) -> {
          let assert Ok(_) =
            render.erase_line(state.dimensions.width, state.conn)
          let assert Ok(_) = render.speech(name, text, state.conn)
        }
        _ -> Ok(Nil)
      }

      let assert Ok(_) = render.prompt_say(buffer, state.conn)
      state
    }
  }
}

type ParseCommandError {
  UnknownCommand
  SayWhat
}

fn parse_command(str: String) -> Result(simulation.Command, ParseCommandError) {
  case string.split(str, " ") {
    ["quit", ..] -> Ok(simulation.CommandQuit)
    ["look", ..] -> Ok(simulation.CommandLook)
    ["say", ..rest] -> {
      case list.length(rest) {
        0 -> Error(SayWhat)
        _ -> Ok(simulation.CommandSayRoom(string.join(rest, " ")))
      }
    }
    _ -> Error(UnknownCommand)
  }
}
