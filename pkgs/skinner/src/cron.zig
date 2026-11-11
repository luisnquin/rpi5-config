const std = @import("std");

pub const Schedule = struct {
    minute: u64,
    hour: u64,
    dom: u64,
    month: u64,
    dow: u64,
    dom_any: bool,
    dow_any: bool,

    pub fn parse(spec: []const u8) !Schedule {
        var it = std.mem.tokenizeAny(u8, spec, " \t");
        const f = [5][]const u8{
            it.next() orelse return error.InvalidCron,
            it.next() orelse return error.InvalidCron,
            it.next() orelse return error.InvalidCron,
            it.next() orelse return error.InvalidCron,
            it.next() orelse return error.InvalidCron,
        };
        if (it.next() != null) return error.InvalidCron;
        var dow = try field(f[4], 0, 7);
        if (dow & (1 << 7) != 0) dow |= 1;
        return .{
            .minute = try field(f[0], 0, 59),
            .hour = try field(f[1], 0, 23),
            .dom = try field(f[2], 1, 31),
            .month = try field(f[3], 1, 12),
            .dow = dow,
            .dom_any = f[2][0] == '*',
            .dow_any = f[4][0] == '*',
        };
    }

    pub fn matches(s: Schedule, epoch: i64) bool {
        const t = Tm.of(epoch);
        if (!bit(s.minute, t.minute) or !bit(s.hour, t.hour) or !bit(s.month, t.month)) return false;
        const d = bit(s.dom, t.dom);
        const w = bit(s.dow, t.dow);
        if (s.dom_any or s.dow_any) return d and w;
        return d or w;
    }
};

fn bit(set: u64, n: u6) bool {
    return set & (@as(u64, 1) << n) != 0;
}

fn field(text: []const u8, lo: u6, hi: u6) !u64 {
    var set: u64 = 0;
    var parts = std.mem.splitScalar(u8, text, ',');
    while (parts.next()) |part| {
        var range = part;
        var step: u6 = 1;
        if (std.mem.indexOfScalar(u8, part, '/')) |i| {
            range = part[0..i];
            step = std.fmt.parseInt(u6, part[i + 1 ..], 10) catch return error.InvalidCron;
            if (step == 0) return error.InvalidCron;
        }
        var a = lo;
        var b = hi;
        if (!std.mem.eql(u8, range, "*")) {
            if (std.mem.indexOfScalar(u8, range, '-')) |i| {
                a = std.fmt.parseInt(u6, range[0..i], 10) catch return error.InvalidCron;
                b = std.fmt.parseInt(u6, range[i + 1 ..], 10) catch return error.InvalidCron;
            } else {
                a = std.fmt.parseInt(u6, range, 10) catch return error.InvalidCron;
                b = if (step > 1) hi else a;
            }
        }
        if (a < lo or b > hi or a > b) return error.InvalidCron;
        var n = a;
        while (n <= b) : (n += step) {
            set |= @as(u64, 1) << n;
            if (@as(u7, n) + step > b) break;
        }
    }
    return set;
}

const CTm = extern struct { sec: c_int, min: c_int, hour: c_int, mday: c_int, mon: c_int, year: c_int, wday: c_int, yday: c_int, isdst: c_int, gmtoff: c_long, zone: ?[*:0]const u8 };
extern "c" fn localtime_r(t: *const i64, out: *CTm) ?*CTm;

/// Shifts a UTC epoch into the host's local wall clock, so schedules read like system cron.
pub fn local(epoch: i64) i64 {
    var t: CTm = undefined;
    return epoch + if (localtime_r(&epoch, &t)) |r| r.gmtoff else 0;
}

pub const Tm = struct {
    year: u16,
    month: u6,
    dom: u6,
    hour: u6,
    minute: u6,
    second: u6,
    dow: u6,

    pub fn of(epoch: i64) Tm {
        const es = std.time.epoch.EpochSeconds{ .secs = @intCast(epoch) };
        const day = es.getEpochDay();
        const yd = day.calculateYearDay();
        const md = yd.calculateMonthDay();
        const ds = es.getDaySeconds();
        return .{
            .year = yd.year,
            .month = @intCast(md.month.numeric()),
            .dom = @intCast(md.day_index + 1),
            .hour = ds.getHoursIntoDay(),
            .minute = ds.getMinutesIntoHour(),
            .second = ds.getSecondsIntoMinute(),
            .dow = @intCast((day.day + 4) % 7),
        };
    }
};

test "fields" {
    try std.testing.expectEqual(@as(u64, 1 << 6), try field("6", 0, 23));
    try std.testing.expectEqual(@as(u64, (1 << 0) | (1 << 15) | (1 << 30) | (1 << 45)), try field("*/15", 0, 59));
    try std.testing.expectEqual(@as(u64, (1 << 1) | (1 << 3) | (1 << 5)), try field("1-5/2", 0, 7));
    try std.testing.expectEqual(@as(u64, (1 << 2) | (1 << 9)), try field("2,9", 0, 23));
    try std.testing.expectError(error.InvalidCron, field("60", 0, 59));
    try std.testing.expectError(error.InvalidCron, field("5-2", 0, 59));
    try std.testing.expectError(error.InvalidCron, Schedule.parse("* * *"));
}

test "matches" {
    const daily = try Schedule.parse("0 6 * * *");
    try std.testing.expect(daily.matches(1762754400));
    try std.testing.expect(!daily.matches(1762754460));
    const sunday = try Schedule.parse("30 2 * * 7");
    try std.testing.expect(sunday.matches(1762655400));
    const either = try Schedule.parse("0 0 1 * 1");
    try std.testing.expect(either.matches(1762732800));
    try std.testing.expect(either.matches(1761955200));
    try std.testing.expect(!either.matches(1762300800));
}

test "local" {
    const c = struct {
        extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
        extern "c" fn tzset() void;
    };
    _ = c.setenv("TZ", "CST6", 1);
    c.tzset();
    try std.testing.expectEqual(@as(i64, 1762754400 - 6 * 3600), local(1762754400));
}

test "tm" {
    const t = Tm.of(1762754400);
    try std.testing.expectEqual(@as(u16, 2025), t.year);
    try std.testing.expectEqual(@as(u6, 11), t.month);
    try std.testing.expectEqual(@as(u6, 10), t.dom);
    try std.testing.expectEqual(@as(u6, 6), t.hour);
    try std.testing.expectEqual(@as(u6, 1), t.dow);
}
