package main

import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:time"
import "core:strings"
import "core:container/queue"
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

width :: 128
height :: 128

tile_size :: 64
grid_size :: Coord{16, 16}

frag_test :: proc(uv: la.Vector2f64) -> la.Vector3f64 {
  return {
    math.cos(uv.x),
    math.sin(uv.y),
    0.0
  }
}

frag_japan :: proc(uv: la.Vector2f64) -> la.Vector3f64 {
  co: la.Vector2f64 = 0.5
  cr := 0.25
  ch := la.distance(uv, co)
  if ch < cr {
    return {1, 0, 0}
  } else {
    return {1, 1, 1}
  }
}

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
  
  if point_in_square(uv, {0.20, 0.20}, {0.6, 0.6}) {
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

create_edges :: proc(bit_mask: u8) -> [dynamic]la.Vector2f64 {
  edges: [dynamic]la.Vector2f64 = {}

  if bit_mask & 0b1 > 0 {
    append(&edges, la.Vector2f64{0.5, 0.0})
  }

  if (bit_mask >> 1) & 0b1 > 0 {
    append(&edges, la.Vector2f64{1.0, 0.5})
  }

  if (bit_mask >> 2) & 0b1 > 0 {
    append(&edges, la.Vector2f64{0.5, 1.0})
  }

  if (bit_mask >> 3) & 0b1 > 0 {
    append(&edges, la.Vector2f64{0.0, 0.5})
  }

  return edges
}

// trbl = bit mask where it needs a top/right/bottom/left edge
create_tile_mask :: proc(trbl: [4]TilePos, rng: ^rand.Rand = nil) -> u8 {
  edges: [dynamic]u8 = {}

  mask: u8 = 0
  if trbl[0] == TilePos.Required || (trbl[0] == TilePos.Allowed && rand.int_max(2, rng) == 0) {
    mask = mask | 0b0001
  }
  if trbl[1] == TilePos.Required || (trbl[1] == TilePos.Allowed && rand.int_max(2, rng) == 0) {
    mask = mask | 0b0010
  }
  if trbl[2] == TilePos.Required || (trbl[2] == TilePos.Allowed && rand.int_max(2, rng) == 0) {
    mask = mask | 0b0100
  }
  if trbl[3] == TilePos.Required || (trbl[3] == TilePos.Allowed && rand.int_max(2, rng) == 0) {
    mask = mask | 0b1000
  }

  // for n in 0..=15 {
  //   if trbl &~ u8(n) == 0 {
  //     append(&edges, u8(n))
  //   }
  // }

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

all_wang_tiles :: proc() {
  data := make([]RGBA, width*height)
  // data: [width*height]RGBA

  for n in 0..=15 {
    // edges := create_edges(u8(n))

    for y := 0; y < height; y += 1 {
      for x := 0; x < width; x += 1 {
        u := f64(x) / f64(width)
        v := f64(y) / f64(height)
        c := frag_tile_circle({u, v}, u8(n))

        data[y*width+x] = RGBA{
          u8(c.r * 255),
          u8(c.g * 255),
          u8(c.b * 255),
          255
        }
      }
    }

    filename := strings.clone_to_cstring(fmt.tprintf("output%d.png", n))
    res := image.write_png(filename, width, height, 4, raw_data(data), width*4)
    fmt.println(res)
  }
}

generate_mask :: proc(current: Coord, masks: ^[]u8, surrounding: ^[dynamic]Coord, seen_tiles: ^map[Coord]bool) -> [4]TilePos {
  result: [4]TilePos

  fmt.printf("surrounding: %d\n", len(surrounding))

  // TODO: clean up
  checked_sides: u8 = 0
  for t in surrounding {
    if t not_in seen_tiles {
      continue
    }
    
    mask := masks[t.y*grid_size.x+t.x]
    if t.y < current.y {
      fmt.printf("found tile above: %4b\n", mask)
      checked_sides = checked_sides | 0b0001
      result[0] = mask & 0b0100 > 0 ? TilePos.Required : TilePos.Disallowed
    }
    if t.y > current.y {
      fmt.printf("found tile below: %4b\n", mask)
      checked_sides = checked_sides | 0b0100
      result[2] = mask & 0b0001 > 0 ? TilePos.Required : TilePos.Disallowed
    }
    if t.x < current.x {
      fmt.printf("found tile left: %4b\n", mask)
      checked_sides = checked_sides | 0b1000
      result[3] = mask & 0b0010 > 0 ? TilePos.Required : TilePos.Disallowed
    }
    if t.x > current.x {
      fmt.printf("found tile right: %4b\n", mask)
      checked_sides = checked_sides | 0b0010
      result[1] = mask & 0b1000 > 0 ? TilePos.Required : TilePos.Disallowed
    }
  }

  if checked_sides & 0b0001 == 0 {
    fmt.println("no tile above")
    result[0] = TilePos.Allowed
  }
  if checked_sides & 0b0010 == 0 {
    fmt.println("no tile right")
    result[1] = TilePos.Allowed
  }
  if checked_sides & 0b0100 == 0 {
    fmt.println("no tile below")
    result[2] = TilePos.Allowed
  }
  if checked_sides & 0b1000 == 0 {
    fmt.println("no tile left")
    result[3] = TilePos.Allowed
  }

  return result
}

main :: proc() {
  // all_wang_tiles()

  rng := rand.create(u64(time.time_to_unix(time.now())))
  masks := make([]u8, grid_size.x*grid_size.y)

  // 1. set a random tile at a random location
  first_x := rand.int_max(grid_size.x, &rng)
  first_y := rand.int_max(grid_size.y, &rng)

  fmt.printf("first: %d,%d\n", first_x, first_y)

  masks[first_y*grid_size.x+first_x] = u8(rand.int_max(16, &rng))

  fmt.printf("set %d,%d to %4b\n", first_x, first_y, masks[first_y*grid_size.x+first_x])

  // 2. expand to surrounding tiles until we've set every bitmask
  seen_tiles := make(map[Coord]bool)
  defer delete(seen_tiles)
  seen_tiles[{first_x, first_y}] = true

  q: queue.Queue(Coord)
  queue.init(&q)

  surrounding := find_surrounding_coords({first_x, first_y})
  queue.push_back_elems(&q, ..surrounding[:])

  for queue.len(q) > 0 {
    current := queue.pop_front(&q)
    if current in seen_tiles {
      continue
    }
    seen_tiles[current] = true

    surrounding := find_surrounding_coords(current)
    mask := generate_mask(current, &masks, &surrounding, &seen_tiles)
    // if (masks[(current.y-1)*grid_size.x+current.x] & 4 > 0? 1 : 0)
    possible_tiles := create_tile_mask(mask, &rng)
    masks[current.y*grid_size.x+current.x] = possible_tiles
    // if len(possible_tiles) == 1 {
    //   masks[current.y*grid_size.x+current.x] = possible_tiles[0]
    // } else if len(possible_tiles) > 1 {
    //   n := rand.int_max(len(possible_tiles), &rng)
    //   masks[current.y*grid_size.x+current.x] = possible_tiles[n]
    // }
    fmt.printf("set %d,%d (%4b) to %4b\n", current.x, current.y, mask, masks[current.y*grid_size.x+current.x])
    // fmt.printf("%v\n", current)

    for t in surrounding {
      if t not_in seen_tiles {
        queue.push_back(&q, t)
      }
    }
  }

  fmt.printf("%#v\n", len(masks))

  // 3. Render tiles
  data := make([]RGBA, grid_size.x*grid_size.y*tile_size*tile_size)
  
  for grid_y := 0; grid_y < grid_size.y; grid_y += 1 {
    for grid_x := 0; grid_x < grid_size.x; grid_x += 1 {
      for y := 0; y < tile_size; y += 1 {
        for x := 0; x < tile_size; x += 1 {
          u := f64(x) / f64(tile_size)
          v := f64(y) / f64(tile_size)
          // edges := create_edges(masks[grid_y*grid_size.x+grid_x])
          c := frag_tile_circle({u, v}, masks[grid_y*grid_size.x+grid_x])
          // c := frag_tile_triangle({u, v}, masks[grid_y*grid_size.x+grid_x])
          // c := frag_japan({u, v})

          // 0  1    2  3
          // 4  5    6  7
          //
          // 8  9    10 11
          // 12 13   14 15
          
          // y*width + x
          px := (grid_y*tile_size+y)*(grid_size.x*tile_size) + (grid_x*tile_size) + x
          data[px] = RGBA{
            u8(c.r * 255),
            u8(c.g * 255),
            u8(c.b * 255),
            255
          }
        }
      }
    }
  }
  
  res := image.write_png("output.png", i32(grid_size.x*tile_size), i32(grid_size.y*tile_size), 4, raw_data(data), i32(grid_size.x*tile_size*4))
  fmt.println(res)

  // a := la.Vector3f64{1.0, 0.0, 0.0}
  // fmt.printf("%.1f %.1f %.1f\n", a.r, a.g, a.b)
  
  // data := make([]RGBA, width*height)

  // for y := 0; y < height; y += 1 {
  //   for x := 0; x < width; x += 1 {
  //     u := f64(x) / f64(width)
  //     v := f64(y) / f64(height)
  //     c := frag_japan({u, v})

  //     data[y*width+x] = RGBA{
  //       u8(c.r * 255),
  //       u8(c.g * 255),
  //       u8(c.b * 255),
  //       255
  //     }
  //   }
  // }

  // res := image.write_png("test.png", width, height, 4, raw_data(data), width*4)
  // fmt.println(res)
}