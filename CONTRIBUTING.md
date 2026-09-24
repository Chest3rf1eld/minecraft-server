# Contributing

## Before opening a pull request

Run the repository checks available in your environment:

```bash
python3 scripts/validate-repository.py
shellcheck scripts/*.sh
ansible-playbook -i ansible/inventory/production/hosts.example.yml ansible/playbooks/bootstrap.yml --syntax-check
ansible-lint ansible/
```

With Docker Desktop running, run the full integration suite:

```bash
bash test/local/run-all.sh
```

This executes the isolated operational test scenarios, then downloads the
pinned Paper and configured plugin artifacts and verifies that Paper starts
and enables each configured plugin. Containers and ephemeral test data are
removed when the run exits, including on test failure or interruption.

For quicker feedback while editing mocked deploy, backup, restore, or config
behavior, run only the offline-friendly scenarios:

```bash
bash test/local/run-fast.sh
```

The fast suite uses shimmed system services, downloads, and a Minecraft
protocol stub. It does not replace the full Paper/plugin startup check.

## CI behavior

GitHub Actions runs static validation, secret scanning, and the same complete
integration command (`bash test/local/run-all.sh`) for pull requests and pushes
to `main` and `dev`. The integration job has no production credentials and
does not connect to Discord or other production services. DiscordSRV is checked
for local startup only; live bot authentication and chat/voice behavior remain
manual verification in `test/paper-local/`.

Test architecture and rationale live in `SPEC.md` §11 and §12.5. Harness
mechanics and scenario-writing guidance live in `test/local/README.md`.
