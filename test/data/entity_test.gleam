import gleam/option.{None, Some}
import gleeunit/should
import data/entity.{handle_event, query}

pub fn query_name_test() {
  let named = entity.new([entity.Named("named")])

  let assert entity.QueryName(Some(name)) =
    named
    |> query(entity.QueryName(None))

  name
  |> should.equal("named")

  let not_named = entity.new([])

  let assert entity.QueryName(None) =
    not_named
    |> query(entity.QueryName(None))
}

pub fn query_status_test() {
  let status = entity.new([entity.Physical(10, 3)])

  let assert entity.QueryStatus(Some(hp)) =
    status
    |> query(entity.QueryStatus(None))

  hp
  |> should.equal(10)

  let no_hp = entity.new([])

  let assert entity.QueryStatus(None) =
    no_hp
    |> query(entity.QueryStatus(None))
}

pub fn query_equipable_test() {
  let equipable =
    entity.new([entity.Equipable([entity.PrimaryHand, entity.Back])])

  let assert entity.QueryEquipable(slots) =
    equipable
    |> query(entity.QueryEquipable([]))

  slots
  |> should.equal([entity.PrimaryHand, entity.Back])

  let not_equipable = entity.new([])

  let assert entity.QueryEquipable([]) =
    not_equipable
    |> query(entity.QueryEquipable([]))
}

pub fn query_paper_doll_test() {
  let paper_doll =
    entity.new([
      entity.PaperDollHead(Some(entity.new([entity.Named("Cap")]))),
      entity.PaperDollHead(None),
      entity.PaperDollBack(Some(entity.new([entity.Named("Backpack")]))),
      entity.PaperDollChest(Some(entity.new([]))),
      entity.PaperDollPrimaryHand(Some(entity.new([entity.Named("Sword")]))),
      entity.PaperDollOffHand(Some(entity.new([entity.Named("Buckler")]))),
      entity.PaperDollLegs(Some(entity.new([entity.Named("Trousers")]))),
      entity.PaperDollFeet(Some(entity.new([entity.Named("Boots")]))),
    ])

  let assert entity.QueryPaperDoll(slots) =
    paper_doll
    |> query(entity.QueryPaperDoll([]))

  slots
  |> should.equal([
    #(entity.Head, Some("Cap")),
    #(entity.Head, None),
    #(entity.Back, Some("Backpack")),
    #(entity.Chest, Some("unknown")),
    #(entity.PrimaryHand, Some("Sword")),
    #(entity.OffHand, Some("Buckler")),
    #(entity.Legs, Some("Trousers")),
    #(entity.Feet, Some("Boots")),
  ])
}

pub fn take_damage_test() {
  let ent = entity.new([entity.Physical(10, 3)])

  let assert #(ent, entity.TakeDamage(damage_amount)) =
    ent
    |> handle_event(entity.TakeDamage(4))

  let assert entity.QueryStatus(Some(hp)) =
    ent
    |> query(entity.QueryStatus(None))

  damage_amount
  |> should.equal(4)

  hp
  |> should.equal(6)
}

pub fn invulnerable_test() {
  let ent = entity.new([entity.Physical(10, 3), entity.Invulnerable])

  let assert #(ent, entity.TakeDamage(damage_amount)) =
    ent
    |> handle_event(entity.TakeDamage(4))

  let assert entity.QueryStatus(Some(hp)) =
    ent
    |> query(entity.QueryStatus(None))

  damage_amount
  |> should.equal(0)

  hp
  |> should.equal(10)
}
