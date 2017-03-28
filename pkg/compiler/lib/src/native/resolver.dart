// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:front_end/src/fasta/scanner.dart' show StringToken, Token;

import '../common.dart';
import '../common/backend_api.dart';
import '../compiler.dart' show Compiler;
import '../constants/values.dart';
import '../elements/elements.dart'
    show
        ClassElement,
        Element,
        FieldElement,
        LibraryElement,
        MemberElement,
        MetadataAnnotation,
        MethodElement;
import '../elements/modelx.dart' show FunctionElementX, MetadataAnnotationX;
import '../elements/resolution_types.dart' show ResolutionDartType;
import '../js_backend/js_backend.dart';
import '../js_backend/native_data.dart';
import '../patch_parser.dart';
import '../tree/tree.dart';
import 'behavior.dart';

/// Interface for computing native members and [NativeBehavior]s in member code
/// based on the AST.
abstract class NativeDataResolver {
  /// Returns `true` if [element] is a JsInterop member.
  bool isJsInteropMember(MemberElement element);

  /// Computes whether [element] is native or JsInterop and, if so, registers
  /// its [NativeBehavior]s to [registry].
  void resolveNativeMember(MemberElement element, NativeRegistry registry);

  /// Computes the [NativeBehavior] for a `JS` call, which can be an
  /// instantiation point for types.
  ///
  /// For example, the following code instantiates and returns native classes
  /// that are `_DOMWindowImpl` or a subtype.
  ///
  ///    JS('_DOMWindowImpl', 'window')
  ///
  NativeBehavior resolveJsCall(Send node, ForeignResolver resolver);

  /// Computes the [NativeBehavior] for a `JS_EMBEDDED_GLOBAL` call, which can
  /// be an instantiation point for types.
  ///
  /// For example, the following code instantiates and returns a String class
  ///
  ///     JS_EMBEDDED_GLOBAL('String', 'foo')
  ///
  NativeBehavior resolveJsEmbeddedGlobalCall(
      Send node, ForeignResolver resolver);

  /// Computes the [NativeBehavior] for a `JS_BUILTIN` call, which can be an
  /// instantiation point for types.
  ///
  /// For example, the following code instantiates and returns a String class
  ///
  ///     JS_BUILTIN('String', 'int2string', 0)
  ///
  NativeBehavior resolveJsBuiltinCall(Send node, ForeignResolver resolver);
}

class NativeDataResolverImpl implements NativeDataResolver {
  static final RegExp _identifier = new RegExp(r'^[a-zA-Z_$][a-zA-Z0-9_$]*$');

  final Compiler _compiler;

  NativeDataResolverImpl(this._compiler);

  JavaScriptBackend get _backend => _compiler.backend;
  DiagnosticReporter get _reporter => _compiler.reporter;
  NativeBasicData get _nativeBasicData => _backend.nativeBasicData;
  NativeDataBuilder get _nativeDataBuilder => _backend.nativeDataBuilder;

  @override
  bool isJsInteropMember(MemberElement element) {
    // TODO(johnniwinther): Avoid computing this twice for external function;
    // once from JavaScriptBackendTarget.resolveExternalFunction and once
    // through JavaScriptBackendTarget.resolveNativeMember.
    bool isJsInterop =
        checkJsInteropMemberAnnotations(_compiler, element, _nativeDataBuilder);
    // TODO(johnniwinther): Avoid this duplication of logic from
    // NativeData.isJsInterop.
    if (!isJsInterop && element is MethodElement && element.isExternal) {
      if (element.enclosingClass != null) {
        isJsInterop = _nativeBasicData.isJsInteropClass(element.enclosingClass);
      } else {
        isJsInterop = _nativeBasicData.isJsInteropLibrary(element.library);
      }
    }
    return isJsInterop;
  }

  void resolveNativeMember(MemberElement element, NativeRegistry registry) {
    bool isJsInterop = isJsInteropMember(element);
    if (element.isFunction ||
        element.isConstructor ||
        element.isGetter ||
        element.isSetter) {
      MethodElement method = element;
      bool isNative = _processMethodAnnotations(method);
      if (isNative || isJsInterop) {
        NativeBehavior behavior = NativeBehavior
            .ofMethodElement(method, _compiler, isJsInterop: isJsInterop);
        _nativeDataBuilder.setNativeMethodBehavior(method, behavior);
        registry.registerNativeData(behavior);
      }
    } else if (element.isField) {
      FieldElement field = element;
      bool isNative = _processFieldAnnotations(field);
      if (isNative || isJsInterop) {
        NativeBehavior fieldLoadBehavior = NativeBehavior
            .ofFieldElementLoad(field, _compiler, isJsInterop: isJsInterop);
        NativeBehavior fieldStoreBehavior =
            NativeBehavior.ofFieldElementStore(field, _compiler);
        _nativeDataBuilder.setNativeFieldLoadBehavior(field, fieldLoadBehavior);
        _nativeDataBuilder.setNativeFieldStoreBehavior(
            field, fieldStoreBehavior);

        // TODO(sra): Process fields for storing separately.
        // We have to handle both loading and storing to the field because we
        // only get one look at each member and there might be a load or store
        // we have not seen yet.
        registry.registerNativeData(fieldLoadBehavior);
        registry.registerNativeData(fieldStoreBehavior);
      }
    }
  }

  /// Process the potentially native [field]. Adds information from metadata
  /// attributes. Returns `true` of [method] is native.
  bool _processFieldAnnotations(Element element) {
    if (_compiler.serialization.isDeserialized(element)) {
      return false;
    }
    if (element.isInstanceMember &&
        _backend.nativeBasicData.isNativeClass(element.enclosingClass)) {
      // Exclude non-instance (static) fields - they are not really native and
      // are compiled as isolate globals.  Access of a property of a constructor
      // function or a non-method property in the prototype chain, must be coded
      // using a JS-call.
      _setNativeName(element);
      return true;
    }
    return false;
  }

  /// Process the potentially native [method]. Adds information from metadata
  /// attributes. Returns `true` of [method] is native.
  bool _processMethodAnnotations(Element method) {
    if (_compiler.serialization.isDeserialized(method)) {
      return false;
    }
    if (_isNativeMethod(method)) {
      if (method.isStatic) {
        _setNativeNameForStaticMethod(method);
      } else {
        _setNativeName(method);
      }
      return true;
    }
    return false;
  }

  /// Sets the native name of [element], either from an annotation, or
  /// defaulting to the Dart name.
  void _setNativeName(MemberElement element) {
    String name = _findJsNameFromAnnotation(element);
    if (name == null) name = element.name;
    _nativeDataBuilder.setNativeMemberName(element, name);
  }

  /// Sets the native name of the static native method [element], using the
  /// following rules:
  /// 1. If [element] has a @JSName annotation that is an identifier, qualify
  ///    that identifier to the @Native name of the enclosing class
  /// 2. If [element] has a @JSName annotation that is not an identifier,
  ///    use the declared @JSName as the expression
  /// 3. If [element] does not have a @JSName annotation, qualify the name of
  ///    the method with the @Native name of the enclosing class.
  void _setNativeNameForStaticMethod(MethodElement element) {
    String name = _findJsNameFromAnnotation(element);
    if (name == null) name = element.name;
    if (_isIdentifier(name)) {
      List<String> nativeNames =
          _nativeBasicData.getNativeTagsOfClass(element.enclosingClass);
      if (nativeNames.length != 1) {
        _reporter.internalError(
            element,
            'Unable to determine a native name for the enclosing class, '
            'options: $nativeNames');
      }
      _nativeDataBuilder.setNativeMemberName(
          element, '${nativeNames[0]}.$name');
    } else {
      _nativeDataBuilder.setNativeMemberName(element, name);
    }
  }

  bool _isIdentifier(String s) => _identifier.hasMatch(s);

  bool _isNativeMethod(FunctionElementX element) {
    if (!_backend.canLibraryUseNative(element.library)) return false;
    // Native method?
    return _reporter.withCurrentElement(element, () {
      Node node = element.parseNode(_compiler.resolution.parsingContext);
      if (node is! FunctionExpression) return false;
      FunctionExpression functionExpression = node;
      node = functionExpression.body;
      Token token = node.getBeginToken();
      if (identical(token.stringValue, 'native')) return true;
      return false;
    });
  }

  /// Returns the JSName annotation string or `null` if no JSName annotation is
  /// present.
  String _findJsNameFromAnnotation(Element element) {
    String name = null;
    ClassElement annotationClass = _backend.helpers.annotationJSNameClass;
    for (MetadataAnnotation annotation in element.implementation.metadata) {
      annotation.ensureResolved(_compiler.resolution);
      ConstantValue value =
          _compiler.constants.getConstantValue(annotation.constant);
      if (!value.isConstructedObject) continue;
      ConstructedConstantValue constructedObject = value;
      if (constructedObject.type.element != annotationClass) continue;

      Iterable<ConstantValue> fields = constructedObject.fields.values;
      // TODO(sra): Better validation of the constant.
      if (fields.length != 1 || fields.single is! StringConstantValue) {
        _reporter.internalError(
            annotation, 'Annotations needs one string: ${annotation}');
      }
      StringConstantValue specStringConstant = fields.single;
      String specString = specStringConstant.toDartString().slowToString();
      if (name == null) {
        name = specString;
      } else {
        _reporter.internalError(
            annotation, 'Too many JSName annotations: ${annotation}');
      }
    }
    return name;
  }

  @override
  NativeBehavior resolveJsCall(Send node, ForeignResolver resolver) {
    return NativeBehavior.ofJsCallSend(node, _reporter,
        _compiler.parsingContext, _compiler.commonElements, resolver);
  }

  @override
  NativeBehavior resolveJsEmbeddedGlobalCall(
      Send node, ForeignResolver resolver) {
    return NativeBehavior.ofJsEmbeddedGlobalCallSend(
        node, _reporter, _compiler.commonElements, resolver);
  }

  @override
  NativeBehavior resolveJsBuiltinCall(Send node, ForeignResolver resolver) {
    return NativeBehavior.ofJsBuiltinCallSend(
        node, _reporter, _compiler.commonElements, resolver);
  }
}

/// Check whether [cls] has a `@Native(...)` annotation, and if so, set its
/// native name from the annotation.
checkNativeAnnotation(Compiler compiler, ClassElement cls,
    NativeBasicDataBuilder nativeBasicDataBuilder) {
  EagerAnnotationHandler.checkAnnotation(
      compiler, cls, new NativeAnnotationHandler(nativeBasicDataBuilder));
}

/// Annotation handler for pre-resolution detection of `@Native(...)`
/// annotations.
class NativeAnnotationHandler extends EagerAnnotationHandler<String> {
  final NativeBasicDataBuilder _nativeBasicDataBuilder;

  NativeAnnotationHandler(this._nativeBasicDataBuilder);

  String getNativeAnnotation(MetadataAnnotationX annotation) {
    if (annotation.beginToken != null &&
        annotation.beginToken.next.lexeme == 'Native') {
      // Skipping '@', 'Native', and '('.
      Token argument = annotation.beginToken.next.next.next;
      if (argument is StringToken) {
        return argument.lexeme;
      }
    }
    return null;
  }

  String apply(
      Compiler compiler, Element element, MetadataAnnotation annotation) {
    if (element.isClass) {
      ClassElement cls = element;
      String native = getNativeAnnotation(annotation);
      if (native != null) {
        _nativeBasicDataBuilder.setNativeClassTagInfo(cls, native);
        return native;
      }
    }
    return null;
  }

  void validate(Compiler compiler, Element element,
      MetadataAnnotation annotation, ConstantValue constant) {
    ResolutionDartType annotationType =
        constant.getType(compiler.commonElements);
    if (annotationType.element !=
        compiler.backend.helpers.nativeAnnotationClass) {
      DiagnosticReporter reporter = compiler.reporter;
      reporter.internalError(annotation, 'Invalid @Native(...) annotation.');
    }
  }
}

void checkJsInteropClassAnnotations(Compiler compiler, LibraryElement library,
    NativeBasicDataBuilder nativeBasicDataBuilder) {
  bool checkJsInteropAnnotation(Element element) {
    return EagerAnnotationHandler.checkAnnotation(
        compiler, element, const JsInteropAnnotationHandler());
  }

  if (checkJsInteropAnnotation(library)) {
    nativeBasicDataBuilder.markAsJsInteropLibrary(library);
  }
  library.forEachLocalMember((Element element) {
    if (element.isClass) {
      ClassElement cls = element;
      if (checkJsInteropAnnotation(element)) {
        nativeBasicDataBuilder.markAsJsInteropClass(cls);
      }
    }
  });
}

bool checkJsInteropMemberAnnotations(Compiler compiler, MemberElement element,
    NativeDataBuilder nativeDataBuilder) {
  bool isJsInterop = EagerAnnotationHandler.checkAnnotation(
      compiler, element, const JsInteropAnnotationHandler());
  if (isJsInterop) {
    nativeDataBuilder.markAsJsInteropMember(element);
  }
  return isJsInterop;
}

/// Annotation handler for pre-resolution detection of `@JS(...)`
/// annotations.
class JsInteropAnnotationHandler implements EagerAnnotationHandler<bool> {
  const JsInteropAnnotationHandler();

  bool hasJsNameAnnotation(MetadataAnnotationX annotation) =>
      annotation.beginToken != null &&
      annotation.beginToken.next.lexeme == 'JS';

  bool apply(
      Compiler compiler, Element element, MetadataAnnotation annotation) {
    return hasJsNameAnnotation(annotation);
  }

  @override
  void validate(Compiler compiler, Element element,
      MetadataAnnotation annotation, ConstantValue constant) {
    JavaScriptBackend backend = compiler.backend;
    ResolutionDartType type = constant.getType(compiler.commonElements);
    if (type.element != backend.helpers.jsAnnotationClass) {
      compiler.reporter
          .internalError(annotation, 'Invalid @JS(...) annotation.');
    }
  }

  bool get defaultResult => false;
}
