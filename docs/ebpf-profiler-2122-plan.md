# Plan: Respond to open-telemetry/opentelemetry-ebpf-profiler#2122

## Problem

The eBPF profiler (`otel/opentelemetry-collector-ebpf-profiler:0.165.0`) fails in the local kind cluster with
`unable to read kallsyms addresses - check capabilities`.

Root cause (per maintainer @florianl, comment 2026-11-18):
- `/proc/kallsyms` is readable but all addresses are zero. With `kptr_restrict=1` the kernel reveals addresses only to
  processes holding `CAP_SYSLOG` in the **initial** user namespace.
- This repo runs **rootless** Podman. kind node capabilities live in a child user namespace, so the addresses stay hidden.
- `kptr_restrict=0` would only move the failure. Loading eBPF and opening perf events also needs `CAP_BPF`/`CAP_PERFMON`/
  `CAP_SYS_ADMIN` in the initial user namespace, which rootless containers can't have.
- Maintainer's conclusion: rootless Podman/kind won't work. Use **rootful Podman or Docker**, and give the profiler pod the
  required privileges.

## Decisions

- Runtime: **rootful Podman**. `KIND_EXPERIMENTAL_PROVIDER=podman` stays.
- Profiler privileges: **`securityContext.privileged: true`** on the ebpf-profiler OpenTelemetryCollector. The `hostPID` and
  hostPath mounts are unchanged.

## Changes

- [ebpf-profiler-collector.yaml](/workspaces/opentelemetry-operator-demo/environments/annotations/local/ebpf-profiler-collector.yaml):
  `securityContext` sets `privileged: true`, replacing the `SYS_ADMIN`/`BPF`/`PERFMON` capability list.
- [devcontainer.json](/workspaces/opentelemetry-operator-demo/.devcontainer/devcontainer.json): the Podman socket comes from
  `/run/podman/podman.sock` instead of `$XDG_RUNTIME_DIR`.
- [README.md](/workspaces/opentelemetry-operator-demo/README.md): rootless setup instructions are replaced with rootful Podman steps.
- [justfile](/workspaces/opentelemetry-operator-demo/justfile): no change needed. It reads the socket from `PODMAN_HOST_SOCKET`,
  and the `kptr_restrict` step still works.

## Host Podman changes (run on the host, not in the repo)

These steps can't run from the dev container. Run them on the host, then rebuild the dev container. Paths such as `/run/podman/podman.sock` refer to the host; inside the dev container the same socket is at `/var/run/podman-host.sock`.

1. **Enable the system Podman socket.**
   - `podman.socket` exists separately in the system and user systemd managers; these are distinct socket instances, even though they have the same unit name.
   - Run `sudo systemctl enable --now podman.socket`.
   - Verify **on the host** with `ls -l /run/podman/podman.sock`. The socket should exist. This path doesn't exist inside the dev container.
   - No need to disable the user socket: the Dev Container explicitly mounts `/run/podman/podman.sock`, not the rootless socket under `$XDG_RUNTIME_DIR`.
2. **Give the dev container user access to the socket.**
   - The socket is owned by root. Your user needs access, usually through the `podman` group.
   - Check the group owner **on the host** with `ls -l /run/podman/podman.sock`. Add your user with `sudo usermod -aG podman $USER`, then log out and back in.
   - Verify **on the host** with `podman --remote --url unix:///run/podman/podman.sock info`.
   - Verify **inside the dev container** (after step 4) with `podman --remote --url unix:///var/run/podman-host.sock info`. The socket is bind-mounted there from the host. Without the `info` subcommand, Podman prints its help and fails with `missing command 'podman COMMAND'`.
3. **Set `kernel.kptr_restrict=1` on the host.**
   - Check with `sysctl kernel.kptr_restrict`.
   - Persist it: `echo 'kernel.kptr_restrict=1' | sudo tee /etc/sysctl.d/99-kptr-restrict.conf && sudo sysctl --system`.
   - The reporter already has this set on the host, but confirm it.
4. **Rebuild the dev container.** This picks up the new `/run/podman/podman.sock` mount in `devcontainer.json`.
5. **Clean up the rootless kind leftovers.**
   - Run `KIND_EXPERIMENTAL_PROVIDER=podman kind get clusters` as your user. A leftover rootless cluster would conflict with the new one.
   - Delete any leftover with `just cluster-delete` before `just cluster-create`.

These steps are verified: `podman --remote --url unix:///var/run/podman-host.sock info` reports `Rootless: false` from the dev container, and the cluster came up. If `podman info` reports a rootless store when the socket is rootful, check the `CONTAINER_HOST` value inside the dev container.

## Todos

- Done: confirm runtime (rootful Podman) and privileges (`privileged: true`).
- Done: update the Collector privileges.
- Done: update the README.
- Done: host Podman changes (steps 1–5) run on the host.
- Done: confirm the justfile needs no change.
- Done: check `docs/architecture.md` and `AGENTS.md` for rootless Podman references. None found.
- Done: `just cluster-create` succeeded and ArgoCD synced the applications.
- Done: validation (plan criteria). On the kind worker node, `/proc/kallsyms` shows non-zero `_stext`/`_text`, and the profiler logs show no kallsyms error.
- Done: posted the reply on #2122 (open-telemetry/opentelemetry-ebpf-profiler#issuecomment-7002332541) after approval.
- Done: the profiler pods are Running on all three kind workers (`ebpf-profiler-collector-*`, 1/1, "Everything is ready").
  The earlier CrashLoopBackOff is gone. The remaining log warning is `Failed to attach prctl monitor: ... sys_exit_prctl ... no such file or directory`.
  It is non-fatal: the tracer and sched monitor still attach. The host kernel (7.3.1) has `# CONFIG_FTRACE_SYSCALLS is not set`,
  so syscall tracepoints are missing. Optional follow-up: a kernel with `CONFIG_FTRACE_SYSCALLS=y` would enable the prctl monitor.
  Checked: the profiling receiver has no option to skip the prctl monitor. Upstream logs a warning and continues because core profiling is unaffected
  Decision: accept the warning. No repo or host change is planned.

## Notes

- The reporter's host is Bluefin, kernel 7.3.1, rootless Podman 6.1.4, kind v0.33.0, Kubernetes v1.37.0.
- Answered: rootful Podman with `kptr_restrict=1` on the host is enough for kallsyms addresses to be non-zero on the kind nodes. The profiler still needs syscall tracepoints (see Todos).
