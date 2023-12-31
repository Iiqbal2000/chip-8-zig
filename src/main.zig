const std = @import("std");
const fs = std.fs;
const testing = std.testing;
const SDL = @import("sdl2");
const target_os = @import("builtin").os;
const RndGen = std.rand.DefaultPrng;

const WINDOW_WIDTH: u16 = 64;
const WINDOW_HEIGHT: u16 = 32;
const SCALE_FACTOR: u16 = 20;
const CHIP8_WIDTH: u16 = 64;
const CHIP8_HEIGHT: u16 = 32;

var rand = RndGen.init(100);

const CHIP8Error = error{UnknownOpcode};

// sprite characters with each size of 5 bytes
const fontset = [80]u8{
    0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
    0x20, 0x60, 0x20, 0x20, 0x70, // 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
    0x90, 0x90, 0xF0, 0x10, 0x10, // 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
    0xF0, 0x10, 0x20, 0x40, 0x40, // 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, // A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
    0xF0, 0x80, 0x80, 0x80, 0xF0, // C
    0xE0, 0x90, 0x90, 0x90, 0xE0, // D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
    0xF0, 0x80, 0xF0, 0x80, 0x80, // F
};

const keymap: [16]SDL.Scancode = [_]SDL.Scancode{
    SDL.Scancode.x,
    SDL.Scancode.@"1",
    SDL.Scancode.@"2",
    SDL.Scancode.@"3",
    SDL.Scancode.q,
    SDL.Scancode.w,
    SDL.Scancode.e,
    SDL.Scancode.a,
    SDL.Scancode.s,
    SDL.Scancode.d,
    SDL.Scancode.z,
    SDL.Scancode.c,
    SDL.Scancode.@"4",
    SDL.Scancode.r,
    SDL.Scancode.f,
    SDL.Scancode.v,
};

const CHIP8 = struct {
    // this stores a current instruction
    opcode: u16,
    //  4096 bytes of addressable memory
    memory: [4096]u8,
    // 16 8-bit registers
    V: [16]u8,
    // This register is generally used to store memory addresses
    I: u16,
    // pc is used to store the address of the next instruction
    pc: u16,
    // stack is used to call and return from subroutines (“functions”)
    stack: [16]u16,
    // sp is used to point to the topmost level of the stack
    sp: u8,
    // this stores a time to control the animation of the display
    delay_timer: u8,
    sound_timer: u8,
    // The graphics of the Chip 8 are black and white and the screen has a total of 2048 pixels (64 x 32)
    display: [CHIP8_WIDTH][CHIP8_HEIGHT]u8,
    // HEX based keypad (0x0-0xF)
    keypad: [16]u8,

    fn initialize() CHIP8 {
        var chip8 = CHIP8{
            .memory = [_]u8{0} ** 4096,
            .pc = 0x200,
            .opcode = 0,
            .I = 0,
            .sp = 0,
            .V = [_]u8{0} ** 16,
            .stack = [_]u16{0} ** 16,
            .delay_timer = 0,
            .sound_timer = 0,
            .display = undefined,
            .keypad = undefined,
        };

        for (fontset, 0..) |f, i| {
            chip8.memory[i] = f;
        }

        return chip8;
    }

    fn load(self: *CHIP8, path: []const u8) !void {
        if (!std.fs.path.isAbsolute(path)) {
            std.log.err("{s}", .{"the program needs a absolute path"});
            std.process.exit(1);
        }

        var file = try fs.openFileAbsolute(path, fs.File.OpenFlags{ .mode = fs.File.OpenMode.read_only });
        defer file.close();

        const stat = try file.stat();

        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const allocator = gpa.allocator();
        defer {
            _ = gpa.deinit();
        }

        const bytes = try allocator.alloc(u8, stat.size);
        defer allocator.free(bytes);

        _ = try file.read(bytes);

        for (bytes, 0..) |b, i| {
            self.memory[i + 0x200] = b;
        }
    }

    fn emulate_cycle(self: *CHIP8) CHIP8Error!void {
        // Fetches a 2-byte opcode from memory
        self.opcode = (@as(u16, self.memory[self.pc]) << 8) | @as(u16, self.memory[self.pc + 1]);

        // std.debug.print("0x{x}\n", .{self.opcode});

        // Decodes a common sign the opcode
        var first_nibble: u16 = (self.opcode >> 12) & 0x000F;

        // get a value of the X register
        var x_regs: u16 = (self.opcode & 0x0F00) >> 8;
        // get a value of the Y register
        var y_regs: u16 = (self.opcode & 0x00F0) >> 4;
        // get 4 bit
        var n: u16 = self.opcode & 0x000F;
        // get the 8-bit nn value
        var nn: u8 = @intCast(self.opcode & 0x00FF);
        // get the 12-bit nnn value
        var nnn: u16 = self.opcode & 0x0FFF;

        // common opcode categories and their corresponding first nibble ranges
        switch (first_nibble) {
            0x0 => {
                var msb: u16 = self.opcode & 0x000F;

                switch (msb) {
                    // 0x00E0: Clears the screen
                    0x0000 => {
                        std.debug.print("Clear screen", .{});
                        for (0..CHIP8_WIDTH) |x| {
                            for (0..CHIP8_HEIGHT) |y| {
                                self.display[x][y] = 0;
                            }
                        }

                        self.pc += 2;
                    },
                    // 0x00EE: Returns from subroutine
                    0x000E => {
                        std.debug.print("0x00EE: Returns from subroutine \n", .{});
                        self.sp -= 1;
                        self.pc = self.stack[self.sp];
                        self.pc += 2;
                    },
                    else => {
                        std.debug.print("UnknownOpcode: 0x{x}\n", .{msb});
                        return CHIP8Error.UnknownOpcode;
                    },
                }
            },
            // jump to NNN location
            0x1 => {
                self.pc = nnn;
            },
            // calls the subroutine at address NNN
            0x2 => {
                self.stack[self.sp] = self.pc;
                self.sp += 1;
                self.pc = nnn;
            },
            // skip one instruction if the value in VX is equal to NN
            0x3 => {
                if (self.V[x_regs] == nn) {
                    self.pc += 2;
                }

                self.pc += 2;
            },
            // skip one instruction if the value in VX is not equal to NN
            0x4 => {
                if (self.V[x_regs] != nn) {
                    self.pc += 2;
                }

                self.pc += 2;
            },
            // skip one instruction if the value in VX is equal to VY
            0x5 => {
                if (self.V[x_regs] == self.V[y_regs]) {
                    self.pc += 2;
                }
                self.pc += 2;
            },
            // set nn to VX register
            0x6 => {
                self.V[x_regs] = nn;
                self.pc += 2;
            },
            // Add NN value to VX
            0x7 => {
                const result = @addWithOverflow(self.V[x_regs], nn);
                if (result[0] != 0) {
                    std.debug.print("Overflow occurred. Result is {d}.\n", .{result[0]});
                    std.debug.print("VX: {d} nn: {d}\n", .{ self.V[x_regs], nn });
                }
                self.V[x_regs] = result[0];
                self.pc += 2;
            },
            // All these instructions are logical or arithmetic operations
            0x8 => {
                // decided instruction by its last nibble
                switch (n) {
                    0 => {
                        self.V[x_regs] = self.V[y_regs];
                        self.pc += 2;
                    },
                    1 => {
                        self.V[x_regs] = self.V[x_regs] | self.V[y_regs];
                        self.pc += 2;
                    },
                    2 => {
                        self.V[x_regs] = self.V[x_regs] & self.V[y_regs];
                        self.pc += 2;
                    },
                    3 => {
                        self.V[x_regs] = self.V[x_regs] ^ self.V[y_regs];
                        self.pc += 2;
                    },
                    4 => {
                        // If sum of VX and VY is overflow put carry bit to VF
                        var sum: u16 = self.V[x_regs];
                        sum += self.V[y_regs];

                        self.V[0xF] = if (sum > 255) 1 else 0;
                        self.V[x_regs] = @as(u8, @truncate(sum & 0x00FF));
                        self.pc += 2;
                    },
                    5 => {
                        self.V[0xF] = if (self.V[x_regs] > self.V[y_regs]) 1 else 0;

                        const result = @subWithOverflow(self.V[x_regs], self.V[y_regs]);
                        if (result[0] != 0) {
                            std.debug.print("Overflow occurred. Result is {d}.\n", .{result[0]});
                            std.debug.print("VX: {d} VY: {d}\n", .{ self.V[x_regs], self.V[y_regs] });
                        }
                        self.V[x_regs] = result[0];
                        self.pc += 2;
                    },
                    6 => {
                        // store the least significant bit
                        self.V[0xF] = self.V[x_regs] & 0x01;
                        // shift VX to the right by one bit
                        self.V[x_regs] >>= 1;
                        self.pc += 2;
                    },
                    7 => {
                        if (self.V[y_regs] > self.V[x_regs]) {
                            self.V[0xF] = 1;
                        } else {
                            self.V[0xF] = 0;
                        }

                        self.V[x_regs] = self.V[y_regs] - self.V[x_regs];
                        self.pc += 2;
                    },
                    0xE => {
                        // store msb value to VF
                        self.V[0xF] = self.V[x_regs] & 0x80;
                        self.V[x_regs] <<= 1;
                        self.pc += 2;
                    },
                    else => {
                        std.debug.print("UnknownOpcode: 0x{x}\n", .{first_nibble});
                        return CHIP8Error.UnknownOpcode;
                    },
                }
            },
            // if VX is not equal to VY skip one instruction
            0x9 => {
                if (self.V[x_regs] != self.V[y_regs]) {
                    self.pc += 2;
                }

                self.pc += 2;
            },
            // Set NNN to the I regs
            0xA => {
                self.I = nnn;
                self.pc += 2;
            },
            // Jump to a address of V regs + NNN
            0xB => {
                self.pc = self.V[0] + nnn;
            },
            // generate random number
            0xC => {
                self.V[x_regs] = rand.random().int(u8) & @as(u8, @intCast(nn));
                self.pc += 2;
            },
            // Draw n-byte sprite
            0xD => {
                try self.draw(self.V[x_regs], self.V[y_regs], n);
                self.pc += 2;
            },
            0xE => {
                switch (nn) {
                    // Skip the next instruction if the key with the value of VX is currently pressed
                    0x9E => {
                        if (self.keypad[self.V[x_regs]] == 1) {
                            self.pc += 2;
                        }
                        self.pc += 2;
                    },
                    // Skip the next instruction if if the key with the value of VX is not currently pressed
                    0xA1 => {
                        if (self.keypad[self.V[x_regs]] != 1) {
                            self.pc += 2;
                        }
                        self.pc += 2;
                    },
                    else => {
                        std.debug.print("UnknownOpcode: 0x{x}\n", .{first_nibble});
                        return CHIP8Error.UnknownOpcode;
                    },
                }
            },
            // instructions are used to manipulate the timers
            0xF => {
                switch (nn) {
                    //  sets VX to the current value of the delay timer
                    0x07 => {
                        self.V[x_regs] = self.delay_timer;
                        self.pc += 2;
                    },
                    // Wait for a key press, and then store the value of the key to VX
                    0x0A => {
                        var pressed = false;

                        for (0..keymap.len) |i| {
                            if (self.keypad[i] == 1) {
                                self.V[x_regs] = @intCast(i);
                                pressed = true;
                            }
                        }

                        if (!pressed)
                            // self.pc -= 2;
                            return;

                        self.pc += 2;
                    },
                    //  sets the VX value to the delay timer
                    0x15 => {
                        self.delay_timer = @intCast(self.V[x_regs]);
                        self.pc += 2;
                    },
                    // sets the VX value to the sound timer
                    0x18 => {
                        self.sound_timer = @intCast(self.V[x_regs]);
                        self.pc += 2;
                    },
                    // Add the values of I and VX, and store the result in I
                    0x1E => {
                        if ((self.I + self.V[x_regs]) > 0xFFF) {
                            self.V[0xF] = 1;
                        } else {
                            self.V[0xF] = 0;
                        }
                        self.I = self.I + self.V[x_regs];
                        self.pc += 2;
                    },
                    // Set the location of the sprite for the digit VX to I.
                    0x29 => {
                        self.I = self.V[x_regs] * 0x5;
                        self.pc += 2;
                    },
                    // Store BCD representation
                    0x33 => {
                        const i: usize = @intCast(self.I);
                        self.memory[i] = self.V[x_regs] / 100;
                        self.memory[i + 1] = (self.V[x_regs] % 100) / 10;
                        self.memory[i + 2] = self.V[x_regs] % 10;
                        self.pc += 2;
                    },
                    // Store registers from V0 to VX in the main memory, starting at location I.
                    0x55 => {
                        var i: usize = 0;
                        while (i <= x_regs) : (i += 1) {
                            self.memory[self.I + i] = self.V[i];
                        }
                        self.pc += 2;
                    },
                    // Load the memory data starting at address I into the registers V0 to VX.
                    0x65 => {
                        var i: usize = 0;
                        while (i <= x_regs) : (i += 1) {
                            self.V[i] = self.memory[self.I + i];
                        }
                        self.pc += 2;
                    },
                    else => {
                        std.debug.print("UnknownOpcode: 0x{x}\n", .{first_nibble});
                        return CHIP8Error.UnknownOpcode;
                    },
                }
            },
            else => {
                std.debug.print("UnknownOpcode: 0x{x}\n", .{first_nibble});
                return CHIP8Error.UnknownOpcode;
            },
        }

        if (self.delay_timer > 0) {
            self.delay_timer -= 1;
        }

        if (self.sound_timer > 0) {
            self.sound_timer -= 1;
        }
    }

    pub fn draw(self: *CHIP8, VX: u16, VY: u16, height: u16) !void {
        var x_coordinate: u16 = VX % CHIP8_WIDTH;
        var y_coordinate: u16 = VY % CHIP8_HEIGHT;
        // initialize collision flag to 0 (no collision)
        self.V[0xF] = 0;

        // Iterate over each row of the sprite
        for (0..height) |row| {
            var sprite = self.memory[self.I + row];
            var col: usize = 0;

            // Iterate over each pixel in sprite byte (8 pixels per byte)
            while (col < 8) : (col += 1) {
                const mask: u8 = 0x80;
                const pixel: u8 = sprite & (mask >> @as(u3, @intCast(col)));
                if (pixel != 0) {
                    var tX = x_coordinate + col;
                    var tY = y_coordinate + row;

                    // If corresponding screen pixel is also on, set collision flag
                    if (self.display[tX][tY] == 1) {
                        self.V[0x0F] = 1;
                    }

                    // Set the screen pixel value
                    self.display[tX][tY] ^= 1;
                }
            }
        }
    }
};

pub fn main() !void {
    try SDL.init(.{ .video = true });
    defer SDL.quit();

    var window = try SDL.createWindow("CHIP-8 Emulator", SDL.WindowPosition.centered, SDL.WindowPosition.centered, WINDOW_WIDTH * SCALE_FACTOR, WINDOW_HEIGHT * SCALE_FACTOR, .{});
    defer window.destroy();

    var surface = try window.getSurface();
    defer surface.destroy();
    // Fill the entire surface with a black color
    try surface.fillRect(null, SDL.Color.black);

    var chip8 = CHIP8.initialize();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        _ = gpa.deinit();
    }

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    try chip8.load(args[1]);

    mainLoop: while (true) {
        try chip8.emulate_cycle();

        while (SDL.pollEvent()) |e| {
            switch (e) {
                .quit => {
                    break :mainLoop;
                },
                .key_down => |keyEvent| {
                    if (keyEvent.scancode == SDL.Scancode.escape) {
                        break :mainLoop;
                    }

                    // Update the CHIP-8 keypad state based on the key pressed
                    for (0..keymap.len) |key_index| {
                        if (keyEvent.scancode == keymap[key_index]) {
                            std.debug.print("key pressed: {s}\nscancode: {s}\n", .{ @tagName(keymap[key_index]), @tagName(keyEvent.scancode) });
                            chip8.keypad[key_index] = 1;
                        }
                    }
                },
                .key_up => |keyEvent| {
                    // Update the CHIP-8 keypad state based on the key released
                    for (0..keymap.len) |key_index| {
                        if (keyEvent.scancode == keymap[key_index]) {
                            chip8.keypad[key_index] = 0;
                        }
                    }
                },
                else => {},
            }
        }

        // Update the display based on the CHIP-8's display state
        for (0..CHIP8_WIDTH) |x| {
            for (0..CHIP8_HEIGHT) |y| {
                if (chip8.display[x][y] == 1) {
                    var rect = SDL.Rectangle{
                        .x = @intCast(x * SCALE_FACTOR),
                        .y = @intCast(y * SCALE_FACTOR),
                        .width = @intCast(SCALE_FACTOR),
                        .height = @intCast(SCALE_FACTOR),
                    };

                    // Fill the rectangle with a white color
                    try surface.fillRect(&rect, SDL.Color.white);
                }
            }
        }

        try window.updateSurface();

        std.time.sleep(12 * 1000 * 1000 * 1);
    }
}
