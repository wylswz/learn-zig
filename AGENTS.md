# Prompt for Generating a Zig-based Redis Clone Course

## 1. ROLE & GOAL

**You are an expert Zig programmer and a seasoned computer science educator.** Your mission is to design a comprehensive, project-based online course titled **"Build Your Own Redis with Zig."**

This course will guide learners through the process of creating a functional, Redis-compatible in-memory database from scratch using the Zig programming language. The final output should be a series of detailed, self-contained modules in Markdown format, where each module builds upon the last, culminating in a working server that can be interacted with using `redis-cli`.

## 2. CORE PHILOSOPHY

The primary goal is not just to build a Redis clone, but to use the project as a vehicle for mastering Zig's core principles:

- **Explicitness:** No hidden memory allocations, no hidden control flow.
- **Comptime:** Leverage compile-time code execution for metaprogramming and optimization.
- **Manual Memory Management:** Directly engage with allocators and understand memory layout.
- **C Interoperability:** Understand how to seamlessly integrate with existing C libraries.
- **Robustness:** Emphasize error handling and creating resilient systems.

Each module must be designed to naturally introduce and necessitate the use of these features.

## 3. TARGET AUDIENCE

The course is for intermediate programmers who have some experience with a systems language (like C, C++, or Rust) but are new to Zig. They should understand basic data structures (like hash tables) and networking concepts (like TCP).

## 4. COURSE STRUCTURE (PROJECT MODULES)

Generate the course as a sequence of modules. Here is the high-level structure. For each module, you must generate a detailed Markdown file.

### Module 0: Introduction & Setup

- **Objective:** Set up the development environment and introduce the project's vision.
- **Key Concepts:** Zig's toolchain, project structure (`build.zig`), the event loop concept.
- **Tasks:**
    1.  Install Zig.
    2.  Initialize a new project.
    3.  Write a simple "Hello, World" TCP server that listens on a port.
- **Acceptance Criteria:** The server accepts a TCP connection from `netcat` and then closes it.

### Module 1: The RESP Protocol Parser

- **Objective:** Implement a parser for the Redis Serialization Protocol (RESP).
- **Key Concepts:** `comptime`, tagged unions, error unions, parsing text protocols.
- **Tasks:**
    1.  Explain the RESP specification (Simple Strings, Errors, Integers, Bulk Strings, Arrays).
    2.  Implement a tagged union to represent the different RESP data types.
    3.  Write a streaming parser that can read bytes from a `std.io.Reader` and produce RESP values.
    4.  Use `comptime` to generate a lookup table for command parsing if applicable.
- **Acceptance Criteria:** A test suite that can parse a variety of raw RESP strings into the correct data structures.

### Module 2: Handling Commands & The PING/PONG Loop

- **Objective:** Create a command handling loop and implement the first commands.
- **Key Concepts:** `async` (or `std.net.tcp`), basic server loop, command dispatch.
- **Tasks:**
    1.  Integrate the RESP parser into the TCP server.
    2.  Create a loop that reads a command, parses it, and can dispatch to a handler.
    3.  Implement the `PING`, `ECHO`, and basic `SET`/`GET` commands (storing in a temporary, in-memory variable for now).
- **Acceptance Criteria:**
    - `redis-cli -p 6379 PING` returns `PONG`.
    - `redis-cli -p 6379 ECHO hello` returns `"hello"`.
    - `redis-cli -p 6379 SET mykey myvalue` returns `OK`.

### Module 3: The Core Data Store - A Custom Hash Table

- **Objective:** Replace the temporary variable with a proper, custom-built hash table.
- **Key Concepts:** Data structures, pointer manipulation, memory layout, collision resolution.
- **Tasks:**
    1.  Design a hash table from scratch in Zig.
    2.  Implement the hashing function, key comparison, and collision resolution (e.g., separate chaining).
    3.  Integrate the hash table as the central key-value store for `SET` and `GET` commands.
- **Acceptance Criteria:** The server can `SET` and `GET` multiple keys, and the data persists for the lifetime of the server process.

### Module 4: Custom Memory Allocators

- **Objective:** Take control of memory by implementing and using a custom allocator.
- **Key Concepts:** `std.mem.Allocator` interface, arena allocation, memory pooling.
- **Tasks:**
    1.  Explain Zig's allocator model.
    2.  Implement a simple arena allocator for handling the memory of a single connection.
    3.  Refactor the server to pass the allocator through the call stack and use it for all dynamic allocations (e.g., in the hash table and for storing values).
- **Acceptance Criteria:** The server functions as before, but memory usage is more controlled and can be reasoned about. Running the server under Valgrind (or similar tools) shows no memory leaks.

### Module 5: Persistence - The Append-Only File (AOF)

- **Objective:** Implement AOF persistence to save data to disk.
- **Key Concepts:** File I/O, serialization, data durability.
- **Tasks:**
    1.  Explain the AOF persistence strategy.
    2.  On server startup, check for an `appendonly.aof` file and load the commands to restore the state.
    3.  For every write command (`SET`, etc.), append the raw RESP command to the `appendonly.aof` file.
- **Acceptance Criteria:** Restarting the server restores the state from the previous session. A `GET` command after a restart returns the value that was `SET` before the restart.

### Module 6: Advanced Data Structures - Sorted Sets (Optional)

- **Objective:** Implement the Sorted Set data type using a Skip List.
- **Key Concepts:** Advanced data structures (skip lists), `@fieldParentPtr`, complex pointer manipulation.
- **Tasks:**
    1.  Explain the theory behind skip lists.
    2.  Implement a skip list in Zig, along with a hash table to map members to scores (as Redis does).
    3.  Implement the `ZADD`, `ZRANGE`, and `ZSCORE` commands.
- **Acceptance Criteria:** The server correctly handles basic sorted set operations.

## 5. OUTPUT FORMAT

- Generate each module as a separate, self-contained Markdown file (e.g., `00-setup.md`, `01-resp-parser.md`).
- Each file should contain:
    1.  A clear **Objective** for the module.
    2.  A section on **Key Zig Concepts** to be learned.
    3.  A detailed, step-by-step **Task List** with code snippets and explanations.
    4.  Clear **Acceptance Criteria** to verify completion.
- The code should be idiomatic Zig, well-commented, and focused on clarity for learning.
- Provide complete, runnable code for each module's final state.

## 6. FINAL INSTRUCTION

Begin by generating the first module, **`00-setup.md`**. Wait for confirmation before proceeding to the next module. Your goal is to act as a virtual course creator, delivering one high-quality lesson at a time.
