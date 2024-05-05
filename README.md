# Useful Docker Compose Templates

The `Makefile` is an example for running commands for nextcloud. Running `make` without argument simply displays a list of available tasks.

It's possible to chain commands. For example:

```bash
make down build up logs
```