// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
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

  StorageLocation getStorageLocation(Reference owner, int index) {
    var locations = storageLocations[owner];
    if (locations == null) {
      throw 'There are no bindings for $owner';
    }
    return locations.locations[index];
  }

  void setBinding(Reference owner, List<StorageLocation> locations) {
    storageLocations[owner] = new RawMemberBinding(owner, locations);
  }
}

class RawMemberBinding {
  final Reference reference;
  final List<StorageLocation> locations;

  RawMemberBinding(this.reference, this.locations);
}
