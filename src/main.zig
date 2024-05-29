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
const asteroid_init_count = 20;

const AsteroidPoints = std.BoundedArray(Vec2, 16);

const alien_score_threshold = 20;

var ship: Ship = undefined;
var state: State = undefined;
var score_str: [20]u8 = std.mem.zeroes([20]u8);

var snd_laser: rl.Sound = undefined;
var snd_thrust: rl.Sound = undefined;
var snd_music: rl.Music = undefined;

fn moveTowards(target: f32, val: f32, delta: f32) f32 {
    if (std.math.sign(val) == -1) {
        const new = val + delta;
        return if (new > target) target else new;
    } else {
        const new = val - delta;
        return if (new < target) target else new;
    }
}

const Dir = enum { Left, Right };

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
    death_time: f32 = 0,
    bullets: std.ArrayList(Bullet),
    enemy_bullets: std.ArrayList(Bullet),
    asteroids: std.ArrayList(Asteroid),
    alien: Alien,
    random: std.Random.Xoshiro256,

    fn init(allocator: std.mem.Allocator) !State {
        const bullets = std.ArrayList(Bullet).init(allocator);
        const enemy_bullets = std.ArrayList(Bullet).init(allocator);
        const asteroids = std.ArrayList(Asteroid).init(allocator);
        const prng = std.rand.DefaultPrng.init(2045);

        return .{
            .alien = Alien{
                .pos = .{ .x = 0, .y = 0 },
                .dead = true,
                .rng = std.rand.DefaultPrng.init(512),
            },
            .bullets = bullets,
            .enemy_bullets = enemy_bullets,
            .asteroids = asteroids,
            .random = prng,
        };
    }

    fn deinit(self: *State) void {
        self.bullets.deinit();
        self.enemy_bullets.deinit();
        self.asteroids.deinit();
    }

    fn reset(self: *State) !void {
        self.score = 0;
        @memset(&score_str, 0);
        self.death_time = 0;
        self.bullets.clearRetainingCapacity();
        self.enemy_bullets.clearRetainingCapacity();
        self.asteroids.clearRetainingCapacity();
        self.alien.dead = true;
        ship.pos = .{ .x = win_w / 2, .y = win_h / 2 };
        ship.vel = rl.Vector2Zero();
        ship.rot = 0.0;
    }

    fn spawnAsteroids(self: *State, n: u32, scale: AsteroidScale) !void {
        self.random.jump();
        const rng = &state.random;

        for (0..n) |_| {
            const padding: u32 = 50;
            const max_x = (win_w / 2) - padding;
            const max_y = (win_h / 2) - padding;
            const sign1: i32 = std.math.pow(i32, -1, rng.random().intRangeAtMost(i32, 1, 2));
            const sign2: i32 = std.math.pow(i32, -1, rng.random().intRangeAtMost(i32, 1, 2));
            const x: f32 = @floatFromInt(rng.random().intRangeAtMost(i32, 0, max_x) * sign1);
            const y: f32 = @floatFromInt(rng.random().intRangeAtMost(i32, 0, max_y) * sign2);
            const pos = .{ .x = x, .y = y };
            const angle = std.math.tau * rng.random().float(f32);
            const a = .{
                .pos = pos,
                .vel = .{ .x = @cos(angle), .y = @sin(angle) },
                .scale = scale,
                .seed = rng.random().int(u32),
            };

            try self.asteroids.append(a);
        }
    }

    fn spawnAlien(self: *State) !void {
        try self.alien.spawn(.{
            .x = self.random.random().float(f32),
            .y = self.random.random().float(f32),
        });
    }

    fn updateBullet(index: usize, arr: *std.ArrayList(Bullet)) void {
        var bullet = &arr.items[index];
        bullet.pos = rl.Vector2Add(bullet.pos, bullet.vel);
        bullet.ttl -= 1;
        if (bullet.ttl <= 0)
            _ = arr.orderedRemove(index);
    }

    fn update(self: *State) !void {
        for (state.asteroids.items) |*a| {
            var pos = rl.Vector2Add(a.*.pos, a.*.vel);
            pos.x = @mod(pos.x, win_w);
            pos.y = @mod(pos.y, win_h);
            a.pos = pos;
        }

        var i: usize = 0;
        while (i < state.bullets.items.len) : (i += 1) {
            State.updateBullet(i, &self.bullets);
        }

        var j: usize = 0;
        while (j < state.enemy_bullets.items.len) : (j += 1) {
            State.updateBullet(j, &self.enemy_bullets);
        }
    }

    fn checkCollision(self: *State) !void {
        var i: usize = 1;
        const len = self.asteroids.items.len;
        while (i <= len) : (i += 1) {
            const j = len - i;
            const a = self.asteroids.items[j];
            const a_scale: f32 = @floatFromInt(@intFromEnum(a.scale));

            if (rl.CheckCollisionCircles(a.pos, a_scale, ship.pos, ship_scale)) {
                ship.dead = true;
                break;
            }

            for (self.bullets.items) |*b| {
                if (rl.CheckCollisionCircles(a.pos, a_scale, b.pos, 5)) {
                    b.ttl = 0;
                    self.score += 1;

                    if (a.scale == .large) try a.split();
                    _ = self.asteroids.orderedRemove(j);
                }
            }
        }

        for (self.bullets.items) |*b| {
            const a = &self.alien;
            if (rl.CheckCollisionCircles(b.pos, 5, a.pos, ship_scale)) {
                a.dead = true;
                self.score += 5;
            }
        }

        for (self.enemy_bullets.items) |*b| {
            if (rl.CheckCollisionCircles(b.pos, 5, ship.pos, ship_scale)) {
                ship.dead = true;
                break;
            }
        }
    }
};

const Ship = struct {
    thrust: bool = false,
    dead: bool = false,
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

    fn forward(self: *Ship) void {
        if (self.dead) return;
        self.vel = .{
            .x = ship.speed * @cos(ship.rot - pi_half),
            .y = ship.speed * @sin(ship.rot - pi_half),
        };
        self.thrust = true;
        if (!rl.IsSoundPlaying(snd_thrust)) {
            rl.PlaySound(snd_thrust);
        }
    }

    fn stop(self: *Ship) void {
        if (self.dead) return;
        self.thrust = false;
    }

    fn rotate(self: *Ship, dir: Dir, dt: f32) void {
        if (self.dead) return;
        switch (dir) {
            .Left => self.rot -= self.rot_speed * dt,
            .Right => self.rot += self.rot_speed * dt,
        }
    }

    fn shoot(self: *Ship) !void {
        if (self.dead) return;
        try state.bullets.append(.{
            .ttl = 100,
            .pos = self.pos,
            .vel = .{
                .x = 10 * @cos(self.rot - pi_half),
                .y = 10 * @sin(self.rot - pi_half),
            },
        });
        rl.PlaySound(snd_laser);
    }

    fn update(self: *Ship, dt: f32) void {
        if (self.dead) return;
        if (!self.thrust) {
            self.vel.x = moveTowards(0, ship.vel.x, 0.3 * dt);
            self.vel.y = moveTowards(0, ship.vel.y, 0.3 * dt);
        }
        self.pos = rl.Vector2Add(ship.pos, rl.Vector2Scale(ship.vel, dt));
        self.pos.x = @mod(ship.pos.x, win_w);
        self.pos.y = @mod(ship.pos.y, win_h);

        self.transform = rl.MatrixMultiply(
            rl.MatrixRotate(.{ .x = 0, .y = 0, .z = 1 }, self.rot),
            rl.MatrixMultiply(
                rl.MatrixScale(ship_scale, ship_scale, ship_scale),
                rl.MatrixTranslate(self.pos.x, self.pos.y, 0),
            ),
        );
    }

    fn draw(self: *Ship, _: f32) void {
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

    fn draw(self: Asteroid) !void {
        state.random.seed(self.seed);
        var random = state.random.random();
        var pts = try AsteroidPoints.init(0);

        const min_radius: u32 = @intFromEnum(self.scale) * 1;
        const max_radius: u32 = @intFromEnum(self.scale) * 2;

        const sides: f32 = 9;
        const step_size: f32 = std.math.tau / sides;
        var i: u32 = 0;
        while (i < sides) : (i += 1) {
            const radius: f32 = @floatFromInt(random.intRangeAtMost(u32, min_radius, max_radius));
            const k: f32 = @floatFromInt(i);
            const angle = k * step_size;

            try pts.append(Vec2{
                .x = self.pos.x + radius * @cos(angle),
                .y = self.pos.y + radius * @sin(angle),
            });
        }
        try pts.append(pts.slice()[0]);
        rl.DrawLineStrip(@ptrCast(&pts), sides + 1, rl.WHITE);
    }

    fn split(asteroid: Asteroid) !void {
        var vel = rl.Vector2Scale(asteroid.vel, 2);
        for (0..2) |_| {
            const a = .{
                .pos = asteroid.pos,
                .vel = vel,
                .scale = .small,
                .seed = state.random.random().int(u32),
            };
            try state.asteroids.append(a);
            vel = rl.Vector2Rotate(vel, std.math.pi / 4.0);
        }
    }
};

const Alien = struct {
    pos: Vec2,
    vel: Vec2 = .{ .x = 0, .y = 0 },
    cooldown: f32 = 0.0,
    rng: std.Random.Xoshiro256,
    seed: u64 = 64,
    dead: bool = false,

    pts: [15]Vec2 = .{
        .{ .x = 1.0, .y = 0.0 },
        .{ .x = 0.8, .y = 0.3 },
        .{ .x = 0.4, .y = 0.3 },
        .{ .x = 0.3, .y = 0.7 },
        .{ .x = -0.3, .y = 0.7 },
        .{ .x = -0.4, .y = 0.3 },
        .{ .x = -0.8, .y = 0.3 },
        .{ .x = -1.0, .y = 0.0 },
        .{ .x = -0.8, .y = -0.3 },
        .{ .x = -0.4, .y = -0.3 },
        .{ .x = -0.3, .y = -0.7 },
        .{ .x = 0.3, .y = -0.7 },
        .{ .x = 0.4, .y = -0.3 },
        .{ .x = 0.8, .y = -0.3 },
        .{ .x = 1.0, .y = 0.0 },
    },

    fn draw(self: Alien) !void {
        const t = rl.MatrixMultiply(
            rl.MatrixScale(ship_scale, ship_scale, ship_scale),
            rl.MatrixTranslate(self.pos.x, self.pos.y, 0),
        );

        var pts: [15]Vec2 = undefined;
        for (self.pts, 0..) |p, i| {
            pts[i] = rl.Vector2Transform(p, t);
        }

        rl.DrawLineStrip(&pts, 15, rl.WHITE);
    }

    fn update(self: *Alien, dt: f32) !void {
        self.pos.x = @mod(self.pos.x + self.vel.x, win_w);
        self.pos.y = @mod(self.pos.y + self.vel.y, win_h);

        if (self.cooldown == 0) {
            const dir = rl.Vector2Scale(rl.Vector2Normalize(rl.Vector2Subtract(ship.pos, self.pos)), 4);
            try state.enemy_bullets.append(.{
                .ttl = 100,
                .pos = self.pos,
                .vel = dir,
            });
            const angle = std.math.tau * self.rng.random().float(f32);
            self.vel.x = @cos(angle);
            self.vel.y = @sin(angle);
            self.cooldown = 2;
        }
        self.cooldown = moveTowards(0, self.cooldown, dt);
    }

    fn spawn(self: *Alien, pos: Vec2) !void {
        self.pos = pos;
        self.dead = false;
    }
};

fn update(dt: f32) !void {
    if (ship.dead) {
        state.death_time += 0.5;
        if (state.death_time >= 50) {
            ship.dead = false;
            state.death_time = 0;
            try state.reset();
            try state.spawnAsteroids(asteroid_init_count, .large);
        }
        return;
    }

    ship.update(dt);
    try state.update();

    if (state.score > alien_score_threshold and state.alien.dead) try state.spawnAlien();
    if (!state.alien.dead) try state.alien.update(dt);

    try state.checkCollision();
}

fn handleInput(dt: f32) !void {
    if (rl.IsKeyDown(rl.KEY_W)) ship.forward() else ship.stop();
    if (rl.IsKeyDown(rl.KEY_A)) ship.rotate(.Left, dt);
    if (rl.IsKeyDown(rl.KEY_D)) ship.rotate(.Right, dt);
    if (rl.IsKeyPressed(rl.KEY_SPACE)) try ship.shoot();
}

// TODO: This isn't great.
fn drawDeath(_: f32) void {
    const vr: Vec2 = .{ .x = @cos(-1 * std.math.pi / 4.0), .y = @sin(-1 * std.math.pi / 4.0) };
    const vl: Vec2 = .{ .x = @cos(-3 * std.math.pi / 4.0), .y = @sin(-3 * std.math.pi / 4.0) };
    const vb: Vec2 = .{ .x = @cos(std.math.pi / 2.0), .y = @sin(std.math.pi / 2.0) };

    const transform = struct {
        fn apply(vec: Vec2, vel: Vec2, d: f32) Vec2 {
            const t = rl.MatrixMultiply(
                rl.MatrixRotate(.{ .x = 0, .y = 0, .z = 1 }, ship.rot + d * 0.1),
                rl.MatrixMultiply(
                    rl.MatrixScale(ship_scale, ship_scale, ship_scale),
                    rl.MatrixTranslate(ship.pos.x + vel.x * d, ship.pos.y + vel.y * d, 0),
                ),
            );
            return rl.Vector2Transform(vec, t);
        }
    };

    rl.DrawLineV(
        transform.apply(ship.points[0], vr, state.death_time),
        transform.apply(ship.points[2], vr, state.death_time),
        rl.WHITE,
    );

    rl.DrawLineV(
        transform.apply(ship.points[0], vl, state.death_time),
        transform.apply(ship.points[1], vl, state.death_time),
        rl.WHITE,
    );

    rl.DrawLineV(
        transform.apply(ship.points[1], vb, state.death_time),
        transform.apply(ship.points[2], vb, state.death_time),
        rl.WHITE,
    );
}

fn draw(dt: f32) !void {
    const len = std.fmt.formatIntBuf(&score_str, state.score, 10, .lower, .{});
    rl.DrawText(@ptrCast(score_str[0..len]), 4, 4, 22, rl.WHITE);
    rl.DrawFPS(win_w - 30, 2);

    for (state.bullets.items) |b| {
        rl.DrawCircleV(b.pos, 2, rl.WHITE);
    }

    for (state.enemy_bullets.items) |b| {
        rl.DrawCircleV(b.pos, 2, rl.WHITE);
    }

    for (state.asteroids.items) |*a| try a.draw();

    if (!state.alien.dead) try state.alien.draw();

    if (ship.dead) drawDeath(dt) else ship.draw(dt);
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

    ship = Ship{};
    state = try State.init(allocator);
    defer state.deinit();
    try state.spawnAsteroids(asteroid_init_count, .large);

    rl.InitWindow(win_w, win_h, "Asteroids");
    defer rl.CloseWindow();
    rl.SetWindowState(rl.FLAG_WINDOW_RESIZABLE);

    rl.SetTargetFPS(60);

    rl.PlayMusicStream(snd_music);

    while (!rl.WindowShouldClose()) {
        const dt = rl.GetFrameTime();
        rl.UpdateMusicStream(snd_music);

        try handleInput(dt);
        try update(dt);

        rl.BeginDrawing();
        rl.ClearBackground(rl.BLACK);
        try draw(dt);
        rl.EndDrawing();
    }
}
