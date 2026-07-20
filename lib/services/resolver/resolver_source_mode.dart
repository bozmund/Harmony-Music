enum ResolverSourceMode {
  both,
  resolverOnly,
  existingOnly;

  bool get usesResolver => this != ResolverSourceMode.existingOnly;

  static ResolverSourceMode fromStoredValue(Object? value) {
    if (value is String) {
      for (final mode in ResolverSourceMode.values) {
        if (mode.name == value) return mode;
      }
    }
    return ResolverSourceMode.both;
  }
}
