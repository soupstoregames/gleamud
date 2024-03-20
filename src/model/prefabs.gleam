import gleam/int
import gleam/option.{None}
import model/entity

pub fn create_guest_player() {
  entity.new([
    entity.Named(name: "Guest" <> int.to_string(int.random(99_999))),
    entity.Physical(hp: 10, size: 0),
    entity.PaperDollHead(entity: None),
    entity.PaperDollBack(entity: None),
    entity.PaperDollChest(entity: None),
    entity.PaperDollPrimaryHand(entity: None),
    entity.PaperDollOffHand(entity: None),
    entity.PaperDollLegs(entity: None),
    entity.PaperDollFeet(entity: None),
  ])
}
