import gleam/dict.{type Dict}

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

pub fn load_world() -> WorldTemplate {
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
