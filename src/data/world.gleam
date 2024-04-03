import gleam/dict.{type Dict}
import gleam/dynamic
import gleam/list
import gleam/option.{Some}
import sqlight

pub type Direction {
  North
  East
  South
  West
  NorthEast
  SouthEast
  SouthWest
  NorthWest
  Up
  Down
}

fn str_to_dir(str: String) -> Direction {
  case str {
    "north" -> North
    "east" -> East
    "south" -> South
    "west" -> West
    "northeast" -> NorthEast
    "southeast" -> SouthEast
    "southwest" -> SouthWest
    "northwest" -> NorthWest
    "up" -> Up
    "down" -> Down
    _ -> Up
  }
}

pub fn dir_to_str(dir: Direction) -> String {
  case dir {
    North -> "north"
    East -> "east"
    South -> "south"
    West -> "west"
    NorthEast -> "northeast"
    SouthEast -> "southeast"
    SouthWest -> "southwest"
    NorthWest -> "northwest"
    Up -> "up"
    Down -> "down"
  }
}

pub fn load_world(conn_string: String) -> WorldTemplate {
  let base_world =
    WorldTemplate(rooms: dict.new())
    |> add_room(
      0,
      RoomTemplate(
        name: "The Testing Room",
        description: "
In the vast expanse of an empty void, there exists a swirling energy brimming with limitless possibility. Though intangible, its presence is palpable, weaving threads of potentiality that stretch into infinity. 
Within this ethereal realm, unseen actors move and interact, their forms mere whispers in the cosmic winds. Through the boundless ether, they communicate in a language of energy and intention, exchanging ideas and emotions beyond the constraints of physicality. Each interaction is a dance of creativity and expression, shaping the very fabric of this limitless expanse with their collective consciousness.

Commands:
quit         exit the game
look         get the room description again
say <text>   say a message to the room
/say         toggle on 'say' mode where anything typed is sent as chat
/e           go back to command mode
",
        exits: dict.new(),
      ),
    )

  use conn <- sqlight.with_connection(conn_string)

  let sql =
    "SELECT rooms.id, rooms.name, rooms.description, exits.direction, exits.target_id FROM rooms LEFT JOIN exits ON rooms.id = exits.room_id;"

  let room_decoder =
    dynamic.tuple5(
      dynamic.int,
      dynamic.string,
      dynamic.string,
      dynamic.optional(dynamic.string),
      dynamic.optional(dynamic.int),
    )

  let assert Ok(rows) =
    sqlight.query(sql, on: conn, with: [], expecting: room_decoder)

  rows
  |> list.fold(base_world, fn(world, row) {
    case dict.get(world.rooms, row.0) {
      Ok(room) -> {
        case row.3, row.4 {
          Some(dir), Some(target) -> {
            world
            |> add_room(
              row.0,
              room
                |> add_exit(str_to_dir(dir), target),
            )
          }
          _, _ -> world
        }
      }
      Error(Nil) -> {
        case row.3, row.4 {
          Some(dir), Some(target) ->
            world
            |> add_room(
              row.0,
              RoomTemplate(name: row.1, description: row.2, exits: dict.new())
                |> add_exit(str_to_dir(dir), target),
            )
          _, _ ->
            world
            |> add_room(
              row.0,
              RoomTemplate(name: row.1, description: row.2, exits: dict.new()),
            )
        }
      }
    }
  })
}

pub type WorldTemplate {
  WorldTemplate(rooms: Dict(Int, RoomTemplate))
}

fn add_room(world: WorldTemplate, id: Int, room: RoomTemplate) {
  WorldTemplate(rooms: dict.insert(world.rooms, id, room))
}

pub type RoomTemplate {
  RoomTemplate(name: String, description: String, exits: Dict(Direction, Int))
}

fn add_exit(room: RoomTemplate, direction: Direction, location: Int) {
  RoomTemplate(..room, exits: dict.insert(room.exits, direction, location))
}
