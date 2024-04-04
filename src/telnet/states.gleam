import gleam/erlang/process.{type Subject}
import simulation

pub type State {
  FirstIAC
  Menu
  InWorld
  RoomSay
}

pub type StateData {
  StateData(
    current_state: State,
    update_subject: Subject(simulation.Update),
    sim_subject: Subject(simulation.Command),
    entity_id: Int,
  )
}
