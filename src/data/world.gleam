import gleam/dict.{type Dict}
import gleam/dynamic
import gleam/int
import gleam/list
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

pub fn parse_dir(str: String) -> Result(Direction, Nil) {
  case str {
    "north" | "n" -> Ok(North)
    "east" | "e" -> Ok(East)
    "south" | "s" -> Ok(South)
    "west" | "w" -> Ok(West)
    "northeast" | "ne" -> Ok(NorthEast)
    "southeast" | "se" -> Ok(SouthEast)
    "southwest" | "sw" -> Ok(SouthWest)
    "northwest" | "nw" -> Ok(NorthWest)
    "up" | "u" -> Ok(Up)
    "down" | "d" -> Ok(Down)
    _ -> Error(Nil)
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

pub fn dir_mirror(dir: Direction) -> Direction {
  case dir {
    North -> South
    East -> West
    South -> North
    West -> East
    NorthEast -> SouthWest
    SouthEast -> NorthWest
    SouthWest -> NorthEast
    NorthWest -> SouthEast
    Up -> Down
    Down -> Up
  }
}

pub type Error {
  SqlError(error: String)
}

pub fn load_world(conn_string: String) -> WorldTemplate {
  let world =
    WorldTemplate(rooms: dict.new())
    |> add_room(
      0,
      RoomTemplate(
        id: 0,
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

  let room_decoder = dynamic.tuple3(dynamic.int, dynamic.string, dynamic.string)
  let room_sql =
    "SELECT id, name, description 
      FROM rooms "

  let assert Ok(rows) =
    sqlight.query(room_sql, on: conn, with: [], expecting: room_decoder)

  let world =
    rows
    |> list.fold(world, fn(acc, row) {
      acc
      |> add_room(
        row.0,
        RoomTemplate(
          id: row.0,
          name: row.1,
          description: row.2,
          exits: dict.new(),
        ),
      )
    })

  let exit_decoder =
    dynamic.tuple4(dynamic.int, dynamic.string, dynamic.int, dynamic.int)
  let exit_sql =
    "SELECT id, direction, target_id, linked_exit
      FROM exits WHERE room_id = ?"

  WorldTemplate(
    rooms: world.rooms
    |> dict.map_values(fn(room_id, room) {
      let assert Ok(rows) =
        sqlight.query(
          exit_sql,
          on: conn,
          with: [sqlight.int(room_id)],
          expecting: exit_decoder,
        )

      rows
      |> list.fold(room, fn(acc, row) {
        let assert Ok(dir) = parse_dir(row.1)
        acc
        |> add_exit(Exit(
          id: row.0,
          direction: dir,
          target_room_id: row.2,
          linked_exit: row.3,
        ))
      })
    }),
  )
}

pub fn insert_room(conn_string, name: String) -> Result(Int, Error) {
  use conn <- sqlight.with_connection(conn_string)

  let sql =
    "INSERT INTO `rooms` (`name`, `description`) VALUES (?, '') RETURNING id;"

  let decoder = dynamic.element(0, dynamic.int)

  case
    sqlight.query(sql, on: conn, with: [sqlight.text(name)], expecting: decoder)
  {
    Ok(rows) -> {
      let assert Ok(id) = list.first(rows)
      Ok(id)
    }
    Error(sqlight.SqlightError(_code, message, _offset)) -> {
      Error(SqlError(message))
    }
  }
}

pub fn insert_exit(
  conn_string,
  dir: Direction,
  room_id: Int,
  reverse_dir: Direction,
  target_room_id: Int,
) -> Result(List(#(Int, Exit)), Error) {
  use conn <- sqlight.with_connection(conn_string)

  let sql =
    "INSERT INTO `exits` (`room_id`, `direction`, `target_id`, `linked_exit`) 
    VALUES (?, ?, ?, 0),  (?, ?, ?, 0) 
    RETURNING `id`, `room_id`, `direction`, `target_id`, `linked_exit`;"

  let decoder =
    dynamic.tuple5(
      dynamic.int,
      dynamic.int,
      dynamic.string,
      dynamic.int,
      dynamic.int,
    )

  case
    sqlight.query(
      sql,
      on: conn,
      with: [
        sqlight.int(room_id),
        sqlight.text(dir_to_str(dir)),
        sqlight.int(target_room_id),
        sqlight.int(target_room_id),
        sqlight.text(dir_to_str(reverse_dir)),
        sqlight.int(room_id),
      ],
      expecting: decoder,
    )
  {
    Ok(rows) -> {
      let ids =
        rows
        |> list.map(fn(row) { row.0 })
        |> list.reverse

      Ok(
        rows
        |> list.zip(ids)
        |> list.map(fn(tuple) {
          let #(row, other_id) = tuple
          let sql =
            "UPDATE `exits` SET `linked_exit` = "
            <> int.to_string(other_id)
            <> " WHERE id = "
            <> int.to_string(row.0)
            <> ";"
          let assert Ok(_) = sqlight.exec(sql, conn)

          let assert Ok(dir) = parse_dir(row.2)
          #(
            row.1,
            Exit(
              id: row.0,
              direction: dir,
              target_room_id: row.3,
              linked_exit: other_id,
            ),
          )
        }),
      )
    }
    Error(sqlight.SqlightError(_code, message, _offset)) -> {
      Error(SqlError(message))
    }
  }
}

pub fn update_room_name(
  conn_string,
  room_id: Int,
  name: String,
) -> Result(Nil, Error) {
  use conn <- sqlight.with_connection(conn_string)

  let decoder = dynamic.element(0, dynamic.int)
  let sql = "UPDATE `rooms` SET `name` = ? WHERE `id` = ? RETURNING id;"

  case
    sqlight.query(
      sql,
      on: conn,
      with: [sqlight.text(name), sqlight.int(room_id)],
      expecting: decoder,
    )
  {
    Ok(_) -> Ok(Nil)
    Error(sqlight.SqlightError(_code, message, _offset)) -> {
      Error(SqlError(message))
    }
  }
}

pub fn update_room_description(
  conn_string,
  room_id: Int,
  description: String,
) -> Result(Nil, Error) {
  use conn <- sqlight.with_connection(conn_string)

  let decoder = dynamic.element(0, dynamic.int)
  let sql = "UPDATE `rooms` SET `description` = ? WHERE `id` = ? RETURNING id;"

  case
    sqlight.query(
      sql,
      on: conn,
      with: [sqlight.text(description), sqlight.int(room_id)],
      expecting: decoder,
    )
  {
    Ok(_) -> Ok(Nil)
    Error(sqlight.SqlightError(_code, message, _offset)) -> {
      Error(SqlError(message))
    }
  }
}

pub type WorldTemplate {
  WorldTemplate(rooms: Dict(Int, RoomTemplate))
}

fn add_room(world: WorldTemplate, id: Int, room: RoomTemplate) {
  WorldTemplate(rooms: dict.insert(world.rooms, id, room))
}

pub type RoomTemplate {
  RoomTemplate(
    id: Int,
    name: String,
    description: String,
    exits: Dict(Direction, Exit),
  )
}

fn add_exit(room: RoomTemplate, exit: Exit) {
  RoomTemplate(..room, exits: dict.insert(room.exits, exit.direction, exit))
}

pub type Exit {
  Exit(id: Int, direction: Direction, target_room_id: Int, linked_exit: Int)
}
