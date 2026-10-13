# Contributing

AirPointer is licensed under the [MIT License](LICENSE). Submit only code and assets that you have the right to contribute under that license.

For a bug report, include the app version, macOS/Xcode version, selected profile, expected behavior and steps to reproduce. Prefer diagnostic-only state text and synthetic examples. Remove personal paths, screen content, credentials and hand recordings from reports and logs.

Run the offline tests described in the README before proposing gesture-engine changes. Keep camera access, input posting and permission prompts out of automated unit tests by using the existing injected permission/action interfaces. Real-world gesture accuracy needs a separate manual check.

Do not commit certificates, provisioning profiles, `.env` files, `.airframes.json` recordings, Xcode user data, build products or diagnostic bundles. Keep your development team settings local. Review new dependencies and asset rights before adding them.

If you discover a credential or private recording in the repository, do not paste it into a public issue. Contact the maintainer through a private channel to coordinate handling.
