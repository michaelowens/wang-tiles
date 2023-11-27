# Wang Tiles

Implementation of [Wang Tiles](https://en.wikipedia.org/wiki/Wang_tile) in Odin. Currently supports 2 color tiles rendered by a shader running on the cpu.

## Quick Start

```
$ odin build main.odin -file
$ ./main -h
usage: odin-wang-tiles [options]

Options:
 -c <columns>  set grid columns (default: 16)
 -d            enable debug output
 -h            show help
 -p <pattern>  set pattern (default: circle)
 -r <rows>     set grid rows (default: 16)
 -s <size>     set tile size in px (default: 64)
```

## Examples

![ex0](./images/ex0.png)
![ex1](./images/ex1.png)
