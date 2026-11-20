bool validDomain(String value) =>
    value.length <= 253 &&
    value.contains('.') &&
    !RegExp(r'^\d+(\.\d+){3}$').hasMatch(value) &&
    value
        .split('.')
        .every(
          (p) =>
              p.isNotEmpty &&
              p.length <= 63 &&
              RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$').hasMatch(p),
        ) &&
    value != 'localhost' &&
    !value.endsWith('.localhost');
