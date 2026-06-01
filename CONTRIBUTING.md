# Contributing to Prism
We love your input! We want to make contributing to this project as easy and transparent as possible, whether it's:

- Reporting a bug
- Discussing the current state of the code
- Submitting a fix
- Proposing new features
- Becoming a maintainer

## We Develop with Github
We use github to host code, to track issues and feature requests, as well as accept pull requests.

## Secrets policy
Runtime secrets are managed in Doppler (project `prism`). Do not rely on local `.env` syncing.

When introducing a new secret, update all three:

1. Doppler config(s) (`dev` and/or `production`)
2. `.env.example` (reference-only schema)
3. `lib/env/env.dart` (if the app reads it via `String.fromEnvironment`)

## We Use [Github Flow](https://guides.github.com/introduction/flow/index.html), So All Code Changes Happen Through Pull Requests
Pull requests are the best way to propose changes to the codebase (we use [Github Flow](https://guides.github.com/introduction/flow/index.html)). We actively welcome your pull requests:

1. Fork the repo and create your branch from `master`.
2. Set up secrets via Doppler — all runtime secrets (API keys, tokens) are managed through Doppler, not local files. Run `make setup-dev` after getting Doppler access. See [README → Secrets with Doppler](README.md#secrets-with-doppler) and [`docs/development/doppler.md`](docs/development/doppler.md) for details.
3. No legacy cloud project or generated config files are required. Configure runtime API keys through Doppler and `lib/env/env.dart`.
4. Run `make file-gen` after making changes to models, routes, or DI registrations to regenerate `freezed`, `auto_route`, and `injectable` code.
5. If you've added code that should be tested, add tests.
6. If you've changed APIs, update the documentation.
7. Ensure the test suite passes (`make test`).
8. Make sure your code passes linting (`make analyze`) and formatting (`make format-check`).
9. Issue that pull request!

## Any contributions you make will be under the BSD-3 Software License
In short, when you submit code changes, your submissions are understood to be under the same [BSD-3 License](https://choosealicense.com/licenses/bsd-3-clause/) that covers the project. Feel free to contact the maintainers if that's a concern.

## Report bugs using Github's [issues](https://github.com/Hash-Studios/Prism/issues)
We use GitHub issues to track public bugs. Report a bug by [opening a new issue](https://github.com/Hash-Studios/Prism/issues/new); it's that easy!

## Write bug reports with detail, background, and sample code
**Great Bug Reports** tend to have:

- A quick summary and/or background
- Steps to reproduce
  - Be specific!
  - Give sample code if you can.
- What you expected would happen
- What actually happens
- Notes (possibly including why you think this might be happening, or stuff you tried that didn't work)

People *love* thorough bug reports. We're not even kidding.

## Use a Consistent Coding Style

- Run `make format-check` before submitting a PR (checks Dart formatting)
- Run `make analyze` for static analysis — fix all warnings before submitting
- Run `make test` to ensure all unit and widget tests pass
- Run `make env-guard` to verify that `String.fromEnvironment` calls only appear in `lib/env/env.dart`
- Run `make analytics-check` if you've added or changed analytics events (regenerates and validates the analytics schema)

## License
By contributing, you agree that your contributions will be licensed under its BSD-3 License.
