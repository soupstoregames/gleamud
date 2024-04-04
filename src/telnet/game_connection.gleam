import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/int
import gleam/list
import gleam/string
import gleam/function
import gleam/bit_array
import glisten
import glisten/transport
import telnet/render
import telnet/states
import simulation

pub type Message {
  Dimensions(Int, Int)
  Data(BitArray)
  Update(simulation.Update)
}

type ClientParams {
  ClientParams(width: Int, height: Int)
}

type ConnState {
  ConnState(
    tcp_subject: Subject(Message),
    client_params: ClientParams,
    game_state: states.StateData,
    conn: glisten.Connection(BitArray),
  )
}

pub fn start(
  parent_subject: Subject(Subject(Message)),
  sim_subject: Subject(simulation.Command),
  conn: glisten.Connection(BitArray),
) -> Result(Subject(Message), actor.StartError) {
  actor.start_spec(actor.Spec(
    init: fn() {
      let tcp_subject = process.new_subject()
      process.send(parent_subject, tcp_subject)

      let update_subject = process.new_subject()

      let selector =
        process.new_selector()
        |> process.selecting(tcp_subject, function.identity)
        |> process.selecting(update_subject, fn(msg) { Update(msg) })

      actor.Ready(
        ConnState(
          tcp_subject,
          ClientParams(80, 24),
          states.StateData(states.FirstIAC, update_subject, sim_subject, 0),
          conn,
        ),
        selector,
      )
    },
    init_timeout: 1000,
    loop: handle_message,
  ))
}

fn handle_message(
  message: Message,
  state: ConnState,
) -> actor.Next(Message, ConnState) {
  case message {
    Dimensions(width, height) -> handle_dimensions(state, width, height)
    Data(bits) -> handle_data(state, bits)
    Update(update) -> handle_update(state, update)
  }
}

fn handle_dimensions(
  state: ConnState,
  width: Int,
  height: Int,
) -> actor.Next(Message, ConnState) {
  // move this into state
  let new_state = case state.game_state.current_state {
    states.FirstIAC -> {
      let assert Ok(_) = render.logo(width, state.conn)
      let assert Ok(_) = render.menu(width, state.conn)
      let assert Ok(_) = render.prompt(state.conn)
      states.Menu
    }
    states.Menu -> {
      let assert Ok(_) = render.logo(width, state.conn)
      let assert Ok(_) = render.menu(width, state.conn)
      let assert Ok(_) = render.prompt(state.conn)
      states.Menu
    }
    states.InWorld -> {
      let assert Ok(_) = render.prompt(state.conn)
      states.InWorld
    }
    states.RoomSay -> {
      let assert Ok(_) = render.prompt_say(state.conn)
      states.RoomSay
    }
  }
  actor.continue(
    ConnState(
      ..state,
      game_state: states.StateData(..state.game_state, current_state: new_state),
      client_params: ClientParams(width: width, height: height),
    ),
  )
}

fn handle_data(
  state: ConnState,
  data: BitArray,
) -> actor.Next(Message, ConnState) {
  let new_state = handle_input(state, data)
  actor.continue(new_state)
}

fn handle_update(
  state: ConnState,
  update: simulation.Update,
) -> actor.Next(Message, ConnState) {
  let ConnState(_tcp_subject, client_params, game_state, conn) = state
  case game_state.current_state {
    states.InWorld -> {
      case update {
        simulation.UpdateRoomDescription(name, desc, exits) -> {
          let assert Ok(_) =
            render.room_descripion(conn, name, desc, exits, client_params.width)
        }
        simulation.UpdatePlayerSpawned(name) -> {
          let assert Ok(_) = render.erase_line(client_params.width, conn)
          let assert Ok(_) =
            render.player_spawned(name, conn, client_params.width)
        }
        simulation.UpdatePlayerQuit(name) -> {
          let assert Ok(_) = render.erase_line(client_params.width, conn)
          let assert Ok(_) = render.player_quit(name, conn, client_params.width)
        }
        simulation.UpdateSayRoom(name, text) -> {
          let assert Ok(_) = render.erase_line(client_params.width, conn)
          let assert Ok(_) =
            render.speech(name, text, conn, client_params.width)
        }
        simulation.UpdatePlayerTeleportedOut(name) -> {
          let assert Ok(_) = render.erase_line(client_params.width, conn)
          let assert Ok(_) =
            render.entity_teleported_out(name, conn, client_params.width)
        }
        simulation.UpdatePlayerTeleportedIn(name) -> {
          let assert Ok(_) = render.erase_line(client_params.width, conn)
          let assert Ok(_) =
            render.entity_teleported_in(name, conn, client_params.width)
        }
        simulation.AdminCommandFailed(reason) -> {
          let assert Ok(_) =
            render.admin_command_failed(reason, conn, client_params.width)
        }
      }
      let assert Ok(_) = render.prompt(conn)
      Nil
    }
    states.RoomSay -> {
      case update {
        simulation.UpdateRoomDescription(name, desc, exits) -> {
          let assert Ok(_) =
            render.room_descripion(conn, name, desc, exits, client_params.width)
        }
        simulation.UpdatePlayerSpawned(name) -> {
          let assert Ok(_) = render.erase_line(client_params.width, conn)
          let assert Ok(_) =
            render.player_spawned(name, conn, client_params.width)
        }
        simulation.UpdatePlayerQuit(name) -> {
          let assert Ok(_) = render.erase_line(client_params.width, conn)
          let assert Ok(_) = render.player_quit(name, conn, client_params.width)
        }
        simulation.UpdateSayRoom(name, text) -> {
          let assert Ok(_) = render.erase_line(client_params.width, conn)
          let assert Ok(_) =
            render.speech(name, text, conn, client_params.width)
        }
        simulation.UpdatePlayerTeleportedOut(name) -> {
          let assert Ok(_) = render.erase_line(client_params.width, conn)
          let assert Ok(_) =
            render.entity_teleported_out(name, conn, client_params.width)
        }
        simulation.UpdatePlayerTeleportedIn(name) -> {
          let assert Ok(_) = render.erase_line(client_params.width, conn)
          let assert Ok(_) =
            render.entity_teleported_out(name, conn, client_params.width)
        }
        simulation.AdminCommandFailed(reason) -> {
          let assert Ok(_) =
            render.admin_command_failed(reason, conn, client_params.width)
        }
      }

      let assert Ok(_) = render.prompt_say(conn)
      Nil
    }
    _ -> Nil
  }
  actor.continue(state)
}

type ParseCommandError {
  UnknownCommand
  InvalidCommand
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
    ["@tp", room, ..] -> {
      case int.parse(room) {
        Ok(room_num) -> Ok(simulation.AdminTeleport(entity_id, room_num))
        Error(Nil) -> Error(InvalidCommand)
      }
    }
    _ -> Error(UnknownCommand)
  }
}

/// convenience function to update the current state inside the ConnState's game_state
fn update_current_state(cs: ConnState, state: states.State) -> ConnState {
  ConnState(
    ..cs,
    game_state: states.StateData(..cs.game_state, current_state: state),
  )
}

fn handle_input(state: ConnState, data: BitArray) -> ConnState {
  let assert Ok(string) = bit_array.to_string(data)
  let ConnState(
    _tcp_subject,
    client_params,
    states.StateData(current_state, up_sub, sim_sub, entity_id),
    conn,
  ) = state
  case current_state {
    states.FirstIAC -> state
    states.Menu -> {
      let assert Ok(msg) = bit_array.to_string(data)
      case string.trim(msg) {
        "guest" -> {
          let assert Ok(entity_id) =
            process.call(sim_sub, simulation.JoinAsGuest(up_sub, _), 1000)
          ConnState(
            ..state,
            game_state: states.StateData(
              ..state.game_state,
              current_state: states.InWorld,
              entity_id: entity_id,
            ),
          )
        }

        "quit" -> {
          let assert Ok(_) = transport.close(conn.transport, conn.socket)
          state
        }
        _ -> state
      }
    }
    states.InWorld -> {
      let assert Ok(msg) = bit_array.to_string(data)
      let trimmed = string.trim(msg)
      case trimmed {
        "/say" ->
          update_current_state(state, states.RoomSay)
          |> on_enter
        _ as str -> {
          case parse_command(entity_id, str) {
            Ok(simulation.CommandQuit(_) as com) -> {
              let assert Ok(_) = transport.close(conn.transport, conn.socket)
              process.send(sim_sub, com)
              Nil
            }
            Ok(com) -> {
              process.send(sim_sub, com)
            }
            Error(UnknownCommand) -> {
              let assert Ok(_) = render.error("Huh?", conn)
              let assert Ok(_) = render.prompt(conn)
              Nil
            }
            Error(InvalidCommand) -> {
              let assert Ok(_) = render.error("Invalid command args", conn)
              let assert Ok(_) = render.prompt(conn)
              Nil
            }
            Error(SayWhat) -> {
              let assert Ok(_) = render.error("Say what?", conn)
              let assert Ok(_) = render.prompt(conn)
              Nil
            }
          }
          update_current_state(state, states.InWorld)
        }
      }
    }
    states.RoomSay -> {
      let assert Ok(msg) = bit_array.to_string(data)
      let trimmed = string.trim(msg)
      case trimmed {
        "/e" ->
          update_current_state(state, states.InWorld)
          |> on_enter
        _ -> {
          let assert Ok(_) = render.erase_line(client_params.width, conn)
          process.send(sim_sub, simulation.CommandSayRoom(entity_id, trimmed))
          state
        }
      }
    }
  }
}

fn on_enter(state: ConnState) -> ConnState {
  let ConnState(_tcp_subject, client_params, game_state, conn) = state
  case game_state.current_state {
    states.FirstIAC -> state
    states.Menu -> {
      let assert Ok(_) = render.logo(client_params.width, conn)
      let assert Ok(_) = render.menu(client_params.width, conn)
      let assert Ok(_) = render.prompt(conn)
      state
    }
    states.InWorld -> {
      let assert Ok(_) = render.prompt(conn)
      state
    }
    states.RoomSay -> {
      let assert Ok(_) = render.prompt_say(conn)
      state
    }
  }
}
