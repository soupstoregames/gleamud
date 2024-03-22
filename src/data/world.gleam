import gleam/dict.{type Dict}
import gleam/list
import gleam/otp/task
import gleam/string
import simplifile
import tom
import data/core

pub type DataError {
  DataError
}

pub type RoomTemplate {
  RoomTemplate(
    region: String,
    name: String,
    description: String,
    exits: Dict(core.Direction, core.Location),
  )
}

pub type RegionTemplate {
  RegionTemplate(name: String, rooms: Dict(String, RoomTemplate))
}

fn add_room(region: RegionTemplate, room_file: String) {
  let rooms =
    parse_room_file("data/" <> room_file <> ".toml")
    |> dict.insert(region.rooms, room_file, _)

  RegionTemplate(..region, rooms: rooms)
}

pub type WorldTemplate {
  WorldTemplate(regions: Dict(String, RegionTemplate))
}

fn add_region(world: WorldTemplate, id: String, region: RegionTemplate) {
  WorldTemplate(regions: dict.insert(world.regions, id, region))
}

fn insert_exit(
  dict: Dict(core.Direction, core.Location),
  direction: core.Direction,
  location_result: Result(core.Location, _),
) {
  case location_result {
    Ok(location) -> dict.insert(dict, direction, location)
    _ -> dict
  }
}

fn parse_exit(
  toml: Dict(String, tom.Toml),
  keys: List(String),
) -> Result(core.Location, String) {
  let region =
    tom.get_string(
      toml,
      keys
        |> list.append(["region"]),
    )
  let room =
    tom.get_string(
      toml,
      keys
        |> list.append(["room"]),
    )

  case region, room {
    Ok(region), Ok(room) -> Ok(core.Location(region, room))
    _, _ -> Error({ "Could not parse exit for " <> string.concat(keys) })
  }
}

fn parse_room_file(file_name: String) -> RoomTemplate {
  let assert Ok(file_contents) = simplifile.read(from: file_name)
  let assert Ok(room_data) = tom.parse(file_contents)
  let assert Ok(name) = tom.get_string(room_data, ["name"])
  let assert Ok(region) = tom.get_string(room_data, ["region"])
  let assert Ok(description) = tom.get_string(room_data, ["description"])

  RoomTemplate(
    region: region,
    name: name,
    description: description,
    exits: dict.new()
      |> insert_exit(core.North, parse_exit(room_data, ["exits", "north"]))
      |> insert_exit(core.North, parse_exit(room_data, ["exits", "north"]))
      |> insert_exit(core.South, parse_exit(room_data, ["exits", "south"]))
      |> insert_exit(core.East, parse_exit(room_data, ["exits", "east"]))
      |> insert_exit(core.West, parse_exit(room_data, ["exits", "west"]))
      |> insert_exit(core.Up, parse_exit(room_data, ["exits", "up"]))
      |> insert_exit(core.Down, parse_exit(room_data, ["exits", "down"]))
      |> insert_exit(
        core.NorthEast,
        parse_exit(room_data, ["exits", "northeast"]),
      )
      |> insert_exit(
        core.NorthWest,
        parse_exit(room_data, ["exits", "northwest"]),
      )
      |> insert_exit(
        core.SouthEast,
        parse_exit(room_data, ["exits", "southeast"]),
      )
      |> insert_exit(
        core.SouthWest,
        parse_exit(room_data, ["exits", "southwest"]),
      ),
  )
}

pub fn load_world() -> Result(WorldTemplate, DataError) {
  let handle =
    task.async(fn() {
      // this will eventually call out to the file system
      Ok(
        WorldTemplate(regions: dict.new())
        |> add_region(
          "testregion",
          RegionTemplate(name: "Test Region", rooms: dict.new())
            |> add_room("ramp-gate-research"),
        ),
      )
    })

  task.await(handle, 60_000)
}
