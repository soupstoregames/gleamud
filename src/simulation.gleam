import gleam/bool
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
  CommandEmote(entity_id: Int, text: String)
  CommandSayRoom(entity_id: Int, text: String)
  CommandMove(entity_id: Int, dir: world.Direction)

  AdminHide(entity_id: Int)
  AdminShow(entity_id: Int)
  AdminTeleport(entity_id: Int, room_id: Int)
  AdminDig(entity_id: Int, room_name: String)
  AdminTunnel(
    entity_id: Int,
    dir: world.Direction,
    target_room_id: Int,
    reverse_dir: world.Direction,
  )
  AdminRoomName(entity_id: Int, name: String)
  AdminRoomDescription(entity_id: Int, description: String)
}

pub fn command_requires_admin(command: Command) -> Bool {
  case command {
    AdminHide(_) -> True
    AdminShow(_) -> True
    AdminTeleport(_, _) -> True
    AdminDig(_, _) -> True
    AdminTunnel(_, _, _, _) -> True
    AdminRoomName(_, _) -> True
    AdminRoomDescription(_, _) -> True
    _ -> False
  }
}

/// Updates are sent from the sim to the game mux
pub type Update {
  UpdateCommandFailed(reason: String)
  UpdateRoomDescription(
    name: #(String, Int),
    description: String,
    exits: Dict(world.Direction, Int),
    sentient_entities: List(#(String, Int)),
    static_entities: List(#(String, Int)),
  )
  UpdatePlayerSpawned(name: #(String, Int))
  UpdatePlayerQuit(name: #(String, Int))
  UpdateEmote(name: #(String, Int), text: String)
  UpdateSayRoom(name: #(String, Int), text: String)
  UpdateEntityLeft(name: #(String, Int), dir: world.Direction)
  UpdateEntityArrived(name: #(String, Int), dir: world.Direction)

  // admin stuff
  UpdateEntityVanished(name: #(String, Int))
  UpdateEntityAppeared(name: #(String, Int))
  UpdateAdminRoomCreated(room_id: Int, name: String)
  UpdateAdminExitCreated(dir: world.Direction, target_room_id: Int)
}

type State {
  State(
    conn_string: String,
    next_temp_entity_id: Int,
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

        actor.Ready(
          State(conn_string, -1, sim_subject, rooms, dict.new()),
          selector,
        )
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

fn loop(message: Command, state: State) -> actor.Next(Command, State) {
  case message {
    Tick -> actor.continue(state)
    Shutdown -> actor.continue(state)
    JoinAsGuest(update_subject, client) -> {
      let room_id = 0
      let entity =
        Entity(
          id: state.next_temp_entity_id,
          data: prefabs.create_guest_player(),
          update_subject: Some(update_subject),
        )
      process.send(client, Ok(entity.id))

      let assert dataentity.QueryNameForced(Some(name)) =
        dataentity.query(entity.data, dataentity.QueryNameForced(None))

      state
      |> send_update_to_room(room_id, UpdatePlayerSpawned(#(name, entity.id)))
      |> add_entity(entity, room_id)
      |> send_room_description_to_entity(entity.id, room_id)
      |> increment_next_temp_entity_id
      |> actor.continue
    }
    //MARK: Command handlers
    CommandQuit(entity_id) -> {
      // get all the stuff
      let assert Ok(ce) = dict.get(state.controlled_entities, entity_id)
      let room_id = ce.room_id

      // tell all other controlled entities in that room that the player quit
      case query_entity_name(state, room_id, entity_id) {
        Some(name) ->
          state
          |> remove_entity(entity_id, room_id)
          |> send_update_to_room(room_id, UpdatePlayerQuit(#(name, entity_id)))
          |> actor.continue
        _ ->
          state
          |> remove_entity(entity_id, room_id)
          |> actor.continue
      }
    }
    CommandLook(entity_id) -> {
      let assert Ok(ce) = dict.get(state.controlled_entities, entity_id)
      let room_id = ce.room_id

      state
      |> send_room_description_to_entity(entity_id, room_id)
      |> actor.continue
    }
    CommandEmote(entity_id, text) -> {
      let assert Ok(ce) = dict.get(state.controlled_entities, entity_id)
      let room_id = ce.room_id
      let entity_name = query_entity_name_forced(state, room_id, entity_id)

      state
      |> send_update_to_room(
        room_id,
        UpdateEmote(#(entity_name, entity_id), text),
      )
      |> actor.continue
    }
    CommandSayRoom(entity_id, text) -> {
      let assert Ok(ce) = dict.get(state.controlled_entities, entity_id)
      let room_id = ce.room_id
      let entity_name = query_entity_name_forced(state, room_id, entity_id)

      state
      |> send_update_to_room(
        room_id,
        UpdateSayRoom(#(entity_name, entity_id), text),
      )
      |> actor.continue
    }
    CommandMove(entity_id, dir) -> {
      let assert Ok(ce) = dict.get(state.controlled_entities, entity_id)
      let room_id = ce.room_id

      let assert Ok(room) = dict.get(state.rooms, room_id)
      case dict.get(room.template.exits, dir) {
        Ok(target_room_id) -> {
          let assert Ok(entity) = get_entity(state, room_id, entity_id)
          let assert Ok(target_room) = dict.get(state.rooms, target_room_id)

          // find the exit that goes the other way
          let assert Ok(reverse_exit) =
            target_room.template.exits
            |> dict.to_list
            |> list.find(fn(exit) { exit.1 == room_id })

          case query_entity_name(state, room_id, entity_id) {
            Some(name) -> {
              state
              |> send_update_to_room(
                target_room_id,
                UpdateEntityArrived(#(name, entity.id), reverse_exit.0),
              )
              |> move_entity(room_id, entity.id, target_room_id)
              |> send_room_description_to_entity(entity_id, target_room_id)
              |> send_update_to_room(
                room_id,
                UpdateEntityLeft(#(name, entity.id), dir),
              )
              |> actor.continue
            }
            _ ->
              state
              |> move_entity(room_id, entity.id, target_room_id)
              |> send_room_description_to_entity(entity_id, target_room_id)
              |> actor.continue
          }
        }
        Error(Nil) -> {
          state
          |> send_failed_to_entity(entity_id, "There is no exit that way.")
          |> actor.continue
        }
      }
    }

    //MARK: Admin command handling
    AdminHide(entity_id) -> {
      let assert Ok(ce) = dict.get(state.controlled_entities, entity_id)
      let room_id = ce.room_id

      case query_entity_visible(state, room_id, entity_id) {
        True -> {
          case query_entity_name(state, room_id, entity_id) {
            Some(name) ->
              state
              |> send_update_to_room(
                room_id,
                UpdateEntityVanished(#(name, entity_id)),
              )
              |> add_components(room_id, entity_id, [dataentity.Invisible])
              |> actor.continue
            _ ->
              state
              |> add_components(room_id, entity_id, [dataentity.Invisible])
              |> actor.continue
          }
        }
        False -> {
          state
          |> send_failed_to_entity(entity_id, "Already hidden")
          |> actor.continue
        }
      }
    }
    AdminShow(entity_id) -> {
      let assert Ok(ce) = dict.get(state.controlled_entities, entity_id)
      let room_id = ce.room_id

      case query_entity_visible(state, room_id, entity_id) {
        True -> {
          state
          |> send_failed_to_entity(entity_id, "Already visible")
          |> actor.continue
        }
        False -> {
          let name = query_entity_name_forced(state, room_id, entity_id)
          state
          |> remove_components(room_id, entity_id, dataentity.TInvisible)
          |> send_update_to_room(
            room_id,
            UpdateEntityAppeared(#(name, entity_id)),
          )
          |> actor.continue
        }
      }
    }
    AdminTeleport(entity_id, target_room_id) -> {
      let assert Ok(ce) = dict.get(state.controlled_entities, entity_id)
      let room_id = ce.room_id

      case dict.has_key(state.rooms, target_room_id) {
        True -> {
          case query_entity_name(state, room_id, entity_id) {
            Some(name) -> {
              state
              |> send_update_to_room(
                target_room_id,
                UpdateEntityAppeared(#(name, entity_id)),
              )
              |> move_entity(room_id, entity_id, target_room_id)
              |> send_room_description_to_entity(entity_id, target_room_id)
              |> send_update_to_room(
                room_id,
                UpdateEntityVanished(#(name, entity_id)),
              )
              |> actor.continue
            }
            _ -> {
              state
              |> move_entity(room_id, entity_id, target_room_id)
              |> send_room_description_to_entity(entity_id, target_room_id)
              |> actor.continue
            }
          }
        }
        False -> {
          state
          |> send_failed_to_entity(entity_id, "Invalid room ID")
          |> actor.continue
        }
      }
    }
    AdminDig(entity_id, room_name) -> {
      case world.insert_room(state.conn_string, room_name) {
        Ok(id) -> {
          state
          |> send_update_to_entity(
            entity_id,
            UpdateAdminRoomCreated(room_id: id, name: room_name),
          )
          |> build_room(id, world.RoomTemplate(id, room_name, "", dict.new()))
          |> actor.continue
        }
        Error(world.SqlError(message)) -> {
          state
          |> send_failed_to_entity(entity_id, "SQL Error: " <> message)
          |> actor.continue
        }
      }
    }
    AdminTunnel(entity_id, dir, target_room_id, reverse_dir) -> {
      let assert Ok(ce) = dict.get(state.controlled_entities, entity_id)
      let room_id = ce.room_id
      let assert Ok(room) = dict.get(state.rooms, room_id)

      // cant tunnel to room 0
      case room_id == 0, target_room_id == 0 {
        False, False ->
          // check the target room exists and get it
          case dict.get(state.rooms, target_room_id) {
            Ok(target_room) ->
              // check that the requested exits dont already exist
              case
                dict.has_key(room.template.exits, dir),
                dict.has_key(target_room.template.exits, reverse_dir)
              {
                False, False -> {
                  // create in db
                  let insert_result =
                    world.insert_exit(
                      state.conn_string,
                      dir,
                      room_id,
                      reverse_dir,
                      target_room_id,
                    )
                  case insert_result {
                    Ok(_) -> {
                      state
                      |> build_exit(room_id, dir, target_room_id)
                      |> build_exit(target_room_id, reverse_dir, room_id)
                      |> send_update_to_entity(
                        entity_id,
                        UpdateAdminExitCreated(dir, target_room_id),
                      )
                      |> actor.continue
                    }
                    Error(world.SqlError(message)) -> {
                      state
                      |> send_failed_to_entity(
                        entity_id,
                        "SQL Error: " <> message,
                      )
                      |> actor.continue
                    }
                  }
                }
                _, _ -> {
                  state
                  |> send_failed_to_entity(
                    entity_id,
                    "One of the directions already has an exit.",
                  )
                  |> actor.continue
                }
              }
            Error(Nil) -> {
              state
              |> send_failed_to_entity(entity_id, "Non-existent room.")
              |> actor.continue
            }
          }
        _, _ -> {
          state
          |> send_failed_to_entity(entity_id, "Cannot tunnel into room #0.")
          |> actor.continue
        }
      }
    }
    AdminRoomName(entity_id, name) -> {
      let assert Ok(ce) = dict.get(state.controlled_entities, entity_id)
      let room_id = ce.room_id

      case room_id == 0 {
        False ->
          case world.update_room_name(state.conn_string, room_id, name) {
            Ok(Nil) -> {
              state
              |> set_room_name(room_id, name)
              |> send_room_description_to_entity(entity_id, room_id)
              |> actor.continue
            }
            Error(world.SqlError(message)) -> {
              state
              |> send_failed_to_entity(entity_id, "SQL Error: " <> message)
              |> actor.continue
            }
          }
        True -> {
          state
          |> send_failed_to_entity(entity_id, "Cannot update room #0.")
          |> actor.continue
        }
      }
    }
    AdminRoomDescription(entity_id, description) -> {
      let assert Ok(ce) = dict.get(state.controlled_entities, entity_id)
      let room_id = ce.room_id

      case room_id == 0 {
        False -> {
          let update_result =
            world.update_room_description(
              state.conn_string,
              room_id,
              description,
            )
          case update_result {
            Ok(Nil) -> {
              state
              |> set_room_description(room_id, description)
              |> send_room_description_to_entity(entity_id, room_id)
              |> actor.continue
            }
            Error(world.SqlError(message)) -> {
              state
              |> send_failed_to_entity(entity_id, "SQL Error: " <> message)
              |> actor.continue
            }
          }
        }
        True -> {
          state
          |> send_failed_to_entity(entity_id, "Cannot update room #0.")
          |> actor.continue
        }
      }
    }
  }
}

pub fn stop(subject: Subject(Command)) {
  process.send(subject, Shutdown)
}

//MARK: state functions
fn add_entity(state: State, entity: Entity, room_id: Int) -> State {
  let assert Ok(room) = dict.get(state.rooms, room_id)
  case entity.update_subject {
    Some(subject) ->
      State(
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
      State(
        ..state,
        rooms: dict.insert(
          state.rooms,
          room_id,
          Room(..room, entities: dict.insert(room.entities, entity.id, entity)),
        ),
      )
  }
}

fn remove_entity(state: State, entity_id: Int, room_id: Int) -> State {
  let assert Ok(room) = dict.get(state.rooms, room_id)
  State(
    ..state,
    controlled_entities: dict.delete(state.controlled_entities, entity_id),
    rooms: dict.insert(
      state.rooms,
      room_id,
      Room(..room, entities: dict.delete(room.entities, entity_id)),
    ),
  )
}

fn add_components(
  state: State,
  room_id: Int,
  entity_id: Int,
  components: List(dataentity.Component),
) -> State {
  let assert Ok(room) = dict.get(state.rooms, room_id)
  let assert Ok(entity) = dict.get(room.entities, entity_id)
  State(
    ..state,
    rooms: dict.insert(
      state.rooms,
      room_id,
      Room(
        ..room,
        entities: dict.insert(
          room.entities,
          entity.id,
          Entity(
            ..entity,
            data: dataentity.add_components(entity.data, components),
          ),
        ),
      ),
    ),
  )
}

fn remove_components(
  state: State,
  room_id: Int,
  entity_id: Int,
  component_type: dataentity.ComponentType,
) -> State {
  let assert Ok(room) = dict.get(state.rooms, room_id)
  let assert Ok(entity) = dict.get(room.entities, entity_id)
  State(
    ..state,
    rooms: dict.insert(
      state.rooms,
      room_id,
      Room(
        ..room,
        entities: dict.insert(
          room.entities,
          entity.id,
          Entity(
            ..entity,
            data: dataentity.remove_all_components_of_type(
              entity.data,
              component_type,
            ),
          ),
        ),
      ),
    ),
  )
}

fn move_entity(
  state: State,
  room_id: Int,
  entity_id: Int,
  target_room_id: Int,
) -> State {
  let assert Ok(room) = dict.get(state.rooms, room_id)
  let assert Ok(entity) = dict.get(room.entities, entity_id)
  let assert Ok(target_room) = dict.get(state.rooms, target_room_id)

  case entity.update_subject {
    Some(subject) ->
      State(
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
      State(
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

fn increment_next_temp_entity_id(state: State) -> State {
  State(..state, next_temp_entity_id: state.next_temp_entity_id - 1)
}

fn build_room(state: State, room_id: Int, template: world.RoomTemplate) -> State {
  State(
    ..state,
    rooms: dict.insert(
      state.rooms,
      room_id,
      Room(template: template, entities: dict.new()),
    ),
  )
}

fn build_exit(
  state: State,
  room_id: Int,
  dir: world.Direction,
  target_room_id: Int,
) -> State {
  let assert Ok(room) = dict.get(state.rooms, room_id)

  State(
    ..state,
    rooms: dict.insert(
      state.rooms,
      room_id,
      Room(
        ..room,
        template: world.RoomTemplate(
          ..room.template,
          exits: dict.insert(room.template.exits, dir, target_room_id),
        ),
      ),
    ),
  )
}

fn set_room_name(state: State, room_id: Int, name: String) -> State {
  let assert Ok(room) = dict.get(state.rooms, room_id)

  State(
    ..state,
    rooms: dict.insert(
      state.rooms,
      room_id,
      Room(..room, template: world.RoomTemplate(..room.template, name: name)),
    ),
  )
}

fn set_room_description(
  state: State,
  room_id: Int,
  description: String,
) -> State {
  let assert Ok(room) = dict.get(state.rooms, room_id)

  State(
    ..state,
    rooms: dict.insert(
      state.rooms,
      room_id,
      Room(
        ..room,
        template: world.RoomTemplate(..room.template, description: description),
      ),
    ),
  )
}

//MARK: procedures
fn send_update_to_entity(state: State, entity_id: Int, update: Update) {
  let assert Ok(controlled_entity) =
    dict.get(state.controlled_entities, entity_id)

  process.send(controlled_entity.update_subject, update)

  state
}

fn send_room_description_to_entity(state: State, entity_id: Int, room_id: Int) {
  let assert Ok(controlled_entity) =
    dict.get(state.controlled_entities, entity_id)
  let assert Ok(room) = dict.get(state.rooms, room_id)
  let entities = list_entities(entity_id, room)

  let update =
    UpdateRoomDescription(
      name: #(room.template.name, room.template.id),
      description: room.template.description,
      exits: room.template.exits,
      sentient_entities: entities.0,
      static_entities: entities.1,
    )

  process.send(controlled_entity.update_subject, update)

  state
}

fn send_failed_to_entity(state: State, entity_id: Int, reason: String) {
  let assert Ok(controlled_entity) =
    dict.get(state.controlled_entities, entity_id)

  process.send(controlled_entity.update_subject, UpdateCommandFailed(reason))

  state
}

fn send_update_to_room(state: State, room_id: Int, update: Update) -> State {
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
  state
}

//MARK: queries
fn get_entity(state: State, room_id: Int, entity_id: Int) -> Result(Entity, Nil) {
  use room <- result.try(dict.get(state.rooms, room_id))
  dict.get(room.entities, entity_id)
}

fn query_entity_name(
  state: State,
  room_id: Int,
  entity_id: Int,
) -> Option(String) {
  let assert Ok(entity) = get_entity(state, room_id, entity_id)
  let query =
    entity.data
    |> dataentity.query(dataentity.QueryName(None))
  case query {
    dataentity.QueryName(Some(name)) -> Some(name)
    _ -> None
  }
}

fn query_entity_name_forced(
  state: State,
  room_id: Int,
  entity_id: Int,
) -> String {
  let assert Ok(entity) = get_entity(state, room_id, entity_id)
  let query =
    entity.data
    |> dataentity.query(dataentity.QueryNameForced(None))
  case query {
    dataentity.QueryNameForced(Some(name)) -> name
    _ -> "Unknown"
  }
}

fn query_entity_visible(state: State, room_id: Int, entity_id: Int) -> Bool {
  let assert Ok(entity) = get_entity(state, room_id, entity_id)
  let assert dataentity.QueryInvisible(invisible) =
    entity.data
    |> dataentity.query(dataentity.QueryInvisible(False))
  bool.negate(invisible)
}

fn list_entities(
  viewer_id: Int,
  room: Room,
) -> #(List(#(String, Int)), List(#(String, Int))) {
  room.entities
  |> dict.values
  |> list.filter(fn(entity) { entity.id != viewer_id })
  |> list.fold(#([], []), fn(acc, entity) {
    let sentient_query =
      dataentity.query(entity.data, dataentity.QuerySentient(False))
    let name_query = dataentity.query(entity.data, dataentity.QueryName(None))

    case name_query, sentient_query {
      dataentity.QueryName(Some(name)), dataentity.QuerySentient(True) -> #(
        [#(name, entity.id), ..acc.0],
        acc.1,
      )
      dataentity.QueryName(Some(name)), dataentity.QuerySentient(False) -> #(
        acc.0,
        [#(name, entity.id), ..acc.1],
      )
      _, _ -> acc
    }
  })
}
