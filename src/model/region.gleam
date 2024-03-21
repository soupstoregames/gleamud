import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/function
import gleam/list
import gleam/otp/actor
import data/world
import model/room
import model/sim_messages as msg
import gleam/io

type RegionState {
  RegionState(
    template: world.RegionTemplate,
    sim_subject: Subject(msg.Message),
    rooms: Dict(String, Subject(msg.Message)),
  )
}

pub fn start(
  template: world.RegionTemplate,
  sim_subject: Subject(msg.Message),
) -> Result(Subject(msg.Message), actor.StartError) {
  let parent_subject = process.new_subject()
  let start_result =
    actor.start_spec(actor.Spec(
      init: fn() {
        // create a msg.Message subject for the sim or child rooms to talk to the region
        let region_subject = process.new_subject()
        process.send(parent_subject, region_subject)

        // spawn the rooms which will spawn the rooms
        // later this will be done ad hoc to cut down on redundant actors
        //   and to support instances
        let rooms =
          template.rooms
          |> dict.to_list()
          |> list.map(fn(kv) {
            let assert Ok(subject) = room.start(kv.1, region_subject)
            #(kv.0, subject)
          })
          |> dict.from_list()

        // always select from the region subject, messages from the sim above or the rooms below
        let selector =
          process.new_selector()
          |> process.selecting(region_subject, function.identity)

        actor.Ready(RegionState(template, sim_subject, rooms), selector)
      },
      init_timeout: 1000,
      loop: handle_message,
    ))

  // receive the region subject from the region actor
  let assert Ok(region_subject) = process.receive(parent_subject, 1000)

  case start_result {
    Ok(_) -> Ok(region_subject)
    Error(err) -> Error(err)
  }
}

fn handle_message(
  message: msg.Message,
  state: RegionState,
) -> actor.Next(msg.Message, RegionState) {
  case message {
    msg.Tick -> {
      // forward the tick to all rooms
      state.rooms
      |> dict.to_list()
      |> list.each(fn(kv) { process.send(kv.1, msg.Tick) })

      actor.continue(state)
    }
  }
}
