```
type ReportFile {
  ConstraintSystem constraints
  EventList events
}

type ConstraintSystem {
  List<ConstraintClusterHeader> headers
  List<ConstraintCluster> clusters
}

type ConstraintClusterHeader {
  CanonicalName owner
  int numberOfStorageLocations
}

type ConstraintCluster {
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
