```
type ReportFile {
  List<BindingData> items
  ConstraintSystem constraints
  EventList events
}

type BindingData {
  CanonicalName owner
  int numberOfStorageLocations
}

type ConstraintSystem {
  List<MemberConstraints> constraints
}

type MemberConstraints {
  CanonicalName owner
  List<Constraint> constraints
}

type EventList {
  List<TransferEvent> transfers
}

type TransferEvent {
  ConstraintReference constraint
  List<ChangeEvent> changes
}

type ChangeEvent {
  StorageLocationReference location
  Value value
  Byte leadsToEscape // 0 or 1
}

type ConstraintReference {
  CanonicalName owner
  int index
}

type StorageLocationReference {
  CanonicalName owner
  int index
}

abstract type Constraint {}

// TODO list constraints
```
