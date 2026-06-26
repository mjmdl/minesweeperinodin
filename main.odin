package main

import "core:fmt"
import "core:math/rand"
import rl "vendor:raylib"

Game_State :: enum u8 {
    Play,
    Win,
    Lose,
}

Game :: struct {
    state: Game_State,
    atlas: Atlas,
    board: Board,

    cell_size: i32,

    guesses: i32,
    flags_placed: i32,
}

game_init :: proc(game: ^Game, rows: i32 = 0, columns: i32 = 0, bomb_density: f32 = 0.0) {
    game.state = .Play

    if !game.atlas.loaded {
        game.atlas = atlas_init()
    }
    if game.cell_size == 0 {
        game.cell_size = 100
    }

    game.guesses = 0
    game.flags_placed = 0
    board_init(&game.board, rows, columns, bomb_density)
    game_fit_screen(game)
}

game_update :: proc(game: ^Game) {
    if rl.IsKeyPressed(.RIGHT_BRACKET) && game.board.bomb_density < 0.8 {
        game_init(game, 0, 0, game.board.bomb_density + 0.05)
        return
    }
    if rl.IsKeyPressed(.LEFT_BRACKET) && game.board.bomb_density > 0.2 {
        game_init(game, 0, 0, game.board.bomb_density - 0.05)
        return
    }

    if rl.IsKeyPressed(.DOWN) && game.board.rows < 64 {
        game_init(game, game.board.rows + 1, 0, 0)
        return
    }
    if rl.IsKeyPressed(.UP) && game.board.rows > 4 {
        game_init(game, game.board.rows - 1, 0, 0)
        return
    }
    if rl.IsKeyPressed(.RIGHT) && game.board.columns < 64 {
        game_init(game, 0, game.board.columns + 1, 0)
        return
    }
    if rl.IsKeyPressed(.LEFT) && game.board.columns > 4 {
        game_init(game, 0, game.board.columns - 1, 0)
        return
    }

    if rl.IsKeyReleased(.SPACE) {
        game_init(game)
        return
    }
        
    if game.state != .Play {
        return
    }

    if rl.IsMouseButtonReleased(.LEFT) {
        handle_left_mouse_button(game)
    }
    if rl.IsMouseButtonReleased(.RIGHT) {
        handle_right_mouse_button(game)
    }

    handle_left_mouse_button :: proc(game: ^Game) {
        x, y, over_board := game_hovered_cell(game^)
        if !over_board {
            return
        }
        cell := &game.board.cells[x + (y * game.board.columns)]
        if .Guess in cell.states || .Flag in cell.states {
            return
        }
        
        if !game.board.bombs_planted {
            board_plant_bombs_safely(&game.board, x, y)
        } else if .Bomb in cell.states {
            game.state = .Lose
            return
        }
        
        game.guesses += board_reveal_cells(&game.board, x, y)
        if game.guesses >= ((game.board.rows * game.board.columns) - game.board.bombs) {
            game.state = .Win
            return
        }
        
        return
    }

    handle_right_mouse_button :: proc(game: ^Game) {
        x, y, over_board := game_hovered_cell(game^)
        if !over_board {
            return
        }
        cell := &game.board.cells[x + (y * game.board.columns)]
        if .Guess in cell.states {
            return
        }
        
        if .Flag in cell.states {
            game.flags_placed -= 1
            cell.states -= {.Flag}
            return
        } else if .Guess not_in cell.states {
            game.flags_placed += 1
            cell.states += {.Flag}
            return
        }
    }
}

game_render :: proc(game: Game) {
    CELL_TINT :: rl.RAYWHITE
    CELL_TARGETED_TINT :: rl.WHITE

    rect := rl.Rectangle{0.0, 0.0, f32(game.cell_size), f32(game.cell_size)}
    for y in 0 ..< game.board.rows {
        rect.y = f32(y * game.cell_size)
        for x in 0 ..< game.board.columns {
            rect.x = f32(x * game.cell_size)
            cell := game.board.cells[x + (y * game.board.columns)]

            tint: rl.Color
            if game.state == .Play || game.state == .Win {
                hover_x, hover_y, over_board := game_hovered_cell(game)
                tint = hover_x == x && hover_y == y && over_board ? CELL_TARGETED_TINT : CELL_TINT
            } else if game.state == .Lose {
                tint = rl.RED
            }

            tile := game.atlas.blank
            show_bombs := game.state == .Lose || game.state == .Win
            if show_bombs && .Bomb in cell.states {
                background_tint := game.state == .Win ? rl.RAYWHITE : rl.RED
                rl.DrawTexturePro(game.atlas.texture, game.atlas.blank, rect, [2]f32{}, 0.0, background_tint)
                rl.DrawTexturePro(game.atlas.texture, game.atlas.bomb, rect, [2]f32{}, 0.0, tint)
                if .Flag in cell.states {
                    overlay_alpha := 0.5 * 255
                    overlay_tint := tint
                    overlay_tint.a = u8(overlay_alpha)
                    rl.DrawTexturePro(game.atlas.texture, game.atlas.flag, rect, [2]f32{}, 0.0, overlay_tint)
                }
            } else if .Guess in cell.states {
                rl.DrawTexturePro(game.atlas.texture, game.atlas.blank, rect, [2]f32{}, 0.0, rl.LIGHTGRAY)
                rl.DrawTexturePro(game.atlas.texture, game.atlas.numbers[cell.bombs_around], rect, [2]f32{}, 0.0, tint)
            } else if .Flag in cell.states {
                rl.DrawTexturePro(game.atlas.texture, game.atlas.flag, rect, [2]f32{}, 0.0, tint)
            } else {
                rl.DrawTexturePro(game.atlas.texture, game.atlas.blank, rect, [2]f32{}, 0.0, tint)
            }
        }
    }
}

game_fit_screen :: proc(game: ^Game) {
    monitor := rl.GetCurrentMonitor()
    monitor_width := rl.GetMonitorWidth(monitor)
    monitor_height := rl.GetMonitorHeight(monitor)
    if monitor_width == 0 || monitor_height == 0 {
        return
    }

    useful_ratio: f32 = 0.7
    useful_width := i32(f32(monitor_width) * useful_ratio)
    useful_height := i32(f32(monitor_height) * useful_ratio)
    requested_width := game.board.columns * game.cell_size
    requested_height := game.board.rows * game.cell_size

    ratio_width: f32 = 1
    if requested_width > useful_width {
        ratio_width = f32(useful_width) / f32(requested_width)
    }
    ratio_height: f32 = 1
    if requested_height > useful_height {
        ratio_height = f32(useful_height) / f32(requested_height)
    }
    ratio := min(ratio_width, ratio_height)
    
    requested_width = i32(f32(requested_width) * ratio)
    requested_height = i32(f32(requested_height) * ratio)
    game.cell_size = i32(f32(game.cell_size) * ratio)

    position_x := i32(f32(monitor_width - requested_width) / 2)
    position_y := i32(f32(monitor_height - requested_height) / 2)
    rl.SetWindowSize(requested_width, requested_height)
    rl.SetWindowPosition(position_x, position_y)
}

game_hovered_cell :: proc(game: Game) -> (x: i32, y: i32, over_board: bool) {
    x = i32(cast(f32)rl.GetMouseX() / cast(f32)game.cell_size)
    y = i32(cast(f32)rl.GetMouseY() / cast(f32)game.cell_size)
    over_board = x >= 0 && x < game.board.columns && y >= 0 && y < game.board.rows
    return x, y, over_board
}

Atlas :: struct {
    loaded: bool,
    texture: rl.Texture2D,

    blank: rl.Rectangle,
    flag: rl.Rectangle,
    bomb: rl.Rectangle,
    numbers: [9]rl.Rectangle,
}

atlas_init :: proc() -> Atlas {
    tile :: proc(x, y: i32) -> rl.Rectangle {
        SIZE :: 16
        return rl.Rectangle{f32(x * SIZE), f32(y * SIZE), SIZE, SIZE}
    }

    return Atlas{
        loaded = true,
        texture = rl.LoadTexture("atlas.png"),

        blank = tile(0, 0),
        flag = tile(1, 0),
        bomb = tile(2, 0),
        numbers = {
            tile(3, 0),
            tile(0, 1),
            tile(1, 1),
            tile(2, 1),
            tile(3, 1),
            tile(0, 2),
            tile(1, 2),
            tile(2, 2),
            tile(3, 2),
        },
    }
}

Board :: struct {
    bombs_planted: bool,
    rows: i32,
    columns: i32,
    bombs: i32,
    bomb_density: f32,
    cells: []Cell,
}

board_init :: proc(board: ^Board, rows: i32, columns: i32, bomb_density: f32 = 0.0) {
    rows := rows > 0 ? rows : board.rows
    columns := columns > 0 ? columns : board.columns
    
    area := rows * columns
    if board.cells == nil {
        board.cells = make([]Cell, area)
    } else if area > board.rows * board.columns {
        delete(board.cells)
        board.cells = make([]Cell, area)
    } else {
        for &cell in board.cells {
            cell = Cell{}
        }
    }

    board.bombs_planted = false
    board.rows = rows
    board.columns = columns
    
    if bomb_density > 0.0 {
        board.bomb_density = bomb_density
    }
    board.bombs = i32(f32(area) * board.bomb_density)
}

board_reveal_cells :: proc(board: ^Board, x: i32, y: i32) -> (reveals: i32 = 1) {
    center_cell := &board.cells[x + (y * board.columns)]
    center_cell.states += {.Guess}
    center_cell.bombs_around = 0
        
    for dy in max(y - 1, 0) ..= min(y + 1, board.rows - 1) {
        for dx in max(x - 1, 0) ..= min(x + 1, board.columns - 1) {
            if dx == x && dy == y {
                continue
            }

            cell := &board.cells[dx + (dy * board.columns)]
            if .Bomb in cell.states {
                center_cell.bombs_around += 1
            }
        }
    }

    if center_cell.bombs_around > 0 {
        return reveals
    }
    
    for dy in max(y - 1, 0) ..= min(y + 1, board.rows - 1) {
        for dx in max(x - 1, 0) ..= min(x + 1, board.columns - 1) {
            if dx == x && dy == y {
                continue
            }
            
            cell := &board.cells[dx + (dy * board.columns)]
            if .Guess in cell.states || .Bomb in cell.states {
                continue
            }
            
            cell.states += {.Guess}
            reveals += board_reveal_cells(board, dx, dy)
        }
    }
    
    return reveals
}

board_plant_bombs_safely :: proc(board: ^Board, safe_x: i32, safe_y: i32) {
    assert((board.rows * board.columns) > board.bombs)
    safe_index := safe_x + (safe_y * board.columns)

    failed_attempts := 0
    bombs_planted: i32 = 0
    for bombs_planted < board.bombs {
        index := rand.int31_max(board.rows * board.columns)
        if index != safe_index {
            cell := &board.cells[index]
            if .Bomb not_in cell.states {
                cell.states += {.Bomb}
                bombs_planted += 1
                failed_attempts = 0
            }
        }
    }
    
    board.bombs_planted = true
}

Cell_State :: enum u8 {
    Guess,
    Flag,
    Bomb,
}

Cell :: struct {
    states: bit_set[Cell_State],
    bombs_around: i32,
}

main :: proc() {
    rl.InitWindow(100, 100, "Minesweeperino")
    rl.SetTargetFPS(60)

    game: Game
    game_init(&game, 12, 8, 0.2)

    for !rl.WindowShouldClose() {
        rl.BeginDrawing()
        game_update(&game)

        rl.ClearBackground(rl.MAGENTA)
        game_render(game)

        rl.EndDrawing()
    }
}
