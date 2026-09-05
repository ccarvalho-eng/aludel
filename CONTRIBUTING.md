# Contributing to Aludel

Thank you for your interest in contributing to Aludel. We appreciate your time and effort in helping improve this project.

## Code of Conduct

We are committed to fostering a welcoming and inclusive environment for all contributors. Our community standards are aligned with established open source best practices:

- **Respectful Communication** — Maintain professionalism in all interactions. Constructive disagreement is encouraged, but must remain respectful and focused on technical merit.
- **Good Faith Collaboration** — Assume positive intent from all participants. We are working toward common goals.
- **Knowledge Sharing** — Support fellow contributors through mentorship and documentation. Help others understand the codebase and development practices.

Harassment, discrimination, or unprofessional conduct will not be tolerated and may result in removal from the project.

## Development Philosophy

Our approach to software development emphasizes pragmatism, quality, and maintainability:

- **Focused Scope** — Each pull request should address a single, well-defined concern. Avoid mixing refactoring with feature development or bug fixes.
- **Pragmatic Solutions** — Address current requirements rather than speculative future needs. Avoid over-engineering.
- **Incremental Delivery** — Large features should be decomposed into smaller, independently shippable units. Iterative delivery reduces risk and accelerates feedback cycles.
- **Quality Over Perfection** — Ship working, well-tested code. Avoid excessive iteration on stylistic concerns that do not materially improve functionality or maintainability.
- **Continuous Improvement** — Leave the codebase in better condition than you found it. However, unrelated cleanup should be separated from functional changes.

## Pull Request Guidelines

Effective pull requests are essential for maintaining project velocity and code quality:

- **Small, Focused Changes** — Smaller pull requests are reviewed more quickly and reduce merge conflicts. They also facilitate easier debugging when issues arise.
- **Single Responsibility** — Each PR should address one logical change. Multiple small PRs are preferred over large, multi-purpose submissions.
- **Timely Review Cycle** — Both authors and reviewers should prioritize rapid iteration. Extended review cycles should be avoided through clear scope and communication.

## AI-Assisted Development

AI-assisted development tools are welcome, provided they are used responsibly:

- **Code Ownership** — All contributed code is your responsibility, regardless of its origin. Review AI-generated code with the same rigor you would apply to code written by any other developer.
- **Quality Assurance** — Changes affecting substantial portions of the codebase or critical functionality require thorough testing to prevent regressions.
- **Technical Understanding** — Contributors must understand the changes they propose. Do not submit complex modifications without comprehending their implications and trade-offs.
- **Attribution** — AI tool attribution in commit messages is acceptable but not required.

## Development Workflow

1. **Fork the repository** and create a feature branch:
   ```bash
   git checkout -b feature/your-feature
   ```

2. **Make your changes** — Keep them focused and scoped.

3. **Run precommit checks** before committing:
   ```bash
   mix precommit
   ```

   This runs:
   - Code formatting (`mix format`)
   - Linting (`mix credo`)
   - Type checking (`mix dialyzer`)
   - Tests (`mix test`)

4. **Commit using [conventional commits](https://www.conventionalcommits.org/)**:
   ```
   feat(prompts): add markdown preview
   fix(runs): handle null response from provider
   docs: update installation instructions
   refactor(ui): simplify button component
   ```

5. **Push your branch** and open a Pull Request.

6. **Address feedback** — Respond to review comments and iterate.

## Working with Assets (CSS/JS)

If you modify CSS or JavaScript:

```bash
# 1. Rebuild assets
mix assets.build

# 2. Force recompile to pick up new asset hashes
mix compile --force
```

Built assets in `priv/static/` are committed to git to ensure asset hashes are calculated correctly at compile time.

For live development:

```bash
# Watch CSS changes
mix tailwind aludel --watch

# Watch JS changes (in another terminal)
mix esbuild aludel --watch
```

Or use the standalone app for full development server:

```bash
cd standalone
mix phx.server
```

## Testing

- Write tests for new features and bug fixes
- Ensure all tests pass before submitting: `mix test`
- Maintain or improve code coverage

## Maintainer Releases

Keep user-facing release notes under `Unreleased` in `CHANGELOG.md`, then run the **Release Hex Package** workflow with the next SemVer version without a leading `v`. The workflow serializes releases, moves those curated notes into the new version, verifies the package, creates the version commit and annotated tag, publishes the GitHub release, and publishes the Hex package and documentation.

Rerun the same version after an interruption. A tag-only state recreates the GitHub release from the versioned changelog, a GitHub release without a Hex package resumes package publication, and an existing Hex package republishes its documentation. The workflow refuses GitHub or Hex release state that has no matching repository tag.

## Questions or Ideas?

- **💬 [Discussions](https://github.com/ccarvalho-eng/aludel/discussions)** — Ask questions, share ideas, or discuss use cases
- **🐛 [Issues](https://github.com/ccarvalho-eng/aludel/issues)** — Report bugs or request features

## License

By contributing, you agree that your contributions will be licensed under the [Apache License 2.0](LICENSE).
