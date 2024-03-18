import gleam/int
import gleam/list

pub type DiceRoll {
  D6(number: Int)
}

pub type DamageType {
  Brute
  Burn
  Shock
}

pub type PaperDollSlotType {
  Head
  Chest
  Back
  Hand
  Legs
  Feet
}

fn paper_doll_slot_type_value(slot_type: PaperDollSlotType) -> Int {
  case slot_type {
    Head -> 0
    Chest -> 1
    Back -> 2
    Hand -> 3
    Legs -> 4
    Feet -> 5
  }
}

pub type PaperDollSlot {
  PaperDollSlot(slot_type: PaperDollSlotType, entity: Entity)
}

pub type Entity {
  Entity(components: List(Component))
}

pub type Component {
  Invulnerable

  Named(name: String)
  Physical(hp: Int, size: Int)

  PaperDoll(slots: List(PaperDollSlot))
  Equipable(slot_type: PaperDollSlotType)

  MeleeWeapon(damage: DiceRoll, damage_type: DamageType)
}

pub type Query {
  QueryName(name: String)
  QueryStatus(hp: Int)
}

pub type Event {
  TakeDamage(amount: Int)
  AddPaperDollSlot(slot: PaperDollSlot)
}

pub fn query(entity: Entity, query: Query) -> Query {
  list.fold(entity.components, query, query_loop)
}

fn query_loop(query: Query, component: Component) -> Query {
  case component, query {
    Named(name), QueryName(_) -> QueryName(name: name)
    Physical(hp, _size), QueryStatus(_) -> QueryStatus(hp: hp)
    _, _ -> query
  }
}

pub fn handle_event(entity: Entity, event: Event) -> #(Entity, Event) {
  let event = list.fold(entity.components, event, transform_event)
  let new_components = list.map(entity.components, apply_event(_, event))
  #(Entity(components: new_components), event)
}

fn transform_event(event: Event, component: Component) -> Event {
  case component, event {
    Invulnerable, TakeDamage(_amount) -> TakeDamage(amount: 0)
    _, _ -> event
  }
}

fn apply_event(component: Component, event: Event) -> Component {
  case component, event {
    Physical(hp, size), TakeDamage(amount) ->
      Physical(hp: hp - amount, size: size)
    PaperDoll(slots), AddPaperDollSlot(slot) -> {
      let new_slots =
        slots
        |> list.append([slot])
        |> list.sort(fn(slot_a: PaperDollSlot, slot_b: PaperDollSlot) {
          let val_a = paper_doll_slot_type_value(slot_a.slot_type)
          let val_b = paper_doll_slot_type_value(slot_b.slot_type)
          int.compare(val_a, val_b)
        })
      PaperDoll(slots: new_slots)
    }
    _, _ -> component
  }
}
