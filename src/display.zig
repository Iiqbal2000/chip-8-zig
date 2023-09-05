// Draw step:
// 1. Fetch coordinates:
//    Fetch X and Y coordinates from VX and VY registers.
// 2. Determine sprite height:
//    The last nibble (4 bits) of the opcode, N, represents the height of the sprite.
//    Fetch it using `opcode & 0x000F`.
// 3. Draw the sprite:
//    - For N rows:
//      - Fetch the row data from memory starting at the address stored in the I register.
//      - For each of the 8 pixels/bits in this sprite row (from left to right):
//          - condition 1: If the sprite's current pixel is on and the corresponding pixel on the display at (X,Y) is also on,
//            do: Turn off the pixel at (X,Y) and set VF to 1 (indicating a collision).
//
//          - condition 2: If the sprite's current pixel is on and the pixel on the display at (X,Y) is off,
//            do: Turn on the pixel at (X,Y).
//
//          - condition 3: If X reaches the right edge of the screen while processing the row,
//            do: Stop drawing this row and proceed to the next row (if any).
//          - Increment X for the next pixel in the row.
//      - Increment Y for the next row of the sprite.
//      - If Y reaches the bottom edge of the screen, stop drawing.
//   - Increment PC
// pub fn draw(VX: u16, VY: u16, N: 16) !void {
//     var x_coordinate: u16 = VX & 63;
//     var y_coordinate: u16 = VY & 31;
//
// }
