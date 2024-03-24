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

pub type Location {
  Location(region: Int, room: Int)
}
