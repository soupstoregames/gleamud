import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/function
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result
import data/entity as dataentity
import data/prefabs
import data/world

/// Commands are sent from game connections to entities
pub type Command {
  Tick
  Shutdown
  JoinAsGuest(Subject(Update), reply_with: Subject(Result(Int, Nil)))

  CommandQuit(entity_id: Int)
  CommandLook(entity_id: Int)
  CommandSayRoom(entity_id: Int, text: String)

  AdminTeleport(entity_id: Int, room_id: Int)
}

/// Updates are sent from the sim to the game mux
pub type Update {
  UpdateRoomDescription(
    name: String,
    description: String,
    exits: Dict(world.Direction, Int),
  )
  UpdatePlayerSpawned(name: String)
  UpdatePlayerQuit(name: String)
  UpdateSayRoom(name: String, text: String)

  // admin stuff
  AdminCommandFailed(reason: String)
  UpdateEntityTeleportedOut(name: String)
  UpdateEntityTeleportedIn(name: String)
}

type SimState {
  SimState(
    next_entity_id: Int,
    sim_subject: Subject(Command),
    rooms: Dict(Int, Room),
    controlled_entities: Dict(Int, ControlledEntity),
  )
}

type Room {
  Room(template: world.RoomTemplate, entities: Dict(Int, Entity))
}

type Entity {
  Entity(
    id: Int,
    data: dataentity.Entity,
    update_subject: Option(Subject(Update)),
  )
}

type ControlledEntity {
  ControlledEntity(room_id: Int, update_subject: Subject(Update))
}

// actor functions
pub fn start(conn_string) -> Result(Subject(Command), actor.StartError) {
  // data loading
  let world = world.load_world(conn_string)

  let parent_subject = process.new_subject()

  let start_result =
    actor.start_spec(actor.Spec(
      init: fn() {
        // create the subject the main process to send control messages on
        let sim_subject = process.new_subject()
        process.send(parent_subject, sim_subject)

        let selector =
          process.new_selector()
          |> process.selecting(sim_subject, function.identity)

        let rooms =
          world.rooms
          |> dict.to_list()
          |> list.map(fn(kv) {
            #(kv.0, Room(template: kv.1, entities: dict.new()))
          })
          |> dict.from_list()

        actor.Ready(SimState(0, sim_subject, rooms, dict.new()), selector)
      },
      init_timeout: 1000,
      loop: loop,
    ))

  let assert Ok(sim_subject) = process.receive(parent_subject, 1000)

  case start_result {
    Ok(_) -> Ok(sim_subject)
    Error(err) -> Error(err)
  }
}

fn loop(message: Command, state: SimState) -> actor.Next(Command, SimState) {
  case message {
    Tick -> actor.continue(state)
    Shutdown -> actor.continue(state)
    JoinAsGuest(update_subject, client) -> {
      let room_id = 0
      let entity =
        Entity(
          id: state.next_entity_id,
          data: prefabs.create_guest_player(),
          update_subject: Some(update_subject),
        )
      process.send(client, Ok(entity.id))

      send_update_to_room(
        state,
        room_id,
        UpdatePlayerSpawned(query_entity_name(entity)),
      )

      let assert Ok(room) = dict.get(state.rooms, room_id)
      process.send(
        update_subject,
        UpdateRoomDescription(
          name: room.template.name,
          description: room.template.description,
          exits: room.template.exits,
        ),
      )

      actor.continue(
        state
        |> add_entity(entity, room_id)
        |> increment_next_entity_id,
      )
    }
    CommandQuit(entity_id) -> {
      // get all the stuff
      let assert Ok(controlled_entity) =
        dict.get(state.controlled_entities, entity_id)
      let assert Ok(entity) =
        get_entity(state, controlled_entity.room_id, entity_id)

      // remove the entity before sending updates
      let new_state =
        state
        |> remove_entity(entity_id, controlled_entity.room_id)

      // tell all other controlled entities in that room that the player quit
      send_update_to_room(
        new_state,
        controlled_entity.room_id,
        UpdatePlayerQuit(query_entity_name(entity)),
      )

      // continue without the entity
      actor.continue(new_state)
    }
    CommandLook(entity_id) -> {
      let assert Ok(controlled_entity) =
        dict.get(state.controlled_entities, entity_id)
      let assert Ok(room) = dict.get(state.rooms, controlled_entity.room_id)

      process.send(
        controlled_entity.update_subject,
        UpdateRoomDescription(
          name: room.template.name,
          description: room.template.description,
          exits: room.template.exits,
        ),
      )

      actor.continue(state)
    }
    CommandSayRoom(entity_id, text) -> {
      let assert Ok(controlled_entity) =
        dict.get(state.controlled_entities, entity_id)
      let assert Ok(entity) =
        get_entity(state, controlled_entity.room_id, entity_id)

      send_update_to_room(
        state,
        controlled_entity.room_id,
        UpdateSayRoom(query_entity_name(entity), text),
      )

      actor.continue(state)
    }

    AdminTeleport(entity_id, target_room_id) -> {
      let assert Ok(controlled_entity) =
        dict.get(state.controlled_entities, entity_id)
      let assert Ok(entity) =
        get_entity(state, controlled_entity.room_id, entity_id)

      case dict.get(state.rooms, target_room_id) {
        Ok(target_room) -> {
          send_update_to_room(
            state,
            target_room_id,
            UpdateEntityTeleportedIn(query_entity_name(entity)),
          )

          let new_state =
            state
            |> move_entity(entity, controlled_entity.room_id, target_room_id)

          process.send(
            controlled_entity.update_subject,
            UpdateRoomDescription(
              name: target_room.template.name,
              description: target_room.template.description,
              exits: target_room.template.exits,
            ),
          )

          send_update_to_room(
            new_state,
            controlled_entity.room_id,
            UpdateEntityTeleportedOut(query_entity_name(entity)),
          )

          actor.continue(new_state)
        }
        Error(Nil) -> {
          process.send(
            controlled_entity.update_subject,
            AdminCommandFailed("Invalid room ID"),
          )
          actor.continue(state)
        }
      }
    }
  }
}

pub fn stop(subject: Subject(Command)) {
  process.send(subject, Shutdown)
}

// state functions
fn add_entity(state: SimState, entity: Entity, room_id: Int) -> SimState {
  let assert Ok(room) = dict.get(state.rooms, room_id)
  case entity.update_subject {
    Some(subject) ->
      SimState(
        ..state,
        controlled_entities: dict.insert(
          state.controlled_entities,
          entity.id,
          ControlledEntity(room_id, subject),
        ),
        rooms: dict.insert(
          state.rooms,
          room_id,
          Room(..room, entities: dict.insert(room.entities, entity.id, entity)),
        ),
      )
    None ->
      SimState(
        ..state,
        rooms: dict.insert(
          state.rooms,
          room_id,
          Room(..room, entities: dict.insert(room.entities, entity.id, entity)),
        ),
      )
  }
}

fn remove_entity(state: SimState, entity_id: Int, room_id: Int) -> SimState {
  let assert Ok(room) = dict.get(state.rooms, room_id)
  SimState(
    ..state,
    controlled_entities: dict.delete(state.controlled_entities, entity_id),
    rooms: dict.insert(
      state.rooms,
      room_id,
      Room(..room, entities: dict.delete(room.entities, entity_id)),
    ),
  )
}

fn move_entity(
  state: SimState,
  entity: Entity,
  room_id: Int,
  target_room_id: Int,
) -> SimState {
  let assert Ok(room) = dict.get(state.rooms, room_id)
  let assert Ok(target_room) = dict.get(state.rooms, target_room_id)

  case entity.update_subject {
    Some(subject) ->
      SimState(
        ..state,
        controlled_entities: dict.insert(
          state.controlled_entities,
          entity.id,
          ControlledEntity(target_room_id, subject),
        ),
        rooms: state.rooms
        |> dict.insert(
          room_id,
          Room(..room, entities: dict.delete(room.entities, entity.id)),
        )
        |> dict.insert(
          target_room_id,
          Room(
            ..target_room,
            entities: dict.insert(target_room.entities, entity.id, entity),
          ),
        ),
      )
    None ->
      SimState(
        ..state,
        rooms: state.rooms
        |> dict.insert(
          room_id,
          Room(..room, entities: dict.delete(room.entities, entity.id)),
        )
        |> dict.insert(
          target_room_id,
          Room(
            ..target_room,
            entities: dict.insert(target_room.entities, entity.id, entity),
          ),
        ),
      )
  }
}

fn increment_next_entity_id(state: SimState) -> SimState {
  SimState(..state, next_entity_id: state.next_entity_id + 1)
}

// procedures
fn send_update_to_room(state: SimState, room_id: Int, update: Update) {
  let assert Ok(room) = dict.get(state.rooms, room_id)
  room.entities
  |> dict.to_list
  |> list.each(fn(kv) {
    case { kv.1 }.update_subject {
      Some(update_subject) -> {
        process.send(update_subject, update)
      }
      _ -> Nil
    }
  })
}

fn get_entity(
  state: SimState,
  room_id: Int,
  entity_id: Int,
) -> Result(Entity, Nil) {
  use room <- result.try(dict.get(state.rooms, room_id))
  dict.get(room.entities, entity_id)
}

fn query_entity_name(entity: Entity) -> String {
  let query =
    entity.data
    |> dataentity.query(dataentity.QueryName(None))
  case query {
    dataentity.QueryName(Some(name)) -> name
    _ -> "Unknown"
  }
}
