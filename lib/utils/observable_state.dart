import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:flutter/foundation.dart';

class ObservableValue<T> extends ChangeNotifier {
  ObservableValue(this._value);

  final _controller = StreamController<T>.broadcast();
  T _value;

  T get value => _value;

  set value(T next) {
    if (_value == next) return;
    _value = next;
    notifyListeners();
    _controller.add(_value);
  }

  StreamSubscription<T> listen(void Function(T value) listener) =>
      _controller.stream.listen(listener);

  void update(void Function(T value) updater) {
    updater(_value);
    notifyListeners();
    _controller.add(_value);
  }

  @override
  String toString() => value.toString();

  @override
  void dispose() {
    unawaited(_controller.close());
    super.dispose();
  }
}

class ObservableNullable<T> extends ObservableValue<T?> {
  ObservableNullable([super.value]);
}

class ObservableList<T> extends ListBase<T> with ChangeNotifier {
  ObservableList([Iterable<T> values = const []]) : _values = List<T>.from(values);

  final _controller = StreamController<List<T>>.broadcast();
  List<T> _values;

  List<T> get value => _values;

  set value(List<T> next) {
    _values = List<T>.from(next);
    _notify();
  }

  void assignAll(Iterable<T> values) {
    _values = List<T>.from(values);
    _notify();
  }

  StreamSubscription<List<T>> listen(void Function(List<T> value) listener) =>
      _controller.stream.listen(listener);

  void _notify() {
    notifyListeners();
    _controller.add(List<T>.unmodifiable(_values));
  }

  void refresh() {
    _notify();
  }

  @override
  int get length => _values.length;

  @override
  set length(int newLength) {
    _values.length = newLength;
    _notify();
  }

  @override
  T operator [](int index) => _values[index];

  @override
  void operator []=(int index, T value) {
    _values[index] = value;
    _notify();
  }

  @override
  void add(T element) {
    _values.add(element);
    _notify();
  }

  @override
  void addAll(Iterable<T> iterable) {
    _values.addAll(iterable);
    _notify();
  }

  @override
  bool remove(Object? element) {
    final removed = _values.remove(element);
    if (removed) _notify();
    return removed;
  }

  @override
  void removeWhere(bool Function(T element) test) {
    _values.removeWhere(test);
    _notify();
  }

  @override
  void insert(int index, T element) {
    _values.insert(index, element);
    _notify();
  }

  @override
  void clear() {
    if (_values.isEmpty) return;
    _values.clear();
    _notify();
  }

  @override
  void sort([int Function(T a, T b)? compare]) {
    _values.sort(compare);
    _notify();
  }

  @override
  void shuffle([Random? random]) {
    _values.shuffle(random);
    _notify();
  }

  @override
  void dispose() {
    unawaited(_controller.close());
    super.dispose();
  }
}

class ObservableMap<K, V> extends MapBase<K, V> with ChangeNotifier {
  ObservableMap([Map<K, V> values = const {}]) : _values = Map<K, V>.from(values);

  final _controller = StreamController<Map<K, V>>.broadcast();
  final Map<K, V> _values;

  Map<K, V> get value => _values;

  set value(Map<K, V> next) {
    _values
      ..clear()
      ..addAll(next);
    _notify();
  }

  void assignAll(Map<K, V> values) {
    _values
      ..clear()
      ..addAll(values);
    _notify();
  }

  StreamSubscription<Map<K, V>> listen(void Function(Map<K, V> value) listener) =>
      _controller.stream.listen(listener);

  void _notify() {
    notifyListeners();
    _controller.add(Map<K, V>.unmodifiable(_values));
  }

  @override
  V? operator [](Object? key) => _values[key];

  @override
  void operator []=(K key, V value) {
    _values[key] = value;
    _notify();
  }

  @override
  void clear() {
    if (_values.isEmpty) return;
    _values.clear();
    _notify();
  }

  @override
  Iterable<K> get keys => _values.keys;

  @override
  V? remove(Object? key) {
    final removed = _values.remove(key);
    _notify();
    return removed;
  }

  @override
  void dispose() {
    unawaited(_controller.close());
    super.dispose();
  }
}
