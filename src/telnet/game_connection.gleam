import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import telnet/states
import simulation
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
  sim_subject: Subject(simulation.Command),
  conn: glisten.Connection(BitArray),
) -> Result(Subject(Message), actor.StartError) {
  actor.start_spec(actor.Spec(
    init: fn() {
      let tcp_subject = process.new_subject()
      process.send(parent_subject, tcp_subject)

      let update_subject = process.new_subject()

      let selector =
        process.new_selector()
        |> process.selecting(tcp_subject, function.identity)
        |> process.selecting(update_subject, fn(msg) { Update(msg) })

      actor.Ready(
        ConnState(
          tcp_subject,
          states.FirstIAC(
            conn: conn,
            update_subject: update_subject,
            dimensions: states.ClientDimensions(80, 24),
            entity_id: 0,
            sim_subject: sim_subject,
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
    states.FirstIAC(conn, update_subject, _, entity_id, sim_subject) ->
      actor.continue(
        ConnState(
          ..state,
          game_state: states.Menu(
            conn,
            update_subject,
            states.ClientDimensions(width, height),
            entity_id,
            sim_subject,
          )
          |> states.on_enter(),
        ),
      )

    states.Menu(conn, update_subject, _, entity_id, sim_subject) ->
      actor.continue(
        ConnState(
          ..state,
          game_state: states.Menu(
            conn,
            update_subject,
            states.ClientDimensions(width, height),
            entity_id,
            sim_subject,
          ),
        ),
      )

    states.InWorld(conn, update_subject, _, entity_id, sim_subject) ->
      actor.continue(
        ConnState(
          ..state,
          game_state: states.InWorld(
            conn,
            update_subject,
            states.ClientDimensions(width, height),
            entity_id,
            sim_subject,
          ),
        ),
      )

    states.RoomSay(conn, update_subject, _, entity_id, sim_subject) ->
      actor.continue(
        ConnState(
          ..state,
          game_state: states.RoomSay(
            conn,
            update_subject,
            states.ClientDimensions(width, height),
            entity_id,
            sim_subject,
          ),
        ),
      )
  }
}

fn handle_data(
  state: ConnState,
  data: BitArray,
) -> actor.Next(Message, ConnState) {
  actor.continue(
    ConnState(
      ..state,
      game_state: state.game_state
      |> states.handle_input(data),
    ),
  )
}

fn handle_update(
  state: ConnState,
  update: simulation.Update,
) -> actor.Next(Message, ConnState) {
  actor.continue(
    ConnState(
      ..state,
      game_state: state.game_state
      |> states.handle_update(update),
    ),
  )
}
