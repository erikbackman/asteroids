const std = @import("std");
const rl = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
    @cInclude("rlgl.h");
});

const Vec2 = rl.Vector2;
const Vec3 = rl.Vector3;
const Mat = rl.Matrix;

const winWidth = 800;
const winHeight = 600;
const pi_half: f32 = std.math.pi / 2.0;
const zero = Vec2{ .x = 0, .y = 0 };
const ship_scale = 20;

var ship: Ship = undefined;
var state: State = undefined;

const Bullet = struct {
    ttl: u32,
    pos: Vec2,
    vel: Vec2,
};

const State = struct {
    score: u32 = 0,
    bullets: std.ArrayList(Bullet) = undefined,
};

const Ship = struct {
    thrust: bool = false,
    speed: f32 = 100,
    rot: f32 = 0.0,
    rot_speed: f32 = 5,
    pos: Vec2 = .{ .x = winWidth / 2, .y = winHeight / 2 },
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

    pub fn draw(self: Ship) void {
        rl.DrawTriangle(
            rl.Vector2Transform(self.points[0], self.transform),
            rl.Vector2Transform(self.points[1], self.transform),
            rl.Vector2Transform(self.points[2], self.transform),
            rl.WHITE,
        );

        if (self.thrust) {
            rl.DrawTriangle(
                rl.Vector2Transform(self.points[3], self.transform),
                rl.Vector2Transform(self.points[4], self.transform),
                rl.Vector2Transform(self.points[5], self.transform),
                rl.WHITE,
            );
        }
    }
};

pub fn update(dt: f32) void {
    if (rl.IsKeyDown(rl.KEY_W)) {
        ship.vel = .{
            .x = ship.speed * @cos(ship.rot - pi_half) * dt,
            .y = ship.speed * @sin(ship.rot - pi_half) * dt,
        };
        ship.thrust = true;
    } else {
        ship.thrust = false;
        ship.vel.x = moveTowards(0, ship.vel.x, 0.3 * dt);
        ship.vel.y = moveTowards(0, ship.vel.y, 0.3 * dt);
    }

    if (rl.IsKeyDown(rl.KEY_A)) ship.rot -= dt * ship.rot_speed;
    if (rl.IsKeyDown(rl.KEY_D)) ship.rot += dt * ship.rot_speed;

    ship.pos = rl.Vector2Add(ship.pos, ship.vel);
    ship.pos.x = @mod(ship.pos.x, winWidth);
    ship.pos.y = @mod(ship.pos.y, winHeight);

    ship.transform = rl.MatrixMultiply(
        rl.MatrixRotate(.{ .x = 0, .y = 0, .z = 1 }, ship.rot),
        rl.MatrixMultiply(
            rl.MatrixScale(ship_scale, ship_scale, ship_scale),
            rl.MatrixTranslate(ship.pos.x, ship.pos.y, 0),
        ),
    );
    updateBullets();
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
    }
    var i: usize = 0;
    while (i < state.bullets.items.len) : (i += 1) {
        var b = &state.bullets.items[i];
        b.pos = rl.Vector2Add(b.pos, b.vel);
        b.ttl -= 1;
        if (b.ttl == 0) {
            _ = state.bullets.swapRemove(i);
        }
    }
}

pub fn draw() void {
    rl.DrawText("Score", 2, 2, 18, rl.WHITE);

    for (state.bullets.items) |b| {
        rl.DrawPixelV(b.pos, rl.WHITE);
    }

    ship.draw();
}

pub fn moveTowards(target: f32, val: f32, delta: f32) f32 {
    if (std.math.sign(val) == -1) {
        const new = val + delta;
        return if (new > target) target else new;
    } else {
        const new = val - delta;
        return if (new < target) target else new;
    }
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();
    var bullets = std.ArrayList(Bullet).init(allocator);
    defer bullets.deinit();

    ship = Ship{};
    state = State{ .bullets = bullets };

    rl.InitWindow(winWidth, winHeight, "Asteroids");
    defer rl.CloseWindow();
    rl.SetTargetFPS(60);

    while (!rl.WindowShouldClose()) {
        const dt = rl.GetFrameTime();
        rl.BeginDrawing();
        rl.ClearBackground(rl.BLACK);
        update(dt);
        draw();
        rl.EndDrawing();
    }
}
