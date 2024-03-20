import gleam/dict.{type Dict}
import gleam/otp/task
import model/core

pub type DataError {
  DataError
}

pub type RoomTemplate {
  RoomTemplate(
    name: String,
    description: String,
    exits: Dict(core.Direction, core.Location),
  )
}

pub type RegionTemplate {
  RegionTemplate(name: String, rooms: Dict(String, RoomTemplate))
}

fn add_room(region: RegionTemplate, id: String, room: RoomTemplate) {
  RegionTemplate(..region, rooms: dict.insert(region.rooms, id, room))
}

pub type WorldTemplate {
  WorldTemplate(regions: Dict(String, RegionTemplate))
}

fn add_region(world: WorldTemplate, id: String, region: RegionTemplate) {
  WorldTemplate(regions: dict.insert(world.regions, id, region))
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
            |> add_room(
              "testroom",
              RoomTemplate(
                name: "Test Room",
                description: "An empty test room",
                exits: dict.new(),
              ),
            ),
        ),
      )
    })

  task.await(handle, 60_000)
}
