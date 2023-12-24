const webp = @import("webp.zig");
const tgs = @import("tgs.zig");
const webm = @import("webm.zig");
const common = @import("common.zig");

pub const Image = common.Image;

pub const readWebp = webp.readWebp;
pub const readTgs = tgs.readTgs;
pub const readWebm = webm.readWebm;
