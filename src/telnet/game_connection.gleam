import gleam/erlang/process.{type Subject}
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/string_builder
import telnet/states/states
import model/simulation
import gleam/function
import glisten

pub type Message {
  Dimensions(Int, Int)
  Data(BitArray)
  Update(simulation.Update)
}

type ConnState {
  ConnState(tcp_subject: Subject(Message), game_state: states.State)
}

pub fn start(
  parent_subject: Subject(Subject(Message)),
  sim_subject: Subject(simulation.Control),
  conn: glisten.Connection(BitArray),
) -> Result(Subject(Message), actor.StartError) {
  actor.start_spec(actor.Spec(
    init: fn() {
      let tcp_subject = process.new_subject()
      process.send(parent_subject, tcp_subject)

      let selector =
        process.new_selector()
        |> process.selecting(tcp_subject, function.identity)

      actor.Ready(
        ConnState(
          tcp_subject,
          states.FirstIAC(
            conn: conn,
            dimensions: states.ClientDimensions(80, 24),
            directory: states.Directory(
              sim_subject: sim_subject,
              command_subject: None,
            ),
            buffer: "",
          ),
        ),
        selector,
      )
    },
    init_timeout: 1000,
    loop: handle_message,
  ))
}

fn handle_message(
  message: Message,
  state: ConnState,
) -> actor.Next(Message, ConnState) {
  case message {
    Dimensions(width, height) -> handle_dimensions(state, width, height)
    Data(bits) -> handle_data(state, bits)
    Update(update) -> handle_update(state, update)
  }
}

fn handle_dimensions(
  state: ConnState,
  width: Int,
  height: Int,
) -> actor.Next(Message, ConnState) {
  // move this into state
  case state.game_state {
    states.FirstIAC(conn, _, directory, buffer) ->
      actor.continue(
        ConnState(
          ..state,
          game_state: states.Menu(
            conn,
            states.ClientDimensions(width, height),
            directory,
            buffer,
          )
          |> states.on_enter(),
        ),
      )

    states.Menu(conn, _, directory, buffer) ->
      actor.continue(
        ConnState(
          ..state,
          game_state: states.Menu(
            conn,
            states.ClientDimensions(width, height),
            directory,
            buffer,
          ),
        ),
      )

    states.InWorld(conn, _, directory, buffer) ->
      actor.continue(
        ConnState(
          ..state,
          game_state: states.InWorld(
            conn,
            states.ClientDimensions(width, height),
            directory,
            buffer,
          ),
        ),
      )
  }
}

fn handle_data(
  state: ConnState,
  data: BitArray,
) -> actor.Next(Message, ConnState) {
  let #(new_state, command_subject) =
    state.game_state
    |> states.handle_input(data)

  case command_subject {
    Some(update_subject) ->
      actor.with_selector(
        actor.continue(ConnState(..state, game_state: new_state)),
        process.new_selector()
          |> process.selecting(state.tcp_subject, function.identity)
          |> process.selecting(update_subject, fn(update) { Update(update) }),
      )
    None -> actor.continue(ConnState(..state, game_state: new_state))
  }
}

fn handle_update(
  state: ConnState,
  update: simulation.Update,
) -> actor.Next(Message, ConnState) {
  case update {
    simulation.CommandSubject(subject) ->
      actor.continue(
        ConnState(
          ..state,
          game_state: states.with_command_subject(state.game_state, subject),
        ),
      )
    simulation.RoomDescription(_, _, _) -> {
      actor.continue(
        ConnState(
          ..state,
          game_state: state.game_state
          |> states.handle_update(update),
        ),
      )
    }
  }
}
