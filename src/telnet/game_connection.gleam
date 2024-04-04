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
import simulation

pub type Message {
  Dimensions(Int, Int)
  Data(BitArray)
  Update(simulation.Update)
}

type State {
  State(
    tcp_subject: Subject(Message),
    sim_subject: Subject(simulation.Command),
    update_subject: Subject(simulation.Update),
    conn: glisten.Connection(BitArray),
    size: #(Int, Int),
    mode: Mode,
    entity_id: Int,
  )
}

type Mode {
  FirstIAC
  Menu
  Command
  RoomSay
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
        State(
          tcp_subject,
          sim_subject,
          update_subject,
          conn,
          #(80, 24),
          FirstIAC,
          0,
        ),
        selector,
      )
    },
    init_timeout: 1000,
    loop: handle_message,
  ))
}

fn handle_message(message: Message, state: State) -> actor.Next(Message, State) {
  case message {
    Dimensions(width, height) -> handle_dimensions(state, width, height)
    Data(bits) -> handle_data(state, bits)
    Update(update) -> handle_update(state, update)
  }
}

fn handle_dimensions(
  state: State,
  width: Int,
  height: Int,
) -> actor.Next(Message, State) {
  let state = case state.mode {
    FirstIAC ->
      State(..state, mode: Menu, size: #(width, height))
      |> on_enter
    _ -> State(..state, size: #(width, height))
  }
  actor.continue(state)
}

fn handle_data(state: State, data: BitArray) -> actor.Next(Message, State) {
  actor.continue(case state.mode {
    FirstIAC -> state
    Menu -> handle_data_menu(state, data)
    Command -> handle_data_command(state, data)
    RoomSay -> handle_data_room_say(state, data)
  })
}

fn handle_data_menu(state: State, data: BitArray) -> State {
  let assert Ok(msg) = bit_array.to_string(data)
  case string.trim(msg) {
    "guest" -> {
      let assert Ok(entity_id) =
        process.call(
          state.sim_subject,
          simulation.JoinAsGuest(state.update_subject, _),
          1000,
        )
      State(..state, mode: Command, entity_id: entity_id)
    }

    "quit" -> {
      let assert Ok(_) =
        transport.close(state.conn.transport, state.conn.socket)
      state
    }
    _ -> state
  }
}

fn handle_data_command(state: State, data: BitArray) -> State {
  let assert Ok(msg) = bit_array.to_string(data)
  case string.trim(msg) {
    "/say" -> on_enter(State(..state, mode: RoomSay))
    _ as trimmed -> {
      case parse_command(state.entity_id, trimmed) {
        Error(UnknownCommand) -> {
          let assert Ok(_) = render.error(state.conn, "Huh?")
          let assert Ok(_) = render.prompt_command(state.conn)
          Nil
        }
        Error(InvalidCommand) -> {
          let assert Ok(_) = render.error(state.conn, "Invalid command args")
          let assert Ok(_) = render.prompt_command(state.conn)
          Nil
        }
        Error(SayWhat) -> {
          let assert Ok(_) = render.error(state.conn, "Say what?")
          let assert Ok(_) = render.prompt_command(state.conn)
          Nil
        }
        Ok(simulation.CommandQuit(_) as com) -> {
          let assert Ok(_) =
            transport.close(state.conn.transport, state.conn.socket)
          process.send(state.sim_subject, com)
        }
        Ok(com) -> process.send(state.sim_subject, com)
      }
      state
    }
  }
}

fn handle_data_room_say(state: State, data: BitArray) -> State {
  let assert Ok(msg) = bit_array.to_string(data)
  case string.trim(msg) {
    "/e" -> on_enter(State(..state, mode: Command))
    _ as trimmed -> {
      process.send(
        state.sim_subject,
        simulation.CommandSayRoom(state.entity_id, trimmed),
      )
      state
    }
  }
}

fn handle_update(
  state: State,
  update: simulation.Update,
) -> actor.Next(Message, State) {
  let assert Ok(_) = case update {
    simulation.UpdateRoomDescription(name, desc, exits) ->
      render.room_descripion(state.conn, name, desc, exits, state.size.0)
    simulation.UpdatePlayerSpawned(name) ->
      render.player_spawned(state.conn, state.size.0, name)
    simulation.UpdatePlayerQuit(name) ->
      render.player_quit(state.conn, state.size.0, name)
    simulation.UpdateSayRoom(name, text) ->
      render.speech(state.conn, state.size.0, name, text)
    simulation.UpdatePlayerTeleportedOut(name) ->
      render.entity_teleported_out(state.conn, state.size.0, name)
    simulation.UpdatePlayerTeleportedIn(name) ->
      render.entity_teleported_in(state.conn, state.size.0, name)
    simulation.AdminCommandFailed(reason) ->
      render.admin_command_failed(state.conn, state.size.0, reason)
  }
  let assert Ok(_) = case state.mode {
    Command -> render.prompt_command(state.conn)
    RoomSay -> render.prompt_say(state.conn)
    _ -> Ok(Nil)
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
    ["say", ..rest] ->
      case list.length(rest) {
        0 -> Error(SayWhat)
        _ ->
          Ok(simulation.CommandSayRoom(
            entity_id: entity_id,
            text: string.join(rest, " "),
          ))
      }
    ["@tp", room, ..] ->
      case int.parse(room) {
        Ok(room_num) -> Ok(simulation.AdminTeleport(entity_id, room_num))
        Error(Nil) -> Error(InvalidCommand)
      }
    _ -> Error(UnknownCommand)
  }
}

fn on_enter(state: State) -> State {
  case state.mode {
    FirstIAC -> state
    Menu -> {
      let assert Ok(_) = render.logo(state.conn, state.size.0)
      let assert Ok(_) = render.menu(state.conn, state.size.0)
      let assert Ok(_) = render.prompt_command(state.conn)
      state
    }
    Command -> {
      let assert Ok(_) = render.prompt_command(state.conn)
      state
    }
    RoomSay -> {
      let assert Ok(_) = render.prompt_say(state.conn)
      state
    }
  }
}
