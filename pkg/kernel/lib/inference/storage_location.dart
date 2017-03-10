// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.storage_location;

import '../ast.dart';
import 'extractor/value_sink.dart';
import 'extractor/value_source.dart';
import 'solver/solver.dart' as solver show StorageLocationBaseClass;
import 'value.dart';

/// An abstract storage location, with which the type inference will associate
/// an abstract value.
///
/// The inference algorithm must associate two things with a storage location:
/// - a [Value] summarizing what can flow in here
/// - whether the values that flow in here can escape
///
class StorageLocation extends solver.StorageLocationBaseClass
    implements ValueSource, ValueSink {
  final Reference reference; // Class or Member
  final int index;

  TypeParameterStorageLocation parameterLocation;

  StorageLocation(this.reference, this.index);

  NamedNode get owner => reference.node;

  String toString() => '$owner:$index';

  T acceptSink<T>(ValueSinkVisitor<T> visitor) {
    return visitor.visitStorageLocation(this);
  }

  T acceptSource<T>(ValueSourceVisitor<T> visitor) {
    return visitor.visitStorageLocation(this);
  }

  @override
  bool isBottom(int mask) {
    return false;
  }
}

class TypeParameterStorageLocation {
  final TreeNode owner;
  final int typeParameterIndex;

  /// Index of the storage location in the [owner]'s bank that corresponds to
  /// the upper bound of this type parameter.
  int indexOfBound;

  TypeParameterStorageLocation(this.owner, this.typeParameterIndex);
}
