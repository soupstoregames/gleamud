import gleam/bit_array
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/string
import simulation
import glisten.{type Connection}
import glisten/transport
import telnet/render

pub type State {
  FirstIAC(
    conn: Connection(BitArray),
    update_subject: Subject(simulation.Update),
    dimensions: ClientDimensions,
    entity_id: Int,
    sim_subject: Subject(simulation.Command),
  )
  Menu(
    conn: Connection(BitArray),
    update_subject: Subject(simulation.Update),
    dimensions: ClientDimensions,
    entity_id: Int,
    sim_subject: Subject(simulation.Command),
  )
  InWorld(
    conn: Connection(BitArray),
    update_subject: Subject(simulation.Update),
    dimensions: ClientDimensions,
    entity_id: Int,
    sim_subject: Subject(simulation.Command),
  )
  RoomSay(
    conn: Connection(BitArray),
    update_subject: Subject(simulation.Update),
    dimensions: ClientDimensions,
    entity_id: Int,
    sim_subject: Subject(simulation.Command),
  )
}

pub type ClientDimensions {
  ClientDimensions(width: Int, height: Int)
}

pub fn on_enter(state: State) -> State {
  case state {
    FirstIAC(_, _, _, _, _) -> state
    Menu(_, _, dim, _, _) -> {
      let assert Ok(_) = render.logo(dim.width, state.conn)
      let assert Ok(_) = render.menu(dim.width, state.conn)
      let assert Ok(_) = render.prompt(state.conn)

      state
    }
    InWorld(_, _, _, _, _) -> {
      let assert Ok(_) = render.prompt(state.conn)
      state
    }
    RoomSay(_, _, _, _, _) -> {
      let assert Ok(_) = render.prompt_say(state.conn)
      state
    }
  }
}

pub fn handle_input(state: State, data: BitArray) -> State {
  case state {
    FirstIAC(_, _, _, _, _) -> state
    Menu(conn, update_subject, dim, _, sim_subject) -> {
      let assert Ok(msg) = bit_array.to_string(data)
      case string.trim(msg) {
        "guest" -> {
          let assert Ok(entity_id) =
            process.call(
              state.sim_subject,
              simulation.JoinAsGuest(update_subject, _),
              1000,
            )
          InWorld(conn, update_subject, dim, entity_id, sim_subject)
        }

        "quit" -> {
          let assert Ok(_) =
            transport.close(state.conn.transport, state.conn.socket)
          state
        }
        _ -> state
      }
    }
    InWorld(conn, update_subject, dim, entity_id, sim_subject) -> {
      let assert Ok(msg) = bit_array.to_string(data)
      let trimmed = string.trim(msg)
      case trimmed {
        "/say" ->
          RoomSay(conn, update_subject, dim, entity_id, sim_subject)
          |> on_enter
        _ as str -> {
          case parse_command(state.entity_id, str) {
            Ok(simulation.CommandQuit(_) as com) -> {
              let assert Ok(_) =
                transport.close(state.conn.transport, state.conn.socket)
              process.send(sim_subject, com)
              Nil
            }
            Ok(com) -> {
              process.send(sim_subject, com)
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
          InWorld(conn, update_subject, dim, entity_id, sim_subject)
        }
      }
    }
    RoomSay(conn, update_subject, dim, entity_id, sim_subject) -> {
      let assert Ok(msg) = bit_array.to_string(data)
      let trimmed = string.trim(msg)
      case trimmed {
        "/e" ->
          InWorld(conn, update_subject, dim, entity_id, sim_subject)
          |> on_enter
        _ -> {
          let assert Ok(_) = render.erase_line(dim.width, conn)
          process.send(
            sim_subject,
            simulation.CommandSayRoom(entity_id, trimmed),
          )
          RoomSay(conn, update_subject, dim, entity_id, sim_subject)
        }
      }
    }
  }
}

pub fn handle_update(state: State, update: simulation.Update) -> State {
  case state {
    FirstIAC(_, _, _, _, _) -> state
    Menu(_, _, _, _, _) -> state
    InWorld(conn, _, dim, _, _) -> {
      case update {
        simulation.UpdateRoomDescription(name, desc) -> {
          let assert Ok(_) =
            render.room_descripion(
              state.conn,
              name,
              desc,
              state.dimensions.width,
            )
        }
        simulation.UpdatePlayerSpawned(name) -> {
          let assert Ok(_) = render.erase_line(dim.width, conn)
          let assert Ok(_) = render.player_spawned(name, conn, dim.width)
        }
        simulation.UpdatePlayerQuit(name) -> {
          let assert Ok(_) = render.erase_line(dim.width, conn)
          let assert Ok(_) = render.player_quit(name, conn, dim.width)
        }
        simulation.UpdateSayRoom(name, text) -> {
          let assert Ok(_) = render.erase_line(dim.width, conn)
          let assert Ok(_) = render.speech(name, text, conn, dim.width)
        }
      }
      let assert Ok(_) = render.prompt(conn)
      state
    }
    RoomSay(conn, _, dim, _, _) -> {
      case update {
        simulation.UpdateRoomDescription(name, desc) -> {
          let assert Ok(_) =
            render.room_descripion(state.conn, name, desc, dim.width)
        }
        simulation.UpdatePlayerSpawned(name) -> {
          let assert Ok(_) = render.erase_line(dim.width, conn)
          let assert Ok(_) = render.player_spawned(name, conn, dim.width)
        }
        simulation.UpdatePlayerQuit(name) -> {
          let assert Ok(_) = render.erase_line(dim.width, conn)
          let assert Ok(_) = render.player_quit(name, conn, dim.width)
        }
        simulation.UpdateSayRoom(name, text) -> {
          let assert Ok(_) = render.erase_line(dim.width, conn)
          let assert Ok(_) = render.speech(name, text, conn, dim.width)
        }
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

fn parse_command(
  entity_id: Int,
  str: String,
) -> Result(simulation.Command, ParseCommandError) {
  case string.split(str, " ") {
    ["quit", ..] -> Ok(simulation.CommandQuit(entity_id))
    ["look", ..] -> Ok(simulation.CommandLook(entity_id))
    ["say", ..rest] -> {
      case list.length(rest) {
        0 -> Error(SayWhat)
        _ ->
          Ok(simulation.CommandSayRoom(
            entity_id: entity_id,
            text: string.join(rest, " "),
          ))
      }
    }
    _ -> Error(UnknownCommand)
  }
}
