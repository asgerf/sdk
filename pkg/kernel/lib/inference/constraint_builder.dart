library kernel.inference.constraint_builder;

import '../ast.dart';
import 'augmented_type.dart';
import 'constraints.dart';
import 'key.dart';
import 'hierarchy.dart';
import 'value.dart';

abstract class TypeParameterScope {
  Bound getTypeParameterBound(TypeParameter parameter);
}

abstract class ConstraintBuilder {
  final AugmentedHierarchy hierarchy;
  final TypeParameterScope scope;

  ConstraintBuilder(this.hierarchy, this.scope);

  List<Bound> getTypeAsInstanceOf(InterfaceAType subtype, Class superclass) {
    return hierarchy.getTypeAsInstanceOf(subtype, superclass).typeArguments;
  }

  void addConstraint(Constraint constraint);

  Value get nullValue;

  Bound getTypeParameterBound(TypeParameter parameter) {
    return scope.getTypeParameterBound(parameter);
  }

  void addImmediateSubtype(Key subtype, AType supertype) {
    assert(subtype != null);
    assert(supertype != null);
    if (!supertype.isAssignable) return;
    Key supertypeKey = supertype.key;
    Key supertypeNullability = supertype.nullability;
    if (supertypeKey != supertypeNullability) {
      addSubtypeConstraint(subtype, supertypeNullability, Flags.null_);
      addSubtypeConstraint(subtype, supertypeKey, Flags.notNull);
    } else {
      addSubtypeConstraint(subtype, supertypeKey);
    }
  }

  void addImmediateValue(Value value, AType supertype) {
    assert(value != null);
    assert(supertype != null);
    if (!supertype.isAssignable) return;
    Key supertypeKey = supertype.key;
    Key supertypeNullability = supertype.nullability;
    if (supertypeKey != supertypeNullability) {
      if (value.canBeNull) {
        addValueConstraint(value, supertypeNullability);
      }
      if (value.canBeNonNull) {
        addValueConstraint(value.masked(Flags.notNull), supertypeKey);
      }
    } else {
      addValueConstraint(value, supertypeKey);
    }
  }

  void addSubtypeConstraint(Key subtype, Key supertype,
      [int mask = Flags.all]) {
    assert(subtype != null);
    assert(supertype != null);
    addConstraint(new SubtypeConstraint(subtype, supertype, mask));
  }

  void addValueConstraint(Value value, Key destination) {
    assert(value != null);
    assert(destination != null);
    addConstraint(new ValueConstraint(destination, value));
  }
}
