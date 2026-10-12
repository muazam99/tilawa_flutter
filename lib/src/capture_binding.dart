// Internal ownership link, without adding recorder objects to the core API.
final captureBindings = Expando<Future<void> Function()>('tilawa capture');
