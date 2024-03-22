import gleam/dict.{type Dict}
import gleam/otp/task
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
                region: "Test Region",
                name: "Test Room",
                description: "An empty test room. A black void of nothingness. You get the odd feeling there are actors here, communicating somehow. Some kind of play, perhaps?",
                exits: dict.new(),
              ),
            ),
        ),
      )
    })

  task.await(handle, 60_000)
}
