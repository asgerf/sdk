library kernel.inference.raw_binding;

import 'package:kernel/ast.dart';
import 'package:kernel/inference/storage_location.dart';

class RawBinding {
  final Map<Reference, RawMemberBinding> storageLocations =
      <Reference, RawMemberBinding>{};

  RawMemberBinding getBinding(Reference owner) {
    return storageLocations[owner] ??=
        new RawMemberBinding(owner, <StorageLocation>[]);
  }
}

class RawMemberBinding {
  final Reference reference;
  final List<StorageLocation> locations;

  RawMemberBinding(this.reference, this.locations);
}
