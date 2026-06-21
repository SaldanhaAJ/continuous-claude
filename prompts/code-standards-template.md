# Coding Standards

This file is injected into every Claude iteration prompt as a mandatory coding standards block.
Replace the contents below with your own project standards.

## Comments
Write comments only when the WHY is non-obvious. Never restate what the code does.

## Naming
Follow the naming conventions of the existing codebase.

## Error Handling
Only add error handling at system boundaries (user input, external APIs, file I/O).
Do not add defensive checks for scenarios that cannot occur in your internal code.

## Tests
Write tests that verify behaviour, not implementation. One assertion concept per test.
