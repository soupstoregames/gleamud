import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import model/sim_messages as msg
import data/entity as dataentity

/// Commands are sent from game connections to entities
pub type Command {
  Look
}

/// Updates are sent from entities to game connections
pub type Update {
  CommandSubject(Subject(Command))
  // RoomDescription
}

type Message {
  SimMessage(msg.Message)
  CommandMessage(Command)
}

type EntityState {
  EntityState(
    entity: dataentity.Entity,
    // the subject to talk to the parent room
    room_subject: Subject(msg.Message),
    // sent to game controllers when they take control of this entity
    command_subject: Subject(Command),
    // used for sending updates to game controllers
    update_subject: Subject(Update),
  )
}

// construct with 
// - the entity data
// - the update_subject to send entity updates to the game controller
// - the parent room's sim_subject to send messages into the room
// and return
// - the entity_subject to send message to the entity
// 
pub fn new(
  entity: dataentity.Entity,
  room_subject: Subject(msg.Message),
  update_subject: Subject(Update),
) -> Result(Subject(msg.Message), actor.StartError) {
  let parent_subject = process.new_subject()

  let start_result =
    actor.start_spec(actor.Spec(
      init: fn() {
        // send the entity subject back to the constructor to be returned
        let entity_subject = process.new_subject()
        process.send(parent_subject, entity_subject)

        // send the command subject over the update subject to the game controller
        let command_subject = process.new_subject()
        process.send(update_subject, CommandSubject(command_subject))

        // 
        let selector =
          process.new_selector()
          |> process.selecting(entity_subject, fn(msg) { SimMessage(msg) })
          |> process.selecting(command_subject, fn(msg) { CommandMessage(msg) })

        actor.Ready(
          EntityState(entity, room_subject, command_subject, update_subject),
          selector,
        )
      },
      init_timeout: 1000,
      loop: handle_message,
    ))

  let assert Ok(entity_subject) = process.receive(parent_subject, 1000)

  case start_result {
    Ok(_) -> Ok(entity_subject)
    Error(err) -> Error(err)
  }
}

fn handle_message(
  message: Message,
  state: EntityState,
) -> actor.Next(Message, EntityState) {
  case message {
    SimMessage(msg.Tick) -> actor.continue(state)
    _ -> todo
  }
}
