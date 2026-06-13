//! ANSI escape codes for terminal colors.
//! Only use when color output is explicitly enabled.

pub const reset = "\x1b[0m";
pub const red = "\x1b[31m";
pub const green = "\x1b[32m";
pub const yellow = "\x1b[33m";
pub const blue = "\x1b[34m";
pub const bold = "\x1b[1m";
