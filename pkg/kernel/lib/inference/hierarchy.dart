// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.strong_inference.hierarchy;

import '../ast.dart';
import '../class_hierarchy.dart';
import 'augmented_type.dart';
import 'binding.dart';
import 'substitution.dart';

class AugmentedHierarchy {
  final ClassHierarchy baseHierarchy;
  final List<Map<Class, Substitution>> _supertypes;

  AugmentedHierarchy(ClassHierarchy hierarchy, Binding bindings)
      : this.baseHierarchy = hierarchy,
        _supertypes =
            new List<Map<Class, Substitution>>(hierarchy.classes.length) {
    for (int i = 0; i < hierarchy.classes.length; ++i) {
      Class class_ = hierarchy.classes[i];
      var map = _supertypes[i] = <Class, Substitution>{};
      map[class_] = Substitution.empty;
      for (ASupertype super_ in bindings.getSupertypes(class_)) {
        int superIndex = hierarchy.getClassIndex(super_.classNode);
        assert(superIndex < i);
        var superMap = _supertypes[superIndex];
        var ownSubstitution = Substitution.fromSupertype(super_);
        superMap.forEach((Class grandSuper, Substitution superSubstitution) {
          map[grandSuper] =
              Substitution.sequence(superSubstitution, ownSubstitution);
        });
      }
    }
  }

  Substitution getClassAsInstanceOf(Class subclass, Class superclass) {
    int index = baseHierarchy.getClassIndex(subclass);
    return _supertypes[index][superclass];
  }

  InterfaceAType getTypeAsInstanceOf(InterfaceAType subtype, Class superclass) {
    if (identical(subtype.classNode, superclass)) return subtype;
    var superSubstitution = getClassAsInstanceOf(subtype.classNode, superclass);
    if (superSubstitution == null) return null;
    var interfaceSubstitution = Substitution.fromInterfaceType(subtype);
    return new InterfaceAType(
        subtype.source,
        subtype.sink,
        superclass,
        superclass.typeParameters.map((p) {
          var upcast = superSubstitution.getSubstitute(p);
          return interfaceSubstitution.substituteType(upcast);
        }).toList(growable: false));
  }
}
