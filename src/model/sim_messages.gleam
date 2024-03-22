import gleam/erlang/process.{type Subject}
import data/core
import data/entity as dataentity

pub type Message {
  Tick
  SpawnActorEntity(dataentity.Entity, core.Location, Subject(Update))

  RequestRoomDescription(Subject(Message))
  ReplyRoomDescription(region: String, name: String, description: String)
}

/// Commands are sent from game connections to entities
pub type Command {
  Look
}

/// Updates are sent from entities to game connections
pub type Update {
  CommandSubject(Subject(Command))
  RoomDescription(region: String, name: String, description: String)
}
