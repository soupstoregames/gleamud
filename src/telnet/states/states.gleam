pub type State {
  FirstIAC(client_dimensions: ClientDimensions)
  Menu(client_dimensions: ClientDimensions)
}

pub type ClientDimensions {
  ClientDimensions(width: Int, height: Int)
}
