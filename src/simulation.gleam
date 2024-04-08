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
import gleam/io

/// Commands are sent from game connections to entities
pub type Command {
  Tick
  Shutdown
  JoinAsGuest(Subject(Update), reply_with: Subject(Result(Int, Nil)))

  CommandQuit(entity_id: Int)
  CommandLook(entity_id: Int)
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

      case query_entity_name(entity) {
        Some(name) ->
          send_update_to_room(
            state,
            room_id,
            UpdatePlayerSpawned(#(name, entity.id)),
          )
        _ -> Nil
      }

      let assert Ok(room) = dict.get(state.rooms, room_id)
      let entities = list_entities(entity.id, room)
      process.send(
        update_subject,
        UpdateRoomDescription(
          name: #(room.template.name, room.template.id),
          description: room.template.description,
          exits: room.template.exits,
          sentient_entities: entities.0,
          static_entities: entities.1,
        ),
      )

      actor.continue(
        state
        |> add_entity(entity, room_id)
        |> increment_next_temp_entity_id,
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
      case query_entity_name(entity) {
        Some(name) ->
          send_update_to_room(
            state,
            controlled_entity.room_id,
            UpdatePlayerQuit(#(name, entity.id)),
          )
        _ -> Nil
      }

      // continue without the entity
      actor.continue(new_state)
    }
    CommandLook(entity_id) -> {
      let assert Ok(controlled_entity) =
        dict.get(state.controlled_entities, entity_id)
      let assert Ok(room) = dict.get(state.rooms, controlled_entity.room_id)
      let entities = list_entities(entity_id, room)

      process.send(
        controlled_entity.update_subject,
        UpdateRoomDescription(
          name: #(room.template.name, room.template.id),
          description: room.template.description,
          exits: room.template.exits,
          sentient_entities: entities.0,
          static_entities: entities.1,
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
        UpdateSayRoom(#(query_entity_name_forced(entity), entity.id), text),
      )

      actor.continue(state)
    }
    CommandMove(entity_id, dir) -> {
      let assert Ok(controlled_entity) =
        dict.get(state.controlled_entities, entity_id)
      let assert Ok(room) = dict.get(state.rooms, controlled_entity.room_id)

      case dict.get(room.template.exits, dir) {
        Ok(target_room_id) -> {
          // get the entity data in order to get the name
          let assert Ok(entity) =
            get_entity(state, controlled_entity.room_id, entity_id)
          // get the target room for the description and arrived text
          let assert Ok(target_room) = dict.get(state.rooms, target_room_id)

          // find the exit that goes the other way
          let assert Ok(reverse_exit) =
            target_room.template.exits
            |> dict.to_list
            |> list.find(fn(exit) { exit.1 == controlled_entity.room_id })

          // tell the entities in the target room that this entity arrived
          case query_entity_name(entity) {
            Some(name) ->
              send_update_to_room(
                state,
                target_room_id,
                UpdateEntityArrived(#(name, entity.id), reverse_exit.0),
              )
            _ -> Nil
          }

          // move the entity
          let new_state =
            state
            |> move_entity(entity, controlled_entity.room_id, target_room_id)

          // send the entity the new room description
          let entities = list_entities(entity_id, target_room)
          process.send(
            controlled_entity.update_subject,
            UpdateRoomDescription(
              name: #(target_room.template.name, target_room.template.id),
              description: target_room.template.description,
              exits: target_room.template.exits,
              sentient_entities: entities.0,
              static_entities: entities.1,
            ),
          )

          // tell all the entities left behind that the player left
          case query_entity_name(entity) {
            Some(name) ->
              send_update_to_room(
                state,
                controlled_entity.room_id,
                UpdateEntityLeft(#(name, entity.id), dir),
              )
            _ -> Nil
          }

          actor.continue(new_state)
        }
        Error(Nil) -> {
          process.send(
            controlled_entity.update_subject,
            UpdateCommandFailed(reason: "There is no exit that way."),
          )
          actor.continue(state)
        }
      }
    }

    AdminHide(entity_id) -> {
      let assert Ok(controlled_entity) =
        dict.get(state.controlled_entities, entity_id)
      let assert Ok(entity) =
        get_entity(state, controlled_entity.room_id, entity_id)

      case dataentity.query(entity.data, dataentity.QueryInvisible(False)) {
        dataentity.QueryInvisible(True) -> {
          process.send(
            controlled_entity.update_subject,
            UpdateCommandFailed("Already hidden"),
          )
          actor.continue(state)
        }
        _ -> {
          case query_entity_name(entity) {
            Some(name) ->
              send_update_to_room(
                state,
                controlled_entity.room_id,
                UpdateEntityVanished(#(name, entity.id)),
              )
            _ -> Nil
          }

          actor.continue(
            state
            |> add_components(controlled_entity.room_id, entity, [
              dataentity.Invisible,
            ]),
          )
        }
      }
    }
    AdminShow(entity_id) -> {
      let assert Ok(controlled_entity) =
        dict.get(state.controlled_entities, entity_id)
      let assert Ok(entity) =
        get_entity(state, controlled_entity.room_id, entity_id)

      case dataentity.query(entity.data, dataentity.QueryInvisible(False)) {
        dataentity.QueryInvisible(False) -> {
          process.send(
            controlled_entity.update_subject,
            UpdateCommandFailed("Already visible"),
          )
          actor.continue(state)
        }
        _ -> {
          let new_state =
            state
            |> remove_components(
              controlled_entity.room_id,
              entity,
              dataentity.TInvisible,
            )
          let assert Ok(entity) =
            get_entity(new_state, controlled_entity.room_id, entity_id)

          case query_entity_name(entity) {
            Some(name) ->
              send_update_to_room(
                new_state,
                controlled_entity.room_id,
                UpdateEntityAppeared(#(name, entity.id)),
              )
            _ -> Nil
          }

          actor.continue(new_state)
        }
      }
    }
    AdminTeleport(entity_id, target_room_id) -> {
      let assert Ok(controlled_entity) =
        dict.get(state.controlled_entities, entity_id)
      let assert Ok(entity) =
        get_entity(state, controlled_entity.room_id, entity_id)

      case dict.get(state.rooms, target_room_id) {
        Ok(target_room) -> {
          case query_entity_name(entity) {
            Some(name) ->
              send_update_to_room(
                state,
                target_room_id,
                UpdateEntityAppeared(#(name, entity.id)),
              )
            _ -> Nil
          }

          let new_state =
            state
            |> move_entity(entity, controlled_entity.room_id, target_room_id)

          let entities = list_entities(entity_id, target_room)
          process.send(
            controlled_entity.update_subject,
            UpdateRoomDescription(
              name: #(target_room.template.name, target_room.template.id),
              description: target_room.template.description,
              exits: target_room.template.exits,
              sentient_entities: entities.0,
              static_entities: entities.1,
            ),
          )

          case query_entity_name(entity) {
            Some(name) ->
              send_update_to_room(
                new_state,
                controlled_entity.room_id,
                UpdateEntityVanished(#(name, entity.id)),
              )
            _ -> Nil
          }

          actor.continue(new_state)
        }
        Error(Nil) -> {
          process.send(
            controlled_entity.update_subject,
            UpdateCommandFailed("Invalid room ID"),
          )
          actor.continue(state)
        }
      }
    }
    AdminDig(entity_id, room_name) -> {
      let assert Ok(controlled_entity) =
        dict.get(state.controlled_entities, entity_id)

      case world.insert_room(state.conn_string, room_name) {
        Ok(id) -> {
          process.send(
            controlled_entity.update_subject,
            UpdateAdminRoomCreated(room_id: id, name: room_name),
          )

          actor.continue(
            state
            |> build_room(
              id,
              world.RoomTemplate(
                id: id,
                name: room_name,
                description: "",
                exits: dict.new(),
              ),
            ),
          )
        }
        Error(world.SqlError(message)) -> {
          process.send(
            controlled_entity.update_subject,
            UpdateCommandFailed(reason: "SQL Error: " <> message),
          )
          actor.continue(state)
        }
      }
    }
    AdminTunnel(entity_id, dir, target_room_id, reverse_dir) -> {
      let assert Ok(controlled_entity) =
        dict.get(state.controlled_entities, entity_id)
      let assert Ok(room) = dict.get(state.rooms, controlled_entity.room_id)

      // cant tunnel to room 0
      case controlled_entity.room_id == 0, target_room_id == 0 {
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
                  case
                    world.insert_exit(
                      state.conn_string,
                      dir,
                      controlled_entity.room_id,
                      reverse_dir,
                      target_room_id,
                    )
                  {
                    Ok(_) -> {
                      // update running state
                      let new_state =
                        state
                        |> build_exit(
                          controlled_entity.room_id,
                          dir,
                          target_room_id,
                        )
                        |> build_exit(
                          target_room_id,
                          reverse_dir,
                          controlled_entity.room_id,
                        )

                      // send confirmation
                      process.send(
                        controlled_entity.update_subject,
                        UpdateAdminExitCreated(dir, target_room_id),
                      )

                      actor.continue(new_state)
                    }
                    Error(world.SqlError(message)) -> {
                      process.send(
                        controlled_entity.update_subject,
                        UpdateCommandFailed(reason: "SQL Error: " <> message),
                      )
                      actor.continue(state)
                    }
                  }
                }
                _, _ -> {
                  process.send(
                    controlled_entity.update_subject,
                    UpdateCommandFailed(
                      reason: "One of the directions already has an exit.",
                    ),
                  )
                  actor.continue(state)
                }
              }
            Error(Nil) -> {
              process.send(
                controlled_entity.update_subject,
                UpdateCommandFailed(reason: "Non-existent room."),
              )
              actor.continue(state)
            }
          }
        _, _ -> {
          process.send(
            controlled_entity.update_subject,
            UpdateCommandFailed(reason: "Cannot tunnel into room #0."),
          )
          actor.continue(state)
        }
      }
    }
    AdminRoomName(entity_id, name) -> {
      let assert Ok(controlled_entity) =
        dict.get(state.controlled_entities, entity_id)

      case controlled_entity.room_id == 0 {
        False ->
          case
            world.update_room_name(
              state.conn_string,
              controlled_entity.room_id,
              name,
            )
          {
            Ok(Nil) -> {
              let new_state =
                state
                |> set_room_name(controlled_entity.room_id, name)

              let assert Ok(room) =
                dict.get(new_state.rooms, controlled_entity.room_id)

              let entities = list_entities(entity_id, room)
              process.send(
                controlled_entity.update_subject,
                UpdateRoomDescription(
                  name: #(room.template.name, room.template.id),
                  description: room.template.description,
                  exits: room.template.exits,
                  sentient_entities: entities.0,
                  static_entities: entities.1,
                ),
              )

              actor.continue(new_state)
            }
            Error(world.SqlError(message)) -> {
              process.send(
                controlled_entity.update_subject,
                UpdateCommandFailed(reason: "SQL Error: " <> message),
              )
              actor.continue(state)
            }
          }
        True -> {
          process.send(
            controlled_entity.update_subject,
            UpdateCommandFailed(reason: "Cannot update room #0."),
          )
          actor.continue(state)
        }
      }
    }
    AdminRoomDescription(entity_id, description) -> {
      let assert Ok(controlled_entity) =
        dict.get(state.controlled_entities, entity_id)

      case controlled_entity.room_id == 0 {
        False ->
          case
            world.update_room_description(
              state.conn_string,
              controlled_entity.room_id,
              description,
            )
          {
            Ok(Nil) -> {
              let new_state =
                state
                |> set_room_description(controlled_entity.room_id, description)

              let assert Ok(room) =
                dict.get(new_state.rooms, controlled_entity.room_id)

              let entities = list_entities(entity_id, room)
              process.send(
                controlled_entity.update_subject,
                UpdateRoomDescription(
                  name: #(room.template.name, room.template.id),
                  description: room.template.description,
                  exits: room.template.exits,
                  sentient_entities: entities.0,
                  static_entities: entities.1,
                ),
              )

              actor.continue(new_state)
            }
            Error(world.SqlError(message)) -> {
              process.send(
                controlled_entity.update_subject,
                UpdateCommandFailed(reason: "SQL Error: " <> message),
              )
              actor.continue(state)
            }
          }
        True -> {
          process.send(
            controlled_entity.update_subject,
            UpdateCommandFailed(reason: "Cannot update room #0."),
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
  entity: Entity,
  components: List(dataentity.Component),
) -> State {
  let assert Ok(room) = dict.get(state.rooms, room_id)
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
  entity: Entity,
  component_type: dataentity.ComponentType,
) -> State {
  let assert Ok(room) = dict.get(state.rooms, room_id)
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
  entity: Entity,
  room_id: Int,
  target_room_id: Int,
) -> State {
  let assert Ok(room) = dict.get(state.rooms, room_id)
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

// procedures
fn send_update_to_room(state: State, room_id: Int, update: Update) {
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

fn get_entity(state: State, room_id: Int, entity_id: Int) -> Result(Entity, Nil) {
  use room <- result.try(dict.get(state.rooms, room_id))
  dict.get(room.entities, entity_id)
}

fn query_entity_name(entity: Entity) -> Option(String) {
  let query =
    entity.data
    |> dataentity.query(dataentity.QueryName(None))
  case query {
    dataentity.QueryName(Some(name)) -> Some(name)
    _ -> None
  }
}

fn query_entity_name_forced(entity: Entity) -> String {
  let query =
    entity.data
    |> dataentity.query(dataentity.QueryNameForced(None))
  case query {
    dataentity.QueryNameForced(Some(name)) -> name
    _ -> "Unknown"
  }
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
      entity.data
      |> dataentity.query(dataentity.QuerySentient(False))
    let name_query =
      entity.data
      |> dataentity.query(dataentity.QueryName(None))

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
