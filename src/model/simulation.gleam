import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor
import data/core
import data/entity as dataentity
import data/prefabs
import data/world
import model/region
import model/sim_messages as msg

/// Control message are sent by top level actors to control the sim directly
pub type Control {
  JoinAsGuest(Subject(msg.Update))
  Tick
  Shutdown
}

type SimMessage {
  Control(Control)
  Sim(msg.Message)
}

type SimState {
  SimState(
    world_template: world.WorldTemplate,
    sim_subject: Subject(msg.Message),
    regions: Dict(String, Subject(msg.Message)),
  )
}

pub fn start() -> Result(Subject(Control), actor.StartError) {
  // data loading
  let assert Ok(world) = world.load_world()

  let parent_subject = process.new_subject()

  let start_result =
    actor.start_spec(actor.Spec(
      init: fn() {
        // create the subject the main process to send control messages on
        let control_subject = process.new_subject()
        process.send(parent_subject, control_subject)

        // dont send this up as it will only be used by child regions
        let sim_subject = process.new_subject()

        // spawn the regions which will spawn the rooms
        // later this will be done ad hoc to cut down on redundant actors
        //   and to support instances
        let regions =
          world.regions
          |> dict.to_list()
          |> list.map(fn(kv) {
            let assert Ok(subject) = region.start(kv.1, sim_subject)
            #(kv.0, subject)
          })
          |> dict.from_list()

        // always select control messages from the main process and sim messages from the child regions
        let selector =
          process.new_selector()
          |> process.selecting(control_subject, fn(msg) { Control(msg) })
          |> process.selecting(sim_subject, fn(msg) { Sim(msg) })

        actor.Ready(SimState(world, sim_subject, regions), selector)
      },
      init_timeout: 1000,
      loop: handle_message,
    ))

  let assert Ok(control_subject) = process.receive(parent_subject, 1000)

  case start_result {
    Ok(_) -> Ok(control_subject)
    Error(err) -> Error(err)
  }
}

pub fn stop(subject: Subject(Control)) {
  process.send(subject, Shutdown)
}

fn handle_message(
  message: SimMessage,
  state: SimState,
) -> actor.Next(SimMessage, SimState) {
  case message {
    Control(JoinAsGuest(update_subject)) -> {
      let location = core.Location("testregion", "testroom")
      let entity = dataentity.Entity(0, prefabs.create_guest_player())
      let assert Ok(region_subject) = dict.get(state.regions, location.region)
      process.send(
        region_subject,
        msg.SpawnActorEntity(entity, location, update_subject),
      )
      actor.continue(state)
    }

    Control(Tick) -> {
      // forward the tick to all regions
      state.regions
      |> dict.to_list()
      |> list.each(fn(kv) { process.send(kv.1, msg.Tick) })
      actor.continue(state)
    }

    Control(Shutdown) -> actor.Stop(process.Normal)

    _ -> actor.continue(state)
  }
}
