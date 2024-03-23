import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/function
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import data/core
import data/entity as dataentity
import data/prefabs
import data/world

/// Control message are sent by top level actors to control the sim directly
pub type Control {
  JoinAsGuest(Subject(Update))
  Tick
  Shutdown
}

/// Commands are sent from game connections to entities
pub type Command {
  CommandLook
  CommandSayRoom(text: String)
}

/// Updates are sent from entities to game connections
pub type Update {
  UpdateCommandSubject(Subject(Command))
  UpdateRoomDescription(region: String, name: String, description: String)
  UpdateSayRoom(name: String, text: String)
}

type SimMessage {
  Control(Control)
  Sim(Internal)
}

type Internal {
  TTick
  SpawnActorEntity(dataentity.Entity, core.Location, Subject(Update))

  RoomDescriptionUp(Subject(Internal))
  RoomDescriptionDown(region: String, name: String, description: String)

  RoomSayUp(name: String, text: String)
  RoomSayDown(name: String, text: String)
}

type SimState {
  SimState(
    next_id: Int,
    world_template: world.WorldTemplate,
    sim_subject: Subject(Internal),
    regions: Dict(String, Subject(Internal)),
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
            let assert Ok(subject) = start_region(kv.1, sim_subject)
            #(kv.0, subject)
          })
          |> dict.from_list()

        // always select control messages from the main process and sim messages from the child regions
        let selector =
          process.new_selector()
          |> process.selecting(control_subject, fn(msg) { Control(msg) })
          |> process.selecting(sim_subject, fn(msg) { Sim(msg) })

        actor.Ready(SimState(0, world, sim_subject, regions), selector)
      },
      init_timeout: 1000,
      loop: fn(message, state) -> actor.Next(SimMessage, SimState) {
        case message {
          Control(JoinAsGuest(update_subject)) -> {
            let location = core.Location("testregion", "testing-room")
            let entity =
              dataentity.Entity(state.next_id, prefabs.create_guest_player())
            let assert Ok(region_subject) =
              dict.get(state.regions, location.region)
            process.send(
              region_subject,
              SpawnActorEntity(entity, location, update_subject),
            )
            actor.continue(SimState(..state, next_id: state.next_id + 1))
          }

          Control(Tick) -> {
            // forward the tick to all regions
            state.regions
            |> dict.to_list()
            |> list.each(fn(kv) { process.send(kv.1, TTick) })
            actor.continue(state)
          }

          Control(Shutdown) -> actor.Stop(process.Normal)

          _ -> actor.continue(state)
        }
      },
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

type RegionState {
  RegionState(
    template: world.RegionTemplate,
    sim_subject: Subject(Internal),
    rooms: Dict(String, Subject(Internal)),
  )
}

fn start_region(
  template: world.RegionTemplate,
  sim_subject: Subject(Internal),
) -> Result(Subject(Internal), actor.StartError) {
  let parent_subject = process.new_subject()
  let start_result =
    actor.start_spec(actor.Spec(
      init: fn() {
        // create a Internal subject for the sim or child rooms to talk to the region
        let region_subject = process.new_subject()
        process.send(parent_subject, region_subject)

        // spawn the rooms which will spawn the rooms
        // later this will be done ad hoc to cut down on redundant actors
        //   and to support instances
        let rooms =
          template.rooms
          |> dict.to_list()
          |> list.map(fn(kv) {
            let assert Ok(subject) = start_room(kv.1, region_subject)
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
      loop: fn(message, state) -> actor.Next(Internal, RegionState) {
        case message {
          TTick -> {
            // forward the tick to all rooms
            state.rooms
            |> dict.to_list()
            |> list.each(fn(kv) { process.send(kv.1, TTick) })

            actor.continue(state)
          }
          SpawnActorEntity(entity, location, update_subject) -> {
            let assert Ok(room_subject) = dict.get(state.rooms, location.room)
            process.send(
              room_subject,
              SpawnActorEntity(entity, location, update_subject),
            )
            actor.continue(state)
          }
          _ -> actor.continue(state)
        }
      },
    ))

  // receive the region subject from the region actor
  let assert Ok(region_subject) = process.receive(parent_subject, 1000)

  case start_result {
    Ok(_) -> Ok(region_subject)
    Error(err) -> Error(err)
  }
}

type RoomState {
  RoomState(
    template: world.RoomTemplate,
    region_subject: Subject(Internal),
    room_subject: Subject(Internal),
    entities: Dict(Int, Subject(Internal)),
  )
}

fn start_room(
  template: world.RoomTemplate,
  region_subject: Subject(Internal),
) -> Result(Subject(Internal), actor.StartError) {
  let parent_subject = process.new_subject()
  let start_result =
    actor.start_spec(actor.Spec(
      init: fn() {
        // create a Internal subject for the region or child entities to talk to the room
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
      loop: fn(message, state) -> actor.Next(Internal, RoomState) {
        case message {
          TTick -> actor.continue(state)
          SpawnActorEntity(entity, _, update_subject) -> {
            let assert Ok(ent) =
              start_entity(entity, state.room_subject, update_subject)
            actor.continue(
              RoomState(
                ..state,
                entities: dict.insert(state.entities, entity.id, ent),
              ),
            )
          }
          RoomDescriptionUp(reply) -> {
            process.send(
              reply,
              RoomDescriptionDown(
                state.template.region,
                state.template.name,
                state.template.description,
              ),
            )
            actor.continue(state)
          }
          RoomSayUp(name, text) -> {
            state.entities
            |> dict.to_list()
            |> list.each(fn(kv) { process.send(kv.1, RoomSayDown(name, text)) })
            actor.continue(state)
          }
          _ -> actor.continue(state)
        }
      },
    ))

  // receive the room subject from the room actor
  let assert Ok(room_subject) = process.receive(parent_subject, 1000)

  case start_result {
    Ok(_) -> Ok(room_subject)
    Error(err) -> Error(err)
  }
}

type EntityMessage {
  InternalMessage(Internal)
  CommandMessage(Command)
}

type EntityState {
  EntityState(
    entity: dataentity.Entity,
    // the subject for this entity
    entity_subject: Subject(Internal),
    // the subject to talk to the parent room
    room_subject: Subject(Internal),
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
fn start_entity(
  entity: dataentity.Entity,
  room_subject: Subject(Internal),
  update_subject: Subject(Update),
) -> Result(Subject(Internal), actor.StartError) {
  let parent_subject = process.new_subject()

  let start_result =
    actor.start_spec(actor.Spec(
      init: fn() {
        // send the entity subject back to the constructor to be returned
        let entity_subject: Subject(Internal) = process.new_subject()
        process.send(parent_subject, entity_subject)

        // send the command subject over the update subject to the game connection
        let command_subject = process.new_subject()
        process.send(update_subject, UpdateCommandSubject(command_subject))

        // request initial room description
        process.send(room_subject, RoomDescriptionUp(entity_subject))

        // 
        let selector =
          process.new_selector()
          |> process.selecting(entity_subject, fn(msg) { InternalMessage(msg) })
          |> process.selecting(command_subject, fn(msg) { CommandMessage(msg) })

        actor.Ready(
          EntityState(
            entity,
            entity_subject,
            room_subject,
            command_subject,
            update_subject,
          ),
          selector,
        )
      },
      init_timeout: 1000,
      loop: fn(message, state) -> actor.Next(EntityMessage, EntityState) {
        case message {
          InternalMessage(TTick) -> actor.continue(state)
          InternalMessage(RoomDescriptionDown(region, name, description)) -> {
            process.send(
              state.update_subject,
              UpdateRoomDescription(region, name, description),
            )
            actor.continue(state)
          }
          InternalMessage(RoomSayDown(name, text)) -> {
            process.send(state.update_subject, UpdateSayRoom(name, text))
            actor.continue(state)
          }
          CommandMessage(CommandLook) -> {
            process.send(room_subject, RoomDescriptionUp(state.entity_subject))
            actor.continue(state)
          }
          CommandMessage(CommandSayRoom(text)) -> {
            let query =
              state.entity
              |> dataentity.query(dataentity.QueryName(None))
            let name = case query {
              dataentity.QueryName(Some(name)) -> name
              _ -> "Unknown"
            }
            process.send(room_subject, RoomSayUp(name, text))
            actor.continue(state)
          }
          _ -> actor.continue(state)
        }
      },
    ))

  let assert Ok(entity_subject) = process.receive(parent_subject, 1000)

  case start_result {
    Ok(_) -> Ok(entity_subject)
    Error(err) -> Error(err)
  }
}
