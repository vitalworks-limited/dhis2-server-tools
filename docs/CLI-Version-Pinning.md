# DHIS2 version pinning per host

Each DHIS2 instance has its own `dhis2_version` in the inventory. The
role resolves that string to a specific WAR URL from
[releases.dhis2.org](https://releases.dhis2.org/v1/versions/stable.json).

## Formats

| `dhis2_version` | Meaning |
| ---------------- | ------- |
| `2.43` (bare, no quotes) | **Latest patch** of the 2.43 channel. Ansible may parse this as a float; the role treats it as "latest in channel". Re-running pulls whatever is newest at that moment. |
| `"2.43"` (quoted) | Same as above - behaves identically to the bare form. |
| `"2.43.2"` | **Pin** to patch 2.43.2 exactly. The role resolves to that patch's URL and SHA-256. |
| `"2.43.2.1"` | Pin to patch 2.43.2.1 exactly. |

Any string with **three or more dotted components** is a pin. Any
string with two or fewer is a channel ("latest patch of X.Y").

## Pin strictness

By default a pin is **lenient**: if the exact patch is not in
`releases.json` (typo, upstream removal, custom build) the role falls
back to the channel's latest patch and prints a `WARNING`. For
production hosts you want this to fail instead:

```ini
[instances]
hmis  ansible_host=172.19.2.11  database_host=postgres \
      dhis2_version="2.43.2"  dhis2_pin_patch_version=true  dhis2_auto_upgrade=false
```

With `dhis2_pin_patch_version=true` the role **fails the deployment**
if `2.43.2` cannot be resolved, preventing silent drift.

## Precedence (highest wins)

```
1. dhis2_war_file  (URL or local path)   — explicit artifact, resolver skipped
2. dhis2_version  "2.X.Y[.Z]"            — pinned patch
3. dhis2_version  2.X                    — latest patch of channel
4. role default (dhis2_version: 2.42)    — fallback
```

`dhis2_auto_upgrade=true` only controls whether the resolver re-runs
and re-downloads on every deployment. It does **not** override the
pin: with `dhis2_version="2.43.2"` the role resolves to `2.43.2` every
time, so auto-upgrade is a no-op for the version itself.

## CLI shortcuts

```bash
# Set and validate against releases.json before writing to inventory
dhis2-instance set-version hmis "2.43.2" --pin

# Lenient - track latest within channel
dhis2-instance set-version hmis "2.43" --allow-latest-patch

# Show what the role will actually resolve to for this host
dhis2-instance resolve-version hmis
```

`set-version` refuses a bare channel (e.g. `2.43`) unless
`--allow-latest-patch` is passed, so operators cannot accidentally
leave a production host tracking "whatever is newest tomorrow".
`--pin` additionally sets `dhis2_pin_patch_version=true` for the host.

## Controlled upgrade

`dhis2-upgrade run --to` requires a full `major.minor.patch`:

```bash
dhis2-upgrade run hmis --to 2.43.2 \
    --backup-before-migration --verify-backup --monitor-migrations
```

A bare `--to 2.43` is rejected. Pass `--allow-latest-patch` only when
you deliberately want to track the latest patch of a channel. The
`run` command sets `dhis2_pin_patch_version=true` by default when a
patch is supplied, so a typo in the version (e.g. `2.43.99`) fails
loudly rather than silently installing whatever is newest.

If you want to upgrade with the pin relaxed on this run only, pass
`--no-pin`:

```bash
dhis2-upgrade run hmis --to 2.43.2 --no-pin   # tolerate fallback to latest if 2.43.2 is gone
```

## Multi-instance precedence example

```ini
[all:vars]
dhis2_version=2.43             # fallback for the whole fleet

[instances]
# Inherits fleet default (latest 2.43.x)
dev    ansible_host=172.19.2.1  database_host=postgres

# Pinned per-host (overrides fleet default)
hmis   ansible_host=172.19.2.11 database_host=postgres \
       dhis2_version="2.43.2" dhis2_pin_patch_version=true

# Different major channel for an older service
legacy ansible_host=172.19.2.12 database_host=postgres \
       dhis2_version="2.40.6.1" dhis2_pin_patch_version=true
```

Per-host overrides win over the `[all:vars]` block. Operators can
confirm each resolution with:

```bash
dhis2-instance resolve-version dev
dhis2-instance resolve-version hmis
dhis2-instance resolve-version legacy
```
