# CDC Schema Evolution Policy

- Additive changes must be backward compatible
- New fields must be nullable or have defaults
- Breaking changes require new contract version
- Deprecated fields remain for >= 1 release
