import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/function
import gleam/otp/actor
import data/world
import model/entity
import model/sim_messages as msg

type RoomState {
  RoomState(
    template: world.RoomTemplate,
    region_subject: Subject(msg.Message),
    room_subject: Subject(msg.Message),
    entities: Dict(Int, Subject(msg.Message)),
  )
}

pub fn start(
  template: world.RoomTemplate,
  region_subject: Subject(msg.Message),
) -> Result(Subject(msg.Message), actor.StartError) {
  let parent_subject = process.new_subject()
  let start_result =
    actor.start_spec(actor.Spec(
      init: fn() {
        // create a msg.Message subject for the region or child entities to talk to the room
        let room_subject = process.new_subject()
        process.send(parent_subject, room_subject)

        // always select from the room subject, messages from the region above or the entities below
        let selector =
          process.new_selector()
          |> process.selecting(room_subject, function.identity)

        actor.Ready(
          RoomState(template, region_subject, room_subject, dict.new()),
          selector,
        )
      },
      init_timeout: 1000,
      loop: handle_message,
    ))

  // receive the room subject from the room actor
  let assert Ok(room_subject) = process.receive(parent_subject, 1000)

  case start_result {
    Ok(_) -> Ok(room_subject)
    Error(err) -> Error(err)
  }
}

fn handle_message(
  message: msg.Message,
  state: RoomState,
) -> actor.Next(msg.Message, RoomState) {
  case message {
    msg.Tick -> actor.continue(state)
    msg.SpawnActorEntity(entity, _, update_subject) -> {
      let assert Ok(ent) =
        entity.start(entity, state.room_subject, update_subject)
      actor.continue(
        RoomState(
          ..state,
          entities: dict.insert(state.entities, entity.id, ent),
        ),
      )
    }
    msg.RequestRoomDescription(reply) -> {
      process.send(
        reply,
        msg.ReplyRoomDescription(
          state.template.region,
          state.template.name,
          state.template.description,
        ),
      )
      actor.continue(state)
    }
    _ -> actor.continue(state)
  }
}
