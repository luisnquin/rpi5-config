const std = @import("std");
const cron = @import("cron.zig");

const Io = std.Io;
const Dir = Io.Dir;
const File = Io.File;
const Allocator = std.mem.Allocator;
const Env = std.process.Environ.Map;
const Strings = std.json.ArrayHashMap([]const u8);

const Config = struct {
    state: []const u8 = "/var/lib/skinner",
    keep: usize = 100,
    hooks: []const []const u8 = &.{},
    hosts: Strings = .{},
    devices: std.json.ArrayHashMap(Device) = .{},
    repos: std.json.ArrayHashMap(Repo) = .{},
};

const Device = struct {
    setup: []const u8 = "",
    recover: []const u8 = "",
    env: Strings = .{},
};

const Repo = struct {
    url: []const u8,
    branch: []const u8 = "main",
    env: Strings = .{},
};

const Job = struct {
    run: []const u8,
    schedule: ?[]const u8 = null,
    device: ?[]const u8 = null,
    shell: []const u8 = "default",
    timeout: u32 = 3600,
};

const Jobs = std.json.ArrayHashMap(Job);

const Request = struct {
    repo: []const u8,
    job: []const u8,
    trigger: []const u8,
};

const Meta = struct {
    id: []const u8,
    repo: []const u8,
    job: []const u8,
    trigger: []const u8,
    status: []const u8 = "running",
    message: ?[]const u8 = null,
    commit: ?[]const u8 = null,
    device: ?[]const u8 = null,
    host: []const u8 = "",
    kernel: []const u8 = "",
    arch: []const u8 = "",
    exit: ?u8 = null,
    started: i64,
    finished: ?i64 = null,
};

const Event = struct {
    event: []const u8,
    time: i64,
    run: ?[]const u8 = null,
    repo: ?[]const u8 = null,
    job: ?[]const u8 = null,
    status: ?[]const u8 = null,
    message: ?[]const u8 = null,
};

const Pending = struct {
    hook: []const u8,
    body: []const u8,
};

const run_script =
    \\cd "$SKINNER_REPO_DIR" || exit 70
    \\if [ -n "${ANDROID_SERIAL:-}" ]; then
    \\  trap 'adb shell input keyevent KEYCODE_SLEEP >/dev/null 2>&1' EXIT
    \\  start=$(adb shell date +%s | tr -d '\r')
    \\  if [ -n "${SKINNER_SETUP:-}" ]; then "$SKINNER_SETUP" || exit 75; fi
    \\fi
    \\timeout -k 30 "$SKINNER_TIMEOUT" nix develop ".#$SKINNER_SHELL" -c "./$SKINNER_RUN"
    \\rc=$?
    \\if [ -n "${ANDROID_SERIAL:-}" ]; then
    \\  adb logcat -d -v threadtime -T "${start:-0}.000" >"$SKINNER_RUN_DIR/logcat.txt" 2>&1
    \\  adb shell getprop >"$SKINNER_RUN_DIR/device.props" 2>&1
    \\fi
    \\cd "$SKINNER_REPO_DIR" && git checkout -q -f "origin/$SKINNER_BRANCH"
    \\exit $rc
;

const sync_script =
    \\set -e
    \\if [ ! -d "$SKINNER_REPO_DIR/.git" ]; then
    \\  git clone --branch "$SKINNER_BRANCH" "$SKINNER_URL" "$SKINNER_REPO_DIR"
    \\fi
    \\cd "$SKINNER_REPO_DIR"
    \\git remote set-url origin "$SKINNER_URL"
    \\git fetch --quiet origin "$SKINNER_BRANCH"
    \\git reset --quiet --hard "origin/$SKINNER_BRANCH"
    \\git clean -qfd
;

const publish_script =
    \\cd "$SKINNER_REPO_DIR" || exit 1
    \\git add "skinner/$SKINNER_JOB.md"
    \\git -c user.name=skinner -c user.email=skinner@chimera -c commit.gpgsign=false commit --quiet -m "$SKINNER_MESSAGE" || exit 1
    \\for _ in 1 2 3; do
    \\  git push --quiet origin "HEAD:$SKINNER_BRANCH" && exit 0
    \\  git pull --quiet --rebase origin "$SKINNER_BRANCH" || git rebase --abort
    \\done
    \\exit 1
;

const Ctx = struct {
    io: Io,
    arena: Allocator,
    env: *const Env,
    cfg: Config,

    fn path(c: *Ctx, comptime fmt: []const u8, args: anytype) []u8 {
        return std.fmt.allocPrint(c.arena, "{s}/" ++ fmt, .{c.cfg.state} ++ args) catch oom();
    }

    fn now(c: *Ctx) i64 {
        return Io.Timestamp.now(c.io, .real).toSeconds();
    }
};

fn oom() noreturn {
    std.debug.print("skinner: out of memory\n", .{});
    std.process.exit(1);
}

fn fail(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print("skinner: " ++ fmt ++ "\n", args);
    std.process.exit(2);
}

const usage =
    \\usage: skinner <command>
    \\  daemon                       scheduler loop
    \\  run <repo> <job> [--wait]    queue a manual run, --wait streams it
    \\  status                       queue and recent runs
    \\  logs [<run>]                 print a run log, the latest by default
    \\  await <host> [--timeout s]   block until a host answers its probe
    \\
;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.skip();
    const cmd = args.next() orelse {
        std.debug.print("{s}", .{usage});
        std.process.exit(2);
    };
    const config_path = init.environ_map.get("SKINNER_CONFIG") orelse "/etc/skinner/config.json";
    const raw = Dir.cwd().readFileAlloc(init.io, config_path, arena, .limited(1 << 20)) catch |e|
        fail("cannot read {s}: {t}", .{ config_path, e });
    const cfg = std.json.parseFromSliceLeaky(Config, arena, raw, .{ .ignore_unknown_fields = true }) catch |e|
        fail("bad config {s}: {t}", .{ config_path, e });
    var c: Ctx = .{ .io = init.io, .arena = arena, .env = init.environ_map, .cfg = cfg };

    if (std.mem.eql(u8, cmd, "daemon")) return daemon(&c);
    if (std.mem.eql(u8, cmd, "run")) {
        const repo = args.next() orelse fail("run needs <repo> <job>", .{});
        const job = args.next() orelse fail("run needs <repo> <job>", .{});
        const wait = if (args.next()) |a| std.mem.eql(u8, a, "--wait") else false;
        return manual(&c, repo, job, wait);
    }
    if (std.mem.eql(u8, cmd, "status")) return status(&c);
    if (std.mem.eql(u8, cmd, "logs")) return logs(&c, args.next());
    if (std.mem.eql(u8, cmd, "await")) {
        const host = args.next() orelse fail("await needs <host>", .{});
        var limit: i64 = 6 * 3600;
        if (args.next()) |flag| {
            if (!std.mem.eql(u8, flag, "--timeout")) fail("unknown flag {s}", .{flag});
            const v = args.next() orelse fail("--timeout needs seconds", .{});
            limit = std.fmt.parseInt(i64, v, 10) catch fail("bad timeout {s}", .{v});
        }
        std.process.exit(if (try wait_host(&c, host, limit)) 0 else 1);
    }
    std.debug.print("{s}", .{usage});
    std.process.exit(2);
}

fn stamp(buf: []u8, epoch: i64) []const u8 {
    const t = cron.Tm.of(epoch);
    return std.fmt.bufPrint(buf, "{d:0>4}{d:0>2}{d:0>2}T{d:0>2}{d:0>2}{d:0>2}Z", .{ t.year, t.month, t.dom, t.hour, t.minute, t.second }) catch unreachable;
}

fn iso(c: *Ctx, epoch: i64) []const u8 {
    const t = cron.Tm.of(epoch);
    return std.fmt.allocPrint(c.arena, "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2} UTC", .{ t.year, t.month, t.dom, t.hour, t.minute, t.second }) catch oom();
}

fn json(c: *Ctx, v: anytype) []u8 {
    return std.json.Stringify.valueAlloc(c.arena, v, .{ .emit_null_optional_fields = false }) catch oom();
}

fn read(c: *Ctx, p: []const u8) ?[]u8 {
    return Dir.cwd().readFileAlloc(c.io, p, c.arena, .limited(64 << 20)) catch null;
}

fn write(c: *Ctx, p: []const u8, data: []const u8) !void {
    const tmp = std.fmt.allocPrint(c.arena, "{s}.tmp", .{p}) catch oom();
    try Dir.cwd().writeFile(c.io, .{ .sub_path = tmp, .data = data });
    try Dir.rename(Dir.cwd(), tmp, Dir.cwd(), p, c.io);
}

fn append(c: *Ctx, p: []const u8, line: []const u8) void {
    const f = Dir.cwd().createFile(c.io, p, .{ .truncate = false }) catch return;
    defer f.close(c.io);
    const end = f.length(c.io) catch return;
    f.writePositionalAll(c.io, line, end) catch {};
}

fn names(c: *Ctx, dir: []const u8) [][]const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    var d = Dir.cwd().openDir(c.io, dir, .{ .iterate = true }) catch return list.items;
    defer d.close(c.io);
    var it = d.iterate();
    while (it.next(c.io) catch null) |e| {
        if (std.mem.endsWith(u8, e.name, ".tmp")) continue;
        list.append(c.arena, c.arena.dupe(u8, e.name) catch oom()) catch oom();
    }
    std.mem.sort([]const u8, list.items, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lt);
    return list.items;
}

fn code(term: std.process.Child.Term) u8 {
    return switch (term) {
        .exited => |n| n,
        .signal => |s| 128 +| @as(u8, @truncate(@intFromEnum(s))),
        else => 255,
    };
}

fn spawn(c: *Ctx, argv: []const []const u8, env: *const Env, out: ?File) u8 {
    const io: std.process.SpawnOptions.StdIo = if (out) |f| .{ .file = f } else .inherit;
    var child = std.process.spawn(c.io, .{ .argv = argv, .environ_map = env, .stdin = .ignore, .stdout = io, .stderr = io }) catch |e| {
        if (out) |f| f.writeStreamingAll(c.io, std.fmt.allocPrint(c.arena, "skinner: spawn {s}: {t}\n", .{ argv[0], e }) catch oom()) catch {};
        return 127;
    };
    return code(child.wait(c.io) catch return 255);
}

fn sh(c: *Ctx, script: []const u8, env: *const Env, out: ?File) u8 {
    return spawn(c, &.{ "sh", "-c", script }, env, out);
}

fn deliver(c: *Ctx, hook: []const u8, body: []const u8) bool {
    var child = std.process.spawn(c.io, .{
        .argv = &.{ "sh", "-c", hook },
        .environ_map = c.env,
        .stdin = .pipe,
        .stdout = .ignore,
        .stderr = .inherit,
    }) catch return false;
    if (child.stdin) |in| {
        in.writeStreamingAll(c.io, body) catch {};
        in.close(c.io);
        child.stdin = null;
    }
    return (child.wait(c.io) catch return false).success();
}

fn emit(c: *Ctx, ev: Event) void {
    const body = json(c, ev);
    if (ev.run) |id| append(c, c.path("runs/{s}/events.jsonl", .{id}), std.fmt.allocPrint(c.arena, "{s}\n", .{body}) catch oom());
    for (c.cfg.hooks, 0..) |hook, i| {
        if (deliver(c, hook, body)) continue;
        var buf: [32]u8 = undefined;
        const name = std.fmt.allocPrint(c.arena, "{s}-{d}-{d}", .{ stamp(&buf, ev.time), i, @mod(Io.Timestamp.now(c.io, .real).toNanoseconds(), 1_000_000_000) }) catch oom();
        Dir.cwd().createDirPath(c.io, c.path("outbox", .{})) catch {};
        write(c, c.path("outbox/{s}.json", .{name}), json(c, Pending{ .hook = hook, .body = body })) catch {};
    }
}

fn flush_outbox(c: *Ctx) void {
    for (names(c, c.path("outbox", .{}))) |name| {
        const p = c.path("outbox/{s}", .{name});
        const raw = read(c, p) orelse continue;
        const pending = std.json.parseFromSliceLeaky(Pending, c.arena, raw, .{}) catch {
            Dir.cwd().deleteFile(c.io, p) catch {};
            continue;
        };
        if (!deliver(c, pending.hook, pending.body)) return;
        Dir.cwd().deleteFile(c.io, p) catch {};
    }
}

fn enqueue(c: *Ctx, req: Request) ![]const u8 {
    var buf: [32]u8 = undefined;
    const suffix = std.fmt.allocPrint(c.arena, "-{s}-{s}.json", .{ req.repo, req.job }) catch oom();
    if (std.mem.eql(u8, req.trigger, "schedule")) {
        for (names(c, c.path("queue", .{}))) |n| if (std.mem.endsWith(u8, n, suffix)) return error.AlreadyQueued;
    }
    const id = std.fmt.allocPrint(c.arena, "{s}-{s}-{s}", .{ stamp(&buf, c.now()), req.repo, req.job }) catch oom();
    try Dir.cwd().createDirPath(c.io, c.path("queue", .{}));
    const f = try Dir.cwd().createFile(c.io, c.path("queue/{s}.json", .{id}), .{ .exclusive = true });
    defer f.close(c.io);
    try f.writeStreamingAll(c.io, json(c, req));
    emit(c, .{ .event = "queued", .time = c.now(), .run = id, .repo = req.repo, .job = req.job });
    return id;
}

fn jobs_of(c: *Ctx, name: []const u8) ?Jobs {
    const raw = read(c, c.path("repos/{s}.jobs.json", .{name})) orelse return null;
    return std.json.parseFromSliceLeaky(Jobs, c.arena, raw, .{ .ignore_unknown_fields = true }) catch null;
}

fn repo_env(c: *Ctx, name: []const u8, repo: Repo) Env {
    var env = c.env.clone(c.arena) catch oom();
    env.put("SKINNER_REPO", name) catch oom();
    env.put("SKINNER_REPO_DIR", c.path("repos/{s}", .{name})) catch oom();
    env.put("SKINNER_URL", repo.url) catch oom();
    env.put("SKINNER_BRANCH", repo.branch) catch oom();
    secrets(c, &env, repo.env);
    return env;
}

fn secrets(c: *Ctx, env: *Env, files: Strings) void {
    var it = files.map.iterator();
    while (it.next()) |kv| {
        const raw = read(c, kv.value_ptr.*) orelse continue;
        env.put(kv.key_ptr.*, std.mem.trimEnd(u8, raw, "\r\n")) catch oom();
    }
}

fn sync(c: *Ctx, name: []const u8, env: *const Env, out: ?File) ?Jobs {
    Dir.cwd().createDirPath(c.io, c.path("repos", .{})) catch return null;
    if (sh(c, sync_script, env, out) != 0) return null;
    const res = std.process.run(c.arena, c.io, .{
        .argv = &.{ "nix", "eval", "--json", ".#skinner.jobs" },
        .cwd = .{ .path = env.get("SKINNER_REPO_DIR").? },
        .environ_map = env,
    }) catch return null;
    if (out) |f| f.writeStreamingAll(c.io, res.stderr) catch {};
    if (!res.term.success()) return null;
    write(c, c.path("repos/{s}.jobs.json", .{name}), res.stdout) catch {};
    return std.json.parseFromSliceLeaky(Jobs, c.arena, res.stdout, .{ .ignore_unknown_fields = true }) catch null;
}

fn verdict(rc: u8) []const u8 {
    return switch (rc) {
        0 => "passed",
        78 => "skipped",
        124, 137 => "timeout",
        70, 75, 127 => "error",
        else => "failed",
    };
}

fn device_ready(c: *Ctx, dev: []const u8, env: *const Env, log: File) u8 {
    return spawn(c, &.{ "phone", "run", "-t", dev, "--", "adb", "get-state" }, env, log);
}

fn execute(c: *Ctx, id: []const u8, req: Request) void {
    const dir = c.path("runs/{s}", .{id});
    Dir.cwd().createDirPath(c.io, dir) catch return;
    const log = Dir.cwd().createFile(c.io, c.path("runs/{s}/run.log", .{id}), .{}) catch return;
    defer log.close(c.io);
    const uts = std.posix.uname();
    var meta: Meta = .{
        .id = id,
        .repo = req.repo,
        .job = req.job,
        .trigger = req.trigger,
        .started = c.now(),
        .host = c.arena.dupe(u8, std.mem.sliceTo(&uts.nodename, 0)) catch oom(),
        .kernel = c.arena.dupe(u8, std.mem.sliceTo(&uts.release, 0)) catch oom(),
        .arch = c.arena.dupe(u8, std.mem.sliceTo(&uts.machine, 0)) catch oom(),
    };
    const meta_path = c.path("runs/{s}/meta.json", .{id});
    write(c, meta_path, json(c, meta)) catch {};
    emit(c, .{ .event = "started", .time = c.now(), .run = id, .repo = req.repo, .job = req.job });

    const finish = struct {
        fn f(cx: *Ctx, m: *Meta, p: []const u8, st: []const u8, msg: ?[]const u8) void {
            m.status = st;
            m.message = msg;
            m.finished = cx.now();
            write(cx, p, json(cx, m.*)) catch {};
        }
    }.f;

    const repo = c.cfg.repos.map.get(req.repo) orelse return finish(c, &meta, meta_path, "error", "unknown repo");
    var env = repo_env(c, req.repo, repo);
    const jobs = sync(c, req.repo, &env, log) orelse return finish(c, &meta, meta_path, "error", "sync or nix eval failed");
    const job = jobs.map.get(req.job) orelse return finish(c, &meta, meta_path, "error", "job not in .#skinner.jobs");
    const head = std.process.run(c.arena, c.io, .{ .argv = &.{ "git", "rev-parse", "HEAD" }, .cwd = .{ .path = env.get("SKINNER_REPO_DIR").? } }) catch null;
    if (head) |h| meta.commit = std.mem.trimEnd(u8, h.stdout, "\n");
    meta.device = job.device;

    const timeout = std.fmt.allocPrint(c.arena, "{d}", .{job.timeout}) catch oom();
    env.put("SKINNER_RUN_ID", id) catch oom();
    env.put("SKINNER_JOB", req.job) catch oom();
    env.put("SKINNER_TRIGGER", req.trigger) catch oom();
    env.put("SKINNER_RUN_DIR", dir) catch oom();
    env.put("SKINNER_REPORT", c.path("runs/{s}/report.md", .{id})) catch oom();
    env.put("SKINNER_RUN", job.run) catch oom();
    env.put("SKINNER_SHELL", job.shell) catch oom();
    env.put("SKINNER_TIMEOUT", timeout) catch oom();

    var rc: u8 = undefined;
    if (job.device) |dev| {
        const device = c.cfg.devices.map.get(dev) orelse Device{};
        env.put("SKINNER_DEVICE", dev) catch oom();
        defer _ = spawn(c, &.{ "phone", "release", "-t", dev }, &env, log);
        if (device.setup.len > 0) env.put("SKINNER_SETUP", device.setup) catch oom();
        secrets(c, &env, device.env);
        const deadline = c.now() + job.timeout;
        var told = false;
        while (true) {
            const ready = device_ready(c, dev, &env, log);
            if (ready == 0) break;
            if (ready == 3 and c.now() < deadline) {
                if (!told) emit(c, .{ .event = "waiting", .time = c.now(), .run = id, .repo = req.repo, .job = req.job, .message = std.fmt.allocPrint(c.arena, "{s} is busy", .{dev}) catch oom() });
                told = true;
                c.io.sleep(.fromSeconds(60), .awake) catch {};
                continue;
            }
            if (ready != 3) {
                if (device.recover.len > 0) _ = sh(c, device.recover, &env, log);
                _ = spawn(c, &.{ "phone", "device", "connect", dev }, &env, log);
                if (device_ready(c, dev, &env, log) == 0) break;
            }
            const msg = std.fmt.allocPrint(c.arena, "{s} unreachable from {s}", .{ dev, meta.host }) catch oom();
            emit(c, .{ .event = "device.unreachable", .time = c.now(), .run = id, .repo = req.repo, .job = req.job, .message = msg });
            finish(c, &meta, meta_path, if (ready == 3) "busy" else "unreachable", msg);
            return report(c, &meta, req, &env, log);
        }
        rc = spawn(c, &.{ "phone", "run", "-t", dev, "--", "sh", "-c", run_script }, &env, log);
    } else {
        rc = sh(c, run_script, &env, log);
    }
    meta.exit = rc;
    finish(c, &meta, meta_path, verdict(rc), null);
    report(c, &meta, req, &env, log);
}

fn tail(text: []const u8, lines: usize) []const u8 {
    var n: usize = 0;
    var i = text.len;
    while (i > 0) : (i -= 1) {
        if (text[i - 1] == '\n' and i != text.len) {
            n += 1;
            if (n == lines) return text[i..];
        }
    }
    return text;
}

fn props(c: *Ctx, raw: []const u8, out: *std.ArrayList(u8)) void {
    const wanted = [_][]const u8{ "ro.product.manufacturer", "ro.product.model", "ro.build.version.release", "ro.build.version.sdk", "ro.build.fingerprint", "persist.sys.timezone" };
    var lines = std.mem.splitScalar(u8, raw, '\n');
    while (lines.next()) |line| {
        for (wanted) |k| {
            const key = std.fmt.allocPrint(c.arena, "[{s}]: [", .{k}) catch oom();
            if (!std.mem.startsWith(u8, line, key)) continue;
            const v = std.mem.trimEnd(u8, line[key.len..], "]\r");
            out.print(c.arena, "| {s} | `{s}` |\n", .{ k, v }) catch oom();
        }
    }
}

fn same_status(prev: []const u8, st: []const u8) bool {
    var lines = std.mem.splitScalar(u8, prev, '\n');
    while (lines.next()) |line| {
        const rest = std.mem.cutPrefix(u8, line, "| status | **") orelse continue;
        return std.mem.startsWith(u8, rest, st) and std.mem.startsWith(u8, rest[st.len..], "**");
    }
    return false;
}

fn report(c: *Ctx, meta: *Meta, req: Request, env: *Env, log: File) void {
    emit(c, .{ .event = "finished", .time = c.now(), .run = meta.id, .repo = req.repo, .job = req.job, .status = meta.status, .message = meta.message });
    if (std.mem.eql(u8, meta.status, "skipped")) return;
    const a = c.arena;
    const repo_dir = env.get("SKINNER_REPO_DIR").?;
    const target = std.fmt.allocPrint(a, "{s}/skinner", .{repo_dir}) catch oom();
    const file = std.fmt.allocPrint(a, "{s}/{s}.md", .{ target, req.job }) catch oom();
    if (read(c, file)) |prev| if (same_status(prev, meta.status)) return;
    var md: std.ArrayList(u8) = .empty;
    const started = meta.started;
    const finished = meta.finished orelse started;
    md.print(a, "# skinner: {s}\n\n| | |\n| --- | --- |\n", .{req.job}) catch oom();
    md.print(a, "| status | **{s}**{s}{s} |\n", .{ meta.status, if (meta.message != null) ": " else "", meta.message orelse "" }) catch oom();
    md.print(a, "| run | `{s}` |\n| trigger | {s} |\n| commit | `{s}` |\n", .{ meta.id, meta.trigger, meta.commit orelse "?" }) catch oom();
    md.print(a, "| window | {s} to {s} ({d}s) |\n", .{ iso(c, started), iso(c, finished), finished - started }) catch oom();
    md.print(a, "| host | {s} ({s}, linux {s}) |\n", .{ meta.host, meta.arch, meta.kernel }) catch oom();
    if (meta.exit) |rc| md.print(a, "| exit | {d} |\n", .{rc}) catch oom();
    if (meta.device) |dev| md.print(a, "| device | {s} |\n", .{dev}) catch oom();
    if (read(c, c.path("runs/{s}/device.props", .{meta.id}))) |raw| props(c, raw, &md);
    if (read(c, c.path("runs/{s}/report.md", .{meta.id}))) |frag| md.print(a, "\n{s}\n", .{std.mem.trimEnd(u8, frag, "\n")}) catch oom();
    if (read(c, c.path("runs/{s}/run.log", .{meta.id}))) |raw|
        md.print(a, "\n## Log (tail)\n\n```text\n{s}\n```\n", .{std.mem.trimEnd(u8, tail(raw, 150), "\n")}) catch oom();
    if (read(c, c.path("runs/{s}/logcat.txt", .{meta.id}))) |raw|
        md.print(a, "\n## Logcat window (tail)\n\n```text\n{s}\n```\n", .{std.mem.trimEnd(u8, tail(raw, 300), "\n")}) catch oom();

    Dir.cwd().createDirPath(c.io, target) catch return;
    write(c, file, md.items) catch return;
    env.put("SKINNER_MESSAGE", std.fmt.allocPrint(a, "chore(skinner): {s} {s} [skip ci]", .{ req.job, meta.status }) catch oom()) catch oom();
    if (sh(c, publish_script, env, log) != 0)
        emit(c, .{ .event = "report.failed", .time = c.now(), .run = meta.id, .repo = req.repo, .job = req.job, .message = "could not push skinner report" });
}

fn prune(c: *Ctx) void {
    const runs = names(c, c.path("runs", .{}));
    if (runs.len <= c.cfg.keep) return;
    for (runs[0 .. runs.len - c.cfg.keep]) |n| Dir.cwd().deleteTree(c.io, c.path("runs/{s}", .{n})) catch {};
}

fn daemon(c: *Ctx) !void {
    const root = c.arena;
    var scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer scratch.deinit();
    var refreshed = std.StringHashMap(i64).init(root);
    var last = @divFloor(c.now(), 60);
    var flushed: i64 = 0;
    for (c.cfg.repos.map.keys()) |name| _ = refreshed.put(name, 0) catch oom();
    while (true) {
        _ = scratch.reset(.retain_capacity);
        c.arena = scratch.allocator();
        const t = c.now();
        if (t - flushed >= 60) {
            flush_outbox(c);
            flushed = t;
        }
        var it = c.cfg.repos.map.iterator();
        while (it.next()) |kv| {
            const seen = refreshed.getPtr(kv.key_ptr.*).?;
            if (t - seen.* < 3600) continue;
            seen.* = t;
            var env = repo_env(c, kv.key_ptr.*, kv.value_ptr.*);
            _ = sync(c, kv.key_ptr.*, &env, null);
        }
        const minute = @divFloor(t, 60);
        var m = @max(last + 1, minute - 1440);
        while (m <= minute) : (m += 1) {
            for (c.cfg.repos.map.keys()) |name| {
                const jobs = jobs_of(c, name) orelse continue;
                var jt = jobs.map.iterator();
                while (jt.next()) |j| {
                    const spec = j.value_ptr.schedule orelse continue;
                    const s = cron.Schedule.parse(spec) catch continue;
                    if (s.matches(cron.local(m * 60))) _ = enqueue(c, .{ .repo = name, .job = j.key_ptr.*, .trigger = "schedule" }) catch {};
                }
            }
        }
        last = minute;
        const queue = names(c, c.path("queue", .{}));
        if (queue.len > 0) {
            const file = c.path("queue/{s}", .{queue[0]});
            const raw = read(c, file);
            Dir.cwd().deleteFile(c.io, file) catch {};
            if (raw) |r| if (std.json.parseFromSliceLeaky(Request, c.arena, r, .{})) |req| {
                execute(c, queue[0][0 .. queue[0].len - ".json".len], req);
                if (c.cfg.repos.map.getPtr(req.repo) != null) refreshed.getPtr(req.repo).?.* = c.now();
                prune(c);
            } else |_| {};
            continue;
        }
        c.io.sleep(.fromSeconds(5), .awake) catch {};
    }
}

fn manual(c: *Ctx, repo: []const u8, job: []const u8, wait: bool) !void {
    if (c.cfg.repos.map.get(repo) == null) fail("unknown repo {s}", .{repo});
    const id = enqueue(c, .{ .repo = repo, .job = job, .trigger = "manual" }) catch |e| fail("cannot queue: {t}", .{e});
    const out = File.stdout();
    try out.writeStreamingAll(c.io, std.fmt.allocPrint(c.arena, "{s}\n", .{id}) catch oom());
    if (!wait) return;
    var offset: u64 = 0;
    var buf: [64 << 10]u8 = undefined;
    while (true) {
        const meta = blk: {
            const raw = read(c, c.path("runs/{s}/meta.json", .{id})) orelse break :blk null;
            break :blk std.json.parseFromSliceLeaky(Meta, c.arena, raw, .{ .ignore_unknown_fields = true }) catch null;
        };
        if (Dir.cwd().openFile(c.io, c.path("runs/{s}/run.log", .{id}), .{})) |f| {
            defer f.close(c.io);
            while (true) {
                const n = f.readPositionalAll(c.io, &buf, offset) catch 0;
                if (n == 0) break;
                offset += n;
                try out.writeStreamingAll(c.io, buf[0..n]);
            }
        } else |_| {}
        if (meta) |m| if (m.finished != null) {
            try out.writeStreamingAll(c.io, std.fmt.allocPrint(c.arena, "skinner: {s} {s}{s}{s}\n", .{ id, m.status, if (m.message != null) ": " else "", m.message orelse "" }) catch oom());
            std.process.exit(if (std.mem.eql(u8, m.status, "passed") or std.mem.eql(u8, m.status, "skipped")) 0 else 1);
        };
        c.io.sleep(.fromSeconds(1), .awake) catch {};
    }
}

fn status(c: *Ctx) !void {
    var out: std.ArrayList(u8) = .empty;
    for (names(c, c.path("queue", .{}))) |n| out.print(c.arena, "queued   {s}\n", .{n[0 .. n.len - ".json".len]}) catch oom();
    const runs = names(c, c.path("runs", .{}));
    const from = runs.len -| 20;
    var i = runs.len;
    while (i > from) {
        i -= 1;
        const raw = read(c, c.path("runs/{s}/meta.json", .{runs[i]})) orelse continue;
        const m = std.json.parseFromSliceLeaky(Meta, c.arena, raw, .{ .ignore_unknown_fields = true }) catch continue;
        out.print(c.arena, "{s: <8} {s}{s}{s}\n", .{ m.status, m.id, if (m.message != null) "  " else "", m.message orelse "" }) catch oom();
    }
    try File.stdout().writeStreamingAll(c.io, out.items);
}

fn logs(c: *Ctx, id: ?[]const u8) !void {
    const runs = names(c, c.path("runs", .{}));
    const which = id orelse (if (runs.len > 0) runs[runs.len - 1] else fail("no runs yet", .{}));
    const raw = read(c, c.path("runs/{s}/run.log", .{which})) orelse fail("no log for {s}", .{which});
    try File.stdout().writeStreamingAll(c.io, raw);
}

fn wait_host(c: *Ctx, host: []const u8, limit: i64) !bool {
    const probe = c.cfg.hosts.map.get(host) orelse fail("unknown host {s}", .{host});
    const run = c.env.get("SKINNER_RUN_ID");
    const repo = c.env.get("SKINNER_REPO");
    const job = c.env.get("SKINNER_JOB");
    const deadline = c.now() + limit;
    var told = false;
    while (true) {
        if (sh(c, probe, c.env, null) == 0) {
            if (told) emit(c, .{ .event = "ready", .time = c.now(), .run = run, .repo = repo, .job = job, .message = host });
            return true;
        }
        if (c.now() >= deadline) {
            emit(c, .{ .event = "await.timeout", .time = c.now(), .run = run, .repo = repo, .job = job, .message = host });
            return false;
        }
        if (!told) emit(c, .{ .event = "waiting", .time = c.now(), .run = run, .repo = repo, .job = job, .message = std.fmt.allocPrint(c.arena, "waiting for {s}", .{host}) catch oom() });
        told = true;
        c.io.sleep(.fromSeconds(@min(30, deadline - c.now())), .awake) catch {};
    }
}

test {
    _ = cron;
}

test "tail" {
    try std.testing.expectEqualStrings("c\nd\n", tail("a\nb\nc\nd\n", 2));
    try std.testing.expectEqualStrings("a\nb", tail("a\nb", 5));
}

test "same_status" {
    const prev = "# skinner: e2e\n\n| | |\n| --- | --- |\n| status | **failed**: boom |\n";
    try std.testing.expect(same_status(prev, "failed"));
    try std.testing.expect(!same_status(prev, "fail"));
    try std.testing.expect(!same_status(prev, "passed"));
    try std.testing.expect(!same_status("", "passed"));
}

test "verdict" {
    try std.testing.expectEqualStrings("skipped", verdict(78));
    try std.testing.expectEqualStrings("timeout", verdict(124));
    try std.testing.expectEqualStrings("failed", verdict(1));
}
