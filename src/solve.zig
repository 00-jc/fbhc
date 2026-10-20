//! Branch-and-bound search for a small set of bit positions that
//! distinguishes every pair of keys.

pub fn solve(comptime K: type, remaining_diffs: []K, chosen_bits: K, max_bits: usize) ?K
{
    if (remaining_diffs.len == 0) return chosen_bits;
    if (@popCount(chosen_bits) >= max_bits) return null;

    var fewest_bit_count: usize = @bitSizeOf(K);
    var fewest_index: usize = 0;
    for (remaining_diffs, 0..) |diff, index|
    {
        const bit_count = @popCount(diff);
        if (bit_count < fewest_bit_count)
        {
            fewest_bit_count = bit_count;
            fewest_index = index;
        }
    }

    const pivot_diff = remaining_diffs[fewest_index];

    var untried_bits = pivot_diff;
    while (untried_bits != 0) : (untried_bits &= untried_bits - 1)
    {
        const candidate_bit = untried_bits & (~untried_bits +% 1);

        var unseparated_count: usize = 0;
        for (remaining_diffs, 0..) |diff, index|
        {
            if (diff & candidate_bit == 0)
            {
                remaining_diffs[index] = remaining_diffs[unseparated_count];
                remaining_diffs[unseparated_count] = diff;
                unseparated_count += 1;
            }
        }

        if (solve(K, remaining_diffs[0..unseparated_count], chosen_bits | candidate_bit, max_bits)) |found_mask|
            return found_mask;
    }
    return null;
}
