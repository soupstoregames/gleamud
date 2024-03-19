import gleam/int
import gleam/list
import gleam/option.{type Option, Some}

pub type DiceRoll {
  DiceRoll(sides: Int, number: Int)
}

pub type DamageType {
  Bludgeoning
  Slashing
  Piercing

  Fire
  Ice
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
  PaperDollSlot(slot_type: PaperDollSlotType, entity: Option(Entity))
}

pub type Entity {
  Entity(components: List(Component))
}

pub fn new(components: List(Component)) -> Entity {
  Entity(
    components
    |> list.sort(fn(a, b) {
      int.compare(component_priority(a), component_priority(b))
    }),
  )
}

pub type Component {
  Invulnerable

  Named(name: String)
  Physical(hp: Int, size: Int)

  PaperDoll(slots: List(PaperDollSlot))
  Equipable(slot_types: List(PaperDollSlotType))

  MeleeWeapon(damage: DiceRoll, damage_type: DamageType)
}

fn component_priority(component: Component) -> Int {
  case component {
    Invulnerable -> 1

    Named(_) -> 100
    Physical(_, _) -> 110

    PaperDoll(_) -> 1000
    Equipable(_) -> 1100

    MeleeWeapon(_, _) -> 10_000
  }
}

pub type Query {
  QueryName(name: Option(String))
  QueryStatus(hp: Option(Int))
  QueryEquipable(slots: List(PaperDollSlotType))
}

pub type Event {
  AddComponents(components: List(Component))

  TakeDamage(amount: Int)
  AddPaperDollSlot(slot: PaperDollSlot)
}

pub fn query(entity: Entity, query: Query) -> Query {
  list.fold(entity.components, query, query_loop)
}

fn query_loop(query: Query, component: Component) -> Query {
  case component, query {
    Named(name), QueryName(_) -> QueryName(name: Some(name))
    Physical(hp, _size), QueryStatus(_) -> QueryStatus(hp: Some(hp))
    Equipable(slots), QueryEquipable(_) -> QueryEquipable(slots: slots)
    _, _ -> query
  }
}

pub fn handle_event(entity: Entity, event: Event) -> #(Entity, Event) {
  case event {
    AddComponents(components) -> {
      let new_components =
        components
        |> list.fold(entity.components, fn(components, component) {
          [component, ..components]
        })
        |> list.sort(fn(a, b) {
          int.compare(component_priority(a), component_priority(b))
        })
      #(Entity(components: new_components), event)
    }
    _ -> {
      let event = list.fold(entity.components, event, transform_event)
      let new_components = list.map(entity.components, apply_event(_, event))
      #(Entity(components: new_components), event)
    }
  }
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
