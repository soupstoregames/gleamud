import gleam/erlang/process.{type Subject}
import gleam/option.{type Option, None, Some}
import model/simulation
import model/sim_messages as msg
import glisten.{type Connection}
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
}

pub type ClientDimensions {
  ClientDimensions(width: Int, height: Int)
}

pub type Directory {
  Directory(
    sim_subject: Subject(simulation.Control),
    command_subject: Option(Subject(msg.Command)),
  )
}

pub fn with_command_subject(
  state: State,
  subject: Subject(msg.Command),
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
  }
}

pub fn on_enter(state: State) -> State {
  case state {
    FirstIAC(_, _, _) -> state
    Menu(_, _, _) -> {
      let assert Ok(_) = render.logo(state.conn)
      let assert Ok(_) = render.menu(state.conn)

      state
    }
    InWorld(_, _, _) -> state
  }
}

pub fn handle_input(
  state: State,
  msg: String,
) -> #(State, Option(Subject(msg.Update))) {
  case state {
    FirstIAC(_, _, _) -> #(state, None)
    Menu(conn, dim, dir) ->
      case msg {
        "3" -> {
          let update_subject = process.new_subject()
          process.send(
            state.directory.sim_subject,
            simulation.JoinAsGuest(update_subject),
          )
          #(InWorld(conn, dim, dir), Some(update_subject))
        }
        _ -> #(state, None)
      }
    InWorld(_, _, _) -> #(state, None)
  }
}

pub fn handle_update(state: State, update: msg.Update) -> State {
  case state {
    FirstIAC(_, _, _) -> state
    Menu(_, _, _) -> state
    InWorld(_, _, _) ->
      case update {
        msg.RoomDescription(region, name, desc) -> {
          let assert Ok(_) =
            render.room_descripion(state.conn, region, name, desc)
          state
        }
        _ -> state
      }
  }
}
