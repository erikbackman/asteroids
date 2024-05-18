const std = @import("std");
const rl = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
    @cInclude("rlgl.h");
});

const Vec2 = rl.Vector2;
const Vec3 = rl.Vector3;
const Mat = rl.Matrix;

const win_w = 800;
const win_h = 600;

const pi_half: f32 = std.math.pi / 2.0;
const zero = Vec2{ .x = 0, .y = 0 };
const ship_scale = 20;
const AsteroidPoints = std.BoundedArray(Vec2, 16);

var ship: Ship = undefined;
var state: State = undefined;
var score_str: [20]u8 = std.mem.zeroes([20]u8);

var snd_laser: rl.Sound = undefined;
var snd_thrust: rl.Sound = undefined;
var snd_music: rl.Music = undefined;

pub fn moveTowards(target: f32, val: f32, delta: f32) f32 {
    if (std.math.sign(val) == -1) {
        const new = val + delta;
        return if (new > target) target else new;
    } else {
        const new = val - delta;
        return if (new < target) target else new;
    }
}

const Bullet = struct {
    ttl: i32,
    pos: Vec2,
    vel: Vec2,
};

const AsteroidScale = enum(u32) {
    small = 10,
    large = 30,
};

const State = struct {
    score: u32 = 0,
    bullets: std.ArrayList(Bullet),
    asteroids: std.ArrayList(Asteroid),
    random: std.Random.Xoshiro256,
};

fn makeVec3(vec: Vec2) Vec3 {
    return .{ .x = vec.x, .y = vec.y, .z = 0 };
}

const Ship = struct {
    thrust: bool = false,
    speed: f32 = 100,
    rot: f32 = 0.0,
    rot_speed: f32 = 5,
    pos: Vec2 = .{ .x = win_w / 2, .y = win_h / 2 },
    vel: Vec2 = .{ .x = 0, .y = 0 },
    transform: Mat = rl.MatrixIdentity(),

    points: [6]Vec2 = .{
        .{ .x = 0.0, .y = -0.5 },
        .{ .x = -0.5, .y = 0.5 },
        .{ .x = 0.5, .y = 0.5 },
        .{ .x = 0.0, .y = 1.0 },
        .{ .x = 0.4, .y = 0.5 },
        .{ .x = -0.4, .y = 0.5 },
    },
    p: Vec2 = .{ .x = win_w / 2, .y = win_h / 2 },
    u: Vec2 = .{ .x = win_w / 2, .y = win_h / 2 },

    pub fn draw(self: *Ship, _: f32) void {
        self.transform = rl.MatrixMultiply(
            rl.MatrixRotate(.{ .x = 0, .y = 0, .z = 1 }, self.rot),
            rl.MatrixMultiply(
                rl.MatrixScale(ship_scale, ship_scale, ship_scale),
                rl.MatrixTranslate(ship.pos.x, ship.pos.y, 0),
            ),
        );

        rl.DrawTriangleLines(
            rl.Vector2Transform(self.points[0], self.transform),
            rl.Vector2Transform(self.points[1], self.transform),
            rl.Vector2Transform(self.points[2], self.transform),
            rl.WHITE,
        );

        if (self.thrust) {
            rl.DrawTriangleLines(
                rl.Vector2Transform(self.points[3], self.transform),
                rl.Vector2Transform(self.points[4], self.transform),
                rl.Vector2Transform(self.points[5], self.transform),
                rl.WHITE,
            );
        }
    }
};

const Asteroid = struct {
    pos: Vec2,
    vel: Vec2,
    scale: AsteroidScale,
    seed: u32,

    pub fn draw(self: Asteroid) !void {
        state.random.seed(self.seed);
        var random = state.random.random();
        var pts = try AsteroidPoints.init(0);

        const min_radius: u32 = @intFromEnum(self.scale) * 1;
        const max_radius: u32 = @intFromEnum(self.scale) * 2;

        const n: f32 = 9;
        const step_size: f32 = std.math.pi * 2 / n;
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            const radius: f32 = @floatFromInt(random.intRangeAtMost(u32, min_radius, max_radius));
            const k: f32 = @floatFromInt(i);
            const angle = k * step_size;
            const point = rl.Vector2Add(self.pos, Vec2{ .x = radius * @cos(angle), .y = radius * @sin(angle) });
            try pts.append(point);
        }
        try pts.append(pts.slice()[0]);
        rl.DrawLineStrip(@ptrCast(&pts), n + 1, rl.WHITE);
    }

    pub fn split(asteroid: Asteroid) !void {
        state.random.jump();
        var random = state.random.random();
        var vel = rl.Vector2Scale(asteroid.vel, 2);
        for (0..2) |_| {
            const a = .{
                .pos = asteroid.pos,
                .vel = vel,
                .scale = .small,
                .seed = random.int(u32),
            };
            try state.asteroids.append(a);
            vel = rl.Vector2Rotate(vel, std.math.pi / 4.0);
        }
    }
};

pub fn spawnAsteroids(n: u32, scale: AsteroidScale) !void {
    state.random.jump();
    var random = state.random.random();

    for (0..n) |_| {
        const pos = .{ .x = random.float(f32) * win_w, .y = random.float(f32) * win_h };
        const angle = std.math.tau * random.float(f32);
        const a = .{
            .pos = pos,
            .vel = .{ .x = @cos(angle), .y = @sin(angle) },
            .scale = scale,
            .seed = random.int(u32),
        };

        try state.asteroids.append(a);
    }
}

pub fn updateShip(dt: f32) void {
    if (rl.IsKeyDown(rl.KEY_W)) {
        ship.vel = .{
            .x = ship.speed * @cos(ship.rot - pi_half) * dt,
            .y = ship.speed * @sin(ship.rot - pi_half) * dt,
        };
        if (!rl.IsSoundPlaying(snd_thrust)) {
            rl.PlaySound(snd_thrust);
        }
        ship.thrust = true;
    } else {
        ship.thrust = false;
        ship.vel.x = moveTowards(0, ship.vel.x, 0.3 * dt);
        ship.vel.y = moveTowards(0, ship.vel.y, 0.3 * dt);
    }

    if (rl.IsKeyDown(rl.KEY_A)) ship.rot -= dt * ship.rot_speed;
    if (rl.IsKeyDown(rl.KEY_D)) ship.rot += dt * ship.rot_speed;

    ship.pos = rl.Vector2Add(ship.pos, ship.vel);
    ship.pos.x = @mod(ship.pos.x, win_w);
    ship.pos.y = @mod(ship.pos.y, win_h);
}

pub fn updateBullets() void {
    if (rl.IsKeyPressed(rl.KEY_SPACE)) {
        state.bullets.append(.{
            .ttl = 100,
            .pos = ship.pos,
            .vel = .{
                .x = 10 * @cos(ship.rot - pi_half),
                .y = 10 * @sin(ship.rot - pi_half),
            },
        }) catch {};
        rl.PlaySound(snd_laser);
    }
    var i: usize = 0;
    while (i < state.bullets.items.len) : (i += 1) {
        var b = &state.bullets.items[i];
        b.pos = rl.Vector2Add(b.pos, b.vel);
        b.ttl -= 1;
        if (b.ttl <= 0) {
            _ = state.bullets.orderedRemove(i);
        }
    }
}

pub fn updateAsteroids() void {
    for (state.asteroids.items) |*a| {
        var pos = rl.Vector2Add(a.*.pos, a.*.vel);
        pos.x = @mod(pos.x, win_w);
        pos.y = @mod(pos.y, win_h);
        a.pos = pos;
    }
}

pub fn checkCollision() void {
    var i: usize = 1;
    const len = state.asteroids.items.len;
    while (i <= len) : (i += 1) {
        const j = len - i;
        const a = state.asteroids.items[j];
        for (state.bullets.items) |*b| {
            // TODO: Don't hardcode radius
            const collides = rl.CheckCollisionCircles(a.pos, 30, b.pos, 5);
            if (collides) {
                b.ttl = 0;
                state.score += 1;
                if (a.scale == .large) {
                    a.split() catch unreachable;
                }
                _ = state.asteroids.orderedRemove(j);
            }
        }
    }
}

pub fn update(dt: f32) void {
    updateShip(dt);
    updateBullets();
    updateAsteroids();
    checkCollision();
}

pub fn draw(dt: f32) !void {
    const len = std.fmt.formatIntBuf(&score_str, state.score, 10, .lower, .{});
    rl.DrawText(@ptrCast(score_str[0..len]), 4, 4, 22, rl.WHITE);
    rl.DrawFPS(win_w - 30, 2);

    for (state.bullets.items) |b| {
        //rl.DrawPixelV(b.pos, rl.WHITE);
        rl.DrawCircleV(b.pos, 2, rl.WHITE);
    }

    for (state.asteroids.items) |*a| {
        try a.draw();
    }

    ship.draw(dt);
}

pub fn main() !void {
    rl.InitAudioDevice();
    defer rl.CloseAudioDevice();

    snd_laser = rl.LoadSound("assets/laser.wav");
    defer rl.UnloadSound(snd_laser);

    snd_thrust = rl.LoadSound("assets/thrust.wav");
    defer rl.UnloadSound(snd_thrust);

    snd_music = rl.LoadMusicStream("assets/music.mp3");
    defer rl.UnloadMusicStream(snd_music);

    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    var bullets = std.ArrayList(Bullet).init(allocator);
    defer bullets.deinit();

    var asteroids = std.ArrayList(Asteroid).init(allocator);
    defer asteroids.deinit();

    ship = Ship{};
    const prng = std.rand.DefaultPrng.init(64);
    state = State{ .bullets = bullets, .asteroids = asteroids, .random = prng };
    try spawnAsteroids(30, .large);

    rl.InitWindow(win_w, win_h, "Asteroids");
    defer rl.CloseWindow();
    rl.SetWindowState(rl.FLAG_WINDOW_RESIZABLE);

    rl.SetTargetFPS(60);

    rl.PlayMusicStream(snd_music);

    while (!rl.WindowShouldClose()) {
        const dt = rl.GetFrameTime();
        rl.UpdateMusicStream(snd_music);
        rl.BeginDrawing();
        rl.ClearBackground(rl.BLACK);
        update(dt);
        try draw(dt);
        rl.EndDrawing();
    }
}
