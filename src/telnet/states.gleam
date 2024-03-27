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
  )
  Menu(
    conn: Connection(BitArray),
    dimensions: ClientDimensions,
    directory: Directory,
  )
  InWorld(
    conn: Connection(BitArray),
    dimensions: ClientDimensions,
    directory: Directory,
  )
  RoomSay(
    conn: Connection(BitArray),
    dimensions: ClientDimensions,
    directory: Directory,
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
    FirstIAC(_, _, _) -> state
    Menu(_, _, _) -> state
    InWorld(conn, dim, dir) ->
      InWorld(
        conn,
        dim,
        Directory(sim_subject: dir.sim_subject, command_subject: Some(subject)),
      )
    RoomSay(conn, dim, dir) ->
      RoomSay(
        conn,
        dim,
        Directory(sim_subject: dir.sim_subject, command_subject: Some(subject)),
      )
  }
}

pub fn on_enter(state: State) -> State {
  case state {
    FirstIAC(_, _, _) -> state
    Menu(_, dim, _) -> {
      let assert Ok(_) = render.logo(dim.width, state.conn)
      let assert Ok(_) = render.menu(dim.width, state.conn)
      let assert Ok(_) = render.prompt(state.conn)

      state
    }
    InWorld(_, _, _) -> {
      let assert Ok(_) = render.prompt(state.conn)
      state
    }
    RoomSay(_, _, _) -> {
      let assert Ok(_) = render.prompt_say(state.conn)
      state
    }
  }
}

pub fn handle_input(
  state: State,
  data: BitArray,
) -> #(State, Option(Subject(simulation.Update))) {
  case state {
    FirstIAC(_, _, _) -> #(state, None)
    Menu(conn, dim, dir) -> {
      let assert Ok(msg) = bit_array.to_string(data)
      let trimmed = string.trim(msg)
      case trimmed {
        "guest" -> {
          let update_subject = process.new_subject()
          process.send(
            state.directory.sim_subject,
            simulation.JoinAsGuest(update_subject),
          )
          #(InWorld(conn, dim, dir), Some(update_subject))
        }
        _ -> #(state, None)
      }
    }
    InWorld(conn, dim, dir) -> {
      let assert Ok(msg) = bit_array.to_string(data)
      let trimmed = string.trim(msg)
      let assert Some(command_subject) = state.directory.command_subject
      case trimmed {
        "/say" -> {
          #(
            RoomSay(conn, dim, dir)
              |> on_enter,
            None,
          )
        }
        _ as str -> {
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
              let assert Ok(_) = render.prompt(conn)
              Nil
            }
            Error(SayWhat) -> {
              let assert Ok(_) = render.error("Say what?", state.conn)
              let assert Ok(_) = render.prompt(conn)
              Nil
            }
          }
          #(InWorld(conn, dim, dir), None)
        }
      }
    }
    RoomSay(conn, dim, dir) -> {
      let assert Ok(msg) = bit_array.to_string(data)
      let trimmed = string.trim(msg)
      let assert Some(command_subject) = state.directory.command_subject
      case trimmed {
        "/e" -> {
          #(
            InWorld(conn, dim, dir)
              |> on_enter,
            None,
          )
        }
        _ -> {
          let assert Ok(_) = render.erase_line(dim.width, conn)
          process.send(command_subject, simulation.CommandSayRoom(trimmed))
          #(RoomSay(conn, dim, dir), None)
        }
      }
    }
  }
}

pub fn handle_update(state: State, update: simulation.Update) -> State {
  case state {
    FirstIAC(_, _, _) -> state
    Menu(_, _, _) -> state
    InWorld(conn, dim, _) -> {
      case update {
        simulation.UpdateRoomDescription(region, name, desc) -> {
          let assert Ok(_) = render.room_descripion(conn, region, name, desc)
        }
        simulation.UpdatePlayerSpawned(name) -> {
          let assert Ok(_) = render.player_spawned(name, conn)
        }
        simulation.UpdatePlayerQuit(name) -> {
          let assert Ok(_) = render.player_quit(name, conn)
        }
        simulation.UpdateSayRoom(name, text) -> {
          // let assert Ok(_) = render.erase_line(dim.width, conn)
          let assert Ok(_) = render.speech(name, text, conn)
        }
        _ -> Ok(Nil)
      }
      let assert Ok(_) = render.prompt(conn)
      state
    }
    RoomSay(conn, dim, _) -> {
      case update {
        simulation.UpdateRoomDescription(region, name, desc) -> {
          let assert Ok(_) = render.room_descripion(conn, region, name, desc)
        }
        simulation.UpdatePlayerSpawned(name) -> {
          let assert Ok(_) = render.erase_line(dim.width, conn)
          let assert Ok(_) = render.player_spawned(name, conn)
        }
        simulation.UpdatePlayerQuit(name) -> {
          let assert Ok(_) = render.erase_line(dim.width, conn)
          let assert Ok(_) = render.player_quit(name, conn)
        }
        simulation.UpdateSayRoom(name, text) -> {
          let assert Ok(_) = render.erase_line(dim.width, conn)
          let assert Ok(_) = render.speech(name, text, conn)
        }
        _ -> Ok(Nil)
      }

      let assert Ok(_) = render.prompt_say(conn)
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
