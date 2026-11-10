const std = @import("std");
const linux = std.os.linux;

const usage =
    \\usage: farm [--once] [--idle secs] [--night H-H] [cgroup...]
    \\
    \\  Draws a farm on its own virtual console and switches to it after the
    \\  active console has seen no input for --idle seconds (300). Any key
    \\  switches back. During --night hours the screen is blanked instead.
    \\  Every running service and user slice becomes a field, biggest RSS
    \\  first: crops grow with its RSS, workers walk it with its CPU. Each
    \\  cgroup argument (a unit like skinner.service, or a path under
    \\  /sys/fs/cgroup) is pinned first and shown even when stopped.
    \\  Tailnet peers are cabins on the hills, a fire burning while online.
    \\  --once prints a single frame to stdout and exits.
    \\
;

const MAXW = 320;
const MAXH = 120;
const FPS = 4;
const MAX_WORK = 64;

const VT_GETSTATE = 0x5603;
const VT_ACTIVATE = 0x5606;
const TIOCLINUX = 0x541C;
const TIOCGWINSZ = 0x5413;

const black: u4 = 0;
const red: u4 = 1;
const green: u4 = 2;
const brown: u4 = 3;
const blue: u4 = 4;
const magenta: u4 = 5;
const white: u4 = 7;
const gray: u4 = 8;
const bred: u4 = 9;
const bgreen: u4 = 10;
const bcyan: u4 = 14;
const yellow: u4 = 11;
const bwhite: u4 = 15;

const Cell = packed struct(u32) { ch: u21 = ' ', fg: u4 = white, bg: u3 = 0, _: u4 = 0 };

var back: [MAXW * MAXH]Cell = undefined;
var front: [MAXW * MAXH]Cell = undefined;
var W: i32 = 80;
var H: i32 = 24;

var out_buf: [1 << 16]u8 = undefined;
var out_len: usize = 0;

var rot: f32 = 0;
var cart: f32 = 0;

var works: [MAX_WORK]Work = undefined;
var nw: usize = 0;
var npin: usize = 0;

const Peer = struct { name: [16]u8 = undefined, len: usize = 0, online: bool = false, active: bool = false };
var peers: [16]Peer = undefined;
var np: usize = 0;
var ts_buf: [1 << 16]u8 = undefined;

const Sys = struct {
    load: f32 = 0,
    busy: f32 = 0,
    cpu_total: u64 = 0,
    cpu_idle: u64 = 0,
    mem: u32 = 0,
    disk: u32 = 0,
    temp: i32 = 0,
    net: f64 = 0,
    up: u64 = 0,
    net_last: u64 = 0,
    wifi: i32 = -1,
    dbm: i32 = 0,
    eth: i32 = 0,
    ts_at: i64 = 0,
    at: i64 = 0,
    tz: i32 = 0,
    host: []const u8 = "farm",
};

const Work = struct {
    buf: [96]u8 = undefined,
    len: usize = 0,
    seen: bool = false,
    up: bool = false,
    rss: u64 = 0,
    cpu: f32 = 0,
    usec: u64 = 0,
    pos: f32 = 0,

    fn init(p: []const u8) ?Work {
        var w: Work = .{};
        if (p.len > w.buf.len) return null;
        @memcpy(w.buf[0..p.len], p);
        w.len = p.len;
        return w;
    }

    fn path(w: *const Work) []const u8 {
        return w.buf[0..w.len];
    }
};

pub fn main(init: std.process.Init) !void {
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.skip();
    var idle: i64 = 300;
    var night = [2]u8{ 0, 0 };
    var once = false;
    while (args.next()) |a| {
        if (std.mem.eql(u8, a, "--once")) {
            once = true;
        } else if (std.mem.eql(u8, a, "--idle")) {
            idle = std.fmt.parseInt(i64, args.next() orelse fail("--idle needs seconds"), 10) catch fail("bad --idle");
        } else if (std.mem.eql(u8, a, "--night")) {
            const v = args.next() orelse fail("--night needs H-H");
            const dash = std.mem.indexOfScalar(u8, v, '-') orelse fail("bad --night");
            night[0] = std.fmt.parseInt(u8, v[0..dash], 10) catch fail("bad --night");
            night[1] = std.fmt.parseInt(u8, v[dash + 1 ..], 10) catch fail("bad --night");
        } else if (a.len > 0 and a[0] == '-') {
            fail(usage);
        } else if (npin < MAX_WORK) {
            works[npin] = Work.init(a) orelse fail("cgroup path too long");
            npin += 1;
        }
    }
    nw = npin;

    var host_buf: [64]u8 = undefined;
    var sys: Sys = .{};
    if (readFile("/proc/sys/kernel/hostname", &host_buf)) |h| sys.host = std.mem.trim(u8, h, " \n");

    if (once) {
        const size = winsize(1) orelse [2]i32{ 120, 40 };
        resize(size);
        const now = realtime();
        sys.tz = tzOffset(now);
        sample(&sys);
        sleepMs(500);
        sample(&sys);
        draw(&sys, 0, now + sys.tz);
        dump();
        return;
    }
    daemon(&sys, idle, night);
}

fn daemon(sys: *Sys, idle: i64, night: [2]u8) noreturn {
    const me = ownVt() orelse fail("stdin is not a virtual console");
    var tio: linux.termios = undefined;
    if (!bad(linux.tcgetattr(0, &tio))) {
        tio.lflag.ICANON = false;
        tio.lflag.ECHO = false;
        tio.lflag.ISIG = false;
        _ = linux.tcsetattr(0, .NOW, &tio);
    }

    var prev: u16 = 1;
    var shown = false;
    var blanked = false;
    var full = true;
    var woke = realtime();
    var frame: u64 = 0;
    while (true) {
        const now = realtime();
        const active = activeVt();
        if (active != me) {
            shown = false;
            if (active != 0) prev = active;
            if (active != 0 and now - @max(ttyAtime(active), woke) >= idle) activate(me);
            sleepMs(1000);
            continue;
        }
        if (!shown) {
            shown = true;
            full = true;
            frame = 0;
            if (winsize(0)) |s| resize(s);
            sys.tz = tzOffset(now);
            emit("\x1b[?25l\x1b[?7l\x1b[0m\x1b[2J");
        }
        const hour: u8 = @intCast(@divFloor(@mod(now + sys.tz, 86400), 3600));
        if (inNight(night, hour)) {
            if (!blanked) {
                emit("\x1b[0m\x1b[2J");
                flushOut();
                blank(true);
                blanked = true;
            }
            if (waitKey(1000)) {
                blank(false);
                blanked = false;
                woke = realtime();
                activate(prev);
            }
            continue;
        }
        if (blanked) {
            blank(false);
            blanked = false;
            full = true;
        }
        if (frame % (FPS * 2) == 0) sample(sys);
        draw(sys, frame, now + sys.tz);
        present(full);
        full = false;
        frame += 1;
        if (waitKey(1000 / FPS)) {
            woke = realtime();
            activate(prev);
        }
    }
}

fn fail(msg: []const u8) noreturn {
    std.debug.print("farm: {s}\n", .{msg});
    std.process.exit(2);
}

fn label(path: []const u8) []const u8 {
    const base = if (std.mem.lastIndexOfScalar(u8, path, '/')) |i| path[i + 1 ..] else path;
    return if (std.mem.lastIndexOfScalar(u8, base, '.')) |i| base[0..i] else base;
}

fn inNight(n: [2]u8, h: u8) bool {
    if (n[0] == n[1]) return false;
    return if (n[0] < n[1]) h >= n[0] and h < n[1] else h >= n[0] or h < n[1];
}


fn bad(rc: usize) bool {
    return @as(isize, @bitCast(rc)) < 0;
}

fn readFile(path: [*:0]const u8, buf: []u8) ?[]u8 {
    const rc = linux.open(path, .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0);
    if (bad(rc)) return null;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    var n: usize = 0;
    while (n < buf.len) {
        const r = linux.read(fd, buf[n..].ptr, buf.len - n);
        if (bad(r)) return null;
        if (r == 0) break;
        n += r;
    }
    return buf[0..n];
}

fn readFmt(out: []u8, comptime fmt: []const u8, args: anytype) ?[]u8 {
    var p: [512]u8 = undefined;
    return readFile(std.mem.printSentinel(&p, fmt, args, 0) catch return null, out);
}

fn clock(id: linux.clockid_t) i64 {
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(id, &ts);
    return @as(i64, ts.sec) * std.time.ns_per_s + ts.nsec;
}

fn realtime() i64 {
    return @divFloor(clock(.REALTIME), std.time.ns_per_s);
}

fn sleepMs(ms: i32) void {
    _ = linux.poll(@ptrFromInt(@alignOf(linux.pollfd)), 0, ms);
}

fn waitKey(ms: i32) bool {
    var fds = [1]linux.pollfd{.{ .fd = 0, .events = linux.POLL.IN, .revents = 0 }};
    const r = linux.poll(&fds, 1, ms);
    if (bad(r) or r == 0) return false;
    if (fds[0].revents & (linux.POLL.HUP | linux.POLL.ERR) != 0) fail("console hung up");
    var b: [64]u8 = undefined;
    _ = linux.read(0, &b, b.len);
    return true;
}

fn statx(fd: i32, path: [*:0]const u8, flags: u32) ?linux.Statx {
    var st: linux.Statx = undefined;
    if (bad(linux.statx(fd, path, flags, .{ .TYPE = true, .ATIME = true }, &st))) return null;
    return st;
}

fn ownVt() ?u16 {
    const st = statx(0, "", linux.AT.EMPTY_PATH) orelse return null;
    if (st.rdev_major != 4 or st.rdev_minor == 0 or st.rdev_minor > 63) return null;
    return @intCast(st.rdev_minor);
}

fn ttyAtime(vt: u16) i64 {
    var p: [32]u8 = undefined;
    const path = std.mem.printSentinel(&p, "/dev/tty{d}", .{vt}, 0) catch return 0;
    const st = statx(linux.AT.FDCWD, path, 0) orelse return 0;
    return st.atime.sec;
}

fn activeVt() u16 {
    var st: [3]u16 = undefined;
    if (bad(linux.ioctl(0, VT_GETSTATE, @intFromPtr(&st)))) return 0;
    return st[0];
}

fn activate(vt: u16) void {
    _ = linux.ioctl(0, VT_ACTIVATE, vt);
}

fn blank(on: bool) void {
    var sub: u8 = if (on) 14 else 4;
    _ = linux.ioctl(0, TIOCLINUX, @intFromPtr(&sub));
}

fn winsize(fd: i32) ?[2]i32 {
    var ws: std.posix.winsize = undefined;
    if (bad(linux.ioctl(fd, TIOCGWINSZ, @intFromPtr(&ws))) or ws.col == 0) return null;
    return .{ ws.col, ws.row };
}

fn resize(s: [2]i32) void {
    W = std.math.clamp(s[0], 1, MAXW);
    H = std.math.clamp(s[1], 1, MAXH);
}


fn nth(s: []const u8, n: usize) ?[]const u8 {
    var it = std.mem.tokenizeAny(u8, s, " \t\n");
    var i: usize = 0;
    while (it.next()) |t| : (i += 1) if (i == n) return t;
    return null;
}

fn field(s: []const u8, key: []const u8) ?u64 {
    const i = std.mem.indexOf(u8, s, key) orelse return null;
    return std.fmt.parseInt(u64, nth(s[i + key.len ..], 0) orelse return null, 10) catch null;
}

fn tailnet() void {
    const rc = linux.socket(linux.AF.UNIX, linux.SOCK.STREAM | linux.SOCK.CLOEXEC, 0);
    if (bad(rc)) return;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    var sa: linux.sockaddr.un = .{ .path = @splat(0) };
    const path = "/run/tailscale/tailscaled.sock";
    @memcpy(sa.path[0..path.len], path);
    const tv: linux.timeval = .{ .sec = 1, .usec = 0 };
    _ = linux.setsockopt(fd, linux.SOL.SOCKET, linux.SO.RCVTIMEO, std.mem.asBytes(&tv), @sizeOf(linux.timeval));
    if (bad(linux.connect(fd, &sa, @sizeOf(linux.sockaddr.un)))) return;
    const req = "GET /localapi/v0/status HTTP/1.0\r\nHost: local-tailscaled.sock\r\n\r\n";
    if (bad(linux.write(fd, req, req.len))) return;
    var n: usize = 0;
    while (n < ts_buf.len) {
        const r = linux.read(fd, ts_buf[n..].ptr, ts_buf.len - n);
        if (bad(r) or r == 0) break;
        n += r;
    }
    parsePeers(ts_buf[0..n]);
}

fn jsonTrue(seg: []const u8, key: []const u8) bool {
    const k = std.mem.indexOf(u8, seg, key) orelse return false;
    return std.mem.startsWith(u8, std.mem.trimStart(u8, seg[k + key.len ..], " \t\n"), "true");
}

fn parsePeers(t: []const u8) void {
    np = 0;
    const key = "\"DNSName\":";
    var i = std.mem.indexOf(u8, t, "\"Peer\":") orelse return;
    while (np < peers.len) {
        const a = std.mem.indexOfPos(u8, t, i, key) orelse break;
        const end = std.mem.indexOfPos(u8, t, a + key.len, key) orelse t.len;
        i = end;
        const seg = t[a + key.len .. end];
        const q0 = std.mem.indexOfScalar(u8, seg, '"') orelse continue;
        const q1 = std.mem.indexOfAnyPos(u8, seg, q0 + 1, ".\"") orelse continue;
        var p: Peer = .{ .online = jsonTrue(seg, "\"Online\":"), .active = jsonTrue(seg, "\"Active\":") };
        p.len = @min(q1 - q0 - 1, p.name.len);
        if (p.len == 0) continue;
        @memcpy(p.name[0..p.len], seg[q0 + 1 ..][0..p.len]);
        peers[np] = p;
        np += 1;
    }
    std.mem.sort(Peer, peers[0..np], {}, struct {
        fn lt(_: void, a: Peer, b: Peer) bool {
            if (a.online != b.online) return a.online;
            return std.mem.lessThan(u8, a.name[0..a.len], b.name[0..b.len]);
        }
    }.lt);
}

fn sample(s: *Sys) void {
    var buf: [8192]u8 = undefined;
    const now = clock(.MONOTONIC);
    const dt: i64 = if (s.at == 0) 0 else now - s.at;
    s.at = now;

    if (readFile("/proc/loadavg", &buf)) |t| s.load = std.fmt.parseFloat(f32, nth(t, 0) orelse "0") catch 0;
    if (readFile("/proc/stat", &buf)) |t| {
        var it = std.mem.tokenizeScalar(u8, t[0 .. std.mem.indexOfScalar(u8, t, '\n') orelse t.len], ' ');
        _ = it.next();
        var total: u64 = 0;
        var idle: u64 = 0;
        var i: usize = 0;
        while (it.next()) |v| : (i += 1) {
            if (i == 8) break;
            const x = std.fmt.parseInt(u64, v, 10) catch 0;
            total += x;
            if (i == 3 or i == 4) idle += x;
        }
        if (s.cpu_total > 0 and total > s.cpu_total and idle >= s.cpu_idle)
            s.busy = 100 - @as(f32, @floatFromInt(idle - s.cpu_idle)) * 100 / @as(f32, @floatFromInt(total - s.cpu_total));
        s.cpu_total = total;
        s.cpu_idle = idle;
    }
    if (readFile("/proc/uptime", &buf)) |t| s.up = @intFromFloat(std.fmt.parseFloat(f64, nth(t, 0) orelse "0") catch 0);
    if (readFile("/sys/class/thermal/thermal_zone0/temp", &buf)) |t|
        s.temp = @divTrunc(std.fmt.parseInt(i32, std.mem.trim(u8, t, " \n"), 10) catch 0, 1000);
    if (readFile("/proc/meminfo", &buf)) |t| {
        const total = field(t, "MemTotal:") orelse 0;
        const avail = field(t, "MemAvailable:") orelse 0;
        if (total > avail) s.mem = @intCast((total - avail) * 100 / total);
    }
    var sf: [16]u64 = undefined;
    if (!bad(linux.syscall2(.statfs, @intFromPtr("/"), @intFromPtr(&sf))) and sf[2] > 0)
        s.disk = @intCast(100 - sf[4] * 100 / sf[2]);
    s.eth = 0;
    if (readFile("/proc/net/dev", &buf)) |t| {
        var total: u64 = 0;
        var lines = std.mem.tokenizeScalar(u8, t, '\n');
        while (lines.next()) |line| {
            const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
            const name = std.mem.trim(u8, line[0..colon], " ");
            var p: [96]u8 = undefined;
            if (statx(linux.AT.FDCWD, std.mem.printSentinel(&p, "/sys/class/net/{s}/device", .{name}, 0) catch continue, 0) == null) continue;
            var small: [32]u8 = undefined;
            const wireless = statx(linux.AT.FDCWD, std.mem.printSentinel(&p, "/sys/class/net/{s}/wireless", .{name}, 0) catch continue, 0) != null;
            const up = if (readFmt(&small, "/sys/class/net/{s}/operstate", .{name})) |o| std.mem.startsWith(u8, o, "up") else false;
            if (up and !wireless) s.eth = @max(s.eth, if (readFmt(&small, "/sys/class/net/{s}/speed", .{name})) |v| std.fmt.parseInt(i32, std.mem.trim(u8, v, " \n"), 10) catch 1 else 1);
            const rest = line[colon + 1 ..];
            total += (std.fmt.parseInt(u64, nth(rest, 0) orelse "0", 10) catch 0) +
                (std.fmt.parseInt(u64, nth(rest, 8) orelse "0", 10) catch 0);
        }
        s.net = if (dt > 0 and s.net_last > 0 and total >= s.net_last)
            @as(f64, @floatFromInt(total - s.net_last)) * std.time.ns_per_s / @as(f64, @floatFromInt(dt))
        else
            0;
        s.net_last = total;
    }
    s.wifi = -1;
    if (readFile("/proc/net/wireless", &buf)) |t| {
        var lines = std.mem.tokenizeScalar(u8, t, '\n');
        while (lines.next()) |line| {
            const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
            const q = std.fmt.parseInt(i32, std.mem.trimEnd(u8, nth(line[colon + 1 ..], 1) orelse continue, "."), 10) catch continue;
            if (q <= s.wifi) continue;
            s.wifi = q;
            s.dbm = std.fmt.parseInt(i32, std.mem.trimEnd(u8, nth(line[colon + 1 ..], 2) orelse "0", "."), 10) catch 0;
        }
    }
    if (s.ts_at == 0 or now - s.ts_at > 30 * std.time.ns_per_s) {
        s.ts_at = now;
        tailnet();
    }

    discover();
    for (works[0..nw]) |*w| {
        var p: [512]u8 = undefined;
        var base: []u8 = &.{};
        var usec: ?u64 = null;
        const nested = std.mem.indexOfScalar(u8, w.path(), '/') != null;
        const pres = [_][]const u8{ "system.slice/", "" };
        for (pres[@intFromBool(nested)..]) |pre| {
            base = std.fmt.bufPrint(&p, "/sys/fs/cgroup/{s}{s}", .{ pre, w.path() }) catch continue;
            usec = if (readFmt(&buf, "{s}/cpu.stat", .{base})) |t| field(t, "usage_usec") else null;
            if (usec != null) break;
        }
        w.up = usec != null;
        if (usec) |u| {
            w.cpu = if (dt > 0 and w.usec > 0 and u >= w.usec)
                @floatCast(@as(f64, @floatFromInt(u - w.usec)) * 1000 * 100 / @as(f64, @floatFromInt(dt)))
            else
                0;
            w.usec = u;
            w.rss = treeRss(&p, base.len, 0);
        } else {
            w.cpu = 0;
            w.usec = 0;
            w.rss = 0;
        }
    }
    std.mem.sort(Work, works[npin..nw], {}, struct {
        fn bigger(_: void, a: Work, b: Work) bool {
            return a.rss > b.rss;
        }
    }.bigger);
}

// Running services and user slices, kept in place across samples so CPU deltas survive.
fn discover() void {
    for (works[npin..nw]) |*w| w.seen = false;
    scan("/sys/fs/cgroup/system.slice", "system.slice/", ".service");
    scan("/sys/fs/cgroup/user.slice", "user.slice/", ".slice");
    var keep = npin;
    for (works[npin..nw]) |w| if (w.seen) {
        works[keep] = w;
        keep += 1;
    };
    nw = keep;
}

fn scan(dir: [*:0]const u8, prefix: []const u8, suffix: []const u8) void {
    var d = Subdirs.open(dir) orelse return;
    defer d.close();
    next: while (d.next()) |name| {
        if (!std.mem.endsWith(u8, name, suffix)) continue;
        var pb: [96]u8 = undefined;
        const p = std.fmt.bufPrint(&pb, "{s}{s}", .{ prefix, name }) catch continue;
        for (works[0..npin]) |*w| {
            const q = w.path();
            if (std.mem.eql(u8, p, q) or (std.mem.endsWith(u8, p, q) and p[p.len - q.len - 1] == '/')) continue :next;
        }
        for (works[npin..nw]) |*w| if (std.mem.eql(u8, w.path(), p)) {
            w.seen = true;
            continue :next;
        };
        if (nw == MAX_WORK) continue;
        works[nw] = Work.init(p) orelse continue;
        works[nw].seen = true;
        nw += 1;
    }
}

const Subdirs = struct {
    fd: i32,
    db: [2048]u8 align(8) = undefined,
    n: usize = 0,
    off: usize = 0,

    fn open(path: [*:0]const u8) ?Subdirs {
        const rc = linux.open(path, .{ .ACCMODE = .RDONLY, .DIRECTORY = true, .CLOEXEC = true }, 0);
        return if (bad(rc)) null else .{ .fd = @intCast(rc) };
    }

    fn close(d: *Subdirs) void {
        _ = linux.close(d.fd);
    }

    fn next(d: *Subdirs) ?[]const u8 {
        while (true) {
            if (d.off >= d.n) {
                const n = linux.getdents64(d.fd, &d.db, d.db.len);
                if (bad(n) or n == 0) return null;
                d.n = n;
                d.off = 0;
            }
            const reclen = std.mem.readInt(u16, d.db[d.off + 16 ..][0..2], .little);
            const typ = d.db[d.off + 18];
            const name = std.mem.sliceTo(d.db[d.off + 19 .. d.off + reclen], 0);
            d.off += reclen;
            if (typ == linux.DT.DIR and name[0] != '.') return name;
        }
    }
};

// Sums RSS over every process in the cgroup subtree; shared pages count once per process.
fn treeRss(p: *[512]u8, len: usize, depth: u8) u64 {
    var total: u64 = 0;
    var buf: [4096]u8 = undefined;
    if (readFmt(&buf, "{s}/cgroup.procs", .{p[0..len]})) |t| {
        var it = std.mem.tokenizeScalar(u8, t, '\n');
        while (it.next()) |pid| {
            var sb: [128]u8 = undefined;
            const st = readFmt(&sb, "/proc/{s}/statm", .{pid}) orelse continue;
            total += (std.fmt.parseInt(u64, nth(st, 1) orelse "0", 10) catch 0) * std.heap.pageSize();
        }
    }
    if (depth >= 4 or len >= p.len - 1) return total;
    p[len] = 0;
    var d = Subdirs.open(@ptrCast(p)) orelse return total;
    defer d.close();
    while (d.next()) |name| {
        if (len + 1 + name.len >= p.len) continue;
        p[len] = '/';
        @memcpy(p[len + 1 ..][0..name.len], name);
        total += treeRss(p, len + 1 + name.len, depth + 1);
    }
    return total;
}

fn tzOffset(now: i64) i32 {
    var buf: [8192]u8 = undefined;
    return tzifOffset(readFile("/etc/localtime", &buf) orelse return 0, now);
}

fn tzifOffset(t: []const u8, now: i64) i32 {
    if (t.len < 44 or !std.mem.eql(u8, t[0..4], "TZif")) return 0;
    const timecnt = std.mem.readInt(u32, t[32..36], .big);
    const typecnt = std.mem.readInt(u32, t[36..40], .big);
    const idxs = 44 + timecnt * 4;
    const types = idxs + timecnt;
    if (typecnt == 0 or types + typecnt * 6 > t.len) return 0;
    var ty: usize = 0;
    for (0..timecnt) |i| {
        if (std.mem.readInt(i32, t[44 + i * 4 ..][0..4], .big) > now) break;
        ty = t[idxs + i];
    }
    if (ty >= typecnt) return 0;
    return std.mem.readInt(i32, t[types + ty * 6 ..][0..4], .big);
}


fn cell(x: i32, y: i32) ?*Cell {
    if (x < 0 or y < 0 or x >= W or y >= H) return null;
    return &back[@intCast(y * W + x)];
}

fn put(x: i32, y: i32, ch: u21, fg: u4) void {
    if (cell(x, y)) |c| {
        c.ch = ch;
        c.fg = fg;
    }
}

fn paint(x: i32, y: i32, ch: u21, fg: u4, bg: u3) void {
    if (cell(x, y)) |c| c.* = .{ .ch = ch, .fg = fg, .bg = bg };
}

fn rect(x: i32, y: i32, w: i32, h: i32, ch: u21, fg: u4, bg: u3) void {
    var j = y;
    while (j < y + h) : (j += 1) {
        var i = x;
        while (i < x + w) : (i += 1) paint(i, j, ch, fg, bg);
    }
}

fn text(x: i32, y: i32, s: []const u8, fg: u4) i32 {
    var it = (std.unicode.Utf8View.init(s) catch return x).iterator();
    var i = x;
    while (it.nextCodepoint()) |cp| : (i += 1) put(i, y, cp, fg);
    return i;
}

fn sprite(x: i32, y: i32, lines: []const []const u8, fg: u4) void {
    for (lines, 0..) |line, j| {
        var it = (std.unicode.Utf8View.init(line) catch continue).iterator();
        var i = x;
        while (it.nextCodepoint()) |cp| : (i += 1) if (cp != ' ') put(i, y + @as(i32, @intCast(j)), cp, fg);
    }
}

fn hash(a: i32, b: i32, c: u32) u32 {
    var h = @as(u32, @bitCast(a)) *% 0x9E3779B1 ^ @as(u32, @bitCast(b)) *% 0x85EBCA77 ^ c *% 0xC2B2AE3D;
    h ^= h >> 15;
    h *%= 0x2C1B3C6D;
    h ^= h >> 12;
    return h;
}


fn emit(s: []const u8) void {
    if (out_len + s.len > out_buf.len) flushOut();
    @memcpy(out_buf[out_len..][0..s.len], s);
    out_len += s.len;
}

fn emitf(comptime fmt: []const u8, args: anytype) void {
    var b: [32]u8 = undefined;
    emit(std.fmt.bufPrint(&b, fmt, args) catch return);
}

fn flushOut() void {
    var off: usize = 0;
    while (off < out_len) {
        const r = linux.write(1, out_buf[off..].ptr, out_len - off);
        if (bad(r)) {
            if (linux.errno(r) == .INTR) continue;
            break;
        }
        off += r;
    }
    out_len = 0;
}

fn emitCell(c: Cell, last: *?Cell) void {
    if (last.* == null or last.*.?.fg != c.fg or last.*.?.bg != c.bg)
        emitf("\x1b[{d};{d}m", .{ if (c.fg < 8) 30 + @as(u8, c.fg) else 82 + @as(u8, c.fg), 40 + @as(u8, c.bg) });
    last.* = c;
    var b: [4]u8 = undefined;
    emit(b[0 .. std.unicode.utf8Encode(c.ch, &b) catch return]);
}

fn present(full: bool) void {
    var last: ?Cell = null;
    var cx: i32 = -1;
    var cy: i32 = -1;
    var y: i32 = 0;
    while (y < H) : (y += 1) {
        var x: i32 = 0;
        while (x < W) : (x += 1) {
            const i: usize = @intCast(y * W + x);
            if (!full and @as(u32, @bitCast(back[i])) == @as(u32, @bitCast(front[i]))) continue;
            if (cx != x or cy != y) emitf("\x1b[{d};{d}H", .{ y + 1, x + 1 });
            emitCell(back[i], &last);
            front[i] = back[i];
            cx = x + 1;
            cy = y;
        }
    }
    flushOut();
}

fn dump() void {
    var y: i32 = 0;
    while (y < H) : (y += 1) {
        var last: ?Cell = null;
        var x: i32 = 0;
        while (x < W) : (x += 1) emitCell(back[@intCast(y * W + x)], &last);
        emit("\x1b[0m\n");
    }
    flushOut();
}


const crops = [_]u21{ '.', ',', 'τ', '♣', '♠' };
const sun = [_][]const u8{ "▄██▄", "▀██▀" };
const moon = [_][]const u8{ "▄▀▀", "▀▄▄" };
const cloud = [_][]const u8{ "  ▄▄█▄▄  ", "▀▀▀▀▀▀▀▀▀" };
const roof = [_][]const u8{ "     ▄██▄     ", "  ▄████████▄  ", "▄████████████▄" };
const door = [_][]const u8{ "╔════╗", "║▒▒▒▒║", "║▒▒▒▒║" };

fn raining(local: i64) bool {
    return hash(@truncate(@divFloor(local, 1200)), 0, 11) % 100 < 12;
}

fn draw(s: *const Sys, frame: u64, local: i64) void {
    @memset(back[0..@intCast(W * H)], .{});
    if (W < 40 or H < 14) return status(s, local);

    const secs: f32 = @floatFromInt(@mod(local, 86400));
    const hour = secs / 3600;
    const day = hour >= 6 and hour < 18;
    const rain = raining(local);
    const dusk = @abs(hour - 6) < 0.5 or @abs(hour - 18) < 0.5;
    const sky: u3 = if (rain) (if (day) white else black) else if (dusk) magenta else if (day) blue else black;
    const soil: u3 = if (day) green else black;
    const hz = @max(6, @divTrunc(H * 2, 5));
    const road = H - 2;
    const f: u32 = @truncate(frame);

    rect(0, 0, W, hz, ' ', white, sky);
    if (!day and !rain) {
        var y: i32 = 0;
        while (y < hz - 2) : (y += 1) {
            var x: i32 = 0;
            while (x < W) : (x += 1) {
                const h = hash(x, y, 1);
                if (h % 61 == 0) put(x, y, if ((h >> 8) % 7 == (f / 6) % 7) '*' else '.', if (h % 2 == 0) bwhite else gray);
            }
        }
    }

    const arc = (if (day) hour - 6 else @mod(hour - 18, 24)) / 12;
    const span: f32 = @floatFromInt(W - 6);
    const lift: f32 = @floatFromInt(hz - 4);
    const by: i32 = @intFromFloat(@as(f32, @floatFromInt(hz - 3)) - @sin(arc * std.math.pi) * lift);
    if (!rain) sprite(@intFromFloat(1 + arc * span), by, if (day) &sun else &moon, if (!day) bwhite else if (s.temp >= 80) bred else yellow);

    const clouds: u32 = s.mem / 12 + @as(u32, if (rain) 8 else 0);
    for (0..clouds) |i| {
        const k: i32 = @intCast(i);
        const lane: u32 = @intCast(W + 18);
        const x = @as(i32, @intCast((hash(k, 0, 7) + f * (1 + hash(k, 0, 3) % 3) / (FPS * 3)) % lane)) - 9;
        const y: i32 = @intCast(hash(k, 0, 5) % @as(u32, @intCast(@max(1, hz - 6))));
        sprite(x, y, &cloud, if (rain) gray else if (day) bwhite else gray);
    }

    var x: i32 = 0;
    while (x < W) : (x += 1) {
        const fx: f32 = @floatFromInt(x);
        const half: i32 = @intFromFloat(2 + (@sin(fx / 7) + 1) * 1.5 + (@sin(fx / 19 + 2) + 1) * 1.5);
        var j: i32 = 0;
        while (j < @divTrunc(half, 2)) : (j += 1) put(x, hz - 1 - j, '█', green);
        if (@mod(half, 2) == 1) put(x, hz - 1 - @divTrunc(half, 2), '▄', green);
    }

    rect(0, hz, W, road - hz, ' ', white, soil);
    var y: i32 = hz;
    while (y < road) : (y += 1) {
        x = 0;
        while (x < W) : (x += 1) {
            const h = hash(x, y, 2);
            if (h % 13 == 0) put(x, y, if (h % 3 == 0) '"' else ',', if (day) bgreen else green);
            if (h % 173 == 0) put(x, y, '♣', black);
        }
    }

    if (rain) {
        x = 0;
        while (x < W) : (x += 1) {
            const h = hash(x, 0, 13);
            if (h % 4 != 0) continue;
            const fall: u32 = (h >> 4) + f * (1 + h % 3);
            for ([_]u32{ 0, @intCast(@divTrunc(road, 2)) }) |o| {
                const dy: i32 = @intCast((fall + o) % @as(u32, @intCast(road)));
                put(x, dy, '|', if (dy < hz) (if (day) blue else bcyan) else bcyan);
            }
        }
    }

    for (peers[0..np], 0..) |*p, i| {
        const k: i32 = @intCast(i);
        const slot = @divTrunc(W, @as(i32, @intCast(np)));
        if (slot < 4) break;
        const name = p.name[0..@min(p.len, @as(usize, @intCast(slot - 1)))];
        const px = slot * k + @divTrunc(slot, 2) - 1;
        const fx: f32 = @floatFromInt(px + 1);
        const half: i32 = @intFromFloat(2 + (@sin(fx / 7) + 1) * 1.5 + (@sin(fx / 19 + 2) + 1) * 1.5);
        const top = hz - 1 - @divTrunc(half - 1, 2);
        _ = text(px, top - 1, "▄█▄", bred);
        put(px, top, '█', brown);
        put(px + 2, top, '█', brown);
        const flame = hash(k, @intCast(f), 17) % 3;
        if (p.online) put(px + 1, top, if (flame == 0) '▓' else '▒', if (flame == 2) yellow else bred) else put(px + 1, top, '█', black);
        if (p.active) put(px + 3, top - 2 - @as(i32, @intCast((f / 2 + i) % 2)), '°', if (day) bwhite else gray);
        _ = text(px + 1 - @as(i32, @intCast(name.len / 2)), top - 2, name, if (p.online) (if (day) bwhite else white) else gray);
    }

    rect(0, road, W, 1, '·', black, brown);
    const kb = s.net / 1024;
    if (kb >= 1) cart += @floatCast(@min(2.0, 0.1 + @log2(kb) * 0.08));
    const cx = @as(i32, @intFromFloat(@mod(cart, @as(f32, @floatFromInt(W + 6))))) - 5;
    _ = text(cx, road, "◙▓▓▓◙", yellow);
    put(cx, road, '◙', black);
    put(cx + 4, road, '◙', black);

    const base = road - 1;
    const bx = 2;
    sprite(bx, base - 6, &roof, bred);
    rect(bx + 1, base - 3, 12, 4, ' ', white, red);
    sprite(bx + 4, base - 2, &door, bwhite);

    const sx = bx + 17;
    const sh: i32 = 9;
    sprite(sx, base - sh + 1, &.{" ▄██▄ "}, white);
    const filled: i32 = @intCast(@divTrunc(@as(u32, @intCast(sh - 1)) * s.disk + 50, 100));
    var j: i32 = 0;
    while (j < sh - 1) : (j += 1) {
        const row = base - j;
        put(sx, row, '▐', white);
        put(sx + 5, row, '▌', white);
        rect(sx + 1, row, 4, 1, if (j < filled) '█' else ' ', yellow, black);
    }

    const hx = sx + 12;
    const hy = base - 9;
    j = hy + 1;
    while (j < base) : (j += 1) put(hx, j, '║', white);
    _ = text(hx - 1, base, "▄█▄", white);
    rot += @min(2, @as(f32, if (rain) 0.4 else 0.1) + s.busy / 100 * 1.5);
    const d0: u32 = @as(u32, @intFromFloat(rot)) % 8;
    const dirs = [8][3]i32{ .{ 1, 0, '─' }, .{ 1, -1, '/' }, .{ 0, -1, '│' }, .{ -1, -1, '\\' }, .{ -1, 0, '─' }, .{ -1, 1, '/' }, .{ 0, 1, '│' }, .{ 1, 1, '\\' } };
    for (0..4) |b| {
        const d = dirs[(d0 + b * 2) % 8];
        const len: i32 = if (d[1] == 0) 4 else 2;
        var l: i32 = 1;
        while (l <= len) : (l += 1) put(hx + d[0] * l, hy + d[1] * l, @intCast(d[2]), bwhite);
    }
    put(hx, hy, 'o', bwhite);

    fields(hx + 7, hz + 1, W - 1, road, day, f);
    status(s, local);
}

fn fields(x0: i32, y0: i32, x1: i32, y1: i32, day: bool, f: u32) void {
    if (nw == 0) return;
    const gap = 2;
    const aw = x1 - x0;
    const ah = y1 - y0;
    const fit = std.math.clamp(@divTrunc(aw + gap, 28 + gap), 1, MAX_WORK) * @max(1, @divTrunc(ah, 7));
    const n: i32 = @min(@as(i32, @intCast(nw)), fit);
    const cols = std.math.clamp(@divTrunc(aw + gap, 28 + gap), 1, n);
    const rows = @divTrunc(n + cols - 1, cols);
    const pw = @min(36, @divTrunc(aw + gap, cols) - gap);
    const ph = std.math.clamp(@divTrunc(ah, rows) - 1, 4, 10);
    if (pw < 12) return;
    const top = @max(y0, y1 - rows * (ph + 1));
    for (works[0..@intCast(n)], 0..) |*w, i| {
        const k: i32 = @intCast(i);
        const px = x0 + @mod(k, cols) * (pw + gap);
        const py = top + @divTrunc(k, cols) * (ph + 1);
        if (py + ph > y1) break;
        plot(w, k, px, py, pw, ph, day, f);
    }
}

fn plot(w: *Work, k: i32, x: i32, y: i32, pw: i32, ph: i32, day: bool, f: u32) void {
    const inner_w = pw - 2;
    const inner_h = ph - 2;
    rect(x + 1, y + 1, inner_w, inner_h, ' ', brown, if (w.up) brown else if (day) green else black);
    var j: i32 = 1;
    while (j <= inner_h) : (j += 1) {
        var i: i32 = 1;
        while (i <= inner_w) : (i += 1) {
            if (!w.up) {
                if (hash(i, j, @intCast(k)) % 4 == 0) put(x + i, y + j, '~', brown);
                continue;
            }
            const stage = growth(w.rss) -| @as(usize, @intFromBool(hash(i, j, @intCast(k)) % 3 == 0));
            put(x + i, y + j, crops[stage], if (stage == 0) yellow else bgreen);
        }
    }
    var i: i32 = 1;
    while (i < pw - 1) : (i += 1) {
        put(x + i, y, '─', white);
        put(x + i, y + ph - 1, '─', white);
    }
    j = 1;
    while (j < ph - 1) : (j += 1) {
        put(x, y + j, '│', white);
        put(x + pw - 1, y + j, '│', white);
    }
    put(x, y, '┌', white);
    put(x + pw - 1, y, '┐', white);
    put(x, y + ph - 1, '└', white);
    put(x + pw - 1, y + ph - 1, '┘', white);

    var nb: [40]u8 = undefined;
    const full = label(w.path());
    const name = std.fmt.bufPrint(&nb, " {s} ", .{full[0..@min(full.len, @as(usize, @intCast(pw - 4)))]}) catch "";
    _ = text(x + 1, y, name, if (w.up) bwhite else gray);
    var lb: [40]u8 = undefined;
    var hb: [8]u8 = undefined;
    const info = if (w.up) std.fmt.bufPrint(&lb, " {s} {d:.0}% ", .{ human(&hb, w.rss), w.cpu }) catch "" else " off ";
    _ = text(x + 1, y + ph - 1, info[0..@min(info.len, @as(usize, @intCast(pw - 2)))], if (w.up) bwhite else gray);

    if (!w.up) {
        put(x + 2 + @as(i32, @intCast(hash(k, 0, 9) % @as(u32, @intCast(inner_w - 2)))), y + 1, 'v', black);
        return;
    }
    if (w.cpu < 1) {
        put(x + inner_w, y + inner_h, '☺', bwhite);
        return;
    }
    w.pos += @min(30, 2 + w.cpu / 10) / FPS;
    const workers: i32 = @min(inner_h, 1 + @as(i32, @intFromFloat(w.cpu / 100)));
    const lane = 2 * inner_w;
    var b: i32 = 0;
    while (b < workers) : (b += 1) {
        const p = @mod(@as(i32, @intFromFloat(w.pos)) + b * 5, lane);
        const wx = if (p < inner_w) p else lane - 1 - p;
        put(x + 1 + wx, y + 1 + @mod(b * 2 + @as(i32, @intCast(f / 64)), inner_h), '☻', bwhite);
    }
}

fn growth(rss: u64) usize {
    const steps = [_]u64{ 16 << 20, 64 << 20, 256 << 20, 1 << 30 };
    var g: usize = 0;
    for (steps) |t| g += @intFromBool(rss >= t);
    return g;
}

fn human(buf: []u8, bytes: u64) []const u8 {
    const units = "BKMGT";
    var v: f64 = @floatFromInt(bytes);
    var u: usize = 0;
    while (v >= 1024 and u < units.len - 1) : (u += 1) v /= 1024;
    return (if (v < 10 and u > 0)
        std.fmt.bufPrint(buf, "{d:.1}{c}", .{ v, units[u] })
    else
        std.fmt.bufPrint(buf, "{d:.0}{c}", .{ v, units[u] })) catch "?";
}

fn status(s: *const Sys, local: i64) void {
    const y = H - 1;
    rect(0, y, W, 1, ' ', white, black);
    const sod: u64 = @intCast(@mod(local, 86400));
    var nb: [8]u8 = undefined;
    var b: [256]u8 = undefined;
    const line = std.fmt.bufPrint(&b, " {s} │ {d:0>2}:{d:0>2} │ up {d}d {d}h │ {d}°C │ cpu {d:.0}% │ load {d:.2} │ ram {d}% │ disk {d}% │ net {s}/s", .{
        s.host,             sod / 3600,  sod / 60 % 60, s.up / 86400, s.up / 3600 % 24,
        s.temp,             s.busy,      s.load,        s.mem,         s.disk,       human(&nb, @intFromFloat(s.net)),
    }) catch return;
    var x = text(0, y, line, white);
    if (s.eth > 0) {
        x = text(x, y, " │ eth ", white);
        x = text(x, y, if (s.eth >= 1000) "1G+" else if (s.eth >= 100) "100M" else "up", bgreen);
    }
    if (s.wifi >= 0) {
        x = text(x, y, " │ wifi ", white);
        const bars: i32 = @divTrunc(s.wifi * 4 + 69, 70);
        const tone: u4 = if (bars >= 3) bgreen else if (bars == 2) yellow else bred;
        var i: i32 = 0;
        while (i < 4) : (i += 1) put(x + i, y, '■', if (i < bars) tone else gray);
        var db: [16]u8 = undefined;
        _ = text(x + 5, y, std.fmt.bufPrint(&db, "{d}dBm", .{s.dbm}) catch "", white);
    }
}

test "tzif offset picks the last transition before now" {
    var t: [44 + 2 * 4 + 2 + 2 * 6]u8 = @splat(0);
    @memcpy(t[0..4], "TZif");
    std.mem.writeInt(u32, t[32..36], 2, .big);
    std.mem.writeInt(u32, t[36..40], 2, .big);
    std.mem.writeInt(i32, t[44..48], 1000, .big);
    std.mem.writeInt(i32, t[48..52], 2000, .big);
    t[52] = 1;
    t[53] = 0;
    std.mem.writeInt(i32, t[54..58], -21600, .big);
    std.mem.writeInt(i32, t[60..64], -18000, .big);
    try std.testing.expectEqual(@as(i32, -21600), tzifOffset(&t, 500));
    try std.testing.expectEqual(@as(i32, -18000), tzifOffset(&t, 1500));
    try std.testing.expectEqual(@as(i32, -21600), tzifOffset(&t, 2500));
    try std.testing.expectEqual(@as(i32, 0), tzifOffset("nope", 0));
}

test "tailnet peers parse from local api status" {
    parsePeers(
        \\{"Self": {"DNSName": "chimera.ts.net.", "Online": true},
        \\ "Peer": {
        \\  "nodekey:a": {"DNSName": "nyx.tail.ts.net.", "OS": "linux", "Online": true, "Active": true},
        \\  "nodekey:b": {"DNSName": "ori0n.tail.ts.net.", "Online": false},
        \\  "nodekey:c": {"DNSName": "faraday.tail.ts.net.", "Online": true, "Active": false}
        \\ }}
    );
    try std.testing.expectEqual(@as(usize, 3), np);
    try std.testing.expectEqualStrings("faraday", peers[0].name[0..peers[0].len]);
    try std.testing.expect(peers[1].online and peers[1].active and !peers[2].online);
    try std.testing.expectEqualStrings("ori0n", peers[2].name[0..peers[2].len]);
}

test "rain falls in some slots but not most" {
    var wet: u32 = 0;
    for (0..1000) |i| wet += @intFromBool(raining(@as(i64, @intCast(i)) * 1200));
    try std.testing.expect(wet > 50 and wet < 250);
}

test "parsers and labels" {
    try std.testing.expectEqual(@as(?u64, 4321), field("usage_usec 4321\nuser_usec 1\n", "usage_usec"));
    try std.testing.expectEqual(@as(?u64, 16000000), field("MemTotal:       16000000 kB\n", "MemTotal:"));
    try std.testing.expectEqualStrings("skinner", label("skinner.service"));
    try std.testing.expectEqualStrings("user-1000", label("user.slice/user-1000.slice"));
    try std.testing.expect(inNight(.{ 23, 6 }, 2) and !inNight(.{ 23, 6 }, 12) and inNight(.{ 1, 7 }, 1) and !inNight(.{ 0, 0 }, 3));
    var b: [8]u8 = undefined;
    try std.testing.expectEqualStrings("312M", human(&b, 312 << 20));
    try std.testing.expectEqualStrings("1.5G", human(&b, 3 << 29));
    try std.testing.expectEqual(@as(usize, 3), growth(300 << 20));
}

test "scene draws at small, typical and max sizes without escaping the grid" {
    for ([_][]const u8{ "skinner.service", "system.slice/a-very-long-workload-name-that-overflows.service", "user.slice/user-1000.slice" }, 0..) |p, i| {
        works[i] = Work.init(p).?;
        works[i].up = i != 1;
        works[i].rss = @as(u64, 300 << 20) >> @intCast(i * 4);
        works[i].cpu = 250 / @as(f32, @floatFromInt(i + 1));
    }
    for (3..MAX_WORK) |i| works[i] = Work.init("x.service").?;
    for (&peers, 0..) |*p, i| p.* = .{ .name = @splat('n'), .len = 16, .online = i % 2 == 0, .active = i % 3 == 0 };
    np = peers.len;
    const sys: Sys = .{ .mem = 99, .disk = 100, .load = 9, .busy = 100, .temp = 80, .net = 1e9, .up = 99999, .wifi = 70, .dbm = -40, .eth = 1000 };
    for ([_][2]i32{ .{ 10, 5 }, .{ 40, 14 }, .{ 80, 24 }, .{ 240, 75 }, .{ MAXW, MAXH } }) |size| {
        resize(size);
        for ([_]i64{ 0, 7 * 3600, 13 * 3600, 23 * 3600 }) |t| {
            nw = MAX_WORK;
            draw(&sys, 999, t);
            nw = 0;
            draw(&sys, 0, t + 1200 * 7);
        }
    }
}
