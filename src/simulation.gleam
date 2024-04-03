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
}

/// Updates are sent from the sim to the game mux
pub type Update {
  UpdateRoomDescription(name: String, description: String)
  UpdatePlayerSpawned(name: String)
  UpdatePlayerQuit(name: String)
  UpdateSayRoom(name: String, text: String)
}

type SimState {
  SimState(
    next_entity_id: Int,
    sim_subject: Subject(Command),
    rooms: Dict(Int, Room),
    controlled_entity_room_ids: Dict(Int, Int),
  )
}

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
      loop: fn(message, state) -> actor.Next(Command, SimState) {
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
              UpdatePlayerSpawned(get_entity_name(entity)),
            )

            let assert Ok(room) = dict.get(state.rooms, room_id)
            process.send(
              update_subject,
              UpdateRoomDescription(
                name: room.template.name,
                description: room.template.description,
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
            let assert Ok(room_id) =
              dict.get(state.controlled_entity_room_ids, entity_id)
            let assert Ok(entity) = get_entity(state, entity_id, room_id)

            // remove the entity before sending updates
            let new_state =
              state
              |> remove_entity(entity_id, room_id)

            // tell all other controlled entities in that room that the player quit
            send_update_to_room(
              new_state,
              room_id,
              UpdatePlayerQuit(get_entity_name(entity)),
            )

            // continue without the entity
            actor.continue(new_state)
          }
          CommandLook(entity_id) -> {
            let assert Ok(room_id) =
              dict.get(state.controlled_entity_room_ids, entity_id)
            let assert Ok(room) = dict.get(state.rooms, room_id)
            let assert Ok(entity) = dict.get(room.entities, entity_id)

            case entity.update_subject {
              Some(update_subject) ->
                process.send(
                  update_subject,
                  UpdateRoomDescription(
                    name: room.template.name,
                    description: room.template.description,
                  ),
                )
              None -> Nil
            }

            actor.continue(state)
          }
          CommandSayRoom(entity_id, text) -> {
            let assert Ok(room_id) =
              dict.get(state.controlled_entity_room_ids, entity_id)
            let assert Ok(room) = dict.get(state.rooms, room_id)
            let assert Ok(entity) = dict.get(room.entities, entity_id)

            send_update_to_room(
              state,
              room_id,
              UpdateSayRoom(get_entity_name(entity), text),
            )

            actor.continue(state)
          }
        }
      },
    ))

  let assert Ok(sim_subject) = process.receive(parent_subject, 1000)

  case start_result {
    Ok(_) -> Ok(sim_subject)
    Error(err) -> Error(err)
  }
}

pub fn stop(subject: Subject(Command)) {
  process.send(subject, Shutdown)
}

fn add_entity(state: SimState, entity: Entity, room_id: Int) -> SimState {
  let assert Ok(room) = dict.get(state.rooms, room_id)
  SimState(
    ..state,
    controlled_entity_room_ids: dict.insert(
      state.controlled_entity_room_ids,
      entity.id,
      room_id,
    ),
    rooms: dict.insert(
      state.rooms,
      room_id,
      Room(..room, entities: dict.insert(room.entities, entity.id, entity)),
    ),
  )
}

fn get_entity(
  state: SimState,
  entity_id: Int,
  room_id: Int,
) -> Result(Entity, Nil) {
  use room <- result.try(dict.get(state.rooms, room_id))
  dict.get(room.entities, entity_id)
}

fn remove_entity(state: SimState, entity_id: Int, room_id: Int) -> SimState {
  let assert Ok(room) = dict.get(state.rooms, room_id)
  SimState(
    ..state,
    controlled_entity_room_ids: dict.delete(
      state.controlled_entity_room_ids,
      entity_id,
    ),
    rooms: dict.insert(
      state.rooms,
      room_id,
      Room(..room, entities: dict.delete(room.entities, entity_id)),
    ),
  )
}

fn increment_next_entity_id(state: SimState) -> SimState {
  SimState(..state, next_entity_id: state.next_entity_id + 1)
}

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

fn get_entity_name(entity: Entity) -> String {
  let query =
    entity.data
    |> dataentity.query(dataentity.QueryName(None))
  case query {
    dataentity.QueryName(Some(name)) -> name
    _ -> "Unknown"
  }
}
