// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.dataflow.extractor.external_model;

import '../../ast.dart';
import '../../class_hierarchy.dart';
import '../../core_types.dart';
import 'constraint_extractor.dart';

/// Specifies the behavior of external methods, special-cased backend library
/// methods, and program entry points.
abstract class ExternalModel {
  /// True if the given external [member] does not return `null` and does not
  /// cause any objects to escape.
  bool isCleanExternal(Member member);

  /// If true, the analysis should treat [member] as external using this model,
  /// even if it has an implementation and/or is overridden by methods in the
  /// core libraries.
  ///
  /// User-defined methods that override the given member still affect interface
  /// calls to the member, but overriders in the core libraries are ignored as
  /// the model is assumed to account for them.
  bool forceExternal(Member member);

  /// True if the given member can be invoked from external code.
  ///
  /// This is not called for `main`, that is treated separately.
  ///
  /// The arguments will be based on worst-case assumptions based on the static
  /// types of its parameters.  The return value is considered escaping.
  bool isEntryPoint(Member member);

  /// Force the type arguments provided in the extends/implements clause of
  /// the given class to be treated as non-nullable.
  ///
  /// This is to special-case certain core library classes that are known to
  /// behave nicely, even though their implementation cannot be analyzed with
  /// the necessary precision.
  ///
  /// For instance, Uint32List implements List<int> with non-nullable `int`, as
  /// it cannot contain null, and ListQueue<E> implements Queue<E> without
  /// a nullability modifier on E, so it can be instantiated as either having
  /// nullable or non-nullable contents (as opposed to being forced nullable
  /// in all instantiations).
  bool forceCleanSupertypes(Class class_);
}

/// Models the behavior of VM externals.
class VmExternalModel extends ExternalModel {
  final CoreTypes coreTypes;
  final ClassHierarchy classHierarchy;
  final Set<Member> entryPointMembers = new Set<Member>();
  Class externalNameAnnotation;
  final Set<Member> forceExternals = new Set<Member>();
  final Set<Member> extraEntryPoints = new Set<Member>();
  Library _typedDataLibrary;
  Library _collectionLibrary;

  VmExternalModel(Program program, this.coreTypes, this.classHierarchy) {
    _typedDataLibrary = coreTypes.getLibrary('dart:typed_data');
    _collectionLibrary = coreTypes.getLibrary('dart:collection');
    externalNameAnnotation =
        coreTypes.getClass('dart:_internal', 'ExternalName');
    forceExternals.addAll(coreTypes.numClass.members);
    forceExternals.addAll(coreTypes.intClass.members);
    forceExternals.addAll(coreTypes.doubleClass.members);
    forceExternals.addAll(coreTypes.stringClass.members);
    forceExternals.addAll(coreTypes.boolClass.members);
    forceExternals.addAll(coreTypes.iterableClass.members);
    forceExternals.addAll(coreTypes.iteratorClass.members);
    forceExternals.addAll(coreTypes.listClass.members);
    forceExternals.addAll(coreTypes.mapClass.members);
    forceExternals.addAll(coreTypes.futureClass.members);
    forceExternals.addAll(coreTypes.streamClass.members);

    forceExternals
        .addAll(coreTypes.getClass('dart:core', '_StringBase').members);

    forceExternals
        .addAll(coreTypes.getClass('dart:collection', 'Queue').members);

    // Ensure methods overriding a forced external are also forced external.
    for (var class_ in classHierarchy.classes) {
      if (class_.enclosingLibrary.importUri.scheme != 'dart') continue;
      classHierarchy.forEachOverridePair(class_, (own, super_, isSetter) {
        if (forceExternals.contains(super_)) {
          forceExternals.add(own);
        }
      });
    }

    // Add some members of _IntegerImplementation as entry points to compensate
    // for the special treatment of arithmetic.
    extraEntryPoints.addAll(coreTypes
        .getClass('dart:core', '_IntegerImplementation')
        .procedures
        .where((m) => overloadedArithmeticOperatorNames.contains(m.name.name)));

    // Helper methods used by kernel->vm translation.
    // TODO: Mark these as entry point?
    extraEntryPoints
        .add(coreTypes.getMember('dart:core', '_StringBase', '_interpolate'));
    extraEntryPoints
        .add(coreTypes.getMember('dart:core', 'List', '_fromLiteral'));
    extraEntryPoints
        .add(coreTypes.getMember('dart:core', 'Map', '_fromLiteral'));

    // Add entry points that are defined by the VM itself, not the embedder.
    // TODO: Put these in a manifest file.
    extraEntryPoints.add(coreTypes.getTopLevelMember(
        'dart:async', '_setScheduleImmediateClosure'));
    extraEntryPoints
        .add(coreTypes.getTopLevelMember('dart:isolate', '_startMainIsolate'));
    extraEntryPoints.add(coreTypes.getMember(
        'dart:isolate', '_RawReceivePortImpl', '_lookupHandler'));
    extraEntryPoints.add(coreTypes.getMember(
        'dart:isolate', '_RawReceivePortImpl', '_handleMessage'));
  }

  ConstructorInvocation getAnnotation(
      List<Expression> annotations, Class class_) {
    for (var annotation in annotations) {
      if (annotation is ConstructorInvocation &&
          annotation.target.enclosingClass == class_) {
        return annotation;
      }
    }
    return null;
  }

  String getAsString(Expression node) {
    return node is StringLiteral ? node.value : null;
  }

  bool isCleanExternal(Member member) {
    if (forceExternal(member)) return true;
    var annotation = getAnnotation(member.annotations, externalNameAnnotation);
    if (annotation == null) return false;
    if (annotation.arguments.positional.length < 1) return false;
    String name = getAsString(annotation.arguments.positional[0]);
    return VMNativeDatabase.natives[name] == VMNativeDatabase.clean;
  }

  bool isEntryPoint(Member member) {
    return member.isForeignEntryPoint || extraEntryPoints.contains(member);
  }

  bool forceExternal(Member member) {
    return forceExternals.contains(member);
  }

  bool forceCleanSupertypes(Class class_) {
    // Ensure that typed data lists implement List with a non-nullable type.
    return class_.enclosingLibrary == _typedDataLibrary ||
        class_.enclosingLibrary == _collectionLibrary;
  }
}

/// Classifies VM natives based on whether they can cause objects to escape
/// and be a source of 'null' entering the dataflow.
///
/// The [clean] and [dirty] flags are currently the only two classifications,
/// though some placeholders are defined to simplify transitioning to a more
/// precise classification.
class VMNativeDatabase {
  static const int clean = 1;
  static const int dirty = 2;

  /// Natives that operate on mirrors.  We always consider these dirty.
  static const int mirror = dirty;

  /// A native that throws an exception.
  static const int thrower = clean;

  /// A native that may return null but does not cause any arguments to escape.
  static const int returnsNull = dirty;

  /// A native that mutates one or more objects reachable from its arguments,
  /// in a way that affects the analysis results.
  static const int mutatesArgument = dirty;

  /// Natives that have side-effects or may return null but because
  /// of they way they are used, it is safe to ignore these effects.
  static const int ignore = clean;

  /// For natives that have not been classified.
  static const int unclassified = dirty;

  static final Map<String, int> natives = <String, int>{
    'AbstractClassInstantiationError_throwNew': thrower,
    'AbstractType_toString': clean,
    'AssertionError_throwNew': thrower,
    'Async_rethrow': thrower,
    'Bigint_allocate': clean,
    'Bigint_getDigits': clean,
    'Bigint_getNeg': clean,
    'Bigint_getUsed': clean,
    'Bool_fromEnvironment': returnsNull, // If default value is null.
    'Builtin_GetCurrentDirectory': clean,
    'Builtin_PrintString': clean,
    'CapabilityImpl_equals': clean,
    'CapabilityImpl_factory': clean,
    'CapabilityImpl_get_hashcode': clean,
    'ClassID_getID': clean,
    'ClassMirror_constructors': mirror,
    'ClassMirror_interfaces': mirror,
    'ClassMirror_interfaces_instantiated': mirror,
    'ClassMirror_invoke': mirror,
    'ClassMirror_invokeConstructor': mirror,
    'ClassMirror_invokeGetter': mirror,
    'ClassMirror_invokeSetter': mirror,
    'ClassMirror_libraryUri': mirror,
    'ClassMirror_members': mirror,
    'ClassMirror_mixin': mirror,
    'ClassMirror_mixin_instantiated': mirror,
    'ClassMirror_supertype': mirror,
    'ClassMirror_supertype_instantiated': mirror,
    'ClassMirror_type_arguments': mirror,
    'ClassMirror_type_variables': mirror,
    'Closure_clone': clean,
    'Closure_equals': clean,
    'Closure_hashCode': clean,
    'ClosureMirror_function': mirror,
    'Crypto_GetRandomBytes': clean,
    'DartAsync_fatal': thrower,
    'DateTime_currentTimeMicros': clean,
    'DateTime_localTimeZoneAdjustmentInSeconds': clean,
    'DateTime_timeZoneName': clean,
    'DateTime_timeZoneOffsetInSeconds': clean,
    'DeclarationMirror_location': mirror,
    'DeclarationMirror_metadata': mirror,
    'Developer_debugger': clean,
    'Developer_getIsolateIDFromSendPort': returnsNull,
    'Developer_getServerInfo': returnsNull,
    'Developer_getServiceMajorVersion': clean,
    'Developer_getServiceMinorVersion': clean,
    'Developer_inspect': returnsNull, // Returns null if given null.
    'Developer_log': clean,
    'Developer_lookupExtension': returnsNull,
    'Developer_postEvent': returnsNull,
    'Developer_registerExtension': dirty,
    'Developer_webServerControl': dirty,
    'Directory_Create': clean,
    'Directory_CreateTemp': clean,
    'Directory_Current': clean,
    'Directory_Delete': clean,
    'Directory_Exists': clean,
    'Directory_FillWithDirectoryListing': mutatesArgument,
    'Directory_GetAsyncDirectoryListerPointer': clean,
    'Directory_Rename': clean,
    'Directory_SetAsyncDirectoryListerPointer': clean,
    'Directory_SetCurrent': clean,
    'Directory_SystemTemp': clean,
    'Double_add': clean,
    'Double_ceil': clean,
    'Double_div': clean,
    'Double_doubleFromInteger': clean,
    'Double_equal': clean,
    'Double_equalToInteger': clean,
    'Double_flipSignBit': clean,
    'Double_floor': clean,
    'Double_getIsInfinite': clean,
    'Double_getIsNaN': clean,
    'Double_getIsNegative': clean,
    'Double_greaterThan': clean,
    'Double_greaterThanFromInteger': clean,
    'Double_modulo': clean,
    'Double_mul': clean,
    'Double_parse': clean,
    'Double_remainder': clean,
    'Double_round': clean,
    'Double_sub': clean,
    'Double_toInt': clean,
    'Double_toString': clean,
    'Double_toStringAsExponential': clean,
    'Double_toStringAsFixed': clean,
    'Double_toStringAsPrecision': clean,
    'Double_truncate': clean,
    'Double_trunc_div': clean,
    'EventHandler_SendData': unclassified, // Can call methods on List or Map?
    'EventHandler_TimerMillisecondClock': clean,
    'ExternalOneByteString_getCid': clean,
    'FallThroughError_throwNew': thrower,
    'File_AreIdentical': clean,
    'File_Close': clean,
    'File_Copy': clean,
    'File_Create': clean,
    'File_CreateLink': clean,
    'File_Delete': clean,
    'File_DeleteLink': clean,
    'File_Exists': clean,
    'File_Flush': clean,
    'File_GetPointer': clean,
    'File_GetStdioHandleType': clean,
    'File_GetType': clean,
    'File_LastAccessed': clean,
    'File_LastModified': clean,
    'File_Length': clean,
    'File_LengthFromPath': clean,
    'File_LinkTarget': clean,
    'File_Lock': clean,
    'File_Open': clean,
    'File_OpenStdio': clean,
    'File_Position': clean,
    'File_Read': clean,
    'File_ReadByte': clean,
    'File_ReadInto': mutatesArgument, // TODO: Will not write 'null' into list.
    'File_Rename': clean,
    'File_RenameLink': clean,
    'File_ResolveSymbolicLinks': clean,
    'File_SetLastAccessed': clean,
    'File_SetLastModified': clean,
    'File_SetPointer': clean,
    'File_SetPosition': clean,
    'File_SetTranslation': clean,
    'File_Stat': clean,
    'FileSystemWatcher_CloseWatcher': clean,
    'FileSystemWatcher_GetSocketId': clean,
    'FileSystemWatcher_InitWatcher': clean,
    'FileSystemWatcher_IsSupported': clean,
    'FileSystemWatcher_ReadEvents': clean,
    'FileSystemWatcher_UnwatchPath': clean,
    'FileSystemWatcher_WatchPath': clean,
    'File_Truncate': clean,
    'File_WriteByte': clean,
    'File_WriteFrom': clean,
    'Filter_CreateZLibDeflate': clean,
    'Filter_CreateZLibInflate': clean,
    'Filter_Process': clean,
    'Filter_Processed': clean,
    'Float32x4_abs': clean,
    'Float32x4_add': clean,
    'Float32x4_clamp': clean,
    'Float32x4_cmpequal': clean,
    'Float32x4_cmpgt': clean,
    'Float32x4_cmpgte': clean,
    'Float32x4_cmplt': clean,
    'Float32x4_cmplte': clean,
    'Float32x4_cmpnequal': clean,
    'Float32x4_div': clean,
    'Float32x4_fromDoubles': clean,
    'Float32x4_fromFloat64x2': clean,
    'Float32x4_fromInt32x4Bits': clean,
    'Float32x4_getSignMask': clean,
    'Float32x4_getW': clean,
    'Float32x4_getX': clean,
    'Float32x4_getY': clean,
    'Float32x4_getZ': clean,
    'Float32x4_max': clean,
    'Float32x4_min': clean,
    'Float32x4_mul': clean,
    'Float32x4_negate': clean,
    'Float32x4_reciprocal': clean,
    'Float32x4_reciprocalSqrt': clean,
    'Float32x4_scale': clean,
    'Float32x4_setW': clean,
    'Float32x4_setX': clean,
    'Float32x4_setY': clean,
    'Float32x4_setZ': clean,
    'Float32x4_shuffle': clean,
    'Float32x4_shuffleMix': clean,
    'Float32x4_splat': clean,
    'Float32x4_sqrt': clean,
    'Float32x4_sub': clean,
    'Float32x4_zero': clean,
    'Float64x2_abs': clean,
    'Float64x2_add': clean,
    'Float64x2_clamp': clean,
    'Float64x2_div': clean,
    'Float64x2_fromDoubles': clean,
    'Float64x2_fromFloat32x4': clean,
    'Float64x2_getSignMask': clean,
    'Float64x2_getX': clean,
    'Float64x2_getY': clean,
    'Float64x2_max': clean,
    'Float64x2_min': clean,
    'Float64x2_mul': clean,
    'Float64x2_negate': clean,
    'Float64x2_scale': clean,
    'Float64x2_setX': clean,
    'Float64x2_setY': clean,
    'Float64x2_splat': clean,
    'Float64x2_sqrt': clean,
    'Float64x2_sub': clean,
    'Float64x2_zero': clean,
    'Function_apply': dirty,
    'FunctionTypeMirror_call_method': mirror,
    'FunctionTypeMirror_parameters': mirror,
    'FunctionTypeMirror_return_type': mirror,
    'GrowableList_allocate': clean,
    'GrowableList_getCapacity': clean,
    'GrowableList_getIndexed': clean,
    'GrowableList_getLength': clean,
    'GrowableList_setData': ignore,
    'GrowableList_setIndexed': ignore,
    'GrowableList_setLength': ignore,
    'Identical_comparison': clean,
    'ImmutableList_from': clean,
    'InstanceMirror_computeType': mirror,
    'InstanceMirror_invoke': mirror,
    'InstanceMirror_invokeGetter': mirror,
    'InstanceMirror_invokeSetter': mirror,
    'Int32x4_add': clean,
    'Int32x4_and': clean,
    'Int32x4_fromBools': clean,
    'Int32x4_fromFloat32x4Bits': clean,
    'Int32x4_fromInts': clean,
    'Int32x4_getFlagW': clean,
    'Int32x4_getFlagX': clean,
    'Int32x4_getFlagY': clean,
    'Int32x4_getFlagZ': clean,
    'Int32x4_getSignMask': clean,
    'Int32x4_getW': clean,
    'Int32x4_getX': clean,
    'Int32x4_getY': clean,
    'Int32x4_getZ': clean,
    'Int32x4_or': clean,
    'Int32x4_select': clean,
    'Int32x4_setFlagW': clean,
    'Int32x4_setFlagX': clean,
    'Int32x4_setFlagY': clean,
    'Int32x4_setFlagZ': clean,
    'Int32x4_setW': clean,
    'Int32x4_setX': clean,
    'Int32x4_setY': clean,
    'Int32x4_setZ': clean,
    'Int32x4_shuffle': clean,
    'Int32x4_shuffleMix': clean,
    'Int32x4_sub': clean,
    'Int32x4_xor': clean,
    'Integer_addFromInteger': clean,
    'Integer_bitAndFromInteger': clean,
    'Integer_bitOrFromInteger': clean,
    'Integer_bitXorFromInteger': clean,
    'Integer_equalToInteger': clean,
    'Integer_fromEnvironment': returnsNull, // If default value is null.,
    'Integer_greaterThanFromInteger': clean,
    'Integer_moduloFromInteger': clean,
    'Integer_mulFromInteger': clean,
    'Integer_subFromInteger': clean,
    'Integer_truncDivFromInteger': clean,
    'Internal_inquireIs64Bit': clean,
    'Internal_makeFixedListUnmodifiable': clean,
    'Internal_makeListFixedLength': clean,
    'InternetAddress_Parse': clean,
    'IOService_NewServicePort': clean,
    'Isolate_getCurrentRootUriStr': clean,
    'Isolate_getPortAndCapabilitiesOfCurrentIsolate': clean,
    'Isolate_sendOOB': clean,
    'Isolate_spawnFunction': clean,
    'Isolate_spawnUri': clean,
    'LibraryMirror_fromPrefix': mirror,
    'LibraryMirror_invoke': mirror,
    'LibraryMirror_invokeGetter': mirror,
    'LibraryMirror_invokeSetter': mirror,
    'LibraryMirror_libraryDependencies': mirror,
    'LibraryMirror_members': mirror,
    'LibraryPrefix_invalidateDependentCode': clean,
    'LibraryPrefix_isLoaded': clean,
    'LibraryPrefix_load': clean,
    'LibraryPrefix_loadError': clean,
    'LinkedHashMap_getData': clean,
    'LinkedHashMap_getDeletedKeys': clean,
    'LinkedHashMap_getHashMask': clean,
    'LinkedHashMap_getIndex': clean,
    'LinkedHashMap_getUsedData': clean,
    'LinkedHashMap_setData': ignore,
    'LinkedHashMap_setDeletedKeys': ignore,
    'LinkedHashMap_setHashMask': ignore,
    'LinkedHashMap_setIndex': ignore,
    'LinkedHashMap_setUsedData': ignore,
    'List_allocate': clean,
    'List_getIndexed': clean,
    'List_getLength': clean,
    'List_setIndexed': ignore,
    'List_slice': clean,
    'Math_acos': clean,
    'Math_asin': clean,
    'Math_atan': clean,
    'Math_atan2': clean,
    'Math_cos': clean,
    'Math_doublePow': clean,
    'Math_exp': clean,
    'Math_log': clean,
    'Math_sin': clean,
    'Math_sqrt': clean,
    'Math_tan': clean,
    'MethodMirror_owner': mirror,
    'MethodMirror_parameters': mirror,
    'MethodMirror_return_type': mirror,
    'MethodMirror_source': mirror,
    'Mint_bitLength': clean,
    'Mint_bitNegate': clean,
    'Mint_shlFromInt': clean,
    'MirrorReference_equals': clean,
    'Mirrors_evalInLibraryWithPrivateKey': mirror,
    'Mirrors_instantiateGenericType': mirror,
    'Mirrors_makeLocalClassMirror': mirror,
    'Mirrors_makeLocalTypeMirror': mirror,
    'Mirrors_mangleName': mirror,
    'MirrorSystem_isolate': mirror,
    'MirrorSystem_libraries': mirror,
    'NetworkInterface_ListSupported': clean,
    'Object_as': ignore,
    'Object_equals': clean,
    'Object_getHash': clean,
    'Object_haveSameRuntimeType': clean,
    'Object_instanceOf': clean,
    'Object_instanceOfDouble': clean,
    'Object_instanceOfInt': clean,
    'Object_instanceOfNum': clean,
    'Object_instanceOfSmi': clean,
    'Object_instanceOfString': clean,
    'Object_noSuchMethod': thrower,
    'Object_runtimeType': clean,
    'Object_setHash': ignore,
    'Object_simpleInstanceOf': clean,
    'Object_toString': clean,
    'OneByteString_allocate': clean,
    'OneByteString_allocateFromOneByteList': clean,
    'OneByteString_setAt': clean,
    'OneByteString_splitWithCharCode': clean,
    'OneByteString_substringUnchecked': clean,
    'ParameterMirror_type': mirror,
    'Platform_Environment': clean,
    'Platform_ExecutableArguments': clean,
    'Platform_ExecutableName': clean,
    'Platform_GetVersion': clean,
    'Platform_LocalHostname': clean,
    'Platform_NumberOfProcessors': clean,
    'Platform_OperatingSystem': clean,
    'Platform_PathSeparator': clean,
    'Platform_ResolvedExecutableName': clean,
    'Process_ClearSignalHandler': clean,
    'Process_Exit': clean,
    'Process_GetExitCode': clean,
    'Process_KillPid': clean,
    'Process_Pid': clean,
    'Process_SetExitCode': clean,
    'Process_SetSignalHandler': clean,
    'Process_Sleep': clean,
    'Process_Start': clean,
    'Process_Wait': clean,
    'Profiler_getCurrentTag': unclassified,
    'Random_initialSeed': clean,
    'Random_nextState': clean,
    'Random_setupSeed': clean,
    'RawReceivePortImpl_closeInternal': clean,
    'RawReceivePortImpl_factory': clean,
    'RawReceivePortImpl_get_id': clean,
    'RawReceivePortImpl_get_sendport': clean,
    'RegExp_ExecuteMatch': clean,
    'RegExp_ExecuteMatchSticky': clean,
    'RegExp_factory': clean,
    'RegExp_getGroupCount': clean,
    'RegExp_getIsCaseSensitive': clean,
    'RegExp_getIsMultiLine': clean,
    'RegExp_getPattern': clean,
    'SecureRandom_getBytes': clean,
    'SecureSocket_Connect': clean,
    'SecureSocket_Destroy': clean,
    'SecureSocket_FilterPointer': clean,
    'SecureSocket_GetSelectedProtocol': clean,
    'SecureSocket_Handshake': clean,
    'SecureSocket_Init': clean,
    'SecureSocket_PeerCertificate': clean,
    'SecureSocket_RegisterBadCertificateCallback': dirty,
    'SecureSocket_RegisterHandshakeCompleteCallback': dirty,
    'SecureSocket_Renegotiate': clean,
    'SecurityContext_Allocate': clean,
    'SecurityContext_AlpnSupported': clean,
    'SecurityContext_SetAlpnProtocols': clean,
    'SecurityContext_SetClientAuthoritiesBytes': clean,
    'SecurityContext_SetTrustedCertificatesBytes': clean,
    'SecurityContext_TrustBuiltinRoots': clean,
    'SecurityContext_UseCertificateChainBytes': clean,
    'SecurityContext_UsePrivateKeyBytes': clean,
    'SendPortImpl_get_hashcode': clean,
    'SendPortImpl_get_id': clean,
    'SendPortImpl_sendInternal_': unclassified, // Can call methods on List/Map?
    'ServerSocket_Accept': clean,
    'ServerSocket_CreateBindListen': clean,
    'Smi_bitAndFromSmi': clean,
    'Smi_bitLength': clean,
    'Smi_bitNegate': clean,
    'Smi_shlFromInt': clean,
    'Smi_shrFromInt': clean,
    'Socket_Available': clean,
    'Socket_CreateBindConnect': clean,
    'Socket_CreateBindDatagram': clean,
    'Socket_CreateConnect': clean,
    'Socket_GetError': clean,
    'Socket_GetOption': clean,
    'Socket_GetPort': clean,
    'Socket_GetRemotePeer': clean,
    'Socket_GetSocketId': clean,
    'Socket_GetStdioHandle': clean,
    'Socket_GetType': clean,
    'Socket_IsBindError': clean,
    'Socket_JoinMulticast': clean,
    'Socket_LeaveMulticast': clean,
    'Socket_Read': ignore,
    'Socket_RecvFrom': clean,
    'Socket_SendTo': clean,
    'Socket_SetOption': clean,
    'Socket_SetSocketId': clean,
    'Socket_WriteList': mutatesArgument, // TODO: Will not write 'null'.
    'StackTrace_asyncStackTraceHelper': clean,
    'StackTrace_clearAsyncThreadStackTrace': clean,
    'StackTrace_current': clean,
    'StackTrace_setAsyncThreadStackTrace': clean,
    'Stdin_GetEchoMode': clean,
    'Stdin_GetLineMode': clean,
    'Stdin_ReadByte': clean,
    'Stdin_SetEchoMode': clean,
    'Stdin_SetLineMode': clean,
    'Stdout_GetTerminalSize': clean,
    'Stopwatch_frequency': clean,
    'Stopwatch_now': clean,
    'StringBase_createFromCodePoints': clean,
    'StringBase_joinReplaceAllResult': clean,
    'StringBase_substringUnchecked': clean,
    'StringBuffer_createStringFromUint16Array': clean,
    'String_charAt': clean,
    'String_codeUnitAt': clean,
    'String_concat': clean,
    'String_concatRange': clean,
    'String_fromEnvironment': returnsNull, // If default value is null.
    'String_getHashCode': clean,
    'String_getLength': clean,
    'String_toLowerCase': clean,
    'StringToSystemEncoding': clean,
    'String_toUpperCase': clean,
    'SystemEncodingToString': clean,
    'Timeline_getIsolateNum': clean,
    'Timeline_getNextAsyncId': clean,
    'Timeline_getThreadCpuClock': clean,
    'Timeline_getTraceClock': clean,
    'Timeline_isDartStreamEnabled': clean,
    'Timeline_reportCompleteEvent': clean,
    'Timeline_reportInstantEvent': clean,
    'Timeline_reportTaskEvent': clean,
    'TwoByteString_allocateFromTwoByteList': clean,
    'TypedData_Float32Array_new': clean,
    'TypedData_Float32x4Array_new': clean,
    'TypedData_Float64Array_new': clean,
    'TypedData_Float64x2Array_new': clean,
    'TypedData_GetFloat32': clean,
    'TypedData_GetFloat32x4': clean,
    'TypedData_GetFloat64': clean,
    'TypedData_GetFloat64x2': clean,
    'TypedData_GetInt16': clean,
    'TypedData_GetInt32': clean,
    'TypedData_GetInt32x4': clean,
    'TypedData_GetInt64': clean,
    'TypedData_GetInt8': clean,
    'TypedData_GetUint16': clean,
    'TypedData_GetUint32': clean,
    'TypedData_GetUint64': clean,
    'TypedData_GetUint8': clean,
    'TypedData_Int16Array_new': clean,
    'TypedData_Int32Array_new': clean,
    'TypedData_Int32x4Array_new': clean,
    'TypedData_Int64Array_new': clean,
    'TypedData_Int8Array_new': clean,
    'TypedData_length': clean,
    'TypedData_SetFloat32': clean,
    'TypedData_SetFloat32x4': clean,
    'TypedData_SetFloat64': clean,
    'TypedData_SetFloat64x2': clean,
    'TypedData_SetInt16': clean,
    'TypedData_SetInt32': clean,
    'TypedData_SetInt32x4': clean,
    'TypedData_SetInt64': clean,
    'TypedData_SetInt8': clean,
    'TypedData_setRange': clean,
    'TypedData_SetUint16': clean,
    'TypedData_SetUint32': clean,
    'TypedData_SetUint64': clean,
    'TypedData_SetUint8': clean,
    'TypedData_Uint16Array_new': clean,
    'TypedData_Uint32Array_new': clean,
    'TypedData_Uint64Array_new': clean,
    'TypedData_Uint8Array_new': clean,
    'TypedData_Uint8ClampedArray_new': clean,
    'TypedefMirror_declaration': mirror,
    'TypedefMirror_referent': mirror,
    'TypeError_throwNew': thrower,
    'TypeMirror_subtypeTest': mirror,
    'TypeVariableMirror_owner': mirror,
    'TypeVariableMirror_upper_bound': mirror,
    'Uri_isWindowsPlatform': clean,
    'UserTag_defaultTag': clean,
    'UserTag_label': clean,
    'UserTag_makeCurrent': clean,
    'UserTag_new': clean,
    'VariableMirror_type': mirror,
    'VMService_CancelStream': clean,
    'VMService_DecodeAssets': clean,
    'VMServiceIO_NotifyServerState': clean,
    'VMServiceIO_Shutdown': clean,
    'VMService_ListenStream': clean,
    'VMService_OnExit': clean,
    'VMService_OnServerAddressChange': clean,
    'VMService_OnStart': clean,
    'VMService_RequestAssets': clean,
    'VMService_SendIsolateServiceMessage': clean,
    'VMService_SendObjectRootServiceMessage': clean,
    'VMService_SendRootServiceMessage': clean,
    'VMService_spawnUriNotify': clean,
    'WeakProperty_getKey': clean,
    'WeakProperty_getValue': clean,
    'WeakProperty_new': clean,
    'WeakProperty_setValue': clean,
    'X509_EndValidity': clean,
    'X509_Issuer': clean,
    'X509_StartValidity': clean,
    'X509_Subject': clean,
  };
}
