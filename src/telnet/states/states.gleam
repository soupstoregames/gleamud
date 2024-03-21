import gleam/erlang/process.{type Subject}
import gleam/option.{type Option, Some}
import model/entity
import model/simulation
import glisten.{type Connection}

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
    command_subject: Option(Subject(entity.Command)),
  )
}

pub fn with_command_subject(
  state: State,
  subject: Subject(entity.Command),
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
