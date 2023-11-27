package main

import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:time"
import "core:strings"
import "core:container/queue"
import "core:os"
import "core:strconv"
import la "core:math/linalg"
import "vendor:stb/image"

RGBA :: distinct [4]u8
Coord :: distinct [2]int
Triangle :: distinct [3]la.Vector2f64

TilePos :: enum {
  Allowed,
  Disallowed,
  Required,
}

tile_size := 64
grid_size := Coord{16, 16}
pattern := "circle"
debug := false

rng := rand.create(u64(time.time_to_unix(time.now())))

frag_tile_circle :: proc(uv: la.Vector2f64, mask: u8) -> la.Vector3f64 {
  co: la.Vector2f64 = 0.5
  cr := 0.25

  c: la.Vector3f64 = {0.68, 0.79, 0.9}

  edges: [dynamic]la.Vector2f64 = {}

  if mask & 0b1 > 0 {
    append(&edges, la.Vector2f64{0.5, 0.0})
  }

  if (mask >> 1) & 0b1 > 0 {
    append(&edges, la.Vector2f64{1.0, 0.5})
  }

  if (mask >> 2) & 0b1 > 0 {
    append(&edges, la.Vector2f64{0.5, 1.0})
  }

  if (mask >> 3) & 0b1 > 0 {
    append(&edges, la.Vector2f64{0.0, 0.5})
  }

  for edge in edges {
    ch := la.distance(uv, edge)
    if ch < cr {
      c = {1, 1, 1}
    }
  }
  
  return c
}

point_in_triangle :: proc(p: la.Vector2f64, p0: la.Vector2f64, p1: la.Vector2f64, p2: la.Vector2f64) -> bool {
  a := 0.5 * (-p1.y * p2.x + p0.y * (-p1.x + p2.x) + p0.x * (p1.y - p2.y) + p1.x * p2.y)
  sign := a < 0 ? f64(-1) : f64(1)
  s := (p0.y * p2.x - p0.x * p2.y + (p2.y - p0.y) * p.x + (p0.x - p2.x) * p.y) * sign
  t := (p0.x * p1.y - p0.y * p1.x + (p0.y - p1.y) * p.x + (p1.x - p0.x) * p.y) * sign
  return s >= 0 && t >= 0 && (s + t) <= 2 * a * sign
}

point_in_square :: proc(p: la.Vector2f64, sq_pos: la.Vector2f64, sq_size: la.Vector2f64) -> bool {
  return p.x >= sq_pos.x && p.x <= (sq_pos.x + sq_size.x) && p.y >= sq_pos.y && p.y <= (sq_pos.y + sq_size.y)
}

frag_tile_triangle :: proc(uv: la.Vector2f64, mask: u8) -> la.Vector3f64 {
  c: la.Vector3f64 = {1, 1, 1}

  edges: [dynamic]Triangle = {}

  if mask & 0b1 > 0 {
    append(&edges, Triangle{{-1, -1}, {0.5, 0.5}, {2, -1}})
  }

  if (mask >> 1) & 0b1 > 0 {
    append(&edges, Triangle{{2, -1}, {0.5, 0.5}, {2, 2}})
  }

  if (mask >> 2) & 0b1 > 0 {
    append(&edges, Triangle{{2, 2}, {0.5, 0.5}, {-1, 2}})
  }

  if (mask >> 3) & 0b1 > 0 {
    append(&edges, Triangle{{-1, -1}, {0.5, 0.5}, {-1, 2}})
  }
  
  if point_in_square(uv, {0.25, 0.25}, {0.5, 0.5}) {
    n := f64(len(edges))
    return {0.25*n, 0.25*n, 0.25*n}
  }

  for edge in edges {
    if point_in_triangle(uv, edge[0], edge[1], edge[2]) {
      c = {0, 0, 0}
    }
  }
  
  return c
}

// trbl = bit mask where it needs a top/right/bottom/left edge
create_tile_mask :: proc(trbl: [4]TilePos) -> u8 {
  edges: [dynamic]u8 = {}

  mask: u8 = 0
  if trbl[0] == TilePos.Required || (trbl[0] == TilePos.Allowed && rand.int_max(2, &rng) == 0) {
    mask = mask | 0b0001
  }
  if trbl[1] == TilePos.Required || (trbl[1] == TilePos.Allowed && rand.int_max(2, &rng) == 0) {
    mask = mask | 0b0010
  }
  if trbl[2] == TilePos.Required || (trbl[2] == TilePos.Allowed && rand.int_max(2, &rng) == 0) {
    mask = mask | 0b0100
  }
  if trbl[3] == TilePos.Required || (trbl[3] == TilePos.Allowed && rand.int_max(2, &rng) == 0) {
    mask = mask | 0b1000
  }

  return mask
}

find_surrounding_coords :: proc(coord: Coord) -> [dynamic]Coord {
  result: [dynamic]Coord

  if coord.x-1 >= 0 {
    append(&result, Coord{coord.x-1, coord.y})
  }
  if coord.x+1 < grid_size.x {
    append(&result, Coord{coord.x+1, coord.y})
  }

  if coord.y-1 >= 0 {
    append(&result, Coord{coord.x, coord.y-1})
  }
  if coord.y+1 < grid_size.y {
    append(&result, Coord{coord.x, coord.y+1})
  }

  return result
}

generate_wang_tiles :: proc(frag_fn: proc(la.Vector2f64, u8) -> la.Vector3f64) -> [][]RGBA {
  tile_data := make([]RGBA, tile_size*tile_size*16)
  data := make([][]RGBA, 16)

  for n in 0..=15 {
    for y := 0; y < tile_size; y += 1 {
      for x := 0; x < tile_size; x += 1 {
        u := f64(x) / f64(tile_size)
        v := f64(y) / f64(tile_size)
        c := frag_fn({u, v}, u8(n))

        tile_data[n*tile_size*tile_size+y*tile_size+x] = RGBA{
          u8(c.r * 255),
          u8(c.g * 255),
          u8(c.b * 255),
          255
        }
      }
    }
    data[n] = tile_data[n*tile_size*tile_size:n*tile_size*tile_size+tile_size*tile_size]
    
    if debug {
      filename := strings.clone_to_cstring(fmt.tprintf("output%d.png", n))
      res := image.write_png(filename, i32(tile_size), i32(tile_size), 4, &data[n], i32(tile_size)*4)
    }
  }

  return data
}

generate_mask :: proc(current: Coord, masks: ^[]u8, surrounding: ^[dynamic]Coord, seen_tiles: ^map[Coord]bool) -> [4]TilePos {
  result: [4]TilePos

  checked_sides: u8 = 0
  for t in surrounding {
    if t not_in seen_tiles {
      continue
    }
    
    mask := masks[t.y*grid_size.x+t.x]
    if t.y < current.y {
      checked_sides = checked_sides | 0b0001
      result[0] = mask & 0b0100 > 0 ? TilePos.Required : TilePos.Disallowed
    }
    if t.y > current.y {
      checked_sides = checked_sides | 0b0100
      result[2] = mask & 0b0001 > 0 ? TilePos.Required : TilePos.Disallowed
    }
    if t.x < current.x {
      checked_sides = checked_sides | 0b1000
      result[3] = mask & 0b0010 > 0 ? TilePos.Required : TilePos.Disallowed
    }
    if t.x > current.x {
      checked_sides = checked_sides | 0b0010
      result[1] = mask & 0b1000 > 0 ? TilePos.Required : TilePos.Disallowed
    }
  }

  if checked_sides & 0b0001 == 0 {
    result[0] = TilePos.Allowed
  }
  if checked_sides & 0b0010 == 0 {
    result[1] = TilePos.Allowed
  }
  if checked_sides & 0b0100 == 0 {
    result[2] = TilePos.Allowed
  }
  if checked_sides & 0b1000 == 0 {
    result[3] = TilePos.Allowed
  }

  return result
}

fill_grid :: proc(grid: ^[]u8, start: Coord) {
  seen_tiles := make(map[Coord]bool)
  defer delete(seen_tiles)
  seen_tiles[start] = true

  q: queue.Queue(Coord)
  queue.init(&q)

  surrounding := find_surrounding_coords(start)
  queue.push_back_elems(&q, ..surrounding[:])
  
  for queue.len(q) > 0 {
    current := queue.pop_front(&q)
    if current in seen_tiles {
      continue
    }
    seen_tiles[current] = true

    surrounding := find_surrounding_coords(current)
    mask := generate_mask(current, grid, &surrounding, &seen_tiles)
    possible_tiles := create_tile_mask(mask)
    grid[current.y*grid_size.x+current.x] = possible_tiles
    // fmt.printf("set %d,%d (%4b) to %4b\n", current.x, current.y, mask, grid[current.y*grid_size.x+current.x])

    for t in surrounding {
      if t not_in seen_tiles {
        queue.push_back(&q, t)
      }
    }
  }
}

render_grid :: proc(grid: ^[]u8, tiles: ^[][]RGBA) -> []RGBA {
  data := make([]RGBA, grid_size.x*grid_size.y*tile_size*tile_size)
  
  for grid_y := 0; grid_y < grid_size.y; grid_y += 1 {
    for grid_x := 0; grid_x < grid_size.x; grid_x += 1 {
      tile := grid[grid_y*grid_size.x+grid_x]
      for y := 0; y < tile_size; y += 1 {
        for x := 0; x < tile_size; x += 1 {
          px := (grid_y*tile_size+y)*(grid_size.x*tile_size) + (grid_x*tile_size) + x
          data[px] = tiles[tile][y*tile_size+x]
        }
      }
    }
  }

  return data
}

print_help :: proc() {
  fmt.println("usage: odin-wang-tiles [options]\n")
  fmt.println("Options:")
  fmt.println(" -c <columns>  set grid columns (default: 16)")
  fmt.println(" -d            enable debug output")
  fmt.println(" -h            show help")
  fmt.println(" -p <pattern>  set pattern (default: circle)")
  fmt.println(" -r <rows>     set grid rows (default: 16)")
  fmt.println(" -s <size>     set tile size in px (default: 64)")
}

assert_arg :: proc(ok: bool, error_msg: string) {
  if !ok {
    fmt.println(error_msg)
    print_help()
    os.exit(1)
  }
}

last_arg_index := -1
pop_arg :: proc() -> Maybe(string) {
  if last_arg_index + 1 >= len(os.args) {
    return nil
  }
  last_arg_index += 1
  return os.args[last_arg_index]
}

main :: proc() {
  program := pop_arg()

  for arg, ok := pop_arg().?; ok; arg, ok = pop_arg().? {
    if arg == "-c" {
      cols, ok := pop_arg().?
      assert(ok, "ERROR: missing columns value")
      grid_size.x = strconv.atoi(cols)
      assert_arg(grid_size.x > 0, "ERROR: columns value should be > 0")
    }

    if arg == "-h" {
      print_help()
      os.exit(0)
    }
    
    if arg == "-d" {
      debug = true
    }
    
    if arg == "-p" {
      // TODO: verify pattern
      pattern, ok = pop_arg().?
      assert(ok, "ERROR: missing pattern value")
    }

    if arg == "-r" {
      rows, ok := pop_arg().?
      assert_arg(ok, "ERROR: missing rows value")
      grid_size.y = strconv.atoi(rows)
      assert_arg(grid_size.y > 0, "ERROR: rows value should be > 0")
    }

    if arg == "-s" {
      size, ok := pop_arg().?
      assert_arg(ok, "ERROR: missing size value")
      tile_size = strconv.atoi(size)
      assert_arg(tile_size > 0, "ERROR: size should be > 0")
    }
  }

  // generate_wang_tiles()
  
  // 1. Generate all tiles
  frag := frag_tile_circle
  if pattern == "triangle" {
    frag = frag_tile_triangle
  }
  
  tiles := generate_wang_tiles(frag)

  // 2. Generate grid with starting tile
  grid := make([]u8, grid_size.x*grid_size.y)

  first_x := rand.int_max(grid_size.x, &rng)
  first_y := rand.int_max(grid_size.y, &rng)

  grid[first_y*grid_size.x+first_x] = u8(rand.int_max(16, &rng))

  // 3. Fill grid
  fill_grid(&grid, {first_x, first_y})

  // 4. Render
  data := render_grid(&grid, &tiles)
  
  res := image.write_png("output.png", i32(grid_size.x*tile_size), i32(grid_size.y*tile_size), 4, raw_data(data), i32(grid_size.x*tile_size*4))
  if res == 0 {
    fmt.fprintln(os.stderr, "Failed to save image")
    os.exit(1)
  }

  fmt.println("Image saved as output.png")
}