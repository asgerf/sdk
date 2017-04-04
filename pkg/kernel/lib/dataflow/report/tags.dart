class ConstraintTag {
  static const int EscapeConstraint = 0;
  static const int AssignConstraint = 1;
  static const int GuardedValueConstraint = 2;
  static const int ValueConstraint = 3;
  static const int FilterConstraint = 3;
}

class DebugTag {
  final int byte;
  final String name;

  DebugTag(this.byte, this.name);

  static final DebugTag LocationReference =
      new DebugTag(0xf0, 'location reference');
  static final DebugTag ConstraintReference =
      new DebugTag(0xf1, 'constraint reference');
  static final DebugTag ChangeEvent = new DebugTag(0xf2, 'change event');
  static final DebugTag TransferEvent = new DebugTag(0xf3, 'transfer event');
  static final DebugTag Value = new DebugTag(0xf4, 'value');
  static final DebugTag Constraint = new DebugTag(0xf5, 'constraint');
}
