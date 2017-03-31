import 'package:kernel/ast.dart';

class HookNames {
  static final String typeCheck = 'typecheck';
  static final String treeShake = 'treeshake';
  static final String dataflow = 'dataflow';
  static final String async_ = 'async';
  static final String erase = 'erase';
  static final String sanitize = 'sanitize';

  static final List<String> values = [
    typeCheck,
    treeShake,
    dataflow,
    async_,
    erase,
    sanitize
  ];
}

typedef void HookCallback(Program program);

class HookCallbacks {
  final Map<String, List<HookCallback>> _before = {};
  final Map<String, List<HookCallback>> _after = {};

  void fireBefore(String hook, Program program) {
    var list = _before[hook];
    if (list != null) {
      for (var callback in list) {
        callback(program);
      }
    }
  }

  void fireAfter(String hook, Program program) {
    var list = _after[hook];
    if (list != null) {
      for (var callback in list) {
        callback(program);
      }
    }
  }

  void beforeHook(String hook, HookCallback callback) {
    var list = _before[hook] ??= <HookCallback>[];
    list.add(callback);
  }

  void afterHook(String hook, HookCallback callback) {
    var list = _after[hook] ??= <HookCallback>[];
    list.add(callback);
  }
}
