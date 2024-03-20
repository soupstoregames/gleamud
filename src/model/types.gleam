// import gleam/dict.{type Dict}
// import model/entity.{type Entity}

// pub type Direction {
//   North
//   East
//   South
//   West
//   NorthEast
//   SouthEast
//   SouthWest
//   NorthWest
//   Up
//   Down
// }

// pub type Location {
//   Location(region: String, room: String)
// }

// pub type RoomTemplate {
//   RoomTemplate(name: String, description: String, exits: Dict(Direction, Exit))
// }

// pub type RegionTemplate {
//   RegionTemplate(name: String, rooms: Dict(String, RoomTemplate))
// }

// pub type Room {
//   Room(location: Location, entities: List(Entity))
// }

// pub type Region {
//   Region(name: String, rooms: Dict(String, Room))
//   RegionInstance(name: String, rooms: Dict(String, Room))
// }

// pub type World {
//   World(templates: Dict(String, RegionTemplate), regions: Dict(String, Region))
// }
