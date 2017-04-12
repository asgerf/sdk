Extraction of a constraint system from the AST.

Extraction happens in four interleaved steps:

 1. [Binding] maps AST types into an augmented type system, where types
    remember where they came from.

 2. [ConstraintExtractor] extracts augmented subtyping judgements from the AST
    based on mostly traditional subtyping rules (in the augmented type system),
    while annotating AST nodes with an index where their computed value
    can be found once the dataflow analysis complete.

 3. [SubtypeTranslator] translates augmented subtyping judgements into
    source/sink assignments.

 4. [SourceSinkTranslator] translates source/sink assignments into constraints.

Concretely, steps 2-4 are fused into a single pass, that is, a subtyping
judgement is immediately translated to a set of constraints when found,
and are not stored in an intermediate buffer.  Step 1 is built on-demand.

Extraction is modular, that is, it does not require knowledge of libraries
other than those imported by the build unit being analyzed.
