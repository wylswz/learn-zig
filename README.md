# Build Your Own Redis with Zig

A project-based course that guides you through building a Redis-compatible in-memory database from scratch using Zig. By the end, you'll have a working server you can talk to with `redis-cli`.

## Who This Is For

Intermediate programmers with some systems language experience (C, C++, or Rust) who are new to Zig. You should understand basic data structures (hash tables) and networking (TCP). No prior Zig knowledge required.

## What You'll Build

- A TCP server on port 6379
- A RESP protocol parser
- Command handling (PING, ECHO, SET, GET, and optionally ZADD, ZRANGE, ZSCORE)
- A custom hash table
- An arena allocator for per-connection memory
- AOF persistence
- Sorted sets via skip lists (optional)

## Prerequisites

- **Zig 0.15.x** — [Install Zig](https://ziglang.org/learn/getting-started/#installing-zig)
- **redis-cli** — For testing (usually bundled with Redis, or `brew install redis` on macOS)
- **netcat** — For early testing (`nc`)

## How to Use This Course

### 1. Clone and Explore

```bash
git clone <this-repo>
cd learnzig
```

### 2. Work Through the Modules in Order

Each module lives in `modules/` and builds on the previous one:

| Module | File | What You'll Do |
|--------|------|----------------|
| 0 | [00-setup.md](modules/00-setup.md) | TCP server skeleton |
| 1 | [01-resp-parser.md](modules/01-resp-parser.md) | RESP parser |
| 2 | [02-commands.md](modules/02-commands.md) | PING, ECHO, SET, GET |
| 3 | [03-hash-table.md](modules/03-hash-table.md) | Custom hash table |
| 4 | [04-allocators.md](modules/04-allocators.md) | Arena allocator |
| 5 | [05-persistence.md](modules/05-persistence.md) | AOF persistence |
| 6 | [06-sorted-sets.md](modules/06-sorted-sets.md) | Sorted sets (optional) |

### 3. Follow the Module Structure

Each module includes:

- **Required Reading** — Links to Zig docs, Redis specs, and references. Skim these before diving in.
- **Key Concepts** — Zig features and ideas you'll use.
- **Tasks** — Step-by-step implementation with code snippets.
- **Acceptance Criteria** — Checklist to verify you're done.

### 4. Build, Run, and Test

```bash
zig build          # Compile
zig build run      # Start the server
zig build test     # Run unit tests
```

In another terminal:

```bash
redis-cli -p 6379 PING      # Should return PONG
redis-cli -p 6379 SET k v   # Should return OK
redis-cli -p 6379 GET k     # Should return "v"
```

## Project Structure

```
learnzig/
├── README.md           ← You are here
├── build.zig           # Build script
├── build.zig.zon       # Package manifest
├── modules/            # Course content (read these!)
│   ├── 00-setup.md
│   ├── 01-resp-parser.md
│   └── ...
└── src/                # Your implementation
    ├── main.zig        # Server entry point
    ├── resp.zig        # RESP parser (Module 1)
    ├── commands.zig    # Command dispatch (Module 2)
    ├── store.zig       # Hash table (Module 3)
    ├── allocator.zig   # Arena allocator (Module 4)
    ├── aof.zig         # AOF persistence (Module 5)
    └── sorted_set.zig  # Sorted sets (Module 6)
```

The `src/` folder may contain starter code or stubs. Implement what each module asks for; the tests and acceptance criteria guide you.

## Tips for Learners

1. **Read before coding** — Each module's Required Reading links to official docs. Use them.
2. **Use the checkboxes** — Acceptance criteria at the end of each module are your definition of done.
3. **Run tests often** — `zig build test` catches regressions.
4. **Module 6 is optional** — Skip it if you want to finish earlier; the core server is complete after Module 5.
5. **Stuck?** — Re-read the Key Concepts section; Zig's explicitness can feel unfamiliar at first.

## License

See the repository for license details.
