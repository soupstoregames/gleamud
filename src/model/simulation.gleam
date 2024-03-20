import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import data/world
import gleam/io

type State {
  State(world_template: world.WorldTemplate)
}

/// Control message are sent by top level actors to control the sim directly
pub type Control {
  JoinAsGuest(Subject(Update))
  Tick
  Shutdown
}

/// Commands are sent from game connections to entities
pub type Command {
  Look
}

/// Updates are sent from entities to game connections
pub type Update {
  CommandSubject(Subject(Command))
  // RoomDescription
}

pub fn start() -> Result(Subject(Control), actor.StartError) {
  // data loading
  let assert Ok(world) = world.load_world()

  actor.start(State(world), handle_message)
}

pub fn stop(subject: Subject(Control)) {
  process.send(subject, Shutdown)
}

fn handle_message(message: Control, state: State) -> actor.Next(Control, State) {
  case message {
    Tick -> {
      //   io.println("tick")
      actor.continue(state)
    }

    JoinAsGuest(subject) -> {
      io.debug("continue as guest")
      actor.continue(state)
    }

    Shutdown -> actor.Stop(process.Normal)
  }
}
