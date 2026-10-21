## UI Components

- Components are designed around a single idea and built to be composable and reusable.

## Documentation

- Keep docs essential and concise. Prefer self-explanatory code and executable tests over explanatory prose.

## Tests

- Normal tests stay offscreen; visible desktop tests require explicit opt-in.
- Tests must verify observable outcomes through public interfaces, not implementation details. Code can change entirely; tests shouldn't.
- Split animation tests from generic UI unit tests, this helps keep unit tests fast for quick validation.
