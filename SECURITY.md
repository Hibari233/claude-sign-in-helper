# Security policy

Claude Sign-In Helper handles sign-in cookies and reads an encryption key from the macOS Keychain, so security reports are taken seriously.

## Reporting a vulnerability

Please **don't open a public issue**. Report privately through GitHub instead: open the repository's **Security** tab and choose **Report a vulnerability**.

Include the helper version (shown in **About Claude Sign-In Helper**), your macOS version, and steps to reproduce.

> [!CAUTION]
> Never include real cookie values, session keys, tokens, Keychain passwords, backup folders, cookie databases, or raw Claude logs. Synthetic examples and the redacted error messages the app shows are enough.

## Scope

**In scope:** how the helper reads, encrypts, writes, backs up, and restores data. That includes anything that could:

- Expose credentials
- Write outside the intended cookie rows or folders
- Follow symbolic links
- Overwrite a newer sign-in
- Leave Claude Desktop's cookie store in a damaged state

**Out of scope:** Claude and Anthropic's services (report those to Anthropic), and Safari or macOS themselves (report those to Apple).

## Supported versions

Only the latest release receives fixes.
