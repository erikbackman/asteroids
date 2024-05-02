const std = @import("std");
const ray = @cImport({
    @cInclude("raylib.h");
});

pub fn main() void {
    const screenWidth = 800;
    const screenHeight = 450;
    ray.InitWindow(screenWidth, screenHeight, "raylib [core] example - basic window");
    defer ray.CloseWindow();
    ray.SetTargetFPS(60);

    while (!ray.WindowShouldClose()) {
        ray.BeginDrawing();
        ray.ClearBackground(ray.WHITE);
        ray.DrawText("Congrats! You created your first window!", 190, 200, 20, ray.LIGHTGRAY);
        ray.EndDrawing();
    }
}
